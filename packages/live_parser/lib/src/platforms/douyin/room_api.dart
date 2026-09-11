/// 抖音房间解析:PC web `enter` 接口(a_bogus 签名)+ 房间页 HTML 回退。
library;

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'ab_sign.dart';
import 'normalize.dart';

/// enter 接口「暂不可查看」业务码。
const int kDouyinStatusCodeUnviewable = 4001038;

/// 质量 key -> 中文名(与 SFVideoLive 对齐)。
const Map<String, String> kDouyinQualityLabels = {
  'ORIGIN': '原画',
  'FULL_HD1': '蓝光',
  'uhd': '蓝光',
  'hd': '超清',
  'HD1': '超清',
  'sd': '高清',
  'SD1': '高清',
  'SD2': '流畅',
  'ld': '流畅',
};

/// 质量排序(索引越小档位越高)。
const List<String> kDouyinQualityOrder = [
  'ORIGIN',
  'FULL_HD1',
  'uhd',
  'HD1',
  'hd',
  'SD1',
  'sd',
  'SD2',
  'ld',
];

/// 播放请求统一 Referer(CDN 防盗链)。
const Map<String, String> kDouyinPlayHeaders = {
  'Referer': 'https://live.douyin.com/',
};

/// 抖音底层客户端:持有会话 cookie(__ac_nonce/ttwid 引导,300s 缓存)。
class DouyinClient {
  DouyinClient({http.Client? httpClient, this.cookieOverride = ''})
    : parserHttp = ParserHttp(
        client: httpClient,
        defaultHeaders: const {'Referer': 'https://live.douyin.com/'},
      );

  final ParserHttp parserHttp;

  /// 外部注入的 cookie(优先级高于自动引导,便于带登录态)。
  final String cookieOverride;

  String _cookie = '';
  DateTime? _cookieAt;
  static const Duration _cookieTtl = Duration(seconds: 300);

  /// 获取会话 cookie:有覆盖用覆盖,否则请求首页收集 Set-Cookie。
  Future<String> sessionCookie({bool force = false}) async {
    final override = cookieOverride.trim();
    if (override.isNotEmpty) return override;
    final at = _cookieAt;
    if (!force &&
        _cookie.isNotEmpty &&
        at != null &&
        DateTime.now().difference(at) < _cookieTtl) {
      return _cookie;
    }
    final seed =
        '__ac_nonce=${_randomHex(21)}; odin_tt=${_randomHex(160)}';
    try {
      final response = await parserHttp.get(
        Uri.parse('https://live.douyin.com/'),
        headers: {
          'User-Agent': kDouyinUserAgent,
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': 'https://live.douyin.com/',
          'Cookie': seed,
        },
      );
      final collected = _setCookieValues(response.headers['set-cookie']);
      _cookie = collected.length > 1 ? collected.join('; ') : seed;
    } on Object {
      _cookie = seed;
    }
    _cookieAt = DateTime.now();
    return _cookie;
  }

  /// 请求房间页 HTML。
  Future<String> fetchRoomPage(String webRid, {String? cookie}) async {
    final response = await parserHttp.get(
      Uri.parse(douyinSourceUrl(webRid)),
      headers: douyinPcHeaders(
        referer: douyinSourceUrl(webRid),
        cookie: cookie ?? _cookie,
      ),
    );
    return utf8.decode(response.bodyBytes);
  }
}

String _randomHex(int length) {
  const chars = '0123456789abcdef';
  final random = Random.secure();
  return String.fromCharCodes(
    Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(16))),
  );
}

List<String> _setCookieValues(String? header) {
  if (header == null || header.trim().isEmpty) return const [];
  final result = <String>[];
  for (final part in header.split(RegExp(r',(?=[^;,=\s]+=)'))) {
    final pair = part.split(';').first.trim();
    if (pair.contains('=')) result.add(pair);
  }
  return result;
}

bool _isRiskControlBody(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ||
      trimmed.startsWith('<!DOCTYPE') ||
      trimmed.startsWith('<html');
}

/// 拉取房间数据:enter 两次尝试(第二次强制刷新 cookie),失败回退房间页。
Future<Map<String, dynamic>> fetchDouyinWebStreamData(
  DouyinClient client,
  String webRid,
) async {
  Object? lastError;
  for (var attempt = 0; attempt <= 1; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    try {
      final cookie = await client.sessionCookie(force: attempt > 0);
      return await _fetchEnterRoomData(client, webRid, cookie);
    } catch (error) {
      lastError = error;
      final message = error.toString();
      final retryable =
          message.contains('风控') ||
          message.contains('服务繁忙') ||
          message.contains('请稍后重试') ||
          message.contains('非 JSON') ||
          message.contains('获取失败') ||
          message.contains('HTTP 444');
      if (!retryable) break;
    }
  }

  try {
    final cookie = await client.sessionCookie();
    final html = await client.fetchRoomPage(webRid, cookie: cookie);
    final room = parseDouyinRoomDataFromHtml(html, webRid);
    if (jsonInt(room['status']) != 4) normalizeDouyinLiveStreamData(room);
    return room;
  } on Object catch (pageError) {
    throw ParserHttpException(
      lastError?.toString() ?? pageError.toString(),
    );
  }
}

Future<Map<String, dynamic>> _fetchEnterRoomData(
  DouyinClient client,
  String webRid,
  String cookie,
) async {
  final params = <MapEntry<String, String>>[
    const MapEntry('aid', '6383'),
    const MapEntry('app_name', 'douyin_web'),
    const MapEntry('live_id', '1'),
    const MapEntry('device_platform', 'web'),
    const MapEntry('language', 'zh-CN'),
    const MapEntry('enter_from', 'web_live'),
    const MapEntry('cookie_enabled', 'true'),
    const MapEntry('screen_width', '1920'),
    const MapEntry('screen_height', '1080'),
    const MapEntry('browser_language', 'zh-CN'),
    const MapEntry('browser_platform', 'Win32'),
    const MapEntry('browser_name', 'Chrome'),
    const MapEntry('browser_version', '141.0.0.0'),
    MapEntry('web_rid', webRid),
    const MapEntry('is_need_double_stream', 'false'),
    MapEntry('msToken', randomDouyinMsToken()),
  ];
  final query = serializeDouyinQuery(params);
  final abogus = douyinAbSign(query, kDouyinUserAgent);
  final uri = Uri.parse(
    'https://live.douyin.com/webcast/room/web/enter/'
    '?$query&a_bogus=${Uri.encodeComponent(abogus)}',
  );
  final response = await client.parserHttp.get(
    uri,
    headers: douyinPcHeaders(
      referer: douyinSourceUrl(webRid),
      cookie: cookie,
    ),
  );
  final text = utf8.decode(response.bodyBytes);
  if (_isRiskControlBody(text)) {
    throw const ParserHttpException('抖音接口触发风控');
  }

  final Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('非对象 JSON');
    json = Map<String, dynamic>.from(decoded);
  } on FormatException {
    throw const ParserHttpException('抖音接口返回非 JSON');
  }

  final payload = jsonMapOf(json['data']);
  final list = jsonListOf(payload['data']);
  if (list.isEmpty) {
    final prompt = jsonText(payload['prompts']).isNotEmpty
        ? jsonText(payload['prompts'])
        : jsonText(payload['message']);
    if (jsonInt(json['status_code']) == kDouyinStatusCodeUnviewable ||
        prompt.contains('无法查看')) {
      throw ParserHttpException(prompt.isEmpty ? '该直播间暂不可查看' : prompt);
    }
    throw ParserHttpException(prompt.isEmpty ? '抖音房间信息获取失败' : prompt);
  }

  final room = Map<String, dynamic>.from(list.first as Map);
  final userNick = jsonText(jsonMapOf(payload['user'])['nickname']);
  final ownerNick = jsonText(jsonMapOf(room['owner'])['nickname']);
  final anchor = userNick.isNotEmpty ? userNick : ownerNick;
  if (anchor.isNotEmpty) room['anchor_name'] = anchor;
  room['live_url'] = douyinSourceUrl(webRid);
  if (jsonInt(room['status']) != 4) normalizeDouyinLiveStreamData(room);
  return room;
}

/// 竖屏 pull_datas / origin 流数据归一(补齐 flv_pull_url / hls_pull_url_map)。
void normalizeDouyinLiveStreamData(Map<String, dynamic> room) {
  final streamUrl = jsonMapOf(room['stream_url']);
  if (streamUrl.isEmpty) return;
  _applyPortraitPullDatas(streamUrl);
  if (_stringMapOf(streamUrl['flv_pull_url']).isEmpty) {
    _mergeOriginStreams(streamUrl);
  }
}

void _applyPortraitPullDatas(Map<String, dynamic> streamUrl) {
  if (jsonInt(streamUrl['stream_orientation']) != 2) return;
  final pullDatas = jsonMapOf(streamUrl['pull_datas']);
  if (pullDatas.isEmpty) return;
  final first = jsonMapOf(pullDatas.values.first);
  final streamData = jsonText(first['stream_data']);
  if (streamData.isEmpty) return;

  final Object? decoded;
  try {
    decoded = jsonDecode(streamData);
  } on FormatException {
    return;
  }
  final data = jsonMapOf(jsonMapOf(decoded)['data']);
  if (data.isEmpty) return;

  final flv = <String, String>{};
  final hls = <String, String>{};
  for (final entry in data.entries) {
    final main = jsonMapOf(jsonMapOf(entry.value)['main']);
    final flvUrl = jsonText(main['flv']).trim();
    final hlsUrl = jsonText(main['hls']).trim();
    if (flvUrl.isNotEmpty) flv[entry.key] = flvUrl;
    if (hlsUrl.isNotEmpty) hls[entry.key] = hlsUrl;
  }
  if (flv.isNotEmpty) streamUrl['flv_pull_url'] = flv;
  if (hls.isNotEmpty) streamUrl['hls_pull_url_map'] = hls;
}

void _mergeOriginStreams(Map<String, dynamic> streamUrl) {
  final pullData = jsonMapOf(jsonMapOf(streamUrl['live_core_sdk_data'])['pull_data']);
  final streamData = jsonText(pullData['stream_data']);
  if (streamData.isEmpty) return;

  final Object? decoded;
  try {
    decoded = jsonDecode(streamData);
  } on FormatException {
    return;
  }
  final origin = jsonMapOf(jsonMapOf(jsonMapOf(decoded)['data'])['origin']);
  final main = jsonMapOf(origin['main']);
  final hls = jsonText(main['hls']).trim();
  final flv = jsonText(main['flv']).trim();
  final codec = _parseSdkParamsCodec(main['sdk_params']);

  final hlsMap = _stringMapOf(streamUrl['hls_pull_url_map']);
  final flvMap = _stringMapOf(streamUrl['flv_pull_url']);
  if (hls.isNotEmpty && !hlsMap.containsKey('ORIGIN')) {
    hlsMap['ORIGIN'] = '$hls&codec=$codec';
  }
  if (flv.isNotEmpty && !flvMap.containsKey('ORIGIN')) {
    flvMap['ORIGIN'] = '$flv&codec=$codec';
  }
  streamUrl['hls_pull_url_map'] = hlsMap;
  streamUrl['flv_pull_url'] = flvMap;
}

String _parseSdkParamsCodec(Object? value) {
  if (value is Map) return jsonText(value['VCodec']);
  final text = jsonText(value).trim();
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    return decoded is Map ? jsonText(decoded['VCodec']) : '';
  } on FormatException {
    return '';
  }
}

/// 从房间页 HTML(转义 JSON)解析房间数据;拿不到时抛 [FormatException]。
Map<String, dynamic> parseDouyinRoomDataFromHtml(String html, String webRid) {
  if (!html.contains(r'\"flv_pull_url\":{')) {
    throw const FormatException('抖音房间页未解析到流地址');
  }
  final flv = extractDouyinEscapedUrlMap(html, 'flv_pull_url');
  final hls = extractDouyinEscapedUrlMap(html, 'hls_pull_url_map');
  if (flv.isEmpty && hls.isEmpty) {
    throw const FormatException('抖音房间页未解析到流地址');
  }
  final flvIdx = html.indexOf(r'\"flv_pull_url\":{');
  final status = jsonInt(_lastGroupBefore(html, flvIdx, RegExp(r'\\"status\\":(\d+)')));
  final title = _lastGroupBefore(html, flvIdx, RegExp(r'\\"title\\":\\"([^"\\]+)\\"'));
  final nickname = _lastGroupBefore(html, flvIdx, RegExp(r'\\"nickname\\":\\"([^"\\]+)\\"'));
  final gameTagName = _lastGroupBefore(
    html,
    flvIdx,
    RegExp(r'\\"game_tag_name\\":\\"([^"\\]+)\\"'),
  );
  final gameTagId = _lastGroupBefore(
    html,
    flvIdx,
    RegExp(r'\\"game_tag_id\\":(\d+|\\"[^"\\]+\\")'),
  );
  final categoryName = _lastGroupBefore(
    html,
    flvIdx,
    RegExp(r'\\"category_name\\":\\"([^"\\]+)\\"'),
  );
  final idStr = _lastGroupBefore(html, flvIdx, RegExp(r'\\"id_str\\":\\"(\d+)\\"'));

  final room = <String, dynamic>{
    'status': status,
    'title': title,
    'anchor_name': nickname,
    'owner': {'nickname': nickname},
    'live_url': douyinSourceUrl(webRid),
    'stream_url': {'flv_pull_url': flv, 'hls_pull_url_map': hls},
  };
  if (idStr.isNotEmpty) room['id_str'] = idStr;
  if (categoryName.isNotEmpty) room['category_name'] = categoryName;
  if (gameTagName.isNotEmpty || gameTagId.isNotEmpty) {
    room['game_data'] = {
      'game_tag_info': {
        'game_tag_name': gameTagName,
        'game_tag_id': gameTagId.replaceAll('"', ''),
      },
    };
  }
  return room;
}

/// 提取转义 JSON 里的 `<KEY>":"<url>"` 映射(如 flv_pull_url)。
///
/// 只在 marker 对应的 `{...}` 对象内匹配,避免 12k 窗口把后续
/// `hls_pull_url_map` 的同名 key(如 ORIGIN)串进 flv 映射。
Map<String, String> extractDouyinEscapedUrlMap(String html, String key) {
  final marker = '\\"$key\\":{';
  final index = html.indexOf(marker);
  if (index < 0) return const {};
  final openIndex = index + marker.length - 1;
  final closeIndex = _closingBraceIndex(html, openIndex);
  final window = html.substring(openIndex, closeIndex + 1);
  final regex = RegExp(
    r'\\"([A-Z0-9_]+)\\":\\"'
    r'((?:https?:\\/\\/|http:\\/\\/)[^"\\]*(?:\\u0026[^"\\]*)*)\\"',
  );
  final result = <String, String>{};
  for (final match in regex.allMatches(window)) {
    final name = match.group(1) ?? '';
    var url = match.group(2) ?? '';
    if (name.isEmpty || url.isEmpty) continue;
    url = url.replaceAll(r'\u0026', '&').replaceAll(r'\/', '/');
    result[name] = url;
  }
  return result;
}

int _closingBraceIndex(String text, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < text.length; i++) {
    final ch = text[i];
    if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  return text.length - 1;
}

String _lastGroupBefore(String html, int index, RegExp regex) {
  var result = '';
  for (final match in regex.allMatches(html)) {
    if (match.start >= index) break;
    result = match.group(1) ?? '';
  }
  return result;
}

/// 构建画质档位:key 并集,按固定顺序排;HLS 优先为 preferredLine。
List<StreamQuality> buildDouyinTiers(Map<String, dynamic> room) {
  final streamUrl = jsonMapOf(room['stream_url']);
  final flvMap = _stringMapOf(streamUrl['flv_pull_url']);
  final hlsMap = _stringMapOf(streamUrl['hls_pull_url_map']);
  final keys = <String>{
    ...flvMap.keys,
    ...hlsMap.keys,
  }.where((key) => (flvMap[key]?.isNotEmpty ?? false) || (hlsMap[key]?.isNotEmpty ?? false)).toList();
  if (keys.isEmpty) return const [];
  keys.sort((a, b) {
    final ai = kDouyinQualityOrder.indexOf(a);
    final bi = kDouyinQualityOrder.indexOf(b);
    return (ai < 0 ? 999 : ai) - (bi < 0 ? 999 : bi);
  });

  final tiers = <StreamQuality>[];
  for (final key in keys) {
    final lines = <StreamLine>[];
    final hls = hlsMap[key] ?? '';
    final flv = flvMap[key] ?? '';
    if (hls.isNotEmpty) {
      lines.add(StreamLine(name: 'HLS', url: hls, format: 'hls', headers: kDouyinPlayHeaders));
    }
    if (flv.isNotEmpty) {
      lines.add(StreamLine(name: 'FLV', url: flv, format: 'flv', headers: kDouyinPlayHeaders));
    }
    tiers.add(
      StreamQuality(
        name: kDouyinQualityLabels[key] ?? key,
        rate: keys.length - tiers.length,
        lines: lines,
      ),
    );
  }
  return tiers;
}

/// 房间在线人数原始值(展示时走 [formatOnlineCount])。
Object? douyinOnlineRaw(Map<String, dynamic> room) {
  final viewStats = jsonMapOf(room['room_view_stats']);
  final display = viewStats['display_value'];
  if (display is num && display > 0) return display;
  final stats = jsonMapOf(room['stats']);
  final countStr = jsonText(stats['user_count_str']);
  if (countStr.isNotEmpty && countStr != '0') return countStr;
  final count = room['user_count'];
  if (count is num && count > 0) return count;
  final fallback = jsonText(room['user_count_str']);
  return fallback.isNotEmpty ? fallback : countStr;
}

/// 房间分类名(游戏标签优先,其次 category_name / 分区)。
String douyinCategoryOf(Map<String, dynamic> room) {
  final tagInfo = jsonMapOf(jsonMapOf(room['game_data'])['game_tag_info']);
  final tag = jsonText(tagInfo['game_tag_name']).trim();
  if (tag.isNotEmpty) return tag;
  final category = jsonText(room['category_name']).trim();
  if (category.isNotEmpty) return category;
  final partition = jsonMapOf(room['partition_road_map']);
  final subTitle = jsonText(jsonMapOf(partition['sub_partition'])['title']).trim();
  if (subTitle.isNotEmpty) return subTitle;
  return jsonText(jsonMapOf(partition['partition'])['title']).trim();
}

/// 房间封面(cover.url_list 首项)。
String douyinCoverOf(Map<String, dynamic> room) {
  final list = jsonListOf(jsonMapOf(room['cover'])['url_list']);
  return list.isEmpty ? '' : httpsDouyinUrl(list.first);
}

/// 主播头像(avatar_thumb / avatar_medium 首项)。
String douyinAvatarOf(Map<String, dynamic> room) {
  final owner = jsonMapOf(room['owner']);
  for (final key in const ['avatar_thumb', 'avatar_medium', 'avatar_larger']) {
    final list = jsonListOf(jsonMapOf(owner[key])['url_list']);
    if (list.isNotEmpty) {
      final url = httpsDouyinUrl(list.first);
      if (url.isNotEmpty) return url;
    }
  }
  return '';
}

/// 解析直播内部房间号(弹幕 WS 需要):id_str/id,兜底房间页正则。
Future<String> resolveDouyinInternalRoomId(
  DouyinClient client,
  String webRid,
  Map<String, dynamic> room,
) async {
  final idStr = jsonText(room['id_str']).trim();
  if (idStr.isNotEmpty) return idStr;
  final rawId = jsonText(room['id']).trim();
  if (rawId.isNotEmpty && rawId != '0') return rawId;
  try {
    final html = await client.fetchRoomPage(webRid);
    final escaped = RegExp(r'roomId\\":\\"(\d+)\\"').firstMatch(html)?.group(1);
    if (escaped != null && escaped.isNotEmpty) return escaped;
    final plain = RegExp(r'"roomId":"(\d+)"').firstMatch(html)?.group(1);
    if (plain != null && plain.isNotEmpty) return plain;
  } on Object {
    // 页面不可用时交由调用方判定。
  }
  return '';
}

Map<String, String> _stringMapOf(Object? value) {
  final map = jsonMapOf(value);
  return {
    for (final entry in map.entries) entry.key: jsonText(entry.value),
  };
}
