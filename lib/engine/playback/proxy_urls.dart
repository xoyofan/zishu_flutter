/// 播放地址的纯逻辑工具：format 判定、代理改写、线路挑选。
///
/// 语义对齐 SFVideoLive：
/// - `playbackUrlKind`   ≙ `web/src/composables/usePlayer.ts` 的 `playUrlKind`
/// - `unwrapProxiedStreamUrl` / 代理 URL ≙ `live-shared/src/playback/stream-proxy.ts`
/// - `pickLines` ≙ `web/src/api/room.ts` 的 `visibleStreamLines`
///
/// 本文件不得 import dart:js_interop / package:web —— 纯 Dart，可在 VM 单测。
library;

import '../contracts/room_models.dart';

/// URL 是否为 HLS（.m3u8 结尾，可带 query）。
/// 对齐 `play-format.ts` 的 `isHlsUrl`。
bool isHlsUrl(String url) =>
    RegExp(r'\.m3u8(?:\?|$)', caseSensitive: false).hasMatch(url.trim());

/// URL 是否为 FLV（.flv 结尾，可带 query）。对齐 `lineIsFlv`。
bool isFlvUrl(String url) =>
    RegExp(r'\.flv(?:\?|$)', caseSensitive: false).hasMatch(url.trim());

/// URL 是否为 TS 直链（.ts 结尾，可带 query）。对齐 `isMpegtsStreamUrl`。
bool isMpegtsUrl(String url) =>
    RegExp(r'\.ts(?:\?|$)', caseSensitive: false).hasMatch(url.trim());

/// 从 `{base}/api/live-stream?url=<encoded>` 解出上游原始地址。
/// 非代理地址原样返回。对齐 `unwrapProxiedStreamUrl`。
String unwrapProxiedStreamUrl(String url) {
  final raw = url.trim();
  if (!raw.contains('/api/live-stream')) return raw;
  try {
    final inner = Uri.parse(raw).queryParameters['url'];
    return inner ?? raw;
  } on FormatException {
    return raw;
  }
}

/// 播放地址格式判定，返回 'hls' | 'flv' | 'mpegts' | 'other'。
/// 对齐 usePlayer 的 playUrlKind：先看 URL 本身/解包后是否像 HLS，
/// 再对解包后的地址判 flv / mpegts（代理后的 playUrl 不再含 .flv 等后缀）。
String playbackUrlKind(String url) {
  final raw = unwrapProxiedStreamUrl(url);
  if (isHlsUrl(url) || isHlsUrl(raw)) return 'hls';
  if (isFlvUrl(raw)) return 'flv';
  if (isMpegtsUrl(raw)) return 'mpegts';
  return 'other';
}

/// 该线路是否必须走服务端代理。
///
/// 浏览器无法自定义 Referer/Origin 等请求头，headers 非空的线路直连必挂
/// （如斗鱼/虎牙 FLV 的防盗链），必须改写为 streaming-server 的
/// /api/live-stream?url=…（代理侧带平台头，且有域名白名单）。
bool needsProxy(StreamLine line) => line.headers.isNotEmpty;

/// 将上游 [url] 改写为 `{base}/api/live-stream?site=&room=&url=<encoded>`。
///
/// - [base] 为空时输出相对路径（同源部署时可用）。
/// - 已是代理地址（含 /api/live-stream）则原样返回，保证幂等。
/// - query 顺序对齐 live-stream-proxy 的读取方式（site/room/url），
///   实际解析按参数名取值，顺序仅保持与 SFVideoLive 一致。
String proxyUrl(String base, String url, {String site = '', String room = ''}) {
  final raw = url.trim();
  if (raw.isEmpty) return raw;
  if (raw.contains('/api/live-stream')) return raw;
  final root = base.trim().replaceAll(RegExp(r'/+$'), '');
  return '$root/api/live-stream'
      '?site=${Uri.encodeQueryComponent(site.trim())}'
      '&room=${Uri.encodeQueryComponent(room.trim())}'
      '&url=${Uri.encodeQueryComponent(raw)}';
}

/// 挑选某档位下可展示/可播的线路（对齐 visibleStreamLines 语义）。
///
/// - [preferHls] 为 true：优先 HLS；无 HLS 回退 FLV；两者皆无返回 HLS 集
///   （忠实复刻 TS 实现：此时可能为空——上游 quirk，调用方需自行兜底）。
/// - [preferHls] 为 false：优先 FLV；无 FLV 返回全部线路（含 mpegts/TS 直链）。
/// - 顺序保持输入顺序。
List<StreamLine> pickLines(QualityStream? stream, {bool preferHls = false}) {
  final list = stream?.lines ?? const <StreamLine>[];
  if (list.isEmpty) return const <StreamLine>[];
  final hls = list.where((l) => l.isHls).toList();
  final flv = list.where((l) => l.isFlv).toList();
  if (preferHls) {
    if (hls.isNotEmpty) return hls;
    if (flv.isNotEmpty) return flv;
    return hls;
  }
  if (flv.isNotEmpty) return flv;
  return list;
}
