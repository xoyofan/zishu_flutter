/// YY 房间详情与播放地址 API。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/header_sanitizer.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';

const String kYySource = 'live_parser/yy';
const String kYyStreamSdkVersion = '5.23.0-beta.2';
const List<String> kYyMobileHlsRates = ['1200', '4000'];

/// YY 媒体流(HLS/FLV)请求头:CDN 以 Referer/Origin 做防盗链,
/// 与解析请求头(YyClient.defaultHeaders)同源。
final Map<String, String> yyPlaybackHeaders = sanitizeHeaders(const {
  'origin': 'https://www.yy.com',
  'referer': 'https://www.yy.com/',
});

class YyRoomDetail {
  const YyRoomDetail({
    required this.sid,
    required this.ssid,
    required this.name,
    required this.desc,
    required this.thumb,
    required this.avatar,
    required this.users,
    required this.uid,
    required this.biz,
    required this.totalViewer,
    required this.startTime,
  });

  final String sid;
  final String ssid;
  final String name;
  final String desc;
  final String thumb;
  final String avatar;
  final String users;
  final String uid;
  final String biz;

  /// 开播中为格式化热度串(如 "145.9万"),未开播恒为空。
  ///
  /// 注意:`users` 与 `totalViewer` 是两个字段 —— 在播判定以 [totalViewer]
  /// 为准(口径对齐 web follow/status.ts;users 在部分场景恒有值,不能当
  /// 在播判据)。
  final String totalViewer;
  final int startTime;

  DateTime? get startedAt => startTime > 0
      ? DateTime.fromMillisecondsSinceEpoch(startTime * 1000)
      : null;
}

class YyRoomDetailResult {
  const YyRoomDetailResult({this.detail, required this.notFound});

  final YyRoomDetail? detail;
  final bool notFound;

  bool get isOffline => detail == null && !notFound;
}

class YyQuality {
  const YyQuality({required this.name, required this.gear});

  final String name;
  final int gear;
}

/// 查询 YY 房间详情。
///
/// `resultCode=0,data=null` 是合法的离线房间响应；非 0 或 HTTP 404
/// 则视为不存在/不可识别，交由 resolver 输出 notFound。
Future<YyRoomDetailResult> fetchYyRoomDetail(
  ParserHttp http,
  String sid,
) async {
  final url = Uri.parse('https://www.yy.com/api/liveInfoDetail/$sid/$sid/0');
  try {
    final response = await http.get(url, headers: const {
      'Accept': 'application/json, */*',
      'Origin': 'https://www.yy.com',
    });
    final json = http.jsonMap(response);
    final resultCode = jsonInt(json['resultCode']);
    if (resultCode != 0) return const YyRoomDetailResult(notFound: true);
    final item = jsonMapOf(json['data']);
    if (item.isEmpty) return const YyRoomDetailResult(notFound: false);

    final topSid = jsonInt(item['sid']) == 0 ? sid : jsonText(item['sid']);
    final subSid = jsonInt(item['ssid']) == 0 ? topSid : jsonText(item['ssid']);
    return YyRoomDetailResult(
      notFound: false,
      detail: YyRoomDetail(
        sid: topSid,
        ssid: subSid,
        name: jsonText(item['name']),
        desc: jsonText(item['desc']),
        thumb: httpsYyUrl(item['thumb2'] ?? item['thumb']),
        avatar: httpsYyUrl(item['avatar']),
        users: jsonText(item['users']),
        uid: jsonText(item['uid']),
        biz: jsonText(item['biz']),
        totalViewer: jsonText(item['totalViewer']),
        startTime: jsonInt(item['startTime']),
      ),
    );
  } on ParserHttpException catch (error) {
    if (error.statusCode == 404) {
      return const YyRoomDetailResult(notFound: true);
    }
    rethrow;
  } on FormatException {
    return const YyRoomDetailResult(notFound: true);
  }
}

/// 请求 stream-manager 的某个 gear。
Future<Map<String, dynamic>?> fetchYyStreamObject(
  ParserHttp http,
  String sid,
  int gear,
) async {
  final sequence = DateTime.now().millisecondsSinceEpoch;
  final body = <String, dynamic>{
    'head': {
      'seq': sequence,
      'appidstr': '0',
      'bidstr': '121',
      'cidstr': sid,
      'sidstr': sid,
      'uid64': 0,
      'client_type': 108,
      'client_ver': kYyStreamSdkVersion,
      'stream_sys_ver': 1,
      'app': 'yylive_web',
      'playersdk_ver': kYyStreamSdkVersion,
      'thundersdk_ver': '0',
      'streamsdk_ver': kYyStreamSdkVersion,
    },
    'client_attribute': {
      'client': 'web',
      'model': 'web0',
      'cpu': '',
      'graphics_card': '',
      'os': 'chrome',
      'osversion': '128.0.0.0',
      'vsdk_version': '',
      'app_identify': '',
      'app_version': '',
      'business': '',
      'width': '1366',
      'height': '768',
      'scale': '',
      'client_type': 8,
      'h265': 0,
    },
    'avp_parameter': {
      'version': 1,
      'client_type': 8,
      'service_type': 0,
      'imsi': 0,
      'send_time': sequence ~/ 1000,
      'line_seq': -1,
      'gear': gear,
      'ssl': 1,
      'stream_format': 0,
    },
  };
  final query = <String, String>{
    'uid': '0',
    'cid': sid,
    'sid': sid,
    'appid': '0',
    'sequence': '$sequence',
    'encode': 'json',
  };
  final uri = Uri.https('stream-manager.yy.com', '/v3/channel/streams', query);
  try {
    final response = await http.postJson(
      uri,
      body: body,
      headers: {
        'Accept': 'application/json, */*',
        'Origin': 'https://www.yy.com',
        'Referer': 'https://www.yy.com/$sid/$sid',
        'Content-Type': 'text/plain;charset=UTF-8',
      },
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on ParserHttpException {
    return null;
  } on FormatException {
    return null;
  }
}

/// 从 stream-manager 响应中提取清晰度，按首次出现顺序去重；同名保留高 gear。
List<YyQuality> parseYyQualities(Object? payload) {
  final root = jsonMapOf(payload);
  final streams = jsonListOf(jsonMapOf(root['channel_stream_info'])['streams']);
  final result = <YyQuality>[];
  final indexes = <String, int>{};
  for (final raw in streams) {
    final item = jsonMapOf(raw);
    final text = jsonText(item['json']).trim();
    if (text.isEmpty) continue;
    try {
      final decoded = jsonDecode(text);
      final gearInfo = jsonMapOf(decoded is Map ? decoded['gear_info'] : null);
      final name = jsonText(gearInfo['name']).trim();
      final gear = int.tryParse(jsonText(gearInfo['gear']).trim());
      if (name.isEmpty || gear == null) continue;
      final index = indexes[name];
      if (index == null) {
        indexes[name] = result.length;
        result.add(YyQuality(name: name, gear: gear));
      } else if (gear > result[index].gear) {
        result[index] = YyQuality(name: name, gear: gear);
      }
    } on FormatException {
      // 单条损坏的 gear 信息不影响其它档位。
    }
  }
  return result;
}

/// 从 stream-manager 响应中提取去重后的 CDN 地址。
List<String> parseYyPlayUrls(Object? payload) {
  final root = jsonMapOf(payload);
  final addresses = jsonMapOf(jsonMapOf(root['avp_info_res'])['stream_line_addr']);
  final result = <String>[];
  for (final value in addresses.values) {
    final url = httpsYyUrl(jsonMapOf(value)['cdn_info'] is Map
        ? jsonMapOf(jsonMapOf(value)['cdn_info'])['url']
        : null);
    if (url.isEmpty || !url.startsWith('http')) continue;
    if (!result.contains(url)) result.add(url);
  }
  return result;
}

/// 移动 HLS 回退，接口返回 JSON 或 JSONP 风格文本。
Future<String> fetchYyMobileHls(
  ParserHttp http,
  String sid,
  String rate,
) async {
  final uri = Uri.https(
    'interface.yy.com',
    '/hls/new/get/$sid/$sid/$rate',
    const {'source': 'wapyy', 'callback': ''},
  );
  try {
    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json, */*',
        'Origin': 'https://www.yy.com',
        'Referer': 'https://wap.yy.com/mobileweb/$sid/$sid',
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1',
      },
    );
    final text = utf8.decode(response.bodyBytes);
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end < start) return '';
    final decoded = jsonDecode(text.substring(start, end + 1));
    final value = jsonMapOf(decoded);
    if (jsonInt(value['code']) != 0) return '';
    final hls = httpsYyUrl(value['hls']);
    return hls.startsWith('http') && hls != '404' ? hls : '';
  } on ParserHttpException catch (_) {
    return '';
  } on FormatException catch (_) {
    return '';
  }
}

Future<List<YyQuality>> fetchYyQualities(ParserHttp http, String sid) async =>
    (await fetchYyQualitiesWithProbe(http, sid)).qualities;

/// 取档位列表,并带回探测用的原始响应(gear=1)。
///
/// 原始响应里的 `stream_line_addr` 就是 gear=1 档的线路,解析侧命中该档时
/// 可直接复用,省掉一次 stream-manager POST。
Future<({List<YyQuality> qualities, Object? probePayload})>
fetchYyQualitiesWithProbe(ParserHttp http, String sid) async {
  final object = await fetchYyStreamObject(http, sid, 1);
  final qualities = parseYyQualities(object);
  if (qualities.isNotEmpty) return (qualities: qualities, probePayload: object);

  final fallback = <YyQuality>[];
  for (final rate in kYyMobileHlsRates) {
    if ((await fetchYyMobileHls(http, sid, rate)).isEmpty) continue;
    fallback.add(
      YyQuality(
        name: rate == kYyMobileHlsRates.first ? '流畅' : '高清',
        gear: int.parse(rate),
      ),
    );
  }
  return (qualities: fallback, probePayload: null);
}

Future<StreamQuality?> buildYyTier(
  ParserHttp http,
  String sid,
  YyQuality quality, {
  Object? prefetched,
}) async {
  final object = prefetched ?? await fetchYyStreamObject(http, sid, quality.gear);
  final urls = parseYyPlayUrls(object);
  if (urls.isNotEmpty) {
    return StreamQuality(
      name: quality.name,
      rate: quality.gear,
      lines: [
        for (final url in urls)
          StreamLine(
            name: '线路',
            url: url,
            format: url.toLowerCase().contains('.m3u8') ? 'hls' : 'flv',
            headers: yyPlaybackHeaders,
          ),
      ],
    );
  }

  final fallbackRate = quality.gear >= 2000 ? '4000' : '1200';
  final hls = await fetchYyMobileHls(http, sid, fallbackRate);
  if (hls.isEmpty) return null;
  return StreamQuality(
    name: quality.name,
    rate: quality.gear,
    lines: [
      StreamLine(
        name: '线路',
        url: hls,
        format: 'hls',
        headers: yyPlaybackHeaders,
      ),
    ],
  );
}
