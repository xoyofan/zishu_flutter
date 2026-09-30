/// B 站房间信息与播放数据:get_info / getRoomPlayInfo / codec 选择与线路构建。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'wbi.dart';

const String kBilibiliSiteId = 'bilibili';

const Map<String, String> kBilibiliPcHeaders = {
  'Referer': 'https://live.bilibili.com/',
};

/// B 站 API 业务错误:code 可用于三态判定(1=房间不存在)。
class BilibiliApiException implements Exception {
  const BilibiliApiException(this.code, this.message, {this.statusCode});

  final int code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'BilibiliApiException($code): $message';
}

/// B 站清晰度档位(qn 名称与顺序与官网一致)。
const List<({int qn, String name})> kBilibiliQnTiers = [
  (qn: 10000, name: '原画'),
  (qn: 400, name: '蓝光'),
  (qn: 250, name: '超清'),
  (qn: 150, name: '高清'),
  (qn: 80, name: '流畅'),
];

String httpsBilibiliUrl(String text) {
  final value = jsonText(text);
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  return value.replaceAll('http://', 'https://');
}

/// 统一 API 基座:WBI 签名(best-effort)+ buvid3 cookie + code 检查。
/// data 可能是对象或数组(Area/getList、getRoomList 返回数组),由调用方解析。
Future<Object?> bilibiliFetchJson(
  ParserHttp http,
  BilibiliCredentials credentials,
  Uri url, {
  Map<String, String>? params,
  String? roomId,
}) async {
  var query = <String, String>{};
  var effectiveUrl = url;
  // nav(WBI 混出 key)与 finger(buvid3)互不依赖:冷启动并行取,之后命中缓存。
  final mixinKeyFuture = params == null
      ? Future<String?>.value(null)
      : credentials.fetchMixinKey(http);
  final buvid3Future = credentials.fetchBuvid3(http)..ignore();
  if (params != null) {
    final mixinKey = await mixinKeyFuture;
    if (mixinKey != null) {
      query = signWbi(
        params,
        mixinKey,
        wts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    } else {
      query = params;
    }
    effectiveUrl = url.replace(
      queryParameters: {...url.queryParameters, ...query},
    );
  }

  final buvid3 = await buvid3Future;
  // Cookie 组装:登录串在前(用户浏览器同源 buvid3 等指纹随之生效,服务器
  // 取首个同名项),匿名 buvid3 兜底在后;两者皆空则不带。
  final cookieParts = [
    if (credentials.loginCookie.isNotEmpty) credentials.loginCookie,
    if (buvid3.isNotEmpty) 'buvid3=$buvid3',
  ];
  final headers = <String, String>{
    ...kBilibiliPcHeaders,
    'Referer': roomId == null ? kBilibiliPcHeaders['Referer']! : 'https://live.bilibili.com/$roomId',
    'Origin': 'https://live.bilibili.com',
    if (cookieParts.isNotEmpty) 'Cookie': cookieParts.join('; '),
  };

  final response = await http.get(effectiveUrl, headers: headers);
  final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
  final code = payload['code'] is num ? (payload['code'] as num).toInt() : 0;
  if (code != 0) {
    throw BilibiliApiException(
      code,
      jsonText(payload['message']).isEmpty
          ? 'B 站 API 错误 $code'
          : jsonText(payload['message']),
    );
  }
  return payload['data'];
}

/// room/v1/Room/get_info。
Future<Map<String, dynamic>> fetchBilibiliRoomInfo(
  ParserHttp http,
  BilibiliCredentials credentials,
  String roomId,
) async =>
    jsonMapOf(
      await bilibiliFetchJson(
        http,
        credentials,
        Uri.parse('https://api.live.bilibili.com/room/v1/Room/get_info'),
        params: {'room_id': roomId},
        roomId: roomId,
      ),
    );

/// 主播资料兜底(UserInfo/get_anchor_in_room)。
Future<({String uname, String face})> fetchBilibiliAnchorInRoom(
  ParserHttp http,
  BilibiliCredentials credentials,
  String roomId,
) async {
  final data = jsonMapOf(
    await bilibiliFetchJson(
      http,
      credentials,
      Uri.parse('https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room'),
      params: {'roomid': roomId},
      roomId: roomId,
    ),
  );
  final info = jsonMapOf(data['info']);
  return (uname: jsonText(info['uname']), face: httpsBilibiliUrl(jsonText(info['face'])));
}

/// 大航海总人数(xlive/app-room/v2/guardTab/topList 的 `data.info.num`)。
///
/// 口径对齐 web `fetchBilibiliGuardInfo`(SFVideoLive
/// `services/streaming-server/src/resolve/bilibili/web-stream.ts:331):
/// 仅在播时查询(调用方门槛)。
///
/// **返回 `null` = 取数失败/不可用**(网络异常、上游错误、参数不足);
/// 返回 `0` = **上游确实报告一个大航海都没有**。2026-09-26 前两者都折成 0,
/// 于是「真 0 人」与「没取到」在展示层无法区分(都显示「—」);实测
/// 40 间真实房间有 38 间能取到非 0,该接口本身可用,故拆开这两种语义。
Future<int?> fetchBilibiliGuardTotal(
  ParserHttp http,
  BilibiliCredentials credentials,
  String roomId,
  int anchorUid,
) async {
  if (roomId.isEmpty || anchorUid <= 0) return null;
  try {
    final data = jsonMapOf(
      await bilibiliFetchJson(
        http,
        credentials,
        Uri.parse(
          'https://api.live.bilibili.com/xlive/app-room/v2/guardTab/topList',
        ),
        params: {
          'roomid': roomId,
          'ruid': '$anchorUid',
          'page': '1',
          'page_size': '50',
        },
        roomId: roomId,
      ),
    );
    final info = jsonMapOf(data['info']);
    // 上游错误/风控响应里没有 `info.num`(实测风控返回 `{"error":-1}`),
    // 此前 jsonInt 缺失键会折成 0,连带把「没取到」说成「一个大航海都没有」。
    if (!info.containsKey('num')) return null;
    return jsonInt(info['num']);
  } on Object {
    return null;
  }
}

/// xlive/web-room/v2/index/getRoomPlayInfo。
Future<Map<String, dynamic>> fetchBilibiliRoomPlayInfo(
  ParserHttp http,
  BilibiliCredentials credentials,
  String roomId, {
  int qn = 10000,
}) async => jsonMapOf(
  await bilibiliFetchJson(
    http,
    credentials,
    Uri.parse('https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo'),
    params: {
      'room_id': roomId,
      'protocol': '0,1',
      'format': '0,1,2',
      'codec': '0,1',
      'qn': '$qn',
      'platform': 'web',
      'ptype': '8',
    },
    roomId: roomId,
  ),
);

String _hevcLabel(Map<String, dynamic> codec) {
  final baseUrl = jsonText(codec['base_url']);
  final codecName = jsonText(codec['codec_name']);
  return baseUrl.contains('minihevc') || codecName == 'hevc' ? 'hevc' : 'avc';
}

List<Map<String, dynamic>> _listCodecsForFormat(
  Map<String, dynamic>? data,
  String protocolName,
  String formatName, {
  int? preferQn,
}) {
  final playurl = jsonMapOf(jsonMapOf(data?['playurl_info'])['playurl']);
  final streams = jsonListOf(playurl['stream']).whereType<Map<String, dynamic>>();
  final targetStream = streams.firstWhere(
    (item) => jsonText(item['protocol_name']) == protocolName,
    orElse: () => const {},
  );
  if (targetStream.isEmpty) return const [];
  final formats = jsonListOf(targetStream['format']).whereType<Map<String, dynamic>>();
  final targetFormat = formats.firstWhere(
    (item) => jsonText(item['format_name']) == formatName,
    orElse: () => const {},
  );
  if (targetFormat.isEmpty) return const [];
  final codecs = jsonListOf(targetFormat['codec'])
      .whereType<Map<String, dynamic>>()
      .where((c) => c.isNotEmpty)
      .toList();
  if (codecs.isEmpty) return const [];

  var pool = codecs;
  if (preferQn != null) {
    final matched = codecs.where((c) => _intOf(c['current_qn']) == preferQn).toList();
    if (matched.isNotEmpty) {
      pool = matched;
    } else {
      final sorted = [...codecs]..sort((a, b) => _intOf(b['current_qn']) - _intOf(a['current_qn']));
      final notAbove = sorted.where((c) => _intOf(c['current_qn']) <= preferQn).toList();
      pool = notAbove.isNotEmpty ? notAbove : sorted;
    }
  }

  return [...pool]..sort((a, b) {
    final avcDelta = _hevcLabel(a).compareTo(_hevcLabel(b));
    if (avcDelta != 0) return avcDelta;
    return _intOf(b['current_qn']) - _intOf(a['current_qn']);
  });
}

int _intOf(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

/// 拼完整播放地址:host + base_url + extra。
String? buildBilibiliPlayUrl(Map<String, dynamic> codec, [int lineIndex = 0]) {
  final urlInfos = jsonListOf(codec['url_info']).whereType<Map<String, dynamic>>().toList();
  final urlInfo = urlInfos.isNotEmpty
      ? (lineIndex < urlInfos.length ? urlInfos[lineIndex] : urlInfos.first)
      : null;
  final host = jsonText(urlInfo?['host']);
  final baseUrl = jsonText(codec['base_url']);
  final extra = jsonText(urlInfo?['extra']);
  if (host.isEmpty || baseUrl.isEmpty || extra.isEmpty) return null;
  return httpsBilibiliUrl('$host$baseUrl$extra');
}

/// codec 列表 → 去重线路(avc-0 / hevc-1 命名)。
List<StreamLineDraft> _linesFromCodecs(
  List<Map<String, dynamic>> codecs,
  String format,
) {
  final lines = <StreamLineDraft>[];
  final seen = <String>{};
  for (final codec in codecs) {
    final kind = _hevcLabel(codec);
    final urlInfos = jsonListOf(codec['url_info']);
    final count = urlInfos.isEmpty ? 1 : urlInfos.length;
    for (var index = 0; index < count; index++) {
      final url = buildBilibiliPlayUrl(codec, index);
      if (url == null || !seen.add(url)) continue;
      lines.add(StreamLineDraft(name: '$kind-$index', url: url, format: format));
    }
  }
  return lines;
}

/// 待构建线路草稿(避免直接依赖 models 的 StreamLine 以保持本模块纯数据)。
class StreamLineDraft {
  const StreamLineDraft({required this.name, required this.url, required this.format});

  final String name;
  final String url;
  final String format;
}

/// 从 playInfo 数据构建一个画质档的全部线路(HLS 在前,FLV 在后)。
List<StreamLineDraft>? bilibiliTierLines(
  Map<String, dynamic>? data,
  int qn,
) {
  final flvCodecs = _listCodecsForFormat(data, 'http_stream', 'flv', preferQn: qn);
  var hlsCodecs = _listCodecsForFormat(data, 'http_hls', 'ts', preferQn: qn);
  if (hlsCodecs.isEmpty) {
    // fmp4 挂在 http_hls 协议下(2026-09-29 对 getRoomPlayInfo 实测:
    // http_stream/flv、http_hls/ts、http_hls/fmp4),此前误查
    // ('http_stream','fmp4') 永远落空,只有 fmp4 的房间会丢线路。
    hlsCodecs = _listCodecsForFormat(data, 'http_hls', 'fmp4', preferQn: qn);
  }
  final lines = [..._linesFromCodecs(hlsCodecs, 'hls'), ..._linesFromCodecs(flvCodecs, 'flv')];
  return lines.isEmpty ? null : lines;
}

/// 服务器实际下发的清晰度(取首个 codec 的 current_qn)。
///
/// 一次 getRoomPlayInfo 只返回**单档**真实流:所有 codec 的 current_qn
/// 一致(实测 qn=10000/400/250/150/80 请求均如此)。未登录/无权限时它
/// 可能低于请求 qn —— 匿名请求 10000 常被降到 250。返回 0 表示无 codec。
int bilibiliCurrentQn(Map<String, dynamic>? data) {
  final playurl = jsonMapOf(jsonMapOf(data?['playurl_info'])['playurl']);
  final streams = jsonListOf(playurl['stream']).whereType<Map<String, dynamic>>();
  for (final stream in streams) {
    for (final format in jsonListOf(stream['format']).whereType<Map<String, dynamic>>()) {
      for (final codec in jsonListOf(format['codec']).whereType<Map<String, dynamic>>()) {
        final qn = _intOf(codec['current_qn']);
        if (qn > 0) return qn;
      }
    }
  }
  return 0;
}

/// 响应内**所有** codec 实给档的最低值(worst/lowest 专用)。
///
/// 登录态下请求 qn=80,服务器可能对不同 codec 下发不同档(2026-09-29
/// 实测 SESSDATA 登录:{250,150} 混合):`bilibiliCurrentQn` 取首个会拿到
/// 高档,低码率流在 fmp4/hevc 等"靠后的 codec"里,最低值才能命中。
int bilibiliLowestCurrentQn(Map<String, dynamic>? data) {
  final playurl = jsonMapOf(jsonMapOf(data?['playurl_info'])['playurl']);
  final streams = jsonListOf(playurl['stream']).whereType<Map<String, dynamic>>();
  var lowest = 0;
  for (final stream in streams) {
    for (final format in jsonListOf(stream['format']).whereType<Map<String, dynamic>>()) {
      for (final codec in jsonListOf(format['codec']).whereType<Map<String, dynamic>>()) {
        final qn = _intOf(codec['current_qn']);
        if (qn > 0 && (lowest == 0 || qn < lowest)) lowest = qn;
      }
    }
  }
  return lowest;
}

/// accept_qn ∩ 官方档位表(保持官网顺序)。
List<({int qn, String name})> bilibiliAvailableQualities(Map<String, dynamic>? data) {
  final playurl = jsonMapOf(jsonMapOf(data?['playurl_info'])['playurl']);
  final streams = jsonListOf(playurl['stream']).whereType<Map<String, dynamic>>();
  var acceptQn = <int>{};
  for (final stream in streams) {
    for (final format in jsonListOf(stream['format']).whereType<Map<String, dynamic>>()) {
      // accept_qn 在 codec 层
      for (final codec in jsonListOf(format['codec']).whereType<Map<String, dynamic>>()) {
        acceptQn = acceptQn.union({
          for (final qn in jsonListOf(codec['accept_qn'])) _intOf(qn),
        });
      }
    }
  }
  return [
    for (final tier in kBilibiliQnTiers)
      if (acceptQn.contains(tier.qn)) tier,
  ];
}

String bilibiliCoverFromRoom(Map<String, dynamic> info) {
  final cover = jsonText(info['user_cover']);
  final keyframe = jsonText(info['keyframe']);
  return httpsBilibiliUrl(cover.isNotEmpty ? cover : keyframe);
}

String bilibiliAvatarFromRoom(Map<String, dynamic> info) =>
    httpsBilibiliUrl(jsonText(info['face']));

String? bilibiliRoomIdFrom(String raw) {
  final roomId = raw.trim();
  return roomId.isEmpty ? null : roomId;
}

/// 便捷入口:任意输入 → 数字房间号。
String resolveBilibiliRoomId(String roomIdOrUrl) =>
    bilibiliRoomIdFromUrl(roomIdOrUrl.contains('bilibili.com') || _digitsOnly.hasMatch(roomIdOrUrl.trim())
        ? normalizeBilibiliUrl(roomIdOrUrl)
        : roomIdOrUrl);

final RegExp _digitsOnly = RegExp(r'^\d+$');
