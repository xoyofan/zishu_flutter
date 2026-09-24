/// 我的关注状态层:关注条目模型 + Notifier 控制器 + data-server 云同步。
/// UI(follow_view / widgets)只负责渲染,业务状态全部收敛在此。
///
/// 云同步策略(整表替换,后写赢):
/// - 启动/登录后:拉取远端关注;远端非空则**替换**本地(服务端为准),
///   远端为空(首次使用)则把本地整表推上去;
/// - 本地任何增删改:落盘后把当前整表推给服务端
///   (服务端 `POST /api/me/follows` = 全量替换 + clientUpdatedAt 逐条合并,
///   删除随之同步)。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/application/auth_provider.dart';
import '../../../shared/application/data_server_api.dart';
import '../../../shared/application/fixture_sources.dart';
import '../../../shared/application/providers.dart' show roomRefresherProvider;
import '../../../shared/domain/category_display.dart';

/// 关注列表持久化键(SharedPreferencesAsync,带前缀避免与其它模块冲突)。
const String _kFollowList = 'zishu.follow.list';

/// 单条关注:契约房间模型 + 关注维度的本地标记。
class FollowEntry {
  const FollowEntry({
    required this.room,
    required this.isSpecial,
    required this.remindOn,
    required this.followedAt,
    this.lastLiveAt = 0,
    this.liveStartAt = 0,
  });

  /// 契约房间模型(与解析核心共享,UI 不消费松散 Map)。
  final RoomSummary room;

  /// 特别关注(金色 ★ 标识,排序置前)。
  final bool isSpecial;

  /// 开播提醒开关。
  final bool remindOn;

  /// 关注时间,用于「最近关注」排序。
  final DateTime followedAt;

  /// 上次开播时间(毫秒 epoch;0 = 无记录)。离线卡据此显示
  /// 「上次开播 MM-DD HH:mm」,语义对齐 web `followDisplay.offlineLastLiveLabel`。
  ///
  /// 数据来源:云端契约 [RemoteFollow.lastLiveAt] 与本地「在播 → 离线」跃迁
  /// 检测,合并一律取 max(见 [mergedInt]),防止旧值/0 值抹掉新记录。
  final int lastLiveAt;

  /// 最近一次开播的起点(毫秒 epoch;0 = 无记录),云端契约透传字段,
  /// 供后续「直播时长」类展示使用,本轮不参与 UI。
  final int liveStartAt;

  /// 稳定键:平台 + 房间号,批量选择/增删都以它定位。
  String get key => '${room.site}:${room.roomId}';

  /// 是否开播:fixture 约定 online 为空即离线。
  bool get isLive => room.online.trim().isNotEmpty;

  /// 是否轮播(录播循环):来自契约 [RoomSummary.roomState],刷新链路
  /// (bilibili live_status==2 / douyu videoLoop==1 / huya 录播)回填。
  /// 轮播的 online 同离线一样为空串 —— isLive 与 isReplay 互斥。
  bool get isReplay => room.roomState == RoomState.replay;

  FollowEntry copyWith({
    RoomSummary? room,
    bool? isSpecial,
    bool? remindOn,
    DateTime? followedAt,
    int? lastLiveAt,
    int? liveStartAt,
  }) {
    return FollowEntry(
      room: room ?? this.room,
      isSpecial: isSpecial ?? this.isSpecial,
      remindOn: remindOn ?? this.remindOn,
      followedAt: followedAt ?? this.followedAt,
      lastLiveAt: lastLiveAt ?? this.lastLiveAt,
      liveStartAt: liveStartAt ?? this.liveStartAt,
    );
  }
}

/// 「上次开播」类时间戳的合并口径:取较大者。
///
/// 云端拉回可能是旧值或 0(远端从未见过该房开播),本地跃迁记录又可能比
/// 云端新 —— 一律取 max,任何一侧都不得把另一侧抹成更早/空。
int mergedInt(int a, int b) => a > b ? a : b;

/// 关注列表控制器:单条增删、特别关注/提醒开关、批量操作与云端同步。
class FollowController extends Notifier<List<FollowEntry>> {
  final DataServerApi _api = DataServerApi();

  /// 云同步进行中标记(防 pull/push 重入)。
  bool _syncing = false;

  /// 分批刷新的游标(见 [refreshStatuses]):在关注列表上环状推进,
  /// 让定时轮询每周期只打一批而不重复同一批。
  int _refreshCursor = 0;

  @override
  List<FollowEntry> build() {
    // 启动时异步从本地存储恢复;完成前 UI 先使用 fixture 种子(空存储时种子即初始数据)。
    Future.microtask(_restore);
    return _seed();
  }

  /// fixture 初始 6 条:由 kFixtureRooms 派生,
  /// 含 2 条特别关注、1 条离线(离线条目把 online 置空,用 online.isEmpty 表达)。
  static List<FollowEntry> _seed() {
    final rooms = kFixtureRooms.take(6).toList();
    final now = DateTime.now();

    // 复制为离线房间:online 置空,其余字段保持契约形状。
    RoomSummary asOffline(RoomSummary source) => RoomSummary(
          site: source.site,
          roomId: source.roomId,
          title: source.title,
          anchorName: source.anchorName,
          cid: source.cid,
          category: source.category,
          online: '',
          cover: source.cover,
          avatar: source.avatar,
          startedAt: source.startedAt,
        );

    return [
      FollowEntry(
        room: rooms[0],
        isSpecial: true,
        remindOn: true,
        followedAt: now.subtract(const Duration(hours: 3)),
      ),
      FollowEntry(
        room: rooms[1],
        isSpecial: false,
        remindOn: false,
        followedAt: now.subtract(const Duration(hours: 27)),
      ),
      FollowEntry(
        room: rooms[2],
        isSpecial: false,
        remindOn: true,
        followedAt: now.subtract(const Duration(days: 5)),
      ),
      FollowEntry(
        room: rooms[3],
        isSpecial: true,
        remindOn: false,
        followedAt: now.subtract(const Duration(days: 9)),
      ),
      FollowEntry(
        room: rooms[4],
        isSpecial: false,
        remindOn: false,
        followedAt: now.subtract(const Duration(days: 12)),
      ),
      FollowEntry(
        room: asOffline(rooms[5]),
        isSpecial: false,
        remindOn: false,
        followedAt: now.subtract(const Duration(days: 15)),
      ),
    ];
  }

  /// 切换特别关注标记。
  void toggleSpecial(String key) {
    state = [
      for (final entry in state)
        if (entry.key == key) entry.copyWith(isSpecial: !entry.isSpecial) else entry,
    ];
    _persist();
  }

  /// 切换单条开播提醒。
  void toggleRemind(String key) {
    state = [
      for (final entry in state)
        if (entry.key == key) entry.copyWith(remindOn: !entry.remindOn) else entry,
    ];
    _persist();
  }

  /// 移除单条关注。
  void remove(String key) {
    state = [for (final entry in state) if (entry.key != key) entry];
    _persist();
  }

  /// 批量移除(删除所选)。
  void removeMany(Iterable<String> keys) {
    final targets = keys.toSet();
    state = [for (final entry in state) if (!targets.contains(entry.key)) entry];
    _persist();
  }

  /// 批量开关提醒。
  void setRemindMany(Iterable<String> keys, bool enabled) {
    final targets = keys.toSet();
    state = [
      for (final entry in state)
        targets.contains(entry.key) ? entry.copyWith(remindOn: enabled) : entry,
    ];
    _persist();
  }

  /// 从房间加入关注(已存在则幂等跳过);
  /// 可携带原条目的标记与关注时间,用于删除后的「撤销」恢复。
  void addFromRoom(
    RoomSummary room, {
    bool isSpecial = false,
    bool remindOn = false,
    DateTime? followedAt,
  }) {
    final key = '${room.site}:${room.roomId}';
    final exists = state.any((entry) => entry.key == key);
    if (exists) return;
    state = [
      FollowEntry(
        room: room,
        isSpecial: isSpecial,
        remindOn: remindOn,
        followedAt: followedAt ?? DateTime.now(),
      ),
      ...state,
    ];
    _persist();
  }

  /// 刷新关注列表的房间状态(真实解析源才可用;无能力时返回 0)。
  ///
  /// 有界并发(4)+ 单条 10s 超时;单条失败保留原数据 —— 网络抖动不得把在播
  /// 房间刷成离线。成功条目以刷新元信息(在线数/标题/封面/分类)为准,但保留
  /// 本地 cid:刷新结果没有分类上下文,覆盖会破坏「我的分类」跳转。
  ///
  /// [limit] > 0 时按 [_refreshCursor] 取一段**窗口**环状刷新(定时轮询用,
  /// 关注 N 条时在 ceil(N/limit) 个周期内全覆盖);= 0 时全量刷新(用户
  /// 主动下拉/点刷新)。返回本轮实际刷新成功的条数。
  Future<int> refreshStatuses({int limit = 0}) async {
    final refresher = ref.read(roomRefresherProvider);
    final entries = state;
    if (refresher == null || entries.isEmpty) return 0;

    final targets = _pickRefreshWindow(entries, limit);
    if (targets.isEmpty) return 0;

    final updated = <String, RoomSummary>{};
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= targets.length) return;
        final entry = targets[index];
        try {
          final room = await refresher
              .refreshRoom(site: entry.room.site, roomId: entry.room.roomId)
              .timeout(const Duration(seconds: 10));
          updated[entry.key] = _mergeRefreshed(entry.room, room);
        } catch (_) {
          // 单条失败:保留原条目,不翻转离线。
        }
      }
    }

    final workers = targets.length < 4 ? targets.length : 4;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);

    // 容器已销毁(应用退出/测试回收)时不再写 state 与存储。
    if (!ref.mounted) return 0;
    if (updated.isEmpty) return 0;
    // 以最新 state 重建:刷新期间用户可能已增删条目,不能被过期快照覆盖。
    // 离线跃迁:原在播、刷新后离线 → 把当下记为「上次开播」(本地数据源的
    // lastLiveAt 就来自这里;云端契约透传值在 pullRemote 侧以 max 合并)。
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    state = [
      for (final entry in state)
        entry.copyWith(
          room: updated[entry.key] ?? entry.room,
          lastLiveAt: _bumpedLastLiveAt(entry, updated[entry.key], nowMs),
        ),
    ];
    await _persist();
    return updated.length;
  }

  /// 刷新后该条目的 lastLiveAt:仅在「原本在播 → 刷新后离线」跃迁时记为
  /// [nowMs](与已有值取 max);其余情况维持原值,不得因刷新回填而清零。
  static int _bumpedLastLiveAt(
    FollowEntry entry,
    RoomSummary? fresh,
    int nowMs,
  ) {
    if (fresh == null) return entry.lastLiveAt;
    final wasLive = entry.isLive;
    final nowOffline = fresh.online.trim().isEmpty;
    if (wasLive && nowOffline) return mergedInt(entry.lastLiveAt, nowMs);
    return entry.lastLiveAt;
  }

  /// 取本轮刷新窗口:`limit <= 0` 或超过总数时取全量并复位游标;
  /// 否则从游标处环状取 [limit] 条,游标同步前进。
  List<FollowEntry> _pickRefreshWindow(List<FollowEntry> entries, int limit) {
    if (limit <= 0 || limit >= entries.length) {
      _refreshCursor = 0;
      return entries;
    }
    final window = <FollowEntry>[
      for (var i = 0; i < limit; i++)
        entries[(_refreshCursor + i) % entries.length],
    ];
    _refreshCursor = (_refreshCursor + limit) % entries.length;
    return window;
  }

  /// 刷新结果与本地条目合并。字段口径(逐字段核对,勿凭感觉增删):
  ///
  /// **以刷新返回为准**(主播元信息会变,刷新就是为了拿最新值):
  /// - `title`/`anchorName`/`cover`:刷新非空则更新,空回退本地
  ///   (上游偶发缺字段,不能把已有值冲掉);
  /// - `category`:刷新非空则更新 —— **主播换分类后必须跟随**,
  ///   (此前的「不同步」正是合并层没有明确这一口径的地方,现钉死:
  ///   分类是上游元信息,不是本地标记)。存储前经
  ///   [displayCategoryName] 归一为中文显示名:解析核心的刷新只带回
  ///   原始名/缩写 + 分区 cid(如 huya 'lol'+gid),不负责归一;
  ///   归一未命中(无跨平台映射)时保持原名;
  /// - `online`:无条件取刷新值,空串即平台明确未开播(在播判据);
  /// - `roomState`:无条件取刷新值 —— 在播/轮播/离线三态互转都跟随
  ///   上游(主播停播改轮播、轮播恢复开播都靠它感知);
  /// - `followers`/`vip`:刷新非空则更新,空回退本地(统计展示增强,
  ///   上游没给就保留上次拿到的值)。
  ///
  /// **保留本地语义**(本地数据源/跳转上下文,刷新结果不可信):
  /// - `cid`:本地非空则保留 —— 关注条目的 cid 是「加入关注时所在分类」
  ///   的跳转上下文;各站刷新接口返回的 cid 口径与 payload 不一致
  ///   (如 douyin cid=房间号),覆盖会破坏「我的分类」跳转;
  /// - `site`/`roomId`:身份键,恒取本地。
  ///
  /// FollowEntry 层的 `followedAt`/`isSpecial`/`remindOn`/`lastLiveAt`
  /// 不在 [RoomSummary] 内,由 [refreshStatuses] 的 copyWith 保持不变。
  static RoomSummary _mergeRefreshed(RoomSummary current, RoomSummary fresh) {
    final mergedCid = current.cid.isNotEmpty ? current.cid : fresh.cid;
    return RoomSummary(
      site: current.site,
      roomId: current.roomId,
      title: fresh.title.trim().isNotEmpty ? fresh.title : current.title,
      anchorName: fresh.anchorName.trim().isNotEmpty
          ? fresh.anchorName
          : current.anchorName,
      cid: mergedCid,
      category: fresh.category.trim().isNotEmpty
          ? displayCategoryName(current.site, fresh.category, mergedCid)
          : current.category,
      // online 以刷新为准:空串即平台明确未开播。
      online: fresh.online,
      cover: fresh.cover.trim().isNotEmpty ? fresh.cover : current.cover,
      // 头像:刷新非空则更新(同 cover 口径;上游没给就保留上次拿到的值)。
      avatar: fresh.avatar.trim().isNotEmpty ? fresh.avatar : current.avatar,
      startedAt: fresh.startedAt ?? current.startedAt,
      // roomState 以刷新为准:在线/轮播/离线互转跟随上游。
      roomState: fresh.roomState,
      followers: fresh.followers.trim().isNotEmpty
          ? fresh.followers
          : current.followers,
      vip: fresh.vip.trim().isNotEmpty ? fresh.vip : current.vip,
      // 第 3 列(web `ROOM_STAT_COLUMNS` 的 `diamondFans` 槽)同 vip 口径:
      // 上游没取到(huya wup 失败 / 平台未实现)时保留已有值,不抹成空。
      diamondFans: fresh.diamondFans.trim().isNotEmpty
          ? fresh.diamondFans
          : current.diamondFans,
    );
  }

  /// 登录 token:登录态 provider 尚未构建时返回 null,不强制构建
  /// authProvider——播放页等非壳场景不触发其启动登录链(测试零网络)。
  /// 容器已销毁时同样返回 null:异步恢复任务可能在 dispose 后到达此处。
  String? get _authToken =>
      ref.mounted && ref.exists(authProvider)
      ? ref.read(authProvider).token
      : null;

  /// 拉取云端关注并合并到本地(登录态才有效)。
  /// 远端非空 → 替换本地;远端为空 → 把本地整表推上去(首次云同步)。
  Future<void> pullRemote() async {
    final token = _authToken;
    if (token == null || _syncing) return;
    _syncing = true;
    try {
      final remote = await _api.fetchFollows(token);
      if (!ref.mounted) return;
      if (remote.isNotEmpty) {
        // 整表以云端为准,但「上次开播」类时间戳与本地同 key 条目取 max:
        // 本地跃迁记录可能比云端新,不得被拉回抹掉。
        final localByKey = {for (final entry in state) entry.key: entry};
        state = [
          for (final item in remote)
            _fromRemote(item, localByKey['${item.site}:${item.id}']),
        ];
        await _persist(syncRemote: false);
        // 云端契约不带分类/在播/统计元信息(见 [_fromRemote] 的置空),整表
        // 替换后立即补一轮刷新回填,不等 60s 轮询 —— 否则关注行分类条与
        // 侧栏头统计要空一个轮询周期。无 refresher(fixture/单测)时该调用
        // 零网络直接返回 0。
        unawaited(refreshStatuses());
      } else {
        await _pushRemote(token);
      }
    } on Exception {
      // 网络失败/会话失效:保留本地数据,不阻塞 UI;下次改动会再次尝试推送。
    } finally {
      _syncing = false;
    }
  }

  /// 从本地存储恢复关注列表,随后等待登录态就绪并拉取云端。
  /// 无数据或解析失败时保留当前种子(空存储时即初始 fixture)。
  Future<void> _restore() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_kFollowList);
      if (raw == null || raw.isEmpty) {
        // 首次使用:把 fixture 种子落盘,后续启动直接读存储。
        await _persist();
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final entries = [
            for (final item in decoded)
              if (item is Map)
                FollowEntry(
                  room: RoomSummary(
                    site: item['site']?.toString() ?? '',
                    roomId: item['roomId']?.toString() ?? '',
                    title: item['title']?.toString() ?? '',
                    anchorName:
                        item['uname']?.toString() ?? item['anchorName']?.toString() ?? '',
                    cid: item['cid']?.toString() ?? '',
                    category: item['category']?.toString() ?? '',
                    online: item['online']?.toString() ?? '',
                    cover: item['cover']?.toString() ?? '',
                    avatar: item['avatar']?.toString() ?? '',
                    roomState: RoomState.values.firstWhere(
                      (state) => state.name == item['roomState'],
                      orElse: () => RoomState.offline,
                    ),
                    startedAt: DateTime.tryParse(
                      item['startedAt']?.toString() ?? '',
                    ),
                    followers: item['followers']?.toString() ?? '',
                    vip: item['vip']?.toString() ?? '',
                    diamondFans: item['diamondFans']?.toString() ?? '',
                  ),
                  isSpecial: item['isSpecial'] == true,
                  remindOn: item['remindOn'] == true,
                  followedAt: item['followedAt'] is String
                      ? DateTime.tryParse(item['followedAt'] as String) ?? DateTime.now()
                      : DateTime.now(),
                  lastLiveAt: (item['lastLiveAt'] as num?)?.toInt() ?? 0,
                  liveStartAt: (item['liveStartAt'] as num?)?.toInt() ?? 0,
                ),
          ];
          if (entries.isNotEmpty) state = entries;
        }
      }
    } catch (_) {
      // 存储不可用/数据损坏:静默保留种子,不阻塞 UI。
    }

    // 尝试拉取云端关注:登录态已就绪(顶栏账号区已构建 authProvider)且
    // token 可用则直接拉;手动登录在后时由顶栏的登录监听触发 pullRemote。
    // 匿名/未就绪时静默跳过,不产生任何网络调用。
    if (!ref.mounted) return;
    await pullRemote();
  }

  /// 本地条目 → 远端契约(avatar/cid/category 在远端为扩展字段,zishu 侧置空)。
  RemoteFollow _toRemote(FollowEntry entry, int nowMs) {
    return RemoteFollow(
      site: entry.room.site,
      id: entry.room.roomId,
      title: entry.room.title,
      anchor: entry.room.anchorName,
      cover: entry.room.cover,
      avatar: '',
      addedAt: entry.followedAt.millisecondsSinceEpoch,
      superFollow: entry.isSpecial,
      liveNotify: entry.remindOn,
      clientUpdatedAt: nowMs,
      lastLiveAt: entry.lastLiveAt,
      liveStartAt: entry.liveStartAt,
    );
  }

  /// 远端契约 → 本地条目(开播状态远端不回传,先按离线呈现,待真实解析链路回填)。
  ///
  /// [previous] 为本地已有条目(按同 key 匹配):「上次开播」类时间戳与本地
  /// 取 max —— 云端可能是旧值/0 值,不得把本地刚记录的跃迁抹掉。
  FollowEntry _fromRemote(RemoteFollow item, [FollowEntry? previous]) {
    final entry = FollowEntry(
      room: RoomSummary(
        site: item.site,
        roomId: item.id,
        title: item.title,
        anchorName: item.anchor,
        cid: '',
        category: '',
        online: '',
        cover: item.cover,
      ),
      isSpecial: item.superFollow,
      remindOn: item.liveNotify,
      followedAt: item.addedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(item.addedAt)
          : DateTime.now(),
      lastLiveAt: item.lastLiveAt,
      liveStartAt: item.liveStartAt,
    );
    if (previous == null) return entry;
    return entry.copyWith(
      lastLiveAt: mergedInt(entry.lastLiveAt, previous.lastLiveAt),
      liveStartAt: mergedInt(entry.liveStartAt, previous.liveStartAt),
    );
  }

  /// 整表推送到服务端(登录态才有效)。
  Future<void> _pushRemote(String token) async {
    if (_syncing || !ref.mounted) return;
    _syncing = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _api.pushFollows(token, [
        for (final entry in state) _toRemote(entry, now),
      ]);
    } on Exception {
      // 推送失败静默:本地已落盘,下次改动会再推。
    } finally {
      _syncing = false;
    }
  }

  /// 把关注列表序列化为 JSON 字符串写入本地存储;[syncRemote] 时随后整表推云端。
  ///
  /// 字段契约:{site, roomId, title, uname, cover} + 元信息(cid/category/
  /// online/roomState/followers/vip/diamondFans/avatar,刷新回填后随落盘保留)+ 本地标记
  /// (isSpecial/remindOn/followedAt),与任务卡 A8 约定的关注落库结构一致。
  Future<void> _persist({bool syncRemote = true}) async {
    try {
      final payload = [
        for (final entry in state)
          {
            'site': entry.room.site,
            'roomId': entry.room.roomId,
            'title': entry.room.title,
            'uname': entry.room.anchorName,
            'cover': entry.room.cover,
            'avatar': entry.room.avatar,
            'cid': entry.room.cid,
            'category': entry.room.category,
            'online': entry.room.online,
            'roomState': entry.room.roomState.name,
            if (entry.room.startedAt != null)
              'startedAt': entry.room.startedAt!.toIso8601String(),
            'followers': entry.room.followers,
            'vip': entry.room.vip,
            'diamondFans': entry.room.diamondFans,
            'isSpecial': entry.isSpecial,
            'remindOn': entry.remindOn,
            'followedAt': entry.followedAt.toIso8601String(),
            'lastLiveAt': entry.lastLiveAt,
            'liveStartAt': entry.liveStartAt,
          },
      ];
      await SharedPreferencesAsync().setString(_kFollowList, jsonEncode(payload));
    } catch (_) {
      // 写盘失败:内存态仍生效,下次启动回退旧值。
    }
    if (syncRemote) {
      final token = _authToken;
      if (token != null) {
        unawaited(_pushRemote(token));
      }
    }
  }
}

/// 关注列表 provider(应用级,不随页面销毁)。
final followProvider =
    NotifierProvider<FollowController, List<FollowEntry>>(FollowController.new);
