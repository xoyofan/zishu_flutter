/// hlsH5Preview:与 FLV 共用 stream key 的 preview m3u8,作为 HLS 线路来源。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import 'encryption.dart';
import 'json_utils.dart';
import 'play_api.dart';

class HlsPreviewResponse {
  const HlsPreviewResponse({required this.error, required this.data});

  final int error;
  final PlayV1Data? data;

  static HlsPreviewResponse fromJson(Map<String, dynamic> json) => HlsPreviewResponse(
    error: jsonInt(json['error']),
    data: jsonMapOf(json['data']).isEmpty
        ? null
        : PlayV1Data.fromJson(jsonMapOf(json['data'])),
  );
}

/// POST hlsH5Preview:header 携带 rid/13 位时间戳/auth = md5(rid + t13)。
Future<HlsPreviewResponse> fetchHlsH5Preview(
  ParserHttp http, {
  required String rid,
  String did = kDouyuDefaultDid,
}) async {
  final t13 = DateTime.now().millisecondsSinceEpoch.toString();
  final auth = md5Hex(rid + t13);
  final response = await http.postForm(
    Uri.parse('https://playweb.douyucdn.cn/lapi/live/hlsH5Preview/$rid'),
    body: {'rid': rid, 'did': did},
    headers: {
      'rid': rid,
      'time': t13,
      'auth': auth,
      'Referer': 'https://www.douyu.com/',
      'Origin': 'https://www.douyu.com',
    },
  );
  return HlsPreviewResponse.fromJson(jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes))));
}

/// 从 preview 数据拼 m3u8 地址;缺 `.m3u8` 时返回空串。
String hlsFromPreviewData(PlayV1Data? data) {
  final base = (data?.rtmpUrl ?? '').replaceFirst(RegExp(r'/+$'), '');
  final live = data?.rtmpLive ?? '';
  if (base.isEmpty || !live.contains('.m3u8')) return '';
  return '$base/$live';
}

bool isDouyuHlsUrl(String url) =>
    url.isNotEmpty && url.contains('.m3u8') && url.contains('douyucdn');
