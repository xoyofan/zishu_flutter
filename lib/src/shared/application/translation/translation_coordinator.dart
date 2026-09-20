/// 直播内容中文化翻译协调器(标题 / 弹幕正文)。
///
/// 纯 Dart,不依赖 Flutter;HTTP 由注入的 [TranslationFetcher] 完成(生产用
/// dio,单测用 fake),不引入任何新 pub 依赖。
///
/// 设计要点(公共翻译实例是志愿者维护的免费服务,必须克制使用):
/// - **缓存去重**:LRU(text → 译文)。弹幕里同一短语重复率极高,缓存是
///   第一道减负;失败记短 TTL 负缓存,避免实例宕机时请求死循环堆积。
/// - **节流队列**:串行小并发 + 最小请求间隔 + 队列上限(溢出丢最旧、
///   回退原文)—— 高峰弹幕每秒可达数十条,宁可原文也不无限堆积延迟。
/// - **失败即回退**:任何失败都返回原文,UI 永不因翻译阻塞或报错。
/// - **按段翻译**:[translateBody] 只翻译文本段、保留表情段,与聊天
///   面板的富文本渲染一一对应;译文缓存在「段文本」粒度,聊天与飘屏
///   共享同一份缓存。
library;

import 'dart:async';
import 'dart:collection';

import 'package:live_parser/live_parser.dart' show DanmakuSegment;

/// 是否需要把文本翻译为中文(已经是中文/纯符号数字 emoji 的跳过)。
///
/// 规则:
/// - 含日文假名 → 翻(日语标题常夹汉字,不能按汉字占比误判为中文);
/// - 含韩文 → 翻(soop);
/// - 无任何字母 → 不翻(纯数字/标点/emoji);
/// - 其余按「表意文字占字母比例」判定:≥ 0.3 视为中文跳过,否则翻。
///   阈值取得宽松(宁可少翻、不错翻):中文标题/弹幕夹游戏名、品牌词
///   十分常见,句子里有一两个汉字通常就是中文,翻回去反而错。
bool needsChineseTranslation(String raw) {
  var hasKana = false;
  var hasHangul = false;
  var cjk = 0;
  var letters = 0;
  for (final rune in raw.runes) {
    if ((rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0x31F0 && rune <= 0x31FF) ||
        (rune >= 0xFF66 && rune <= 0xFF9D)) {
      hasKana = true;
      letters++;
    } else if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F)) {
      hasHangul = true;
      letters++;
    } else if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0xF900 && rune <= 0xFAFF)) {
      cjk++;
      letters++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xC0 && rune <= 0x24F) ||
        (rune >= 0x0400 && rune <= 0x04FF)) {
      letters++;
    }
  }
  if (hasKana || hasHangul) return true;
  if (letters == 0) return false;
  return cjk / letters < 0.3;
}

/// 主播名是否需要翻译(用户口径 2026-09-20):**韩文名要翻,英文名不翻**。
///
/// 规则与正文判定([needsChineseTranslation])不同——名字是专有名词,
/// 英文/中文名保留原样;仅含谚文(韩,soop 主播)或假名(日)的名字转中文。
bool needsNameTranslation(String raw) {
  for (final rune in raw.runes) {
    final isHangul =
        (rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F);
    final isKana =
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0x31F0 && rune <= 0x31FF) ||
        (rune >= 0xFF66 && rune <= 0xFF9D);
    if (isHangul || isKana) return true;
  }
  return false;
}

/// 翻译引擎:把一段文本译为简体中文;失败返回 null(内部吞掉异常,不抛出)。
abstract interface class TranslationEngine {
  Future<String?> translate(String text);
}

/// 可选批量能力:一次请求翻译多条文本(用户口径 2026-09-20:批量几个
/// 一起请求再拆分对应,显著降低请求数)。返回与 [texts] 等长的结果列表,
/// 元素 null = 该条失败;返回 null 本身 = 引擎不支持/本批失败,调用方
/// 回退逐条。
abstract interface class TranslationBatchEngine implements TranslationEngine {
  Future<List<String?>?> translateBatch(List<String> texts);
}

/// 单次批量请求的最大条数(多行合并一次 gtx 请求)。
const int kTranslationBatchSize = 12;

/// 引擎取数函数:GET [uri] 并解析 JSON 响应体(注入便于单测)。
typedef TranslationFetcher = Future<Object?> Function(Uri uri);

/// 引擎单请求正文上限:CJK 文本经公共实例约 1250 字符就到编码上限,
/// 弹幕/标题远用不满;超长直接放弃(回原文)。
const int kTranslationMaxChars = 1200;

/// 实例基地址归一:去尾斜杠,拼路径时统一单斜杠。
String _normalizeBase(String base) {
  var trimmed = base.trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

/// 宽容取字段:引擎只关心顶层字符串值,响应 Map 的具体类型不敏感。
String? _stringField(Object? data, String key) {
  if (data is! Map) return null;
  final value = data[key];
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

/// Google 网页翻译公开端点(client=gtx):无需 key,经上游代理可达且稳定
/// (内置志愿者实例 2026-09-20 实测集体失效:Cloudflare 盾/上游错误/下线),
/// 故作为首选引擎;志愿者实例降级为后备。
/// 响应形如 `[[["译文","原文",...],...],...]`,取全部分句拼接。
class GoogleWebEngine implements TranslationEngine, TranslationBatchEngine {
  GoogleWebEngine({required this.fetcher});

  final TranslationFetcher fetcher;

  static const _base = 'https://translate.googleapis.com';

  @override
  Future<String?> translate(String text) async {
    if (text.length > kTranslationMaxChars) return null;
    final uri = Uri.parse(
      '$_base/translate_a/single'
      '?client=gtx&sl=auto&tl=zh-CN&dt=t&q=${Uri.encodeComponent(text)}',
    );
    final data = await fetcher(uri);
    if (data is! List || data.isEmpty) return null;
    final sentences = data.first;
    if (sentences is! List) return null;
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      if (sentence is List && sentence.isNotEmpty && sentence.first is String) {
        buffer.write(sentence.first);
      }
    }
    final translated = buffer.toString();
    return translated.isEmpty ? null : translated;
  }

  /// 批量:多行合并为一次 gtx 请求(Google 按行分段返回,行数可一一对应);
  /// 合并体超长/行数不齐时返回 null,调用方回退逐条。
  @override
  Future<List<String?>?> translateBatch(List<String> texts) async {
    if (texts.isEmpty) return const [];
    if (texts.any((t) => t.length > kTranslationMaxChars)) return null;
    final joined = texts.join('\n');
    if (joined.length > kTranslationMaxChars) return null;
    final uri = Uri.parse(
      '$_base/translate_a/single'
      '?client=gtx&sl=auto&tl=zh-CN&dt=t&q=${Uri.encodeComponent(joined)}',
    );
    final data = await fetcher(uri);
    if (data is! List || data.isEmpty) return null;
    final sentences = data.first;
    if (sentences is! List) return null;
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      if (sentence is List && sentence.isNotEmpty && sentence.first is String) {
        buffer.write(sentence.first);
      }
    }
    final lines = buffer.toString().split('\n');
    if (lines.length != texts.length) return null;
    return [for (final line in lines) line.trim().isEmpty ? null : line.trim()];
  }
}

/// Lingva 引擎:`GET {base}/api/v1/auto/zh/{text}` → `{"translation": ...}`。
class LingvaEngine implements TranslationEngine {
  LingvaEngine({required this.bases, required this.fetcher});

  /// 实例基地址(按序 failover)。
  final List<String> bases;
  final TranslationFetcher fetcher;

  @override
  Future<String?> translate(String text) async {
    if (text.length > kTranslationMaxChars || bases.isEmpty) return null;
    for (final rawBase in bases) {
      final base = _normalizeBase(rawBase);
      if (base.isEmpty) continue;
      try {
        final uri = Uri.parse(
          '$base/api/v1/auto/zh/${Uri.encodeComponent(text)}',
        );
        final value = _stringField(await fetcher(uri), 'translation');
        if (value != null) return value;
      } catch (_) {
        // 实例失败试下一个;全部失败返回 null(上层回退原文/下一引擎)。
      }
    }
    return null;
  }
}

/// SimplyTranslate 引擎:
/// `GET {base}/api?engine=google&lang=auto&tl=zh-CN&text=...`
/// → `{"translated-text": ...}`。
class SimplyTranslateEngine implements TranslationEngine {
  SimplyTranslateEngine({required this.bases, required this.fetcher});

  final List<String> bases;
  final TranslationFetcher fetcher;

  @override
  Future<String?> translate(String text) async {
    if (text.length > kTranslationMaxChars || bases.isEmpty) return null;
    for (final rawBase in bases) {
      final base = _normalizeBase(rawBase);
      if (base.isEmpty) continue;
      try {
        final root = Uri.parse(base);
        final apiPath = '${root.path}/api'.replaceFirst(RegExp(r'^//'), '/');
        final uri = root.replace(
          path: apiPath,
          queryParameters: {
            'engine': 'google',
            'lang': 'auto',
            'tl': 'zh-CN',
            'text': text,
          },
        );
        final value = _stringField(await fetcher(uri), 'translated-text');
        if (value != null) return value;
      } catch (_) {
        // 同 Lingva:逐实例 failover。
      }
    }
    return null;
  }
}

/// 队列中的待翻译任务。
class _PendingTranslation {
  _PendingTranslation({
    required this.key,
    required this.display,
    required this.completer,
  });

  /// 缓存/请求键(trim 后文本)。
  final String key;

  /// 失败回退展示文本(未 trim 原文)。
  final String display;
  final Completer<String> completer;
}

/// 翻译协调器:缓存 + 节流队列 + 引擎 failover 的应用级单例。
///
/// 生命周期由 riverpod provider 管理([dispose] 在 provider 销毁时调用);
/// 引擎列表构造时注入,自定义实例地址变更走 provider 重建(缓存随之
/// 清空,属可接受的一次性代价)。
class TranslationCoordinator {
  TranslationCoordinator({
    required this.engines,
    this.maxConcurrent = 2,
    this.minInterval = const Duration(milliseconds: 300),
    this.requestTimeout = const Duration(seconds: 6),
    // 批量翻译(8 条/请求)后吞吐提升,队列上限同步放大:洪峰弹幕
    // 少丢一轮(超过仍丢最旧回原文,保延迟)。
    this.maxQueue = 256,
    this.cacheCapacity = 1024,
    this.failureTtl = const Duration(minutes: 2),
  });

  /// 引擎按序 failover;公开为只读字段便于测试断言注入。
  final List<TranslationEngine> engines;
  final int maxConcurrent;
  final Duration minInterval;
  final Duration requestTimeout;
  final int maxQueue;
  final int cacheCapacity;
  final Duration failureTtl;

  /// LRU 译文缓存(LinkedHashMap:尾=最近使用,头=最旧可淘汰)。
  final LinkedHashMap<String, String> _cache = LinkedHashMap();

  /// 失败负缓存:text → 可重试时刻。
  final Map<String, DateTime> _failures = {};

  /// 在途去重:同一文本并发请求合并为一个 Future。
  final Map<String, Future<String>> _inflight = {};

  final List<_PendingTranslation> _queue = [];
  int _active = 0;
  DateTime _nextSlot = DateTime.now();

  /// 节流槽排程 Timer(一次性):到点续跑 [_pump];dispose 时取消,
  /// 避免在 fake-async 测试/快速重建场景残留 pending Timer。
  Timer? _slotTimer;
  bool _disposed = false;

  /// 翻译一段文本;失败/无需翻译时原样返回,Future 永不抛错。
  Future<String> translate(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !needsChineseTranslation(trimmed)) {
      return Future.value(text);
    }
    final cached = _lookup(trimmed);
    if (cached != null) return Future.value(cached);
    final inflight = _inflight[trimmed];
    if (inflight != null) return inflight;
    if (_disposed) return Future.value(text);

    // 队列满:丢最旧(高峰期宁可早到的回原文,不放大整体延迟)。
    while (_queue.length >= maxQueue) {
      _queue.removeAt(0).completer.complete(text);
    }
    final completer = Completer<String>();
    final future = completer.future;
    _inflight[trimmed] = future;
    unawaited(future.whenComplete(() => _inflight.remove(trimmed)));
    _queue.add(
      _PendingTranslation(key: trimmed, display: text, completer: completer),
    );
    // 聚合同一事件循环内的入队(用户口径 2026-09-20 批量翻译):零延迟
    // Timer 让同批弹幕/标题攒成一个批量请求;已有排程时不重复。
    _schedulePump();
    return future;
  }

  /// 翻译弹幕正文:文本段逐段翻、表情段原样保留。
  ///
  /// 返回与输入「段数对应」的结果;内容无变化时返回与输入相等的列表
  /// (segments 具备值相等),调用方据此跳过替换。segments 为空时退化为
  /// 整条 [text] 翻译(无变化返回空列表)。
  Future<List<DanmakuSegment>> translateBody({
    required String text,
    List<DanmakuSegment> segments = const [],
  }) async {
    if (segments.isEmpty) {
      if (!needsChineseTranslation(text)) return const [];
      final translated = await translate(text);
      if (translated == text) return const [];
      return [DanmakuSegment.text(translated)];
    }
    final out = <DanmakuSegment>[];
    var changed = false;
    for (final segment in segments) {
      if (segment.isEmoji || !needsChineseTranslation(segment.text)) {
        out.add(segment);
        continue;
      }
      final translated = await translate(segment.text);
      if (translated == segment.text) {
        out.add(segment);
      } else {
        out.add(DanmakuSegment.text(translated));
        changed = true;
      }
    }
    return changed ? out : segments;
  }

  /// provider 销毁:未出队任务全部回退原文,防泄漏。
  void dispose() {
    _disposed = true;
    _slotTimer?.cancel();
    _slotTimer = null;
    for (final job in _queue) {
      if (!job.completer.isCompleted) job.completer.complete(job.display);
    }
    _queue.clear();
    _inflight.clear();
  }

  /// 命中返回译文;负缓存期内返回原文(调用方直接回退,不入队);
  /// 都没有返回 null。
  String? _lookup(String key) {
    final retryAt = _failures[key];
    if (retryAt != null) {
      if (DateTime.now().isBefore(retryAt)) return key;
      _failures.remove(key);
    }
    final hit = _cache[key];
    if (hit != null) {
      // LRU touch:重插到尾部。
      _cache.remove(key);
      _cache[key] = hit;
    }
    return hit;
  }

  /// 聚合排程:零延迟 Timer 聚合同批入队后一次批量派发;已有排程不重复。
  /// dispose 时随 _slotTimer 一并取消,无残留。
  void _schedulePump() {
    if (_slotTimer != null || _disposed) return;
    _slotTimer = Timer(Duration.zero, () {
      _slotTimer = null;
      _pump();
    });
  }

  /// 派发循环:能立即派发的当场发;未到节流槽则排一次性 Timer 到点续跑。
  ///
  /// 不用「循环内 await delay」——那种长挂 await 在测试结束校验里是
  /// pending Timer;一次性 Timer 随 [dispose] 取消,无残留。
  void _pump() {
    if (_disposed || _slotTimer != null) return;
    while (!_disposed && _queue.isNotEmpty && _active < maxConcurrent) {
      final now = DateTime.now();
      final wait = _nextSlot.difference(now);
      if (wait <= Duration.zero) {
        // 批量派发(用户口径 2026-09-20):一次请求翻译多条再拆分对应,
        // 显著降低请求数。一个批占用一个节流槽/一个并发名额。
        final batch = <_PendingTranslation>[];
        while (_queue.isNotEmpty && batch.length < kTranslationBatchSize) {
          batch.add(_queue.removeAt(0));
        }
        _active++;
        _nextSlot = now.add(minInterval);
        unawaited(_runBatch(batch));
        continue;
      }
      _slotTimer = Timer(wait, () {
        _slotTimer = null;
        _pump();
      });
      return;
    }
  }

  Future<void> _run(_PendingTranslation job) async {
    var result = job.display;
    try {
      final translated = await _translateViaEngines(job.key)
          .timeout(requestTimeout);
      if (translated != null) {
        result = translated;
        _cachePut(job.key, translated);
      } else {
        _failures[job.key] = DateTime.now().add(failureTtl);
      }
    } catch (_) {
      _failures[job.key] = DateTime.now().add(failureTtl);
    } finally {
      _active--;
      if (!job.completer.isCompleted) job.completer.complete(result);
      _pump();
    }
  }

  /// 批量执行:优先走引擎批量能力(GoogleWeb 多行合并一次请求);
  /// 引擎不支持/整批失败 → 逐条回退([_run]);个别条目失败记负缓存。
  /// 每条独立缓存,completer 逐条完成。
  Future<void> _runBatch(List<_PendingTranslation> batch) async {
    if (batch.length == 1) {
      _active--;
      await _run(batch.single);
      _pump();
      return;
    }
    final results = List<String?>.filled(batch.length, null);
    try {
      for (final engine in engines) {
        if (engine is! TranslationBatchEngine) continue;
        final out = await engine
            .translateBatch(batch.map((job) => job.key).toList())
            .timeout(requestTimeout);
        if (out != null && out.length == batch.length) {
          for (var i = 0; i < out.length; i++) {
            results[i] = out[i];
          }
          break;
        }
      }
    } catch (_) {
      // 批量失败:保持 null,下方逐条回退。
    }
    for (var i = 0; i < batch.length; i++) {
      final job = batch[i];
      final translated = results[i];
      var result = job.display;
      if (translated != null && translated.trim().isNotEmpty) {
        result = translated;
        _cachePut(job.key, translated);
      } else {
        // 该条批量失败:逐条重试一次(与旧行为等价),仍失败记负缓存。
        try {
          final single = await _translateViaEngines(job.key)
              .timeout(requestTimeout);
          if (single != null) {
            result = single;
            _cachePut(job.key, single);
          } else {
            _failures[job.key] = DateTime.now().add(failureTtl);
          }
        } catch (_) {
          _failures[job.key] = DateTime.now().add(failureTtl);
        }
      }
      if (!job.completer.isCompleted) job.completer.complete(result);
    }
    _active--;
    _pump();
  }

  Future<String?> _translateViaEngines(String text) async {
    for (final engine in engines) {
      final out = await engine.translate(text);
      if (out != null && out.trim().isNotEmpty) return out;
    }
    return null;
  }

  void _cachePut(String key, String value) {
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
  }
}
