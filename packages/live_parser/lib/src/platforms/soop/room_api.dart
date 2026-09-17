/// SOOP 房间详情、清晰度与播放地址 API。
///
/// 取流链路对齐 pure_live:`player_live_api(type=live)` 拿房间与 VIEWPRESET,
/// 每个档位再经 `broad_stream_assign` 换 CDN 地址 + `player_live_api(type=aid)`
/// 换播放凭证,最终 `{cdn}?aid={aid}`。
library;

import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/header_sanitizer.dart';
import '../douyu/json_utils.dart';

/// SOOP 媒体流(HLS)请求头:CDN 以 Referer/Origin 做防盗链,
/// 与解析请求头(SoopClient.defaultHeaders / player_live_api)同源。
final Map<String, String> soopPlaybackHeaders = sanitizeHeaders(const {
  'origin': 'https://www.sooplive.co.kr',
  'referer': 'https://www.sooplive.co.kr/',
});

/// player_live_api 业务码:1 在播、0 未开播、-2 封禁、-6 需登录。
const int kSoopResultLive = 1;
const int kSoopResultOffline = 0;
const int kSoopResultBanned = -2;
const int kSoopResultNeedLogin = -6;

/// 一个 SOOP 清晰度档位。
class SoopQuality {
  const SoopQuality({
    required this.rawName,
    required this.name,
    required this.bps,
    required this.rank,
  });

  /// 上游请求名(quality 参数),如 `original` / `HD`。
  final String rawName;

  /// 展示名(中文归一)。
  final String name;
  final int bps;

  /// 档位序(越大越高),用于排序与缺 bps 时的兜底。
  final int rank;

  /// [StreamQuality.rate] 取值:优先真实码率,缺失时用档位序放大。
  int get rate => bps > 0 ? bps : rank * 1000000;

  int get sortKey => rank * 100000000 + bps.clamp(0, 99999999);
}

/// SOOP 房间详情。
class SoopRoomDetail {
  const SoopRoomDetail({
    required this.resultCode,
    required this.roomId,
    required this.nick,
    required this.title,
    required this.category,
    required this.bno,
    required this.rmd,
    required this.cdn,
    required this.viewers,
    required this.qualities,
    required this.chatNo,
    required this.chatDomain,
    required this.chatPort,
  });

  final int resultCode;
  final String roomId;
  final String nick;
  final String title;
  final String category;
  final String bno;
  final String rmd;
  final String cdn;

  /// 在线人数(数值字符串,展示时再走 [formatOnlineCount])。
  final String viewers;
  final List<SoopQuality> qualities;

  final String chatNo;
  final String chatDomain;
  final String chatPort;

  bool get isLive => resultCode == kSoopResultLive;

  bool get isBanned => resultCode == kSoopResultBanned;

  bool get hasChat => chatNo.isNotEmpty && chatDomain.isNotEmpty && chatPort.isNotEmpty;
}

/// 请求 `player_live_api.php`。
///
/// [type] 为 `live`(房间/弹幕参数)或 `aid`(播放凭证)。
/// 上游偶发提前关闭复用的短连接;对瞬时传输错误短重试,保留连接复用
/// (强制 `Connection: close` 会让经代理的每次请求都重握手,得不偿失)。
Future<Map<String, dynamic>> fetchSoopPlayerApi(
  ParserHttp http,
  String roomId, {
  String type = 'live',
  String bno = '',
  String quality = 'HD',
}) => _retrySoop(() async {
  final uri = Uri.https(
    'live.sooplive.co.kr',
    '/afreeca/player_live_api.php',
    {'bjid': roomId},
  );
  final response = await http.postForm(
    uri,
    body: {
      'bid': roomId,
      'bno': bno,
      'type': type,
      'pwd': '',
      'player_type': 'html5',
      'stream_type': 'common',
      'quality': quality,
      'mode': 'landing',
      'from_api': '0',
      'is_revive': 'false',
    },
    headers: const {
      'Accept': '*/*',
      'Origin': 'https://www.sooplive.co.kr',
      'Referer': 'https://www.sooplive.co.kr/',
    },
  );
  return http.jsonMap(response);
});

/// 对瞬时传输错误(握手/连接被重置/超时)重试 3 次。
Future<T> _retrySoop<T>(Future<T> Function() action) async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
    }
    try {
      return await action();
    } on Object catch (error) {
      lastError = error;
    }
  }
  Error.throwWithStackTrace(lastError!, StackTrace.current);
}

/// 归一 player_live_api 响应为 [SoopRoomDetail]。
SoopRoomDetail parseSoopRoomDetail(
  Map<String, dynamic> payload,
  String fallbackRoomId,
) {
  final channel = jsonMapOf(payload['CHANNEL']);
  final tags = jsonListOf(channel['CATEGORY_TAGS']);
  final roomId = jsonText(channel['BJID']).trim();
  return SoopRoomDetail(
    resultCode: jsonInt(channel['RESULT']),
    roomId: roomId.isEmpty ? fallbackRoomId : roomId,
    nick: jsonText(channel['BJNICK']),
    title: jsonText(channel['TITLE']),
    category: tags.isEmpty ? '' : jsonText(tags.first),
    bno: jsonText(channel['BNO']),
    rmd: jsonText(channel['RMD']),
    cdn: jsonText(channel['CDN']),
    viewers: soopOnlineViewers(channel),
    qualities: parseSoopQualities(channel['VIEWPRESET']),
    chatNo: jsonText(channel['CHATNO']),
    chatDomain: jsonText(channel['CHDOMAIN']),
    chatPort: jsonText(channel['CHPT']),
  );
}

/// 解析 VIEWPRESET 为清晰度列表:跳过 auto,按上游名去重,高档在前。
List<SoopQuality> parseSoopQualities(Object? viewpreset) {
  if (viewpreset is! List) return const [];
  final merged = <String, SoopQuality>{};
  for (final raw in viewpreset) {
    if (raw is! Map) continue;
    final rawName = jsonText(raw['name']).trim();
    if (rawName.isEmpty || rawName.toLowerCase() == 'auto') continue;
    final bps = jsonInt(raw['bps']);
    final existing = merged[rawName.toLowerCase()];
    if (existing != null && bps <= existing.bps) continue;
    merged[rawName.toLowerCase()] = SoopQuality(
      rawName: rawName,
      name: soopQualityLabel(rawName),
      bps: bps,
      rank: soopQualityRank(rawName),
    );
  }
  final qualities = merged.values.toList();
  qualities.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return qualities;
}

/// 上游清晰度名归一为中文标签;未知名原样返回。
String soopQualityLabel(String rawName) {
  final token = rawName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return switch (token) {
    'original' || 'origin' || 'source' => '原画',
    'master' || 'uhd' => '蓝光',
    'fullhd' || 'fhd' => '超清',
    'hd' => '高清',
    'sd' || 'normal' => '标清',
    'low' || 'ld' => '流畅',
    'hd4k' || '4k' => '4K',
    'hd8k' || '8k' => '8K',
    _ => rawName,
  };
}

/// 清晰度档位序:数值越大越高;未知返回 0。
int soopQualityRank(String rawName) {
  final token = rawName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return switch (token) {
    'original' || 'origin' || 'source' => 6,
    'master' || 'uhd' => 5,
    'fullhd' || 'fhd' => 4,
    'hd' => 3,
    'sd' || 'normal' => 2,
    'low' || 'ld' => 1,
    _ => 0,
  };
}

/// SOOP 观众数:PC/移动拆分字段需相加;`total_view_cnt` 优先。
///
/// 返回数值字符串(无有效值时为空串),与 pure_live 语义一致。
String soopOnlineViewers(Object? room) {
  final map = room is Map ? room : const {};
  String? explicitZero;

  String positiveValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null' || !RegExp(r'[0-9]').hasMatch(text)) {
      return '';
    }
    final parsed = int.tryParse(text.replaceAll(',', '').replaceAll('，', ''));
    if (parsed == null) return '';
    if (parsed == 0) explicitZero ??= '0';
    return parsed > 0 ? '$parsed' : '';
  }

  for (final value in [
    map['total_view_cnt'],
    map['view_cnt'],
    map['VIEW_CNT'],
  ]) {
    final parsed = positiveValue(value);
    if (parsed.isNotEmpty) return parsed;
  }

  int? sumPair(Object? left, Object? right) {
    final leftText = left?.toString().trim().replaceAll(',', '') ?? '';
    final rightText = right?.toString().trim().replaceAll(',', '') ?? '';
    final leftValue = int.tryParse(leftText);
    final rightValue = int.tryParse(rightText);
    if (leftValue == null && rightValue == null) return null;
    return (leftValue ?? 0) + (rightValue ?? 0);
  }

  for (final pair in [
    (map['pc_view_cnt'], map['mobile_view_cnt']),
    (map['current_view_cnt'], map['m_current_view_cnt']),
  ]) {
    final total = sumPair(pair.$1, pair.$2);
    if (total == null) continue;
    if (total > 0) return '$total';
    explicitZero ??= '0';
  }

  return explicitZero ?? '';
}

/// 房间封面(BNO 图像接口,带时间戳防缓存)。
String soopCoverUrl(String bno) {
  if (bno.isEmpty) return '';
  return 'https://liveimg.sooplive.co.kr/m/$bno?_t=${DateTime.now().millisecondsSinceEpoch}';
}

/// 通过 `broad_stream_assign.html` 换取所选清晰度的 CDN 地址。
Future<String> fetchSoopAssignUrl(
  ParserHttp http, {
  required SoopRoomDetail detail,
  required String quality,
}) => _retrySoop(() async {
  if (detail.rmd.isEmpty || detail.bno.isEmpty) return '';
  final cdn = detail.cdn;
  final returnType = cdn.contains('gs_cdn')
      ? 'gs_cdn_pc_web'
      : cdn.contains('lg_cdn')
      ? 'lg_cdn_pc_web'
      : cdn;
  if (returnType.isEmpty) return '';

  final base = detail.rmd.replaceAll(RegExp(r'/+$'), '');
  final query = Uri(
    queryParameters: {
      'return_type': returnType,
      'broad_key': '${detail.bno}-common-$quality-hls',
    },
  ).query;
  final response = await http.get(
    Uri.parse('$base/broad_stream_assign.html?$query'),
  );
  final json = http.jsonMap(response);
  return jsonText(json['view_url']);
});

/// 通过 `player_live_api(type=aid)` 换取播放凭证。
Future<String> fetchSoopStreamAid(
  ParserHttp http, {
  required String roomId,
  required String bno,
  required String quality,
}) async {
  final payload = await fetchSoopPlayerApi(
    http,
    roomId,
    type: 'aid',
    bno: bno,
    quality: quality,
  );
  return jsonText(jsonMapOf(payload['CHANNEL'])['AID']);
}

/// 构建一个可播放档位;assign 与 aid 互不依赖,并行请求。
/// 任一缺失返回 null(该档静默跳过)。
Future<StreamQuality?> buildSoopTier(
  ParserHttp http,
  SoopRoomDetail detail,
  SoopQuality quality,
) async {
  final results = await Future.wait<Object?>([
    fetchSoopAssignUrl(http, detail: detail, quality: quality.rawName),
    fetchSoopStreamAid(
      http,
      roomId: detail.roomId,
      bno: detail.bno,
      quality: quality.rawName,
    ),
  ]);
  final cdnUrl = results[0] as String;
  final aid = results[1] as String;
  if (cdnUrl.isEmpty || aid.isEmpty) return null;
  return StreamQuality(
    name: quality.name,
    rate: quality.rate,
    lines: [
      StreamLine(
        name: '线路',
        url: '$cdnUrl?aid=$aid',
        format: 'hls',
        headers: soopPlaybackHeaders,
      ),
    ],
  );
}
