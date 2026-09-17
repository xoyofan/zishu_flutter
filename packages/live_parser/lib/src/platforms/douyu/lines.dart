/// 线路构建:CDN 列表解析排序、按画质档拉取各 CDN 的 FLV 线路、HLS 兜底线、
/// 媒体流请求头。
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

/// 在线路列表尾部追加 HLS preview 线，**仅当没有任何 FLV 线路时**。
///
/// 历史实现把 hlsH5Preview 插在列表头，而 [StreamQuality.preferredLine]
/// 是「有 hls 就选 hls」，于是斗鱼每档的首选线路恒为此预览流。
/// 但 `hlsH5Preview` 返回的是 `preview=1&edge_slice=true&pt=3` 的**预览切片**:
/// 边缘切片播放列表与 token 寿命都短，实测实机 mpv 每几秒就
/// `Failed to open …m3u8?txSecret=…&txTime=…` → 缓冲看门狗整组重开 → 观感
/// 「黑屏闪一下又恢复」。参考实现 pure_live 从不使用该接口，只用 getH5PlayV1
/// 的 FLV / 混合地址。故这里改为**兜底**:FLV 全灭时仍可播，FLV 可用时不再抢首选。
List<DouyuLineDraft> appendHlsFallbackLine(
  List<DouyuLineDraft> lines,
  String hlsUrl,
) {
  if (hlsUrl.isEmpty || lines.isNotEmpty) return lines;
  return [DouyuLineDraft(name: 'HLS', url: hlsUrl, format: 'hls')];
}

/// 斗鱼媒体流请求头(与 pure_live `DouyuUtils.playbackHeaders` 同源)。
///
/// 斗鱼 CDN 的 `token=web-h5-…` / `web-douyu-…` 是按浏览器上下文签发的，
/// 缺 Referer/UA/Cookie 时部分边缘节点直接拒绝或半开连接 —— 宿主播放器侧
/// 表现为 mpv `Failed to open` → 重开循环。之前斗鱼线路 `headers` 为空，
/// 而参考实现对**每个平台**都注入该组头。
Map<String, String> douyuPlaybackHeaders(String roomId) {
  final rid = roomId.trim();
  return {
    'origin': 'https://www.douyu.com',
    'referer': rid.isEmpty
        ? 'https://www.douyu.com/'
        : 'https://www.douyu.com/$rid',
    'user-agent': kDouyuPlaybackUserAgent,
    'cookie': 'dy_did=$kDouyuDefaultDid; acf_did=$kDouyuDefaultDid',
  };
}

/// 斗鱼页面对应浏览器 UA(token 按该 UA 签发)。
const String kDouyuPlaybackUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/128.0.0.0 Safari/537.36';
