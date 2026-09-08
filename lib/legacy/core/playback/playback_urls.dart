/// 播放地址的跨端纯逻辑工具。
///
/// 不依赖 Flutter Widget、JS 或具体播放器，可由 Windows/Web 播放适配器共同使用。
library;

import '../contracts/room_models.dart';

bool isHlsUrl(String url) =>
    RegExp(r'\.m3u8(?:\?|$)', caseSensitive: false).hasMatch(url.trim());

bool isFlvUrl(String url) =>
    RegExp(r'\.flv(?:\?|$)', caseSensitive: false).hasMatch(url.trim());

bool isMpegtsUrl(String url) =>
    RegExp(r'\.ts(?:\?|$)', caseSensitive: false).hasMatch(url.trim());

String unwrapProxiedStreamUrl(String url) {
  final raw = url.trim();
  if (!raw.contains('/api/live-stream')) return raw;
  try {
    return Uri.parse(raw).queryParameters['url'] ?? raw;
  } on FormatException {
    return raw;
  }
}

String playbackUrlKind(String url) {
  final raw = unwrapProxiedStreamUrl(url);
  if (isHlsUrl(url) || isHlsUrl(raw)) return 'hls';
  if (isFlvUrl(raw)) return 'flv';
  if (isMpegtsUrl(raw)) return 'mpegts';
  return 'other';
}

bool needsProxy(StreamLine line) => line.headers.isNotEmpty;

String proxyUrl(String base, String url, {String site = '', String room = ''}) {
  final raw = url.trim();
  if (raw.isEmpty || raw.contains('/api/live-stream')) return raw;
  final root = base.trim().replaceAll(RegExp(r'/+$'), '');
  return '$root/api/live-stream'
      '?site=${Uri.encodeQueryComponent(site.trim())}'
      '&room=${Uri.encodeQueryComponent(room.trim())}'
      '&url=${Uri.encodeQueryComponent(raw)}';
}

List<StreamLine> pickLines(QualityStream? stream, {bool preferHls = false}) {
  final list = stream?.lines ?? const <StreamLine>[];
  if (list.isEmpty) return const <StreamLine>[];
  final hls = list.where((line) => line.isHls).toList();
  final flv = list.where((line) => line.isFlv).toList();
  if (preferHls) {
    if (hls.isNotEmpty) return hls;
    if (flv.isNotEmpty) return flv;
    return hls;
  }
  return flv.isNotEmpty ? flv : list;
}
