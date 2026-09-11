/// 平台「解析 → 播放」耗时基准工具。
///
/// 口径:
/// - 选房:browse 拉到首个可解析在播房(最多试 4 个),选房耗时不计入解析;
/// - 解析:resolveRoom 连测 3 轮取中位数,同时按 host+path 聚合所有 HTTP
///   请求耗时(通过注入计时的 http.Client,无需改动包内代码);
/// - 播放就绪:对首选线路做首字节探测(HLS=清单+首分片,FLV=首包 TTFB),
///   近似 media_kit 打开媒体的网络等待。
///
/// 用法(在 packages/live_parser 下):
///   dart run tool/benchmark_platforms.dart --out ../../benchmark.md
///   dart run tool/benchmark_platforms.dart douyu soop youtube
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/bilibili_site.dart';
import 'package:live_parser/src/platforms/douyu/douyu_site.dart';
import 'package:live_parser/src/platforms/huya/huya_site.dart';
import 'package:live_parser/src/platforms/twitch/twitch_site.dart';

const List<String> _defaultSites = [
  'douyu',
  'huya',
  'bilibili',
  'douyin',
  'yy',
  'twitch',
  'kuaishou',
  'soop',
  'youtube',
];

const int _resolveRounds = 3;

/// 无 browse 结果时的兜底样例房间(仅为不同环境可跑,可能离线)。
const Map<String, String> _fallbackRooms = {
  'douyu': '9999',
  'huya': '660000',
  'bilibili': '6',
  'yy': '1414787909',
  'twitch': 'shroud',
  'soop': 'khm11903',
};

/// 计分轮的偏好档:与 app `effectiveDefaultQuality` 一致
/// (platformDefaultQuality 优先,其余回落全局默认「超清」)。
/// 懒取流的平台只解析该档;解析器内 60s 结果缓存也以它为缓存键。
const Map<String, String> _preferredQualities = {
  'douyu': '超清',
  'huya': '超清',
  'bilibili': '超清',
  'douyin': '超清',
  'yy': '超清',
  'twitch': '720p',
  'kuaishou': '超清',
  'soop': '高清',
  'youtube': '720p',
};

/// 各平台的非 HTTP 阶段说明(报告里标出,便于定位优化点)。
const Map<String, String> _nonHttpNotes = {
  'douyin': 'a_bogus 签名(SM3+RC4,纯 CPU)在每次带签请求前计算;cookie 引导(300s TTL)',
  'youtube': 'yt-dlp 子进程(含 Deno/EJS;提取结果与地址链校验 60s 实例缓存)+ master/变体/首分片三段预校验;解析优先 dlp;结果 20s 缓存',
  'soop': '房间详情/档位 60s 缓存;偏好档懒取流(其余档空线路占位);瞬时错误短重试',
  'kuaishou': '房间页 HTML 解析(__INITIAL_STATE__),feed 弹幕不走解析链路',
  'bilibili': 'WBI 签名 nav/finger 并行;get_info 已带主播名/头像时跳过 anchor;anchor 与 play_info 并行',
  'huya': 'anti-code(Tars 编码,纯 CPU);页面与 profile 并行,web-stream 两段',
  'douyu': '白名单加密 md5 auth(TTL 缓存);偏好档懒取流(未命中才全档并行);播放接口响应 60s 缓存',
  'yy': 'detail + gear1 探测(命中偏好档时直接复用响应);未命中全档并行',
  'twitch': 'GQL POST + playback access token(元数据/token 并行);直播结果 20s 缓存',
};

class HttpTiming {
  const HttpTiming({
    required this.method,
    required this.url,
    required this.ms,
    this.status,
    this.error,
  });

  final String method;
  final Uri url;
  final int ms;
  final int? status;
  final String? error;

  String get key => '${url.host}${url.path}';
}

/// 计时 http.Client:完整记录请求(含读取 body)耗时。
class TimingHttpClient extends http.BaseClient {
  TimingHttpClient(this._inner);

  final http.Client _inner;
  final List<HttpTiming> records = [];

  void reset() => records.clear();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      final controller = StreamController<List<int>>();
      response.stream.listen(
        controller.add,
        onError: (Object error) {
          records.add(
            HttpTiming(
              method: request.method,
              url: request.url,
              ms: stopwatch.elapsedMilliseconds,
              error: '$error',
            ),
          );
          controller.addError(error);
        },
        onDone: () {
          records.add(
            HttpTiming(
              method: request.method,
              url: request.url,
              ms: stopwatch.elapsedMilliseconds,
              status: response.statusCode,
            ),
          );
          controller.close();
        },
        cancelOnError: true,
      );
      return http.StreamedResponse(
        controller.stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on Object catch (error) {
      records.add(
        HttpTiming(
          method: request.method,
          url: request.url,
          ms: stopwatch.elapsedMilliseconds,
          error: '$error',
        ),
      );
      rethrow;
    }
  }
}

class RoundResult {
  const RoundResult({required this.ms, required this.ok, required this.note});

  final int ms;
  final bool ok;
  final String note;
}

class PlatformReport {
  PlatformReport(this.site);

  final String site;
  final List<RoundResult> resolveRounds = [];
  final List<int> warmRounds = [];
  final List<HttpTiming> lastRecords = [];
  String roomId = '';
  String title = '';
  String state = '';
  String? error;
  List<String> qualities = const [];
  int? streamReadyMs;
  String streamDetail = '';
  String streamUrl = '';
  int? dlpMs;
  String? skipReason;

  int? get warmMedianMs {
    final values = [...warmRounds]..sort();
    if (values.isEmpty) return null;
    return values[values.length ~/ 2];
  }

  int? get medianMs {
    final values = resolveRounds
        .where((round) => round.ok)
        .map((round) => round.ms)
        .toList()
      ..sort();
    if (values.isEmpty) return null;
    return values[values.length ~/ 2];
  }

  int? get minMs {
    final values = resolveRounds
        .where((round) => round.ok)
        .map((round) => round.ms)
        .toList()
      ..sort();
    return values.isEmpty ? null : values.first;
  }

  int? get maxMs {
    final values = resolveRounds
        .where((round) => round.ok)
        .map((round) => round.ms)
        .toList()
      ..sort();
    return values.isEmpty ? null : values.last;
  }
}

Future<void> main(List<String> args) async {
  final sites = <String>[];
  String? outPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out') {
      if (i + 1 < args.length) outPath = args[++i];
      continue;
    }
    if (!args[i].startsWith('--')) sites.add(args[i]);
  }
  final effectiveSites = sites.isEmpty ? _defaultSites : sites;

  final reports = <PlatformReport>[];
  for (final site in effectiveSites) {
    stdout.writeln('=== benchmarking $site ...');
    final report = await _benchmarkSite(site);
    reports.add(report);
    stdout.writeln(
      '    resolve=${report.medianMs ?? "-"}ms '
      'streamReady=${report.streamReadyMs ?? "-"}ms '
      'state=${report.state} err=${report.error ?? "-"}',
    );
  }

  final markdown = _renderMarkdown(reports);
  if (outPath != null) {
    File(outPath).writeAsStringSync(markdown);
    stdout.writeln('written: $outPath');
  } else {
    stdout.writeln(markdown);
  }
}

Future<PlatformReport> _benchmarkSite(String site) async {
  final report = PlatformReport(site);
  final registration = _buildRegistration(site);
  if (registration == null) {
    report.skipReason = '未注册/暂不支持注入 httpClient';
    return report;
  }

  final candidates = await _pickCandidates(registration, site);
  if (candidates.isEmpty) {
    report.skipReason = 'browse 未取到在播房间';
    return report;
  }
  report.roomId = candidates.first;

  // 先选出一个可解析在播房(不计分)。
  String? chosen;
  for (final candidate in candidates.take(4)) {
    try {
      final probePayload = await registration.resolver.resolveRoom(
        RoomRequest(site: site, roomIdOrUrl: candidate),
      );
      if (probePayload.isLive) {
        chosen = candidate;
        report.roomId = candidate;
        report.title = probePayload.title;
        report.state = probePayload.roomState.name;
        report.error = probePayload.error;
        report.qualities = probePayload.availableQualities
            .map((quality) => quality.name)
            .toList();
        break;
      }
    } on Object catch (error) {
      report.error = '$error';
    }
  }
  if (chosen == null) {
    report.state = 'offline';
    report.error ??= '无可解析在播房';
    return report;
  }

  // 预热(不进样本):连接池/DNS/签名缓存等一次性噪声。
  try {
    await registration.resolver.resolveRoom(
      RoomRequest(site: site, roomIdOrUrl: chosen),
    );
  } on Object {
    // 预热失败不影响计分轮。
  }

  RoomPayload? livePayload;
  final preferredQuality = _preferredQualities[site];
  for (var round = 0; round < _resolveRounds; round++) {
    final timing = TimingHttpClient(http.Client());
    final roundRegistration = _buildRegistration(site, httpClient: timing)!;
    final stopwatch = Stopwatch()..start();
    try {
      final payload = await roundRegistration.resolver.resolveRoom(
        RoomRequest(
          site: site,
          roomIdOrUrl: chosen,
          preferredQuality: preferredQuality,
        ),
      );
      stopwatch.stop();
      report.resolveRounds.add(
        RoundResult(ms: stopwatch.elapsedMilliseconds, ok: true, note: ''),
      );
      report.lastRecords
        ..clear()
        ..addAll(timing.records);
      if (payload.isLive) {
        livePayload = payload;
        report.state = payload.roomState.name;
        report.title = payload.title;
        report.error = payload.error;
        report.qualities = payload.availableQualities
            .map((quality) => quality.name)
            .toList();
      }
    } on Object catch (error) {
      stopwatch.stop();
      report.resolveRounds.add(
        RoundResult(
          ms: stopwatch.elapsedMilliseconds,
          ok: false,
          note: '$error',
        ),
      );
    }
  }
  if (livePayload == null) return report;

  /// 热解析(同一实例连续解析):验证 60s 结果缓存(带偏好档)/ soop 档位 60s /
  /// twitch,youtube 20s 缓存 与 HTTP 连接复用收益。
  final warmRegistration = _buildRegistration(site);
  if (warmRegistration != null) {
    for (var round = 0; round < 3; round++) {
      final stopwatch = Stopwatch()..start();
      try {
        await warmRegistration.resolver.resolveRoom(
          RoomRequest(
            site: site,
            roomIdOrUrl: chosen,
            preferredQuality: preferredQuality,
          ),
        );
      } on Object {
        // 热轮失败不计入缓存收益,仅记录耗时。
      }
      stopwatch.stop();
      report.warmRounds.add(stopwatch.elapsedMilliseconds);
    }
  }

  // 播放就绪探测。
  final line = livePayload.streams.isEmpty
      ? null
      : livePayload.streams.first.preferredLine;
  if (line != null) {
    report.streamUrl = line.url;
    final probe = await _probeStream(line);
    report.streamReadyMs = probe.ms;
    report.streamDetail = probe.detail;
  }

  // YouTube:单独量化 yt-dlp 子进程耗时(解析里的一部分)。
  if (site == 'youtube') {
    final dlpStopwatch = Stopwatch()..start();
    final extract = await extractYoutubeViaDlp(report.roomId);
    dlpStopwatch.stop();
    if (extract != null) report.dlpMs = dlpStopwatch.elapsedMilliseconds;
  }
  return report;
}

SiteRegistration? _buildRegistration(String site, {http.Client? httpClient}) {
  switch (site) {
    case 'douyu':
      return buildDouyuRegistration(httpClient: httpClient);
    case 'huya':
      return buildHuyaRegistration(httpClient: httpClient);
    case 'bilibili':
      return buildBilibiliRegistration(httpClient: httpClient);
    case 'douyin':
      return buildDouyinRegistration(httpClient: httpClient);
    case 'yy':
      return buildYyRegistration(httpClient: httpClient);
    case 'twitch':
      return buildTwitchRegistration(httpClient: httpClient);
    case 'kuaishou':
      return buildKuaishouRegistration(httpClient: httpClient);
    case 'soop':
      return buildSoopRegistration(httpClient: httpClient);
    case 'youtube':
      return buildYoutubeRegistration(httpClient: httpClient);
    default:
      return null;
  }
}

Future<List<String>> _pickCandidates(
  SiteRegistration registration,
  String site,
) async {
  final candidates = <String>[];
  try {
    final request = switch (site) {
      'huya' => const RoomListRequest(site: 'huya', cid: '1', limit: 10),
      'youtube' => const RoomListRequest(site: 'youtube', cid: 'live', limit: 10),
      _ => RoomListRequest(site: site, limit: 10),
    };
    final result = await registration.browse!.fetchRooms(request);
    for (final room in result.rooms) {
      if (room.roomId.trim().isNotEmpty) candidates.add(room.roomId);
    }
  } on Object {
    // 浏览失败用兜底房间。
  }
  final fallback = _fallbackRooms[site];
  if (candidates.isEmpty && fallback != null && fallback.isNotEmpty) {
    candidates.add(fallback);
  }
  return candidates;
}

Future<({int? ms, String detail})> _probeStream(StreamLine line) async {
  final headers = <String, String>{
    'User-Agent': kDefaultParserUserAgent,
    ...line.headers,
  };
  final client = http.Client();
  final stopwatch = Stopwatch()..start();
  try {
    if (line.format == 'hls' || line.url.contains('.m3u8')) {
      var target = line.url;
      var content = await _readText(client, target, headers);
      if (content.contains('#EXT-X-STREAM-INF')) {
        final variant = _firstUri(content, target);
        if (variant.isEmpty) {
          return (ms: stopwatch.elapsedMilliseconds, detail: 'hls master only');
        }
        target = variant;
        content = await _readText(client, target, headers);
      }
      final segment = _firstUri(content, target);
      if (segment.isEmpty) {
        return (ms: stopwatch.elapsedMilliseconds, detail: 'hls playlist only');
      }
      final code = await _firstChunk(client, segment, headers);
      return (
        ms: code >= 400 ? null : stopwatch.elapsedMilliseconds,
        detail: 'hls playlist+segment${code >= 400 ? ' HTTP $code' : ''}',
      );
    }
    final code = await _firstChunk(client, line.url, headers);
    return (
      ms: code >= 400 ? null : stopwatch.elapsedMilliseconds,
      detail: 'flv first bytes${code >= 400 ? ' HTTP $code' : ''}',
    );
  } on Object catch (error) {
    return (ms: null, detail: 'probe error: $error');
  } finally {
    client.close();
  }
}

Future<String> _readText(
  http.Client client,
  String url,
  Map<String, String> headers,
) async {
  final response = await client.get(Uri.parse(url), headers: headers);
  if (response.statusCode >= 400) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  return utf8.decode(response.bodyBytes);
}

Future<int> _firstChunk(
  http.Client client,
  String url,
  Map<String, String> headers,
) async {
  final request = http.Request('GET', Uri.parse(url))
    ..headers.addAll({...headers, 'Range': 'bytes=0-2048'});
  final response = await client.send(request);
  if (response.statusCode < 400) {
    await response.stream.first;
  }
  return response.statusCode;
}

String _firstUri(String content, String base) {
  for (final raw in const LineSplitter().convert(content)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    return Uri.parse(base).resolve(line).toString();
  }
  return '';
}

String _renderMarkdown(List<PlatformReport> reports) {
  final buffer = StringBuffer();
  buffer.writeln('# 平台「解析 → 播放」耗时基准');
  buffer.writeln();
  buffer.writeln('- 生成时间: ${DateTime.now().toString().substring(0, 19)}');
  buffer.writeln(
    '- 环境: Windows 桌面(本机网络,含透明代理;绝对值仅供同环境对比,跨网络需重跑)',
  );
  buffer.writeln(
    '- 方法: browse 选首个可解析在播房 → 计分轮带 app 平台默认偏好档'
    '(soop 高清 / twitch,youtube 720p / 其余超清),`resolveRoom` 预热 1 次 + '
    '计分 3 次取中位;「热解析」= 同一实例连续解析 3 次中位(带偏好档的 60s '
    '结果缓存与连接复用)',
  );
  buffer.writeln(
    '- HTTP 请求耗时经注入的计时 `http.Client` 按 `host+path` 聚合(仅最后一轮冷解析)',
  );
  buffer.writeln(
    '- 播放就绪:首选线路首字节探测(HLS = 清单/变体 + 首分片 TTFB;FLV = 首包 TTFB),近似播放器打开等待',
  );
  buffer.writeln();
  buffer.writeln('## 总览');
  buffer.writeln();
  buffer.writeln(
    '| 平台 | 状态 | 解析中位(ms) | 最快/最慢(ms) | 热解析中位(ms) | 播放就绪(ms) | 房号 | 档位 |',
  );
  buffer.writeln('|---|---|---:|---|---:|---:|---|---|');
  for (final report in reports) {
    final state = report.skipReason != null
        ? 'SKIP'
        : (report.state.isEmpty ? '-' : report.state);
    final min = report.minMs;
    final max = report.maxMs;
    final range = min == null || max == null ? '-' : '$min / $max';
    buffer.writeln(
      '| ${report.site} | $state | ${report.medianMs ?? '-'} | $range | '
      '${report.warmMedianMs ?? '-'} | ${report.streamReadyMs ?? '-'} | ${report.roomId} | '
      '${report.qualities.isEmpty ? '-' : report.qualities.join("/")} |',
    );
  }
  buffer.writeln();
  final failed = reports
      .where((report) => report.medianMs == null && report.skipReason != null)
      .toList();
  if (failed.isNotEmpty) {
    buffer.writeln('跳过:');
    for (final report in failed) {
      buffer.writeln('- ${report.site}: ${report.skipReason}');
    }
    buffer.writeln();
  }

  buffer.writeln('## 各平台请求耗时分布(最后一轮解析)');
  for (final report in reports) {
    if (report.lastRecords.isEmpty) continue;
    buffer.writeln();
    buffer.writeln(
      '### ${report.site} · 偏好档 ${_preferredQualities[report.site] ?? '-'}',
    );
    buffer.writeln();
    buffer.writeln('| 请求 (host+path) | 次数 | 总耗时(ms) | 均值(ms) | 状态 |');
    buffer.writeln('|---|---:|---:|---:|---|');
    final grouped = <String, List<HttpTiming>>{};
    for (final record in report.lastRecords) {
      grouped.putIfAbsent(record.key, () => []).add(record);
    }
    final keys = grouped.keys.toList()
      ..sort(
        (a, b) => grouped[b]!
            .fold<int>(0, (sum, item) => sum + item.ms)
            .compareTo(grouped[a]!.fold<int>(0, (sum, item) => sum + item.ms)),
      );
    for (final key in keys) {
      final items = grouped[key]!;
      final total = items.fold<int>(0, (sum, item) => sum + item.ms);
      final errors = items.where((item) => item.error != null).length;
      buffer.writeln(
        '| $key | ${items.length} | $total | ${(total / items.length).round()} | '
        '${errors > 0 ? '$errors 失败' : 'OK'} |',
      );
    }
    if (report.resolveRounds.isNotEmpty) {
      final failedRounds = report.resolveRounds
          .where((round) => !round.ok)
          .toList();
      if (failedRounds.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('失败轮次:');
        for (final round in failedRounds) {
          buffer.writeln('- ${round.ms}ms: ${round.note}');
        }
      }
    }
    final note = _nonHttpNotes[report.site];
    if (note != null) {
      buffer.writeln();
      buffer.writeln('非 HTTP 阶段: $note');
    }
    if (report.dlpMs != null) {
      buffer.writeln();
      buffer.writeln('yt-dlp `-J` 单独耗时: ${report.dlpMs}ms(已含在解析中位数内)');
    }
    if (report.streamUrl.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        '播放探测: ${report.streamDetail} — '
        '`${report.streamUrl.length > 100 ? '${report.streamUrl.substring(0, 100)}...' : report.streamUrl}`',
      );
    }
  }
  return buffer.toString();
}
