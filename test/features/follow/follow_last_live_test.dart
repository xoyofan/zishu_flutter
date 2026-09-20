/// 离线关注卡「上次开播」链路单测。
///
/// 对齐 web `followDisplay.offlineLastLiveLabel` 的语义:离线且有过开播记录时
/// 显示「上次开播 MM-DD HH:mm」,否则「未开播」。
///
/// 数据链路(四段全覆盖):
/// 1. **本地恢复**:存储 JSON 的 `lastLiveAt` → `FollowEntry.lastLiveAt`(此前被丢弃);
/// 2. **离线跃迁**:刷新观察到「在播 → 离线」时记录当下为上次开播时间;
/// 3. **持久化往返**:再落盘不得丢字段;
/// 4. **文案渲染**:卡片离线态按 lastLiveAt 显示对应文案。
///
/// 宿主写法与 follow_status_refresh_test 一致(ProviderContainer + 内存存储)。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show RoomPayload, RoomSummary;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_common.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_card.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

/// 假刷新源(与 follow_status_refresh_test 同构,按脚本返回结果)。
class _FakeRefresher implements RoomRefresher {
  _FakeRefresher({this.results = const {}});

  final Map<String, RoomSummary> results;

  @override
  Future<RoomSummary> refreshRoom({
    required String site,
    required String roomId,
  }) async {
    final room = results[roomId];
    if (room == null) throw StateError('no scripted result: $roomId');
    return room;
  }

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    throw UnimplementedError('本轨不校验解析路径');
  }
}

Map<String, Object> _seedEntry({
  required String roomId,
  required String online,
  int lastLiveAt = 0,
}) => {
  'site': 'douyu',
  'roomId': roomId,
  'title': '标题',
  'uname': '主播$roomId',
  'cover': 'https://cdn/cover.jpg',
  'cid': '',
  'category': '网游',
  'online': online,
  'isSpecial': false,
  'remindOn': false,
  'followedAt': '2026-09-01T00:00:00.000Z',
  if (lastLiveAt != 0) 'lastLiveAt': lastLiveAt,
};

RoomSummary _fresh({required String roomId, required String online}) =>
    RoomSummary(
      site: 'douyu',
      roomId: roomId,
      title: '标题',
      anchorName: '主播$roomId',
      cid: '',
      category: '网游',
      online: online,
      cover: 'https://cdn/cover.jpg',
    );

Future<ProviderContainer> _container({
  required List<Map<String, Object>> seed,
  RoomRefresher? refresher,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(<String, Object>{
        'zishu.follow.list': jsonEncode(seed),
      });
  final container = ProviderContainer(
    overrides: [
      roomRefresherProvider.overrideWithValue(refresher ?? _FakeRefresher()),
    ],
  );
  addTearDown(container.dispose);
  for (var i = 0; i < 20; i++) {
    if (container.read(followProvider).length == seed.length) break;
    await Future<void>.delayed(Duration.zero);
  }
  return container;
}

void main() {
  group('offlineLastLiveLabel 纯函数', () {
    test('lastLiveAt <= 0 显示「未开播」', () {
      expect(offlineLastLiveLabel(0), '未开播');
      expect(offlineLastLiveLabel(-1), '未开播');
    });

    test('lastLiveAt > 0 显示「上次开播 MM-DD HH:mm」', () {
      // 固定时间戳:2026-09-01 08:30(本地时区)。
      final ts = DateTime(2026, 9, 1, 8, 30).millisecondsSinceEpoch;
      expect(offlineLastLiveLabel(ts), '上次开播 09-01 08:30');
    });
  });

  group('本地恢复透传', () {
    test('存储里的 lastLiveAt 恢复到 FollowEntry,不再被丢弃', () async {
      final container = await _container(
        seed: [_seedEntry(roomId: '1001', online: '', lastLiveAt: 1234567890000)],
      );

      final entry = container.read(followProvider).single;
      expect(entry.lastLiveAt, 1234567890000, reason: '恢复时必须透传 lastLiveAt');
      expect(entry.isLive, isFalse);
    });
  });

  group('离线跃迁', () {
    test('刷新观察到「在播 → 离线」时记录上次开播时间;保持在播的条目不动', () async {
      final fake = _FakeRefresher(
        results: {
          '1001': _fresh(roomId: '1001', online: ''), // 刚离线。
          '1002': _fresh(roomId: '1002', online: '3.3万'), // 仍在播。
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '1.2万'),
          _seedEntry(roomId: '1002', online: '2.2万'),
        ],
        refresher: fake,
      );

      final before = DateTime.now().millisecondsSinceEpoch;
      await container.read(followProvider.notifier).refreshStatuses();

      final entries = container.read(followProvider);
      final offline = entries.firstWhere((e) => e.room.roomId == '1001');
      final live = entries.firstWhere((e) => e.room.roomId == '1002');
      expect(
        offline.lastLiveAt,
        inInclusiveRange(before - 1000, before + 5000),
        reason: '刚刚离线的条目应记录上次开播时间(近似当下)',
      );
      expect(live.lastLiveAt, 0, reason: '在播条目不产生上次开播记录');
    });
  });

  group('持久化往返', () {
    test('触发 _persist 后存储里 lastLiveAt 不丢', () async {
      final container = await _container(
        seed: [_seedEntry(roomId: '1001', online: '', lastLiveAt: 1234567890000)],
      );

      // 触发一次会写盘的操作(切特别关注;同步方法,写盘在内部异步跟进)。
      container.read(followProvider.notifier).toggleSpecial('douyu:1001');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final raw = await SharedPreferencesAsync().getString('zishu.follow.list');
      expect(raw, isNotNull);
      final payload = jsonDecode(raw!) as List;
      expect(
        (payload.single as Map)['lastLiveAt'],
        1234567890000,
        reason: '落盘结构必须带 lastLiveAt,否则重启即丢',
      );
    });
  });

  group('离线卡文案', () {
    /// 组件级宿主:直接 pump FollowEntryCard。
    Widget host(FollowEntry entry) => ProviderScope(
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: Scaffold(
          body: SizedBox(width: 220, child: FollowEntryCard(entry: entry)),
        ),
      ),
    );

    FollowEntry entryWith(int lastLiveAt) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // 直接构造条目(不依赖 provider 状态)。
      return FollowEntry(
        room: const RoomSummary(
          site: 'douyu',
          roomId: '1001',
          title: '离线房',
          anchorName: '主播',
          cid: '',
          category: '网游',
          online: '',
          cover: '',
        ),
        isSpecial: false,
        remindOn: false,
        followedAt: DateTime(2026, 9, 1),
        lastLiveAt: lastLiveAt,
      );
    }

    testWidgets('有开播记录:显示「上次开播 MM-DD HH:mm」', (tester) async {
      final ts = DateTime(2026, 9, 1, 8, 30).millisecondsSinceEpoch;
      await tester.pumpWidget(host(entryWith(ts)));
      await tester.pump(const Duration(milliseconds: 50));

      // 卡片两处同源文案(meta 行 + 底部遮罩条),与改前「未开播」的呈现
      // 结构一致,只替换文案内容。
      expect(find.text('上次开播 09-01 08:30'), findsNWidgets(2));
      expect(find.text('未开播'), findsNothing);
    });

    testWidgets('无开播记录:维持「未开播」', (tester) async {
      await tester.pumpWidget(host(entryWith(0)));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('未开播'), findsWidgets);
    });
  });
}
