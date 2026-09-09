/// 我的关注状态层:关注条目模型 + Notifier 控制器。
/// UI(follow_view / widgets)只负责渲染,业务状态全部收敛在此。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/fixture_sources.dart';

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

/// 关注列表控制器:单条增删、特别关注/提醒开关与批量操作。
class FollowController extends Notifier<List<FollowEntry>> {
  @override
  List<FollowEntry> build() => _seed();

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
  }

  /// 切换单条开播提醒。
  void toggleRemind(String key) {
    state = [
      for (final entry in state)
        if (entry.key == key) entry.copyWith(remindOn: !entry.remindOn) else entry,
    ];
  }

  /// 移除单条关注。
  void remove(String key) {
    state = [for (final entry in state) if (entry.key != key) entry];
  }

  /// 批量移除(删除所选)。
  void removeMany(Iterable<String> keys) {
    final targets = keys.toSet();
    state = [for (final entry in state) if (!targets.contains(entry.key)) entry];
  }

  /// 批量开关提醒。
  void setRemindMany(Iterable<String> keys, bool enabled) {
    final targets = keys.toSet();
    state = [
      for (final entry in state)
        targets.contains(entry.key) ? entry.copyWith(remindOn: enabled) : entry,
    ];
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
  }
}

/// 关注列表 provider(应用级,不随页面销毁)。
final followProvider =
    NotifierProvider<FollowController, List<FollowEntry>>(FollowController.new);
