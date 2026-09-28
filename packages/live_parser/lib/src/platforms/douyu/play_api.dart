/// getH5PlayV1 播放接口:POST 表单 + 白名单签名,返回 FLV 主线与档位/CDN 元数据。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import 'encryption.dart';
import 'json_utils.dart';

/// getH5PlayV1 固定客户端版本(SFVideoLive 同款)。
const String kDouyuPlayVer = '219032101';

class DouyuMultirate {
  const DouyuMultirate({required this.name, required this.rate});

  final String name;
  final int rate;

  factory DouyuMultirate.fromJson(Map<String, dynamic> json) => DouyuMultirate(
    name: jsonText(json['name']),
    rate: jsonInt(json['rate']),
  );
}

class DouyuCdnRaw {
  const DouyuCdnRaw({
    required this.name,
    required this.cdn,
    required this.reWeight,
  });

  final String name;
  final String cdn;

  /// 上游同时存在 `re-weight` 与 `reWeight` 两种拼写。
  final num reWeight;

  factory DouyuCdnRaw.fromJson(Map<String, dynamic> json) => DouyuCdnRaw(
    name: jsonText(json['name']),
    cdn: jsonText(json['cdn']),
    reWeight: (json['re-weight'] ?? json['reWeight']) is num
        ? (json['re-weight'] ?? json['reWeight']) as num
        : num.tryParse(jsonText(json['re-weight'] ?? json['reWeight'])) ?? 0,
  );
}

class PlayV1Data {
  const PlayV1Data({
    required this.rtmpUrl,
    required this.rtmpLive,
    required this.rtmpCdn,
    required this.isMixed,
    required this.mixedUrl,
    required this.multirates,
    required this.cdnsWithName,
  });

  final String rtmpUrl;
  final String rtmpLive;
  final String rtmpCdn;
  final bool isMixed;
  final String mixedUrl;
  final List<DouyuMultirate> multirates;
  final List<DouyuCdnRaw> cdnsWithName;

  static PlayV1Data fromJson(Map<String, dynamic> json) => PlayV1Data(
    rtmpUrl: jsonText(json['rtmp_url']),
    rtmpLive: jsonText(json['rtmp_live']),
    rtmpCdn: jsonText(json['rtmp_cdn']),
    isMixed: jsonBool(json['is_mixed']),
    mixedUrl: jsonText(json['mixed_url']),
    multirates: jsonListOf(json['multirates'])
        .whereType<Map<String, dynamic>>()
        .map(DouyuMultirate.fromJson)
        .toList(growable: false),
    cdnsWithName: jsonListOf(json['cdnsWithName'])
        .whereType<Map<String, dynamic>>()
        .map(DouyuCdnRaw.fromJson)
        .toList(growable: false),
  );
}

class PlayV1Response {
  const PlayV1Response({required this.error, required this.msg, required this.data});

  final int error;
  final String msg;
  final PlayV1Data? data;

  static PlayV1Response fromJson(Map<String, dynamic> json) => PlayV1Response(
    error: jsonInt(json['error']),
    msg: jsonText(json['msg']),
    data: jsonMapOf(json['data']).isEmpty
        ? null
        : PlayV1Data.fromJson(jsonMapOf(json['data'])),
  );
}

/// 拉取 getH5PlayV1;[rate] 为 `0` 表示默认档(用于探测档位与 CDN 列表)。
Future<PlayV1Response> fetchH5PlayV1(
  ParserHttp http, {
  required String rid,
  required String rate,
  required WhiteKey white,
  String cdn = 'hw-h5',
  String did = kDouyuDefaultDid,
}) async {
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final auth = computeDouyuAuth(rid: rid, white: white, ts: ts);
  final response = await http.postForm(
    Uri.parse('https://playweb.douyucdn.cn/lapi/live/getH5PlayV1/$rid'),
    body: {
      'rate': rate,
      'ver': kDouyuPlayVer,
      'iar': '0',
      'ive': '0',
      'rid': rid,
      'hevc': '0',
      'fa': '0',
      'sov': '0',
      'enc_data': white.encData,
      'tt': '$ts',
      'did': did,
      'auth': auth,
      'cdn': cdn,
    },
    headers: {
      'Referer': 'https://www.douyu.com/',
      'Origin': 'https://www.douyu.com',
    },
  );
  return PlayV1Response.fromJson(jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes))));
}

/// 拼装 FLV 直播地址。
String flvFromApiData(PlayV1Data data) => '${data.rtmpUrl}/${data.rtmpLive}';

/// 有效斗鱼 CDN 地址:`douyucdn*` 域,或官方 scdn 智能选线的 `edgesrv.com`
/// 就近边缘(2026-09-28 实测官方 web 拉流落在
/// `stream-<城市>-<运营商>-*.edgesrv.com:8443`,re-weight 99999 首选)。
/// 此前把 edgesrv 当代理线排除,恰好挡掉了官方主力线路。
bool isDouyucdnUrl(String url) =>
    url.isNotEmpty && (url.contains('douyucdn') || url.contains('edgesrv.com'));
