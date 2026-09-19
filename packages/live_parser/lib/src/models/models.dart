/// 标准解析模型:UI 与 server 只依赖这些稳定类型,不接触站点内部结构。
///
/// 内部 Dart 字段一律 lowerCamelCase;HTTP server 负责转换为与旧 API
/// 兼容的 snake_case JSON。
library;

import 'dart:convert';

/// 房间在线状态。
enum RoomState { live, offline, notFound }

/// 一条可播放线路。
class StreamLine {
  const StreamLine({
    required this.name,
    required this.url,
    required this.format,
    this.headers = const {},
  });

  final String name;

  /// `hls` / `flv` 等小写格式标识。
  final String format;
  final String url;
  final Map<String, String> headers;

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'format': format,
    if (headers.isNotEmpty) 'headers': headers,
  };

  factory StreamLine.fromJson(Map<String, dynamic> json) => StreamLine(
    name: json['name']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    format: json['format']?.toString() ?? '',
    headers: (json['headers'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v.toString()),
    ) ?? const {},
  );
}

/// 一个画质档位:名称 + 该档位下的全部线路。
class StreamQuality {
  const StreamQuality({required this.name, required this.rate, required this.lines});

  final String name;
  final int rate;
  final List<StreamLine> lines;

  StreamLine? get preferredLine {
    for (final line in lines) {
      if (line.format == 'hls') return line;
    }
    return lines.isEmpty ? null : lines.first;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'rate': rate,
    'lines': lines.map((line) => line.toJson()).toList(),
  };

  factory StreamQuality.fromJson(Map<String, dynamic> json) => StreamQuality(
    name: json['name']?.toString() ?? '',
    rate: (json['rate'] as num?)?.toInt() ?? 0,
    lines: ((json['lines'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => StreamLine.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
  );
}

/// 清晰度选项(不含线路)。
class QualityOption {
  const QualityOption({required this.name, required this.rate});

  final String name;
  final int rate;

  Map<String, dynamic> toJson() => {'name': name, 'rate': rate};

  factory QualityOption.fromJson(Map<String, dynamic> json) => QualityOption(
    name: json['name']?.toString() ?? '',
    rate: (json['rate'] as num?)?.toInt() ?? 0,
  );
}

/// 房间解析结果:播放页与编排层的主契约。
class RoomPayload {
  const RoomPayload({
    required this.site,
    required this.roomId,
    required this.sourceUrl,
    required this.anchorName,
    required this.title,
    required this.cover,
    required this.avatar,
    required this.category,
    required this.cid,
    required this.roomState,
    required this.streams,
    required this.availableQualities,
    required this.source,
    required this.fetchedAt,
    this.error,
    this.startedAt,
  });

  final String site;
  final String roomId;
  final String sourceUrl;
  final String anchorName;
  final String title;
  final String cover;
  final String avatar;
  final String category;
  final String cid;
  final RoomState roomState;

  /// 画质档位 -> 线路。离线/不存在时为空。
  final List<StreamQuality> streams;
  final List<QualityOption> availableQualities;

  /// 产出方标识:`live_parser/douyu` 等。
  final String source;
  final DateTime fetchedAt;
  final String? error;

  /// 本场开播时间(平台真实返回时才有值)。
  ///
  /// 斗鱼取 betard 的 `show_time`;其余平台暂未提供,保持 null,
  /// 由 UI 侧以占位符呈现。**不得伪造**:拿不到就留空。
  final DateTime? startedAt;

  bool get isLive => roomState == RoomState.live;

  /// 默认播放地址:首选画质的首选线路。
  String get playUrl => streams.isEmpty ? '' : (streams.first.preferredLine?.url ?? '');

  /// 按画质名选择档位;未命中时回退首选档。
  StreamQuality? qualityByName(String? name) {
    if (streams.isEmpty) return null;
    if (name == null || name.isEmpty) return streams.first;
    for (final stream in streams) {
      if (stream.name == name) return stream;
    }
    for (final stream in streams) {
      if (name.contains(stream.name) || stream.name.contains(name)) return stream;
    }
    return streams.first;
  }

  Map<String, dynamic> toJson() => {
    'site': site,
    'roomId': roomId,
    'sourceUrl': sourceUrl,
    'anchorName': anchorName,
    'title': title,
    'cover': cover,
    'avatar': avatar,
    'category': category,
    'cid': cid,
    'roomState': roomState.name,
    'isLive': isLive,
    'streams': streams.map((s) => s.toJson()).toList(),
    'availableQualities': availableQualities.map((q) => q.toJson()).toList(),
    'source': source,
    'fetchedAt': fetchedAt.toIso8601String(),
    if (error != null) 'error': error,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
  };

  factory RoomPayload.fromJson(Map<String, dynamic> json) => RoomPayload(
    site: json['site']?.toString() ?? '',
    roomId: json['roomId']?.toString() ?? '',
    sourceUrl: json['sourceUrl']?.toString() ?? '',
    anchorName: json['anchorName']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    cid: json['cid']?.toString() ?? '',
    roomState: RoomState.values.firstWhere(
      (state) => state.name == json['roomState'],
      orElse: () => RoomState.offline,
    ),
    streams: ((json['streams'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => StreamQuality.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    availableQualities: ((json['availableQualities'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => QualityOption.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    source: json['source']?.toString() ?? '',
    fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    error: json['error']?.toString(),
    startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
  );

  String encode() => jsonEncode(toJson());

  factory RoomPayload.decode(String text) =>
      RoomPayload.fromJson(Map<String, dynamic>.from(jsonDecode(text) as Map));
}

/// 画质偏好匹配:精确同名优先,其次双向包含(与 [RoomPayload.qualityByName]
/// 及播放侧 `_pickQuality` 同语义)。平台解析侧据此定位「偏好档」做懒取流;
/// 返回 null 表示未命中(调用方决定回退策略)。
T? matchQualityPreference<T>(
  List<T> items,
  String? preferred,
  String Function(T item) nameOf,
) {
  final name = preferred?.trim() ?? '';
  if (name.isEmpty || items.isEmpty) return null;
  for (final item in items) {
    if (nameOf(item) == name) return item;
  }
  for (final item in items) {
    final itemName = nameOf(item);
    if (itemName.isNotEmpty &&
        (name.contains(itemName) || itemName.contains(name))) {
      return item;
    }
  }
  return null;
}

/// 房间网格卡片摘要。
class RoomSummary {
  const RoomSummary({
    required this.site,
    required this.roomId,
    required this.title,
    required this.anchorName,
    required this.cid,
    required this.category,
    required this.online,
    required this.cover,
    this.promoTag,
  });

  final String site;
  final String roomId;
  final String title;
  final String anchorName;
  final String cid;
  final String category;
  final String online;
  final String cover;
  final String? promoTag;

  Map<String, dynamic> toJson() => {
    'site': site,
    'roomId': roomId,
    'title': title,
    'anchorName': anchorName,
    'cid': cid,
    'category': category,
    'online': online,
    'cover': cover,
    if (promoTag != null) 'promoTag': promoTag,
  };

  factory RoomSummary.fromJson(Map<String, dynamic> json) => RoomSummary(
    site: json['site']?.toString() ?? '',
    roomId: json['roomId']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    anchorName: json['nickname']?.toString() ?? json['anchorName']?.toString() ?? '',
    cid: json['cid']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    online: json['online']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    promoTag: json['promoTag']?.toString(),
  );
}

/// 分类房间列表分页结果。
class RoomListResult {
  const RoomListResult({required this.rooms, required this.page, required this.hasMore});

  final List<RoomSummary> rooms;
  final int page;
  final bool hasMore;
}

/// 二级分类项。
class CategoryItem {
  const CategoryItem({required this.cid, required this.name, required this.pic});

  final String cid;
  final String name;
  final String pic;
}

/// 一级分类分组。
class CategoryGroup {
  const CategoryGroup({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<CategoryItem> items;
}

/// 平台分类索引结果。
class CategoryResult {
  const CategoryResult({required this.site, required this.groups});

  final String site;
  final List<CategoryGroup> groups;
}

/// 搜索命中的状态。
enum SearchHitState { live, replay, offline }

/// 搜索结果条目(主播或房间)。
class SearchHit {
  const SearchHit({
    required this.id,
    required this.anchor,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.state,
    required this.category,
    required this.online,
    this.fans,
  });

  final String id;
  final String anchor;
  final String title;
  final String avatar;
  final String cover;
  final SearchHitState state;
  final String category;
  final String online;
  final String? fans;
}

/// 搜索结果。
class SearchResult {
  const SearchResult({required this.site, required this.hits});

  final String site;
  final List<SearchHit> hits;
}

/// 平台能力声明:UI 按 capabilities 分支,禁止到处写 `site == 'xxx'`。
class SiteCapabilities {
  const SiteCapabilities({
    this.browse = false,
    this.roomSearch = false,
    this.anchorSearch = false,
    this.danmaku = false,
    this.multiQuality = false,
    this.multiLine = false,
    this.requiresCookie = false,
  });

  final bool browse;
  final bool roomSearch;
  final bool anchorSearch;
  final bool danmaku;
  final bool multiQuality;
  final bool multiLine;
  final bool requiresCookie;
}

/// 弹幕消息类别:chat 为普通弹幕,其余按平台消息逐步接入(P9)。
enum DanmakuMessageType { chat, gift, enter, welcome, other }

/// 弹幕会话状态。
enum DanmakuSessionState { connecting, connected, disconnected }

/// 一条归一后的弹幕消息。
class DanmakuMessage {
  const DanmakuMessage({
    required this.type,
    required this.userName,
    required this.userId,
    required this.text,
    this.roomId = '',
    this.color = 0,
    this.badgeName = '',
    this.badgeLevel = 0,
    this.userLevel = 0,
    this.badgeColorStart = 0,
    this.badgeColorEnd = 0,
    this.badgeColorBorder = 0,
    this.badgeTextColor = 0,
    this.badgeColorLevel = 0,
    this.id = '',
    this.sentAt,
    this.rawType = '',
  });

  final DanmakuMessageType type;
  final String roomId;

  /// 0 表示使用 UI 默认弹幕色;否则为 0xRRGGBB。
  final int color;
  final String userName;
  final String userId;
  final String text;
  final String badgeName;
  final int badgeLevel;
  final int userLevel;

  /// 粉丝牌渐变起止色(0xRRGGBB;0 = 协议未提供,B 站专属语义)。
  /// UI 端对齐 web ChatFanBadge 的 bilibiliComposed 渐变(to left, start→end)。
  final int badgeColorStart;
  final int badgeColorEnd;

  /// 粉丝牌描边色(0xRRGGBB;0 = 协议未提供)。
  final int badgeColorBorder;

  /// 粉丝牌文字色(0xRRGGBB;0 = 协议未提供,UI 回落白色)。
  /// B 站新协议 `v2_medal_color_text`(对齐 web fanBadges/bilibili.ts:121-126)。
  final int badgeTextColor;

  /// 粉丝牌等级数字色(0xRRGGBB;0 = 协议未提供,UI 回落文字色)。
  /// B 站新协议 `v2_medal_color_level`(对齐 web fanBadges/bilibili.ts:137-141)。
  final int badgeColorLevel;

  /// 协议消息 id(空 = 未提供)。用于弹幕去重(协议重推同一条时按 id 判重),
  /// 消除「用户+正文」兜底 key 对同名同文的误杀。
  /// - huya:MessageNotice.sMessageId(tag 20);
  /// - bilibili:info[0][15].extra JSON 的 id_str(web bilibiliMeta.ts:274-290)。
  final String id;
  final DateTime? sentAt;

  /// 上游原始 type(如 `chatmsg`),便于 UI/日志区分细分来源。
  final String rawType;
}
