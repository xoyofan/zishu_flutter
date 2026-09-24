/// FOLLOW 公共能力自动化矩阵。
///
/// 本文件只验证跨能力边界：关注生命周期持久化、特别关注、刷新结果隔离、
/// 平台/房间身份键，以及 provider 列表状态与筛选结果的一致性；详细的刷新
/// 合并规则与纯排序规则分别由 follow_status_refresh_test / follow_sort_test 覆盖。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show RoomPayload, RoomRecord, RoomState, RoomSummary;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_sort.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

const _followKey = 'zishu.follow.list';

RoomSummary _room({
  required String site,
  required String roomId,
  String online = '1.0万',
  RoomState roomState = RoomState.live,
}) => RoomSummary(
  site: site,
  roomId: roomId,
  title: '$site-$roomId',
  anchorName: '主播-$site-$roomId',
  cid: 'cid-$site-$roomId',
  category: '网游',
  online: online,
  cover: 'https://cdn/$site-$roomId.jpg',
  roomState: roomState,
);

Map<String, Object> _stored({
  required String site,
  required String roomId,
  String online = '1.0万',
  bool isSpecial = false,
}) => {
  'site': site,
  'roomId': roomId,
  'title': '$site-$roomId',
  'uname': '主播-$site-$roomId',
  'cover': 'https://cdn/$site-$roomId.jpg',
  'cid': 'cid-$site-$roomId',
  'category': '网游',
  'online': online,
  'isSpecial': isSpecial,
  'remindOn': false,
  'followedAt': '2026-09-01T00:00:00.000Z',
};

Future<ProviderContainer> _container({
  required List<Map<String, Object>> seed,
  RoomRefresher? refresher,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(<String, Object>{
        _followKey: jsonEncode(seed),
      });
  final container = ProviderContainer(
    overrides: [if (refresher != null) roomRefresherProvider.overrideWithValue(refresher)],
  );
  addTearDown(container.dispose);
  for (var i = 0; i < 30; i++) {
    final entries = container.read(followProvider);
    if (entries.length == seed.length &&
        (seed.isEmpty || entries.first.key == '${seed.first['site']}:${seed.first['roomId']}')) {
      break;
    }
    await Future<void>.delayed(Duration.zero);
  }
  return container;
}

Future<void> _settlePersistence() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _MatrixRefresher implements RoomRefresher {
  _MatrixRefresher({required this.results, this.failures = const {}});

  final Map<String, RoomSummary> results;
  final Set<String> failures;
  final List<String> calls = [];

  @override
  Future<RoomRecord> refreshRoom({
    required String site,
    required String roomId,
  }) async {
    final key = '$site:$roomId';
    calls.add(key);
    if (failures.contains(key)) throw StateError('refresh failed: $key');
    final result = results[key];
    if (result == null) throw StateError('missing result: $key');
    // 刷新端口已返回统一 RoomRecord:脚本仍按 RoomSummary 描述平台返回值,
    // 在端口边界经 fromSummary 转换(关注存储本切片仍为 RoomSummary)。
    return RoomRecord.fromSummary(result);
  }

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  group('FOLLOW 公共能力矩阵', () {
    test('关注/取消关注持久化，特别关注与同房号跨平台身份不串线', () async {
      final first = await _container(
        seed: [_stored(site: 'douyu', roomId: '42')],
      );
      final notifier = first.read(followProvider.notifier);

      // 同一 roomId 但不同 site 是两个独立关注身份；同时验证从房间加入的状态。
      notifier.addFromRoom(_room(site: 'huya', roomId: '42'), isSpecial: true);
      notifier.addFromRoom(_room(site: 'douyu', roomId: '43'));
      notifier.toggleSpecial('douyu:42');
      await _settlePersistence();

      final current = first.read(followProvider);
      expect(current.map((entry) => entry.key), ['douyu:43', 'huya:42', 'douyu:42']);
      expect(current.first.isSpecial, isFalse);
      expect(current[1].isSpecial, isTrue);
      expect(current.last.isSpecial, isTrue);

      final persisted = jsonDecode(
        (await SharedPreferencesAsync().getString(_followKey))!,
      ) as List;
      expect(
        persisted.map((item) => '${item['site']}:${item['roomId']}'),
        containsAll(<String>['douyu:42', 'douyu:43', 'huya:42']),
      );
      expect(
        persisted.where((item) => (item as Map)['isSpecial'] == true).length,
        2,
      );

      final restored = await _container(
        seed: [
          _stored(site: 'huya', roomId: '42', isSpecial: true),
          _stored(site: 'douyu', roomId: '42', isSpecial: true),
          _stored(site: 'douyu', roomId: '43'),
        ],
      );
      expect(restored.read(followProvider).map((entry) => entry.key),
          ['huya:42', 'douyu:42', 'douyu:43']);
      expect(restored.read(followProvider).every((entry) =>
          entry.isSpecial == (entry.key != 'douyu:43')), isTrue);

      // 取消关注必须只删除目标平台的同房号条目。
      restored.read(followProvider.notifier).remove('douyu:42');
      await _settlePersistence();
      expect(restored.read(followProvider).map((entry) => entry.key),
          ['huya:42', 'douyu:43']);
      final afterRemove = jsonDecode(
        (await SharedPreferencesAsync().getString(_followKey))!,
      ) as List;
      expect(afterRemove.map((item) => '${item['site']}:${item['roomId']}'),
          ['huya:42', 'douyu:43']);
    });

    test('刷新成功与失败按平台+房间键隔离，不覆盖失败条目', () async {
      final refresher = _MatrixRefresher(
        results: {
          'douyu:42': _room(site: 'douyu', roomId: '42', online: '9.9万'),
          'huya:42': _room(site: 'huya', roomId: '42', online: '8.8万'),
        },
        failures: {'douyu:99'},
      );
      final container = await _container(
        seed: [
          _stored(site: 'douyu', roomId: '42', online: '1.0万'),
          _stored(site: 'huya', roomId: '42', online: '2.0万'),
          _stored(site: 'douyu', roomId: '99', online: '3.0万'),
        ],
        refresher: refresher,
      );

      final refreshed = await container.read(followProvider.notifier).refreshStatuses();

      expect(refreshed, 2);
      expect(refresher.calls, containsAll(<String>['douyu:42', 'huya:42', 'douyu:99']));
      expect(
        container.read(followProvider).firstWhere((entry) => entry.key == 'douyu:42').room.online,
        '9.9万',
      );
      expect(
        container.read(followProvider).firstWhere((entry) => entry.key == 'huya:42').room.online,
        '8.8万',
      );
      final failed = container.read(followProvider).firstWhere((entry) => entry.key == 'douyu:99');
      expect(failed.room.online, '3.0万');
      expect(failed.isLive, isTrue, reason: '失败不得将原有在播状态伪造成离线');
    });

    test('provider 状态、特别关注排序与关注列表筛选保持同一份状态', () async {
      final container = await _container(
        seed: [
          _stored(site: 'douyu', roomId: 'live'),
          _stored(site: 'douyu', roomId: 'offline', online: ''),
        ],
      );
      final notifier = container.read(followProvider.notifier);

      notifier.toggleSpecial('douyu:live');
      notifier.addFromRoom(_room(site: 'bilibili', roomId: 'new'));
      expect(container.read(followProvider).length, 3);
      expect(
        container.read(followProvider).firstWhere((entry) => entry.key == 'douyu:live').isSpecial,
        isTrue,
      );

      final visible = visibleFollowEntries(container.read(followProvider));
      expect(visible.map((entry) => entry.key),
          ['douyu:live', 'bilibili:new', 'douyu:offline']);

      notifier.remove('bilibili:new');
      expect(container.read(followProvider).map((entry) => entry.key),
          ['douyu:live', 'douyu:offline']);
      expect(visibleFollowEntries(container.read(followProvider)).map((entry) => entry.key),
          ['douyu:live', 'douyu:offline']);
    });
  });
}
