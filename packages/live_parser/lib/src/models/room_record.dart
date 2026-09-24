/// 统一房间记录:浏览列表、状态刷新与播放详情共享的同一种房间(不可变)。
///
/// 钉住三类语义(2026-09-24 Windows 统一契约 Task 1):
/// 1. 状态真源是 [roomState],统计缺失为 `null`,有效 `'0'` 不当作缺失;
/// 2. 旧 JSON 键(`online`/`diamondFans`/缺 `roomState`)可读,[toJson]
///    迁移期同时输出兼容键,历史数据不丢;
/// 3. 刷新合并只覆盖有值字段、状态强制取 fresh,不把已有已知字段清空。
///
/// 请求/协议失败通过异常或 [error] 显式表达,不以“空房间”冒充成功。
library;

import 'models.dart';

/// 站点专属信息的类型化扩展上界。
///
/// 仅在统一公共字段不能无损表达、且 UI 确有展示需求时才新增 `sealed`
/// 子类;序列化必须带 [site] + 版本化判别标识,Windows 只能按类型匹配
/// 访问。当前没有具体子类,未知判别读取时安全回落 `null`(公共字段
/// 不受影响),不为九站创建空扩展。
sealed class RoomExtension {
  const RoomExtension({required this.site, required this.version});

  /// 扩展归属站点 id(序列化判别之一)。
  final String site;

  /// 扩展结构版本(序列化判别之一,子类结构变化时递增)。
  final int version;

  /// 输出带站点与版本判别的 JSON。
  Map<String, dynamic> toJson();
}

/// 统一房间记录:九站与 Windows 消费层共享的同一种房间值对象。
class RoomRecord {
  const RoomRecord({
    required this.site,
    required this.roomId,
    required this.roomState,
    this.title,
    this.anchorName,
    this.audience,
    this.followers,
    this.vip,
    this.svip,
    this.sourceUrl,
    this.cover,
    this.avatar,
    this.category,
    this.cid,
    this.cateNo,
    this.promoTag,
    this.startedAt,
    this.streams = const [],
    this.availableQualities = const [],
    this.source,
    this.fetchedAt,
    this.error,
    this.extension,
  });

  final String site;
  final String roomId;
  final RoomState roomState;

  // 展示。
  final String? title;
  final String? anchorName;
  final String? sourceUrl;
  final String? cover;
  final String? avatar;
  final String? category;
  final String? cid;
  final String? cateNo;
  final String? promoTag;

  /// 本场开播时间(平台真实返回时才有值,不伪造)。
  final DateTime? startedAt;

  // 统计:沿用当前格式化字符串口径;无实际值为 null,有效 `'0'` 不当作缺失。
  final String? audience;
  final String? followers;
  final String? vip;
  final String? svip;

  // 播放:非播放请求或离线为空列表,不凭空制造播放地址。
  final List<StreamQuality> streams;
  final List<QualityOption> availableQualities;

  // 来源/诊断:列表无此信息时可空。
  final String? source;
  final DateTime? fetchedAt;

  /// 请求/解析错误:显式保留,不转换为空房间。
  final String? error;

  /// 站点专属扩展(无实际扩展的站点为 null)。
  final RoomExtension? extension;

  /// 在播(状态真源是 [roomState],与统计数字无关)。
  bool get isLive => roomState == RoomState.live;

  /// 轮播/录播循环态(非实时直播)。
  bool get isReplay => roomState == RoomState.replay;

  /// 默认播放地址:首选画质的首选线路。
  String get playUrl =>
      streams.isEmpty ? '' : (streams.first.preferredLine?.url ?? '');

  /// 按画质名选择档位;未命中时回退首选档。
  ///
  /// 与 [RoomPayload.qualityByName] 同语义:精确、双向包含、回退首选档。
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

  /// 从浏览/刷新摘要转换(状态取 [RoomSummary.roomState] 真源,不从
  /// 统计数字推断在线)。
  factory RoomRecord.fromSummary(RoomSummary summary) => RoomRecord(
    site: summary.site,
    roomId: summary.roomId,
    roomState: summary.roomState,
    title: _blankToNull(summary.title),
    anchorName: _blankToNull(summary.anchorName),
    audience: _blankToNull(summary.online),
    followers: _blankToNull(summary.followers),
    vip: _blankToNull(summary.vip),
    svip: _blankToNull(summary.diamondFans),
    cover: _blankToNull(summary.cover),
    avatar: _blankToNull(summary.avatar),
    category: _blankToNull(summary.category),
    cid: _blankToNull(summary.cid),
    promoTag: _blankToNull(summary.promoTag),
    startedAt: summary.startedAt,
  );

  /// 回写浏览/刷新摘要(迁移期兼容;`null` 统计回旧口径空串)。
  RoomSummary toSummary() => RoomSummary(
    site: site,
    roomId: roomId,
    title: title ?? '',
    anchorName: anchorName ?? '',
    cid: cid ?? '',
    category: category ?? '',
    online: audience ?? '',
    cover: cover ?? '',
    avatar: avatar ?? '',
    promoTag: promoTag,
    followers: followers ?? '',
    vip: vip ?? '',
    diamondFans: svip ?? '',
    roomState: roomState,
    startedAt: startedAt,
  );

  /// 从播放详情转换(error/线路/来源诊断原样保留)。
  factory RoomRecord.fromPayload(RoomPayload payload) => RoomRecord(
    site: payload.site,
    roomId: payload.roomId,
    roomState: payload.roomState,
    title: _blankToNull(payload.title),
    anchorName: _blankToNull(payload.anchorName),
    sourceUrl: _blankToNull(payload.sourceUrl),
    cover: _blankToNull(payload.cover),
    avatar: _blankToNull(payload.avatar),
    category: _blankToNull(payload.category),
    cid: _blankToNull(payload.cid),
    cateNo: _blankToNull(payload.cateNo),
    streams: payload.streams,
    availableQualities: payload.availableQualities,
    source: _blankToNull(payload.source),
    fetchedAt: payload.fetchedAt,
    error: _blankToNull(payload.error),
    startedAt: payload.startedAt,
  );

  /// 回写播放详情(迁移期兼容;旧模型必填空字段以空串占位)。
  RoomPayload toPayload() => RoomPayload(
    site: site,
    roomId: roomId,
    sourceUrl: sourceUrl ?? '',
    anchorName: anchorName ?? '',
    title: title ?? '',
    cover: cover ?? '',
    avatar: avatar ?? '',
    category: category ?? '',
    cid: cid ?? '',
    roomState: roomState,
    cateNo: cateNo ?? '',
    streams: streams,
    availableQualities: availableQualities,
    source: source ?? '',
    fetchedAt: fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    error: error,
    startedAt: startedAt,
  );

  /// 轻量刷新合并:校验房间身份;状态强制取 [fresh];每个字段“此次
  /// 提供的覆盖、未提供的保留”;线路与画质仅在 fresh 非空时覆盖,
  /// 不把已有已知字段清空;真实离线状态靠 [RoomState] 覆盖旧在播。
  RoomRecord mergeRefresh(RoomRecord fresh) {
    if (site != fresh.site || roomId != fresh.roomId) {
      throw ArgumentError('cannot merge different rooms');
    }
    return RoomRecord(
      site: site,
      roomId: roomId,
      roomState: fresh.roomState,
      title: fresh.title ?? title,
      anchorName: fresh.anchorName ?? anchorName,
      audience: fresh.audience ?? audience,
      followers: fresh.followers ?? followers,
      vip: fresh.vip ?? vip,
      svip: fresh.svip ?? svip,
      sourceUrl: fresh.sourceUrl ?? sourceUrl,
      cover: fresh.cover ?? cover,
      avatar: fresh.avatar ?? avatar,
      category: fresh.category ?? category,
      cid: fresh.cid ?? cid,
      cateNo: fresh.cateNo ?? cateNo,
      promoTag: fresh.promoTag ?? promoTag,
      startedAt: fresh.startedAt ?? startedAt,
      streams: fresh.streams.isNotEmpty ? fresh.streams : streams,
      availableQualities: fresh.availableQualities.isNotEmpty
          ? fresh.availableQualities
          : availableQualities,
      source: fresh.source ?? source,
      fetchedAt: fresh.fetchedAt ?? fetchedAt,
      error: fresh.error ?? error,
      extension: fresh.extension ?? extension,
    );
  }

  Map<String, dynamic> toJson() => {
    'site': site,
    'roomId': roomId,
    'roomState': roomState.name,
    if (title != null) 'title': title,
    if (anchorName != null) 'anchorName': anchorName,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (cover != null) 'cover': cover,
    if (avatar != null) 'avatar': avatar,
    if (category != null) 'category': category,
    if (cid != null) 'cid': cid,
    if (cateNo != null) 'cateNo': cateNo,
    if (promoTag != null) 'promoTag': promoTag,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (audience != null) 'audience': audience,
    if (followers != null) 'followers': followers,
    if (vip != null) 'vip': vip,
    if (svip != null) 'svip': svip,
    // 迁移期兼容键:旧消费者依赖 online 键恒存在,空串表示未提供;
    // diamondFans 仅在有值时输出,不序列化伪造的零。
    'online': audience ?? '',
    if (svip != null) 'diamondFans': svip,
    'streams': streams.map((s) => s.toJson()).toList(),
    'availableQualities': availableQualities.map((q) => q.toJson()).toList(),
    if (source != null) 'source': source,
    if (fetchedAt != null) 'fetchedAt': fetchedAt!.toIso8601String(),
    if (error != null) 'error': error,
    if (extension != null) 'extension': extension!.toJson(),
  };

  /// 读取新旧 JSON:旧键 `online`/`diamondFans`/`nickname` 归一到公共
  /// 字段;缺 `roomState` 的历史数据按旧 `online` 非空判在播(仅用于
  /// 读取历史数据,显式 `roomState` 是真源);未知扩展安全回落 null。
  factory RoomRecord.fromJson(Map<String, dynamic> json) {
    final audience = _blankToNull(
      (json['audience'] ?? json['online'])?.toString(),
    );
    return RoomRecord(
      site: json['site']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? '',
      roomState: _roomStateFromJson(json, audience),
      title: _blankToNull(json['title']?.toString()),
      anchorName: _blankToNull(
        (json['nickname'] ?? json['anchorName'])?.toString(),
      ),
      audience: audience,
      followers: _blankToNull(json['followers']?.toString()),
      vip: _blankToNull(json['vip']?.toString()),
      svip: _blankToNull((json['svip'] ?? json['diamondFans'])?.toString()),
      sourceUrl: _blankToNull(json['sourceUrl']?.toString()),
      cover: _blankToNull(json['cover']?.toString()),
      avatar: _blankToNull(json['avatar']?.toString()),
      category: _blankToNull(json['category']?.toString()),
      cid: _blankToNull(json['cid']?.toString()),
      cateNo: _blankToNull(json['cateNo']?.toString()),
      promoTag: _blankToNull(json['promoTag']?.toString()),
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
      streams: ((json['streams'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => StreamQuality.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      availableQualities: ((json['availableQualities'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => QualityOption.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      source: _blankToNull(json['source']?.toString()),
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? ''),
      error: _blankToNull(json['error']?.toString()),
      extension: _readExtension(json['extension']),
    );
  }

  /// 空串视作“未提供”归一为 null;有效 `'0'` 保留。
  static String? _blankToNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  static RoomState _roomStateFromJson(
    Map<String, dynamic> json,
    String? audience,
  ) {
    final raw = json['roomState']?.toString();
    if (raw == null) {
      // 历史数据缺 roomState:按旧 online 非空判在播,仅用于读取旧数据。
      return audience != null ? RoomState.live : RoomState.offline;
    }
    // 未知值与 RoomSummary.fromJson 同口径回落 offline。
    return RoomState.values.firstWhere(
      (state) => state.name == raw,
      orElse: () => RoomState.offline,
    );
  }

  static RoomExtension? _readExtension(Object? raw) {
    // 当前尚无已知扩展子类:未知或缺失判别一律安全回落 null,公共字段
    // 照常读取;首个具体子类落地时在此按 site + version 分发。
    return null;
  }
}
