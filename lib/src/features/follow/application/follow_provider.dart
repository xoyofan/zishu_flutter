/// 我的关注状态层:关注条目模型 + Notifier 控制器。
/// UI(follow_view / widgets)只负责渲染,业务状态全部收敛在此。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 关注列表控制器:单条增删、特别关注/提醒开关与批量操作。
class FollowController extends Notifier<List<FollowEntry>> {
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

  /// 从本地存储恢复关注列表;无数据或解析失败时保留当前种子(空存储时即初始 fixture)。
  Future<void> _restore() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_kFollowList);
      if (raw == null || raw.isEmpty) {
        // 首次使用:把 fixture 种子落盘,后续启动直接读存储。
        _persist();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final entries = [
        for (final item in decoded)
          if (item is Map)
            FollowEntry(
              room: RoomSummary(
                site: item['site']?.toString() ?? '',
                roomId: item['roomId']?.toString() ?? '',
                title: item['title']?.toString() ?? '',
                anchorName: item['uname']?.toString() ?? item['anchorName']?.toString() ?? '',
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
      state = entries;
    } catch (_) {
      // 存储不可用/数据损坏:静默保留种子,不阻塞 UI。
    }
  }

  /// 把关注列表序列化为 JSON 字符串写入本地存储。
  ///
  /// 字段契约:{site, roomId, title, uname, cover} + 本地标记(isSpecial/remindOn/
  /// followedAt),与任务卡 A8 约定的关注落库结构一致。
  Future<void> _persist() async {
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
  }
}

/// 关注列表 provider(应用级,不随页面销毁)。
final followProvider =
    NotifierProvider<FollowController, List<FollowEntry>>(FollowController.new);
