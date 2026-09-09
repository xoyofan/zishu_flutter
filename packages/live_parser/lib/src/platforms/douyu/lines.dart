/// 线路构建:CDN 列表解析排序、按画质档拉取各 CDN 的 FLV 线路、附加 HLS。
library;

import '../../http/parser_http.dart';
import 'encryption.dart';
import 'play_api.dart';

class DouyuCdnItem {
  const DouyuCdnItem({required this.name, required this.cdn, required this.weight});

  final String name;
  final String cdn;
  final int weight;
}

/// hw-h5 恒排最前,其余按 weight 降序。
List<DouyuCdnItem> sortDouyuCdnList(List<DouyuCdnItem> cdns) {
  final sorted = [...cdns];
  sorted.sort((a, b) {
    if (a.cdn == 'hw-h5' && b.cdn != 'hw-h5') return -1;
    if (b.cdn == 'hw-h5' && a.cdn != 'hw-h5') return 1;
    return b.weight - a.weight;
  });
  return sorted;
}

/// 解析 cdnsWithName;空时回退 rtmp_cdn(缺省 hw-h5)单条。
List<DouyuCdnItem> parseDouyuCdnList(PlayV1Data? data) {
  final parsed = sortDouyuCdnList([
    for (final raw in data?.cdnsWithName ?? const <DouyuCdnRaw>[])
      if (raw.cdn.isNotEmpty)
        DouyuCdnItem(
          name: raw.name.isEmpty ? raw.cdn : raw.name,
          cdn: raw.cdn,
          weight: raw.reWeight.toInt(),
        ),
  ]);
  if (parsed.isNotEmpty) return parsed;
  final fallback = (data?.rtmpCdn.isNotEmpty ?? false) ? data!.rtmpCdn : 'hw-h5';
  return [DouyuCdnItem(name: '默认', cdn: fallback, weight: 0)];
}

/// 首选 CDN:偏好存在则用偏好,否则取排序后的第一条。
String preferredDouyuCdnCode(List<DouyuCdnItem> cdns, [String preferred = 'hw-h5']) {
  for (final item in cdns) {
    if (item.cdn == preferred) return preferred;
  }
  return cdns.isEmpty ? preferred : cdns.first.cdn;
}

/// 从播放接口响应提取可用播放地址:混合流优先,普通流回退 rtmp_url/rtmp_live。
String playUrlFromResponse(PlayV1Response response) {
  final data = response.data;
  if (data == null) return '';
  final base = data.rtmpUrl.replaceFirst(RegExp(r'/+$'), '');
  if (data.isMixed && data.mixedUrl.isNotEmpty) {
    final mixed = data.mixedUrl;
    if (isDouyucdnUrl(mixed)) return mixed;
    final joined = base.isEmpty ? '' : '$base/${mixed.replaceFirst(RegExp('^/+'), '')}';
    if (isDouyucdnUrl(joined)) return joined;
  }
  if (data.rtmpLive.contains('mix=1') && data.mixedUrl.isNotEmpty) {
    final mixed = data.mixedUrl;
    final joined = mixed.startsWith('http')
        ? mixed
        : base.isEmpty
        ? ''
        : '$base/$mixed';
    if (isDouyucdnUrl(joined)) return joined;
  }
  return flvFromApiData(data);
}

/// 一个待构建的播放线路草稿。
class DouyuLineDraft {
  const DouyuLineDraft({required this.name, required this.url, required this.format});

  final String name;
  final String url;
  final String format;
}

/// 并行拉取该画质档下所有 CDN 的 FLV 线路;失败/非法地址跳过,按 CDN 去重。
/// [cachedResponses] 复用同 rate 已有响应(如探测阶段的 rate=0),会回写缓存。
Future<List<DouyuLineDraft>> fetchFlvLinesForRate({
  required ParserHttp http,
  required String rid,
  required String rate,
  required WhiteKey white,
  required List<DouyuCdnItem> cdns,
  required Map<String, PlayV1Response> cachedResponses,
}) async {
  final responses = await Future.wait([
    for (final item in cdns) _fetchOrCached(http, rid, rate, white, item, cachedResponses),
  ]);

  final seen = <String>{};
  final lines = <DouyuLineDraft>[];
  for (var i = 0; i < responses.length; i++) {
    final item = cdns[i];
    final response = responses[i];
    if (response.error != 0) continue;
    final url = playUrlFromResponse(response);
    if (!isDouyucdnUrl(url)) continue;
    final dedupeKey = item.cdn.isNotEmpty ? item.cdn : item.name;
    if (!seen.add(dedupeKey)) continue;
    lines.add(DouyuLineDraft(name: '${item.name} FLV', url: url, format: 'flv'));
  }
  return lines;
}

Future<PlayV1Response> _fetchOrCached(
  ParserHttp http,
  String rid,
  String rate,
  WhiteKey white,
  DouyuCdnItem item,
  Map<String, PlayV1Response> cachedResponses,
) async {
  final cached = cachedResponses[item.cdn];
  if (cached != null) return cached;
  final response = await fetchH5PlayV1(http, rid: rid, rate: rate, white: white, cdn: item.cdn);
  cachedResponses[item.cdn] = response;
  return response;
}

/// 在线路列表头部追加 HLS preview 线(无 HLS 时原样返回)。
List<DouyuLineDraft> appendHlsLine(List<DouyuLineDraft> lines, String hlsUrl) {
  if (hlsUrl.isEmpty) return lines;
  return [DouyuLineDraft(name: 'HLS', url: hlsUrl, format: 'hls'), ...lines];
}
