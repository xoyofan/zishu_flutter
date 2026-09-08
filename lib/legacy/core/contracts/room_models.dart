/// streaming-server 契约模型。
///
/// 字段对齐 `SFVideoLive/contracts/room.schema.json`（snake_case JSON，
/// Dart 属性 lowerCamelCase）。手写 fromJson，未知字段忽略，可选字段给安全默认值。
library;

/// 单条播放线路。
class StreamLine {
  final String name;
  final String url;
  final String format; // hls | flv | mpegts | ''
  final Map<String, String> headers;

  const StreamLine({
    required this.name,
    required this.url,
    this.format = '',
    this.headers = const {},
  });

  factory StreamLine.fromJson(Map<String, dynamic> json) => StreamLine(
    name: json['name']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    format: json['format']?.toString() ?? '',
    headers: (json['headers'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, v?.toString() ?? ''),
    ),
  );

  bool get isHls => format == 'hls' || url.contains('.m3u8');
  bool get isFlv =>
      format == 'flv' ||
      RegExp(r'\.flv(?:\?|$)', caseSensitive: false).hasMatch(url);

  /// 浏览器/WebView 场景：需要 Referer 等头的线路无法直连，
  /// 必须经 streaming-server 的 /api/live-stream 代理。
  bool get needsProxy => headers.isNotEmpty;
}

/// 一个画质档位（streams[i]），内含多条线路。
class QualityStream {
  final String name;
  final Object? rate; // number | string | null
  final List<StreamLine> lines;

  const QualityStream({required this.name, this.rate, this.lines = const []});

  factory QualityStream.fromJson(Map<String, dynamic> json) => QualityStream(
    name: json['name']?.toString() ?? '',
    rate: json['rate'],
    lines: ((json['lines'] as List<dynamic>? ?? []))
        .whereType<Map<String, dynamic>>()
        .map(StreamLine.fromJson)
        .toList(),
  );
}

/// 清晰度元信息（available_qualities[i]）。
class QualityMeta {
  final String name;
  final Object? rate;

  const QualityMeta({required this.name, this.rate});

  factory QualityMeta.fromJson(Map<String, dynamic> json) =>
      QualityMeta(name: json['name']?.toString() ?? '', rate: json['rate']);
}

/// 房间状态枚举（room_state 字段）。
enum RoomState { live, offline, replay, unknown }

/// /api/room 响应（RoomPayload）。
class RoomPayload {
  final bool ok;
  final String error;
  final String site;
  final String roomId;
  final String title;
  final String anchorName;
  final String cover;
  final String avatar;
  final String category;
  final String cid;
  final RoomState roomState;
  final bool isLive;
  final String playUrl;
  final String flvUrl;
  final String m3u8Url;
  final List<String> backupUrls;
  final bool partial; // lazy 模式分段解析标志
  final String quality; // partial 时本次解析的档位
  final List<QualityMeta> availableQualities;
  final List<QualityStream> streams;
  final bool cached;

  const RoomPayload({
    required this.ok,
    this.error = '',
    required this.site,
    required this.roomId,
    this.title = '',
    this.anchorName = '',
    this.cover = '',
    this.avatar = '',
    this.category = '',
    this.cid = '',
    this.roomState = RoomState.unknown,
    this.isLive = false,
    this.playUrl = '',
    this.flvUrl = '',
    this.m3u8Url = '',
    this.backupUrls = const [],
    this.partial = false,
    this.quality = '',
    this.availableQualities = const [],
    this.streams = const [],
    this.cached = false,
  });

  static RoomState _parseRoomState(Object? raw) {
    switch (raw?.toString()) {
      case 'live':
        return RoomState.live;
      case 'offline':
        return RoomState.offline;
      case 'replay':
        return RoomState.replay;
      default:
        return RoomState.unknown;
    }
  }

  factory RoomPayload.fromJson(Map<String, dynamic> json) => RoomPayload(
    ok: json['ok'] == true,
    error: json['error']?.toString() ?? '',
    site: json['site']?.toString() ?? '',
    roomId: json['room_id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    anchorName: json['anchor_name']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    cid: json['cid']?.toString() ?? '',
    roomState: _parseRoomState(json['room_state']),
    isLive: json['is_live'] == true,
    playUrl: json['play_url']?.toString() ?? '',
    flvUrl: json['flv_url']?.toString() ?? '',
    m3u8Url: json['m3u8_url']?.toString() ?? '',
    backupUrls: (json['backup_urls'] as List<dynamic>? ?? [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(),
    partial: json['partial'] == true,
    quality: json['quality']?.toString() ?? '',
    availableQualities: ((json['available_qualities'] as List<dynamic>? ?? []))
        .whereType<Map<String, dynamic>>()
        .map(QualityMeta.fromJson)
        .toList(),
    streams: ((json['streams'] as List<dynamic>? ?? []))
        .whereType<Map<String, dynamic>>()
        .map(QualityStream.fromJson)
        .toList(),
    cached: json['cached'] == true,
  );

  /// 档位名列表：优先 available_qualities，缺省回退 streams 名称。
  List<String> get qualityNames {
    if (availableQualities.isNotEmpty) {
      return availableQualities.map((e) => e.name).toList();
    }
    return streams.map((e) => e.name).toList();
  }

  QualityStream? streamByName(String name) {
    for (final s in streams) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// 取指定档位+线路的直连 URL（index 与 qualityNames 对齐）。
  String lineUrl(int qualityIndex, int lineIndex) {
    final names = qualityNames;
    if (qualityIndex < 0 || qualityIndex >= names.length) return '';
    final stream = streamByName(names[qualityIndex]);
    if (stream == null || lineIndex >= stream.lines.length) return '';
    return stream.lines[lineIndex].url;
  }
}
