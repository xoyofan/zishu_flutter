import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 斗鱼**钻粉 suffix 默认款**图 URL（钻石图形，右侧叠加在粉丝牌后）。
///
/// 即官网钻粉配置 `inter_com_w_diamond_fans.json` → `data.diamond_list['1']
/// .web_medal_pic`（2024-03 上线至今未变）。用户消息携带 `diafid` 且装扮表
/// 有对应条目时改用装扮款（见 [DouyuFansMedalConfig.diamondSuffixUrl]）。
const String kDouyuDiamondFanSuffixUrl =
    'https://sta-op.douyucdn.cn/dygev/2024/03/29/6ab5daa5255a43c34b70347977051a90.png';

/// 斗鱼**钻粉 suffix 主播装扮表**（`inter_com_w_anchor_rights.json`）。
///
/// chatmsg `diafid` → `data.list[diafid].webPic`（`vswitch.web==1` 才启用）。
/// 条目是主播购买/活动的「钻粉发言后缀」装扮，如 126/127→中秋钻粉活动、
/// 100085→常驻千钻尾拖（2026-09-27 房间 96555 实测三款均按此渲染）。
const String kDouyuAnchorRightsUrl =
    'https://wconf.douyucdn.cn/resource/common/config/inter_com_w_anchor_rights.json';

/// 斗鱼粉丝牌样式资产(与官网 web `dy-fan-medal` lit 组件**同源配置**)。
///
/// 官网 2024 起的粉丝牌不再是单张烘焙 PNG,而是四层组合:
/// 1. 背景图:等级按 5 级一档分桶(`bg_{level}` → `com_bg_{bucket}`),桶名
///    经 `bgPics` 映射到 `sta-op.douyucdn.cn` 完整 URL;`lbg_*` 是大图
///    (周年庆 suffix 场景);
/// 2. 前缀图:房间自定义徽记,`fansMedals[].room_ids_v2` 按**房间号**
///    (弹幕协议 `brid`)匹配,URL 在 `resource.webHdPic`;
/// 3. 等级数字:组件内嵌的 per-level 小图(每级一张,编译进 CSS,web 独有);
/// 4. 团名:白色 12px 文本(web `.name`)。
///
/// 配置单一来源:`https://wconf.douyucdn.cn/resource/common/fans_medal_web_v5.json`
/// (从官网 `lit-web-components-master` bundle 里 `aA.MEDAL` 注册表确证,
/// 2026-09-27 房间 96555 实测)。
///
/// 用法:UI 先 `await DouyuFansMedalAssets.instance.get()`,拿到的
/// [DouyuFansMedalConfig] 提供 [DouyuFansMedalConfig.backdropUrl] /
/// [DouyuFansMedalConfig.prefixUrl]。加载失败返回 null,调用方回落旧渲染。
class DouyuFansMedalConfig {
  const DouyuFansMedalConfig({
    required this.backdropByLevel,
    required this.largeBackdropByLevel,
    required this.prefixByRoomId,
    this.diamondIconByDiafid = const {},
  });

  /// level → 普通背景图 URL(`commBg['bg_{lv}']` → `bgPics[key]`)。
  final Map<int, String> backdropByLevel;

  /// level → 大图背景 URL(`commBg['lbg_{lv}']`,周年庆 suffix 用)。
  final Map<int, String> largeBackdropByLevel;

  /// 房间号(`brid`)→ 房间自定义前缀图 URL(`fansMedals` 反转索引)。
  final Map<int, String> prefixByRoomId;

  /// 钻粉 suffix 装扮 id(`diafid`)→ web 图 URL(`anchor_rights.list[].webPic`)。
  final Map<int, String> diamondIconByDiafid;

  /// 粉丝牌背景图 URL;等级无对应桶(理论上不会,commBg 覆盖 0..61+)返回 null。
  String? backdropUrl(int level, {bool large = false}) {
    if (level < 0) return null;
    final map = large ? largeBackdropByLevel : backdropByLevel;
    return map[level];
  }

  /// 房间自定义前缀图 URL;该房间无定制前缀返回 null。
  String? prefixUrl(int? brid) {
    if (brid == null || brid <= 0) return null;
    return prefixByRoomId[brid];
  }

  /// 钻粉 suffix 图 URL:有 `diafid` 且装扮表命中返回装扮款(动图 webp),
  /// 否则 null(UI 回落 [kDouyuDiamondFanSuffixUrl] 默认款)。
  String? diamondSuffixUrl(int? diafid) {
    if (diafid == null || diafid <= 0) return null;
    return diamondIconByDiafid[diafid];
  }
}

/// 解析 v5 配置 JSON 的 `data` 字段(纯函数,可离线单测)。
///
/// 实测样本(2026-09-27):
/// ```
/// data.commBg = {"bg_0": "com_bg_0", "bg_1": "com_bg_1", ..., "bg_12": "com_bg_11", ...}
/// data.bgPics = {"com_bg_0": "https://sta-op.douyucdn.cn/...", ...}
/// data.fansMedals = [{"t":"3", "resource":{"webHdPic":"https://.../x.webp"},
///                     "room_ids_v2": {"941266": 1, ...}}, ...]
/// ```
DouyuFansMedalConfig? parseDouyuFansMedalConfig(Map<String, Object?>? data) {
  if (data == null) return null;
  final commBg = _stringMap(data['commBg']);
  final bgPics = _stringMap(data['bgPics']);
  if (commBg == null || bgPics == null) return null;

  String? resolve(String? bucket) {
    if (bucket == null || bucket.isEmpty) return null;
    final url = bgPics[bucket];
    return (url == null || url.isEmpty) ? null : url;
  }

  final backdrop = <int, String>{};
  final largeBackdrop = <int, String>{};
  commBg.forEach((key, bucket) {
    final match = RegExp(r'^(l?bg)_(\d+)$').firstMatch(key);
    if (match == null) return;
    final url = resolve(bucket);
    if (url == null) return;
    final level = int.tryParse(match.group(2)!);
    if (level == null) return;
    if (match.group(1) == 'lbg') {
      largeBackdrop[level] = url;
    } else {
      backdrop[level] = url;
    }
  });

  final prefixByRoomId = <int, String>{};
  final fansMedals = data['fansMedals'];
  if (fansMedals is List) {
    for (final entry in fansMedals) {
      if (entry is! Map) continue;
      final resource = entry['resource'];
      final prefix = resource is Map
          ? (resource['webHdPic'] as String?)
          : null;
      if (prefix == null || prefix.isEmpty) continue;
      final roomIds = entry['room_ids_v2'];
      if (roomIds is! Map) continue;
      roomIds.forEach((roomId, flag) {
        // room_ids_v2 的 value 语义未确证(实测全为 1),非 0 视为生效。
        if (flag == null || '$flag' == '0') return;
        final rid = int.tryParse('$roomId'.trim());
        if (rid != null && rid > 0) prefixByRoomId[rid] = prefix;
      });
    }
  }

  if (backdrop.isEmpty) return null;
  return DouyuFansMedalConfig(
    backdropByLevel: Map.unmodifiable(backdrop),
    largeBackdropByLevel: Map.unmodifiable(largeBackdrop),
    prefixByRoomId: Map.unmodifiable(prefixByRoomId),
  );
}

Map<String, String>? _stringMap(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, String>{};
  raw.forEach((key, value) {
    if (value == null) return;
    out['$key'] = '$value';
  });
  return out;
}

/// 解析钻粉 suffix 装扮表(`inter_com_w_anchor_rights.json` 的 `data`,纯函数)。
///
/// 实测样本(2026-09-27):
/// ```
/// data.list = {"126": {"id":126, "btype":"wsj2023", "desc":"中秋钻粉活动-1",
///   "webPic":"https://sta-op.douyucdn.cn/dygev/.../092bacff....webp",
///   "vswitch": {"ios":"", "android":"", "web":1, "pc":1}}, ...}
/// ```
/// 只收 `webPic` 非空且 `vswitch.web == 1` 的条目。
Map<int, String> parseDouyuDiamondSuffixIcons(Map<String, Object?>? data) {
  final out = <int, String>{};
  if (data == null) return out;
  final list = data['list'];
  if (list is! Map) return out;
  list.forEach((key, entry) {
    if (entry is! Map) return;
    final vswitch = entry['vswitch'];
    if (vswitch is! Map || '${vswitch['web'] ?? ''}' != '1') return;
    final pic = entry['webPic'];
    if (pic is! String || pic.isEmpty) return;
    final id = int.tryParse('$key'.trim());
    if (id != null && id > 0) out[id] = pic;
  });
  return out;
}

/// 配置加载器:内存缓存 + TTL + 单飞(single-flight)。
///
/// - 无文件缓存:配置 ~110KB,一次进房拉一次即可,内存 TTL 内复用;
/// - 加载失败不抛异常,返回 null(UI 回落旧渲染),并允许下次重试;
/// - [reset] 供测试隔离。
class DouyuFansMedalAssets {
  DouyuFansMedalAssets._();

  static final DouyuFansMedalAssets instance = DouyuFansMedalAssets._();

  static const String configUrl =
      'https://wconf.douyucdn.cn/resource/common/fans_medal_web_v5.json';

  /// 缓存 TTL。官网每次页面加载都拉一次;我们按会话级缓存,6 小时过期。
  static const Duration ttl = Duration(hours: 6);

  /// 装扮表拉取失败后的重试退避:失败不该把「空表」当成功缓存 6 小时
  /// (2026-09-27 教训:并行拉取任一失败 → 全会话回落默认款,用户观感
  /// 「钻粉图标全是一种样式」),短退避后下次 [get] 立即重试。
  static const Duration _iconsRetryBackoff = Duration(minutes: 1);

  DouyuFansMedalConfig? _config;
  DateTime _loadedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<DouyuFansMedalConfig?>? _inflight;

  /// 装扮表(diafid → 图)独立缓存:null = 尚未成功拉取(允许重试)。
  Map<int, String>? _icons;
  DateTime _iconsLoadedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _iconsFailedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<Map<int, String>?>? _iconsInflight;

  /// 主配置 + 装扮表的合并结果缓存(按 [_mergedIcons] 身份失效)。
  DouyuFansMedalConfig? _merged;
  Map<int, String>? _mergedIcons;

  final http.Client _client = http.Client();

  /// 当前配置(过期/未加载时触发拉取)。失败返回 null。
  ///
  /// 主配置与装扮表**各自独立缓存**;装扮表失败只降级空表(默认款)且
  /// 不污染主配置,退避后自动重试。
  Future<DouyuFansMedalConfig?> get() async {
    final main = await _getMain();
    if (main == null) return null;
    final icons = await _getIcons();
    if (icons == null || icons.isEmpty) return main;
    // 合并结果按 icons 实例身份缓存,避免每次 get() 重建对象。
    if (_merged != null && identical(icons, _mergedIcons)) return _merged;
    _merged = DouyuFansMedalConfig(
      backdropByLevel: main.backdropByLevel,
      largeBackdropByLevel: main.largeBackdropByLevel,
      prefixByRoomId: main.prefixByRoomId,
      diamondIconByDiafid: icons,
    );
    _mergedIcons = icons;
    return _merged;
  }

  Future<DouyuFansMedalConfig?> _getMain() {
    final now = DateTime.now();
    final cached = _config;
    if (cached != null && now.difference(_loadedAt) < ttl) {
      return Future.value(cached);
    }
    return _inflight ??= _fetchMain().whenComplete(() => _inflight = null);
  }

  Future<Map<int, String>?> _getIcons() {
    final now = DateTime.now();
    final cached = _icons;
    if (cached != null && now.difference(_iconsLoadedAt) < ttl) {
      return Future.value(cached);
    }
    if (now.difference(_iconsFailedAt) < _iconsRetryBackoff) {
      return Future.value(_icons);
    }
    return _iconsInflight ??=
        _fetchIcons().whenComplete(() => _iconsInflight = null);
  }

  Future<DouyuFansMedalConfig?> _fetchMain() async {
    try {
      final response = await _client
          .get(Uri.parse(configUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final config = parseDouyuFansMedalConfig(decoded is Map
          ? (decoded['data'] as Map<String, Object?>?)
          : null);
      if (config != null) {
        _config = config;
        _loadedAt = DateTime.now();
      }
      return config;
    } catch (_) {
      return null;
    }
  }

  Future<Map<int, String>?> _fetchIcons() async {
    try {
      final response = await _client
          .get(Uri.parse(kDouyuAnchorRightsUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        _iconsFailedAt = DateTime.now();
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final icons = parseDouyuDiamondSuffixIcons(decoded is Map
          ? (decoded['data'] as Map<String, Object?>?)
          : null);
      // 空表也视为成功(配置端无任何启用装扮是合法状态),按 TTL 缓存。
      _icons = icons;
      _iconsLoadedAt = DateTime.now();
      return icons;
    } catch (_) {
      _iconsFailedAt = DateTime.now();
      return null;
    }
  }

  /// 清缓存(测试用)。
  void reset() {
    _config = null;
    _loadedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _inflight = null;
    _icons = null;
    _iconsLoadedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _iconsFailedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _iconsInflight = null;
    _merged = null;
    _mergedIcons = null;
  }
}
