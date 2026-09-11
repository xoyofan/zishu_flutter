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

/// 关注列表持久化键(SharedPreferencesAsync,带前缀避免与其它模块冲突)。
const String _kFollowList = 'zishu.follow.list';

/// 单条关注:契约房间模型 + 关注维度的本地标记。
class FollowEntry {
  const FollowEntry({
    required this.room,
    required this.isSpecial,
    required this.remindOn,
    required this.followedAt,
  });

  /// 契约房间模型(与解析核心共享,UI 不消费松散 Map)。
  final RoomSummary room;

  /// 特别关注(金色 ★ 标识,排序置前)。
  final bool isSpecial;

  /// 开播提醒开关。
  final bool remindOn;

  /// 关注时间,用于「最近关注」排序。
  final DateTime followedAt;

  /// 稳定键:平台 + 房间号,批量选择/增删都以它定位。
  String get key => '${room.site}:${room.roomId}';

  /// 是否开播:fixture 约定 online 为空即离线。
  bool get isLive => room.online.trim().isNotEmpty;

  FollowEntry copyWith({
    RoomSummary? room,
    bool? isSpecial,
    bool? remindOn,
    DateTime? followedAt,
  }) {
    return FollowEntry(
      room: room ?? this.room,
      isSpecial: isSpecial ?? this.isSpecial,
      remindOn: remindOn ?? this.remindOn,
      followedAt: followedAt ?? this.followedAt,
    );
  }
}

/// 关注列表控制器:单条增删、特别关注/提醒开关、批量操作与云端同步。
class FollowController extends Notifier<List<FollowEntry>> {
  final DataServerApi _api = DataServerApi();

  /// 云同步进行中标记(防 pull/push 重入)。
  bool _syncing = false;

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

  /// 登录 token:登录态 provider 尚未构建时返回 null,不强制构建
  /// authProvider——播放页等非壳场景不触发其启动登录链(测试零网络)。
  String? get _authToken =>
      ref.exists(authProvider) ? ref.read(authProvider).token : null;

  /// 拉取云端关注并合并到本地(登录态才有效)。
  /// 远端非空 → 替换本地;远端为空 → 把本地整表推上去(首次云同步)。
  Future<void> pullRemote() async {
    final token = _authToken;
    if (token == null || _syncing) return;
    _syncing = true;
    try {
      final remote = await _api.fetchFollows(token);
      if (remote.isNotEmpty) {
        state = [for (final item in remote) _fromRemote(item)];
        await _persist(syncRemote: false);
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
                  ),
                  isSpecial: item['isSpecial'] == true,
                  remindOn: item['remindOn'] == true,
                  followedAt: item['followedAt'] is String
                      ? DateTime.tryParse(item['followedAt'] as String) ?? DateTime.now()
                      : DateTime.now(),
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
    );
  }

  /// 远端契约 → 本地条目(开播状态远端不回传,先按离线呈现,待真实解析链路回填)。
  FollowEntry _fromRemote(RemoteFollow item) {
    return FollowEntry(
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
    );
  }

  /// 整表推送到服务端(登录态才有效)。
  Future<void> _pushRemote(String token) async {
    if (_syncing) return;
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
  /// 字段契约:{site, roomId, title, uname, cover} + 本地标记(isSpecial/remindOn/
  /// followedAt),与任务卡 A8 约定的关注落库结构一致。
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
            'cid': entry.room.cid,
            'category': entry.room.category,
            'online': entry.room.online,
            'isSpecial': entry.isSpecial,
            'remindOn': entry.remindOn,
            'followedAt': entry.followedAt.toIso8601String(),
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
