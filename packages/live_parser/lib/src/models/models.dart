/// 标准解析模型:UI 与 server 只依赖这些稳定类型,不接触站点内部结构。
///
/// 内部 Dart 字段一律 lowerCamelCase;HTTP server 负责转换为与旧 API
/// 兼容的 snake_case JSON。
library;

import 'dart:convert';

/// 房间在线状态。
///
/// `replay` 为平台「轮播/录播循环」态:B 站 `live_status==2`、斗鱼
/// betard `videoLoop==1`、虎牙 `huyaRoomState` replay 分支(均对齐
/// SFVideoLive `follow/status.ts` 的三态快照口径)。轮播**不是实时
/// 直播**:宿主在播判据仍是「online 非空」,replay 的 [RoomSummary.online]
/// 契约同离线一样为空串(见 [RoomSummary.roomState])。
/// 枚举按 name 序列化,`replay` 追加在末尾不影响旧 JSON 的读写。
enum RoomState { live, offline, notFound, replay }

/// 房间统计列对应的稳定数据字段。
///
/// UI 不直接依赖平台字段名,只消费 [RoomStatColumn] 与这里的公共枚举。
enum RoomStatField { audience, vip, svip }

/// 房间统计列的视觉语义,对应现有主题 token。
enum RoomStatTone { audience, vip, svip }

/// 一个平台公开的房间统计列。
class RoomStatColumn {
  const RoomStatColumn({
    required this.field,
    required this.label,
    required this.tone,
  });

  final RoomStatField field;
  final String label;
  final RoomStatTone tone;
}

/// 站点在 UI 中公开的展示能力。
///
/// 这是纯 Dart 描述,不包含 Flutter/UI 依赖;`site == ...` 分支不应
/// 重新定义这些标签。
class SiteDisplaySpec {
  const SiteDisplaySpec({
    this.showFollowers = false,
    this.showStartedAt = false,
    this.roomStats = const [],
  });

  /// 是否显示独立的「关注 N」字段。
  final bool showFollowers;

  /// 是否显示本场开播时间字段。
  final bool showStartedAt;

  /// 平台公开的房间统计列,按展示顺序排列。
  final List<RoomStatColumn> roomStats;
}

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
    headers:
        (json['headers'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        const {},
  );
}

/// 一个画质档位:名称 + 该档位下的全部线路。
class StreamQuality {
  const StreamQuality({
    required this.name,
    required this.rate,
    required this.lines,
  });

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
    this.cateNo = '',
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

  /// 平台分类号(soop 等 cid 另作他用的站点填写;如 soop 的 CHANNEL.CATE)。
  /// 空串表示与 [cid] 同义或站点无分类号概念。收藏分类等需要**分类 id**
  /// 的场景应优先取本字段,不得拿 [cid](可能是房间号)冒充。
  final String cateNo;

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

  /// 轮播/录播循环态(非实时直播;streams 通常为空)。
  bool get isReplay => roomState == RoomState.replay;

  /// 默认播放地址:首选画质的首选线路。
  String get playUrl =>
      streams.isEmpty ? '' : (streams.first.preferredLine?.url ?? '');

  /// 按画质名选择档位;未命中时回退首选档。
  StreamQuality? qualityByName(String? name) {
    if (streams.isEmpty) return null;
    if (name == null || name.isEmpty) return streams.first;
    for (final stream in streams) {
      if (stream.name == name) return stream;
    }
    for (final stream in streams) {
      if (name.contains(stream.name) || stream.name.contains(name)) {
        return stream;
      }
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
    if (cateNo.isNotEmpty) 'cateNo': cateNo,
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
    cateNo: json['cateNo']?.toString() ?? '',
    streams: ((json['streams'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => StreamQuality.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    availableQualities: ((json['availableQualities'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => QualityOption.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    source: json['source']?.toString() ?? '',
    fetchedAt:
        DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    error: json['error']?.toString(),
    startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
  );

  RoomPayload copyWith({
    List<StreamQuality>? streams,
    DateTime? fetchedAt,
    String? error,
  }) => RoomPayload(
    site: site,
    roomId: roomId,
    sourceUrl: sourceUrl,
    anchorName: anchorName,
    title: title,
    cover: cover,
    avatar: avatar,
    category: category,
    cid: cid,
    cateNo: cateNo,
    roomState: roomState,
    streams: streams ?? this.streams,
    availableQualities: availableQualities,
    source: source,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    error: error ?? this.error,
    startedAt: startedAt,
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
    this.avatar = '',
    this.promoTag,
    this.followers = '',
    this.vip = '',
    this.diamondFans = '',
    this.roomState = RoomState.offline,
    this.startedAt,
  });

  final String site;
  final String roomId;
  final String title;
  final String anchorName;
  final String cid;
  final String category;
  final String online;
  final String cover;

  /// 主播头像 URL(状态刷新/列表接口提供时填充)。
  ///
  /// 关注 hover 浮层与顶栏头像堆叠优先用它(web `FollowRoomEntry.avatar` /
  /// `pickFollowAvatarSrc`:avatar 优先、cover 兜底);空串 = 尚未获取,
  /// UI 回退房间封面。斗鱼的过期截图 CDN 排除在 UI 侧判定(与 web 同口径)。
  final String avatar;

  final String? promoTag;

  /// 粉丝/关注数文案(已格式化,如「123456」)。
  ///
  /// 口径对齐 web 关注快照 `FollowStatus.fans`(SFVideoLive
  /// `packages/shared/src/types/follow.ts:25`;SideHeader「关注：N」行):
  /// - douyu:getAnchorNewCard 的 `roomInfo.fansNum`;
  /// - huya:profileRoom 的 `profileInfo.activityCount ?? liveData.activityCount`;
  /// - douyin:enter 响应 `owner.follow_info.follower_count`;
  /// - bilibili:get_info 的 `attention`;
  /// - soop:channel dashboard 的 `upd.fanCnt`;
  /// - yy/kuaishou:上游无免登录接口,恒为空(数据诚实性:不伪造)。
  ///
  /// 空串 = 平台未提供(展示为「—」);只承载文本,不做数值解析。
  final String followers;

  /// VIP/贵宾类计数文案(已格式化,如「1.2万」)。
  ///
  /// 口径对齐 web 关注快照 `FollowStatus.vip`(follow.ts:30)与
  /// `ROOM_STAT_COLUMNS` 的 vip 列(douyu/huya「贵宾」、douyin「会员」、
  /// soop「订阅」;SFVideoLive `platformCatalog.ts:29`):
  /// - douyu:getAnchorNewCard 的 `functionShow.giftCard.total`
  ///   (web 真源另有弹幕 WS oni 实时榜,轻量刷新不复刻 WS);
  /// - soop:channel dashboard 的 `subscription.total`;
  /// - huya:在播时 `liveui/getVipBarList`(Tars wup 二进制协议,
  ///   `platforms/huya/huya_wup.dart`)的 `VipBarListRsp.iTotalNum`;
  ///   wup 失败/为 0 留空;
  /// - bilibili/douyin/yy/kuaishou:上游需要额外签名/Tars 协议或
  ///   真源本身无此字段,恒为空(注:抖音的会员数在 web 真源是 `vip`
  ///   字段,但落在第 3 列,本包按列口径归入 [diamondFans])。
  final String vip;

  /// 第 3 列「SVIP 档」计数文案(已格式化,如「1.2万」)。
  ///
  /// 字段名沿用 web 真源的同一个键 `FollowStatus.diamondFans`
  /// (SFVideoLive `packages/shared/src/types/follow.ts:27`)与
  /// `ROOM_STAT_COLUMNS` 的第 3 列(tone=svip);**不做平台专属重命名**,
  /// 因为真源本身就是一个字段承载各平台不同语义 —— 本包统一由
  /// `diamondFans` 承载各站第 3 列的值(语义随平台变):
  /// - douyu:label「钻粉」= `getAnchorNewCard` 的
  ///   `anchorLevel.dFansInfo.curDfansNum`(与粉丝/贵宾同一卡片请求);
  /// - huya:label「超粉」= 超粉人数(wup `getSuperFansInfo`);
  /// - douyin:label「会员」= web 真源 `FollowStatus.vip`
  ///   (`/webcast/user/profile/` 的 `subscribe_info.member_count`,仅播时);
  /// - bilibili:label「大航海」= web 真源 `FollowStatus.guard`
  ///   (`guardTab/topList` 的 `data.info.num`,仅播时)。
  ///
  /// 虎牙取数(对齐 web `fetchHuyaSuperFanCount`,SFVideoLive
  /// `services/streaming-server/src/follow/huya-wup.ts:199`):仅在播时走
  /// `wupui/getSuperFansInfo`(`iSuperFansNum + iYearSuperFansNum`,Tars wup
  /// 二进制协议,见 `platforms/huya/huya_wup.dart`),为 0/不可信时回退
  /// `wupui/getSuperFansRankPanel`(`iNum + iPlusNum`);置信度校验沿用
  /// web `isPlausibleHuyaSuperFanCount`。失败、字段缺失、计数为 0
  /// **一律留空串**(展示层渲染「—」;数据诚实性:不伪造、不回填 0)。
  /// 列表/浏览行不逐房发 wup,恒为空串。
  final String diamondFans;

  /// 房间三态(在播/离线/轮播)，`refresher` 与列表共同承载 replay 语义。
  ///
  /// 口径对齐 web 关注快照 `FollowState = live|replay|offline`
  /// (SFVideoLive `follow/status.ts:42`):
  /// - `live` ⇔ [online] 非空(既有在播判据,不变);
  /// - `replay` = 轮播/录播循环:**[online] 契约同离线一样为空串**,
  ///   宿主以 [roomState] 单独区分(「我的关注」页据此排序与打标);
  /// - 默认 [RoomState.offline]:旧 JSON(无 `roomState` 键)与未适配
  ///   replay 判定的站点自然回落,行为不变。
  final RoomState roomState;

  /// 本场开播时间;平台没有提供或旧数据缺失时为 null。
  final DateTime? startedAt;

  /// 在播(与 [online] 非空一致;轮播/离线均为 false)。
  bool get isLive => roomState == RoomState.live;

  /// 轮播/录播循环态。
  bool get isReplay => roomState == RoomState.replay;

  Map<String, dynamic> toJson() => {
    'site': site,
    'roomId': roomId,
    'title': title,
    'anchorName': anchorName,
    'cid': cid,
    'category': category,
    'online': online,
    'cover': cover,
    if (avatar.isNotEmpty) 'avatar': avatar,
    'roomState': roomState.name,
    if (promoTag != null) 'promoTag': promoTag,
    if (followers.isNotEmpty) 'followers': followers,
    if (vip.isNotEmpty) 'vip': vip,
    if (diamondFans.isNotEmpty) 'diamondFans': diamondFans,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
  };

  factory RoomSummary.fromJson(Map<String, dynamic> json) => RoomSummary(
    site: json['site']?.toString() ?? '',
    roomId: json['roomId']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    anchorName:
        json['nickname']?.toString() ?? json['anchorName']?.toString() ?? '',
    cid: json['cid']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    online: json['online']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    roomState: RoomState.values.firstWhere(
      (state) => state.name == json['roomState'],
      orElse: () => RoomState.offline,
    ),
    startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
    promoTag: json['promoTag']?.toString(),
    followers: json['followers']?.toString() ?? '',
    vip: json['vip']?.toString() ?? '',
    diamondFans: json['diamondFans']?.toString() ?? '',
  );
}

/// 分类房间列表分页结果。
class RoomListResult {
  const RoomListResult({
    required this.rooms,
    required this.page,
    required this.hasMore,
  });

  final List<RoomSummary> rooms;
  final int page;
  final bool hasMore;
}

/// 二级分类项。
class CategoryItem {
  const CategoryItem({
    required this.cid,
    required this.name,
    required this.pic,
  });

  final String cid;
  final String name;
  final String pic;
}

/// 一级分类分组。
class CategoryGroup {
  const CategoryGroup({
    required this.id,
    required this.name,
    required this.items,
  });

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

/// 搜索档位:主播 / 房间。对齐 web `SearchDialog` 服务端分流的
/// `type=anchors|rooms`(SFVideoLive `http/routes/resolve.ts:24`)。
enum SearchType { anchors, rooms }

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

/// 弹幕富文本段类型:文本 / 表情图。
enum DanmakuSegmentType { text, emoji }

/// 一枚可独立展示的聊天身份徽章。SOOP 0005 帧允许同一条消息同时带多枚。
class DanmakuBadge {
  const DanmakuBadge({
    required this.name,
    required this.level,
    this.color = 0,
    this.kind = '',
    this.url = '',
    this.iconUrl = '',
    this.vFlag = 0,
    this.vLogo = '',
  });

  final String name;
  final int level;
  final int color;
  final String kind;

  /// 徽章主体/图标 URL。SOOP 订阅等平台可同时使用 [url] 与 [iconUrl]。
  final String url;

  /// 平台协议直接下发的图标 URL。
  final String iconUrl;

  /// 虎牙超粉标记与 V 标图片。
  final int vFlag;
  final String vLogo;
}

/// 弹幕富文本段:文本段与表情图段按协议顺序排列。
///
/// 对齐 web 真源通用段模型 `{type, text, name?, url?}`:
/// - 抖音 `DouyinRichSegment`(SFVideoLive packages/shared/src/protocol/
///   douyin/protobuf-lite.ts:613-618);
/// - twitch `TwitchEmoteSegment`(apps/web/src/utils/danmaku/twitchEmotes.ts:14-18)。
///
/// name 不单列:表情段 [text] 恒为 `[表情名]` 括号形态,UI 需要纯名字时
/// 去括号即可(web normalizeEmojiName 同语义)。
class DanmakuSegment {
  const DanmakuSegment({
    required this.type,
    this.text = '',
    this.url = '',
    this.name = '',
  });

  /// 文本段。
  const DanmakuSegment.text(this.text)
    : type = DanmakuSegmentType.text,
      url = '',
      name = '';

  /// 表情图段:[text] 为 `[表情名]`,[url] 为表情图 CDN(协议未携带时为空,
  /// UI 回退渲染 [text] 原文,web DanmakuRichText 同语义)。
  const DanmakuSegment.emoji({required this.text, this.url = '', this.name = ''})
    : type = DanmakuSegmentType.emoji;

  final DanmakuSegmentType type;
  final String text;

  /// 表情图 CDN 地址;文本段恒为空。
  final String url;

  /// 协议提供的可读名称,用于图片 alt/tooltip。
  final String name;

  bool get isEmoji => type == DanmakuSegmentType.emoji;

  @override
  bool operator ==(Object other) =>
      other is DanmakuSegment &&
      other.type == type &&
      other.text == text &&
      other.url == url &&
      other.name == name;

  @override
  int get hashCode => Object.hash(type, text, url, name);

  @override
  String toString() =>
      'DanmakuSegment(${type.name}, text: $text${url.isEmpty ? '' : ', url: $url'})';
}

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
    this.badgeKind = '',
    this.badgeUrl = '',
    this.badges = const [],
    this.guard,
    this.userLevelIconUrl = '',
    this.userLevelBadgeStyle = 0,
    this.userLevelIsPolished = 0,
    this.userLevelColor = 0,
    this.id = '',
    this.sentAt,
    this.rawType = '',
    this.segments = const [],
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

  /// 徽章语义。SOOP 支持同一条消息同时带订阅、管理员、铁粉、粉丝团；
  /// [badges] 是完整的顺序化徽章集合，[badgeName]/[badgeLevel] 保留首牌兼容。
  final String badgeKind;
  final String badgeUrl;
  final List<DanmakuBadge> badges;

  /// B站大航海等独立身份徽章;与普通粉丝牌分开显示。
  final DanmakuBadge? guard;

  /// 用户等级图标/样式元数据(平台协议直接提供时使用)。
  final String userLevelIconUrl;
  final int userLevelBadgeStyle;
  final int userLevelIsPolished;
  final int userLevelColor;

  /// 协议消息 id(空 = 未提供)。用于弹幕去重(协议重推同一条时按 id 判重),
  /// 消除「用户+正文」兜底 key 对同名同文的误杀。
  /// - huya:MessageNotice.sMessageId(tag 20);
  /// - bilibili:info[0][15].extra JSON 的 id_str(web bilibiliMeta.ts:274-290)。
  final String id;
  final DateTime? sentAt;

  /// 上游原始 type(如 `chatmsg`),便于 UI/日志区分细分来源。
  final String rawType;

  /// 富文本段:文本段与表情图段按序排列。
  ///
  /// **空(默认)= 纯文本**:UI 直接渲染 [text],零破坏;非空时 UI 按
  /// segments 渲染(文本段用 [text]、表情图段用图片 CDN),各文本段拼接
  /// 与 [text] 一致。
  /// - douyin:WebcastChatMessage Text(#22/#4) 的 image piece(web 真源
  ///   parseDouyinTextMessage,protobuf-lite.ts:494-527);
  /// - huya:MessageNotice 当前协议(web 真源 huyaJce.ts parseMessageNotice
  ///   391-435 行)无表情段,正文括号表情保持纯文本,segments 恒空。
  final List<DanmakuSegment> segments;
}
