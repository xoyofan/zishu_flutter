/// 关注「在播状态」刷新与轮询单测。
///
/// 覆盖三件事:
/// 1. `FollowController.refreshStatuses` 的**合并语义**(成功覆盖 online/标题/封面、
///    失败保留原值不翻转离线、本地 cid 不被刷掉);
/// 2. 分批上限 + 游标轮转(定时轮询用,避免每周期全量打网络);
/// 3. 无 refresher(fixture/测试)时返回 0 且**零网络**。
///
/// 宿主:直接构造 ProviderContainer(不 pump UI),存储后端注入
/// InMemorySharedPreferencesAsync;刷新能力用假 [RoomRefresher] 注入。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show RoomPayload, RoomState, RoomSummary;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_status_poller.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

/// 假刷新源:记录被刷新的房间,并按脚本返回结果 / 抛错。
class FakeRefresher implements RoomRefresher {
  FakeRefresher({this.results = const {}, this.failures = const {}});

  /// roomId → 刷新后的房间(缺省则抛错,模拟该条刷新失败)。
  final Map<String, RoomSummary> results;

  /// roomId 集合:命中即抛错(与 [results] 同时存在时以抛错优先)。
  final Set<String> failures;

  /// 调用记录,顺序即实际刷新顺序。
  final List<String> calls = [];

  int get callCount => calls.length;

  @override
  Future<RoomSummary> refreshRoom({
    required String site,
    required String roomId,
  }) async {
    calls.add('$site:$roomId');
    if (failures.contains(roomId)) {
      throw StateError('refresh failed: $roomId');
    }
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

/// 种子条目:roomId + online + cid 可控。
Map<String, Object> _seedEntry({
  required String roomId,
  required String online,
  String site = 'douyu',
  String cid = '',
  String title = '标题',
  String cover = 'https://cdn/cover.jpg',
  String category = '网游',
  String followers = '',
  String vip = '',
  String diamondFans = '',
}) => {
  'site': site,
  'roomId': roomId,
  'title': title,
  'uname': '主播$roomId',
  'cover': cover,
  'cid': cid,
  'category': category,
  'online': online,
  'followers': followers,
  'vip': vip,
  'diamondFans': diamondFans,
  'isSpecial': false,
  'remindOn': false,
  'followedAt': '2026-09-01T00:00:00.000Z',
};

/// 刷新结果房间(模拟平台返回值)。
RoomSummary _fresh({
  required String roomId,
  required String online,
  String site = 'douyu',
  String cid = '',
  String title = '新标题',
  String cover = 'https://cdn/new.jpg',
  String category = '新分类',
  String followers = '',
  String vip = '',
  String diamondFans = '',
  RoomState roomState = RoomState.offline,
}) => RoomSummary(
  site: site,
  roomId: roomId,
  title: title,
  anchorName: '主播$roomId',
  cid: cid,
  category: category,
  online: online,
  cover: cover,
  followers: followers,
  vip: vip,
  diamondFans: diamondFans,
  roomState: roomState,
);

Future<ProviderContainer> _container({
  required List<Map<String, Object>> seed,
  RoomRefresher? refresher,
  bool overrideRefresher = false,
}) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(
    <String, Object>{'zishu.follow.list': jsonEncode(seed)},
  );
  final container = ProviderContainer(
    overrides: [
      if (overrideRefresher) roomRefresherProvider.overrideWithValue(refresher),
    ],
  );
  addTearDown(container.dispose);
  // 等 _restore 从存储灌入种子。
  for (var i = 0; i < 20; i++) {
    if (container.read(followProvider).length == seed.length &&
        container.read(followProvider).first.room.roomId ==
            (seed.first['roomId'] as String)) {
      break;
    }
    await Future<void>.delayed(Duration.zero);
  }
  return container;
}

void main() {
  group('refreshStatuses 合并语义', () {
    test('成功:online/标题/封面以刷新为准,本地 cid 保留', () async {
      final fake = FakeRefresher(
        results: {
          '1001': _fresh(roomId: '1001', online: '1.2万'),
          '1002': _fresh(roomId: '1002', online: ''),
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '5千', cid: 'cid-local'),
          _seedEntry(roomId: '1002', online: '3千'),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      final refreshed = await container
          .read(followProvider.notifier)
          .refreshStatuses();

      expect(refreshed, 2);
      final entries = container.read(followProvider);
      final first = entries.firstWhere((e) => e.room.roomId == '1001');
      expect(first.room.online, '1.2万');
      expect(first.room.title, '新标题');
      expect(first.room.cover, 'https://cdn/new.jpg');
      expect(
        first.room.cid,
        'cid-local',
        reason: '刷新结果没有分类上下文,覆盖会破坏「我的分类」跳转',
      );
      final second = entries.firstWhere((e) => e.room.roomId == '1002');
      expect(second.room.online, '', reason: '空串即平台明确未开播');
      expect(second.isLive, isFalse);
    });

    test('主播换分类:category/统计以刷新为准,cid 与本地标记保留', () async {
      final fake = FakeRefresher(
        results: {
          '1001': _fresh(
            roomId: '1001',
            online: '2.2万',
            followers: '123456',
            vip: '321',
          ),
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(
            roomId: '1001',
            online: '5千',
            cid: 'cid-local',
            category: '旧分类',
            followers: '1',
            vip: '2',
          ),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      await container.read(followProvider.notifier).refreshStatuses();

      final entry = container.read(followProvider).single;
      // 分类是上游元信息:主播换分类后必须跟随刷新值,不能留在旧分类。
      expect(entry.room.category, '新分类');
      expect(entry.room.online, '2.2万');
      expect(entry.room.followers, '123456');
      expect(entry.room.vip, '321');
      // cid 是「加入关注时所在分类」的跳转上下文,刷新不覆盖。
      expect(entry.room.cid, 'cid-local');
    });

    test('刷新未返回统计(空串)时保留本地已有值,不把统计冲成空', () async {
      final fake = FakeRefresher(
        results: {
          '1001': _fresh(roomId: '1001', online: '8千'),
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(
            roomId: '1001',
            online: '5千',
            followers: '654321',
            vip: '99',
            diamondFans: '1300',
          ),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      await container.read(followProvider.notifier).refreshStatuses();

      final entry = container.read(followProvider).single;
      expect(entry.room.followers, '654321', reason: '上游缺字段不得冲掉旧值');
      expect(entry.room.vip, '99');
      expect(
        entry.room.diamondFans,
        '1300',
        reason: '第 3 列(svip 档)同上:vip 没取到超粉数时不得把已有值冲成空',
      );
    });

    test('第 3 列(svip 档)刷新回填:diamondFans 随刷新落地', () async {
      final fake = FakeRefresher(
        results: {
          '1001': _fresh(roomId: '1001', online: '2.2万', diamondFans: '1300'),
        },
      );
      final container = await _container(
        seed: [_seedEntry(roomId: '1001', online: '5千')],
        refresher: fake,
        overrideRefresher: true,
      );

      await container.read(followProvider.notifier).refreshStatuses();

      final entry = container.read(followProvider).single;
      expect(
        entry.room.diamondFans,
        '1300',
        reason: 'huya 超粉/douyu 钻粉走 diamondFans,合并时不得丢掉',
      );
    });

    test('刷新后 diamondFans 不丢:合并结果与落盘都保留', () async {
      final fake = FakeRefresher(
        results: {'1001': _fresh(roomId: '1001', online: '2.2万')},
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '5千', diamondFans: '1300'),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      await container.read(followProvider.notifier).refreshStatuses();

      expect(
        container.read(followProvider).single.room.diamondFans,
        '1300',
        reason: '刷新链路必须带上 diamondFans,否则第 3 列刷一轮就空',
      );

      // 落盘往返:重启后第 3 列仍要有值。
      final raw = await SharedPreferencesAsync().getString('zishu.follow.list');
      expect(raw, isNotNull);
      final payload = jsonDecode(raw!) as List;
      expect(
        (payload.single as Map)['diamondFans'],
        '1300',
        reason: '落盘结构必须带 diamondFans,否则重启即丢第 3 列',
      );
    });

    test('单条失败保留原值:不得把在播刷成离线', () async {
      final fake = FakeRefresher(
        results: {'1001': _fresh(roomId: '1001', online: '9千')},
        failures: {'1002'},
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '5千'),
          _seedEntry(roomId: '1002', online: '3千'),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      final refreshed = await container
          .read(followProvider.notifier)
          .refreshStatuses();

      expect(refreshed, 1, reason: '只有成功条目计入返回数');
      final entries = container.read(followProvider);
      expect(entries.firstWhere((e) => e.room.roomId == '1001').room.online, '9千');
      final failed = entries.firstWhere((e) => e.room.roomId == '1002');
      expect(failed.room.online, '3千', reason: '失败条目保留原值');
      expect(failed.isLive, isTrue, reason: '网络抖动不是「下播」');
    });

    test('roomState 跟随刷新:在播→轮播、轮播→开播互转', () async {
      final fake = FakeRefresher(
        results: {
          // 停播改轮播:online 空 + replay。
          '1001': _fresh(
            roomId: '1001',
            online: '',
            roomState: RoomState.replay,
          ),
          // 轮播恢复开播:online 非空 + live。
          '1002': _fresh(
            roomId: '1002',
            online: '2万',
            roomState: RoomState.live,
          ),
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '5千'),
          _seedEntry(roomId: '1002', online: ''),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      await container.read(followProvider.notifier).refreshStatuses();

      final entries = container.read(followProvider);
      final toReplay = entries.firstWhere((e) => e.room.roomId == '1001');
      expect(toReplay.room.roomState, RoomState.replay,
          reason: '三态跟随上游:主播停播改轮播要感知到');
      expect(toReplay.isLive, isFalse);
      expect(toReplay.isReplay, isTrue);
      final toLive = entries.firstWhere((e) => e.room.roomId == '1002');
      expect(toLive.room.roomState, RoomState.live, reason: '轮播恢复开播跟随上游');
      expect(toLive.isLive, isTrue);
      expect(toLive.isReplay, isFalse);
    });

    test('刷新期间用户删条目:以最新 state 重建,不被过期快照覆盖', () async {
      final fake = FakeRefresher(
        results: {
          '1001': _fresh(roomId: '1001', online: '1万'),
          '1002': _fresh(roomId: '1002', online: '2万'),
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '1'),
          _seedEntry(roomId: '1002', online: '2'),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      final future = container.read(followProvider.notifier).refreshStatuses();
      // 刷新进行中删掉 1002。
      container.read(followProvider.notifier).remove('douyu:1002');
      await future;

      final entries = container.read(followProvider);
      expect(entries.map((e) => e.room.roomId), ['1001']);
      expect(entries.single.room.online, '1万');
    });
  });

  group('刷新分类归一(displayCategoryName)', () {
    test('huya 刷新返回缩写 + 分区 cid:存储归一为中文显示名', () async {
      // 解析核心刷新只带回原始名/缩写 + 分区 cid(huya lol 的 gid=1);
      // 合并层负责经 displayCategoryName 归一(真实 cross 表行为)。
      final fake = FakeRefresher(
        results: {
          '1001': _fresh(
            roomId: '1001',
            online: '2万',
            site: 'huya',
            category: 'lol',
            cid: '1',
          ),
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '1万', site: 'huya', category: 'lol'),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      await container.read(followProvider.notifier).refreshStatuses();

      final entry = container.read(followProvider).single;
      expect(
        entry.room.category,
        '英雄联盟',
        reason: 'cross 表 lol(huya cid=1)→ 英雄联盟',
      );
    });

    test('归一未命中:保持刷新原名', () async {
      final fake = FakeRefresher(
        results: {
          '1001': _fresh(
            roomId: '1001',
            online: '2万',
            site: 'huya',
            category: '小众自研游戏',
          ),
        },
      );
      final container = await _container(
        seed: [
          _seedEntry(roomId: '1001', online: '1万', site: 'huya'),
        ],
        refresher: fake,
        overrideRefresher: true,
      );

      await container.read(followProvider.notifier).refreshStatuses();

      final entry = container.read(followProvider).single;
      expect(
        entry.room.category,
        '小众自研游戏',
        reason: '无跨平台映射时保持上游原名,不伪造中文',
      );
    });
  });

  group('分批与游标轮转', () {
    test('limit=2 时按窗口环状刷新,三次覆盖 5 条', () async {
      final fake = FakeRefresher(
        results: {
          for (final id in ['1', '2', '3', '4', '5'])
            id: _fresh(roomId: id, online: '在线$id'),
        },
      );
      final container = await _container(
        seed: [
          for (final id in ['1', '2', '3', '4', '5'])
            _seedEntry(roomId: id, online: ''),
        ],
        refresher: fake,
        overrideRefresher: true,
      );
      final notifier = container.read(followProvider.notifier);

      expect(await notifier.refreshStatuses(limit: 2), 2);
      expect(fake.calls, ['douyu:1', 'douyu:2']);
      expect(await notifier.refreshStatuses(limit: 2), 2);
      expect(fake.calls, ['douyu:1', 'douyu:2', 'douyu:3', 'douyu:4']);
      // 第三次窗口环状回绕到第 5 条 + 第 1 条。
      expect(await notifier.refreshStatuses(limit: 2), 2);
      expect(fake.calls.sublist(4), ['douyu:5', 'douyu:1']);

      // 全量刷新复位游标并覆盖全部 5 条(前 3 次窗口 = 6 次调用,再加全量 5 次)。
      expect(await notifier.refreshStatuses(), 5);
      expect(fake.calls.length, 6 + 5);
    });

    test('limit 不小于条数时退化为全量', () async {
      final fake = FakeRefresher(
        results: {
          for (final id in ['1', '2', '3']) id: _fresh(roomId: id, online: 'x'),
        },
      );
      final container = await _container(
        seed: [for (final id in ['1', '2', '3']) _seedEntry(roomId: id, online: '')],
        refresher: fake,
        overrideRefresher: true,
      );
      final refreshed = await container
          .read(followProvider.notifier)
          .refreshStatuses(limit: 16);
      expect(refreshed, 3);
      expect(fake.calls.length, 3);
    });
  });

  group('无刷新能力时', () {
    test('fixture 源(roomRefresherProvider=null)返回 0 且零网络', () async {
      final fake = FakeRefresher(
        results: {'1001': _fresh(roomId: '1001', online: '1万')},
      );
      // 不 override → 默认 roomSourceProvider 为 FixtureRoomSource(不实现
      // RoomRefresher)→ provider 解析为 null。
      final container = await _container(
        seed: [_seedEntry(roomId: '1001', online: '5千')],
        refresher: fake,
      );

      expect(container.read(roomRefresherProvider), isNull);
      final refreshed = await container
          .read(followProvider.notifier)
          .refreshStatuses();
      expect(refreshed, 0);
      expect(fake.callCount, 0, reason: '不得产生任何刷新调用');
      expect(
        container.read(followProvider).single.room.online,
        '5千',
        reason: '保持样例数据不变',
      );
    });

    test('无 refresher 时不建轮询 timer(provider 为 null)', () async {
      final container = await _container(
        seed: [_seedEntry(roomId: '1001', online: '5千')],
      );
      expect(container.read(followStatusPollerProvider), isNull);
    });
  });

  group('FollowStatusPoller', () {
    test('start 后按周期触发,dispose 后停止;wake 立即跑一轮', () async {
      var runs = 0;
      final poller = FollowStatusPoller(
        refresh: () async {
          runs++;
          return 1;
        },
        interval: const Duration(milliseconds: 15),
      );
      addTearDown(poller.dispose);

      expect(await poller.wake(), 1);
      expect(runs, 1);

      poller.start();
      expect(poller.running, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final afterPeriods = runs;
      expect(afterPeriods, greaterThanOrEqualTo(3), reason: '周期应多次触发');

      poller.dispose();
      expect(poller.running, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runs, afterPeriods, reason: 'dispose 后不应再触发');
    });

    test('上一轮未结束时跳过本轮,异常静默返回 0', () async {
      var concurrent = 0;
      var maxConcurrent = 0;
      final poller = FollowStatusPoller(
        refresh: () async {
          concurrent++;
          maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          concurrent--;
          throw StateError('boom');
        },
      );

      final first = poller.tick();
      final second = await poller.tick();
      expect(second, 0, reason: '重入直接跳过');
      await first;
      expect(maxConcurrent, 1, reason: '同一时刻只应有一轮在跑');
      expect(await poller.tick(), 0, reason: '异常被吞掉,不向 UI 抛错');
      expect(concurrent, 0);
    });
  });
}
