/// 注册表出口的 `CachedRoomResolver` 必须**透传**轻量刷新能力。
///
/// 宿主(关注列表)拿到的是注册表里的 `CachedRoomResolver` 包装,不是平台
/// resolver 本体;若包装不实现 [RoomSummaryRefresher],能力探测恒为假,
/// 整条「定时刷新在播状态」链路会静默失效。同时刷新**不能走短缓存** ——
/// 刷新本身就是为了拿最新状态。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/douyu_site.dart';
import 'package:live_parser/src/registry/cached_room_resolver.dart';
import 'package:test/test.dart';

import '../../support/fake_douyu_api.dart';

/// 未实现刷新能力的占位 resolver(模拟尚未接入的站点)。
class _PlainResolver implements RoomResolver {
  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async =>
      throw UnimplementedError();
}

void main() {
  test('包装后仍可被探测到 RoomSummaryRefresher(能力透传)', () {
    final fake = FakeDouyuApi();
    final cached = CachedRoomResolver(DouyuRoomResolver(DouyuClient(httpClient: fake)));
    expect(cached, isA<RoomSummaryRefresher>());
  });

  test('刷新不写短缓存:连续两次刷新各打一次上游', () async {
    final fake = FakeDouyuApi()
      ..betardResponse = {
        'room': {
          'room_id': 9527,
          'nickname': '测试主播',
          'show_status': 1,
          'room_name': '斗鱼测试房间',
          'cate_id': 1,
          'cate_name': '英雄联盟',
        },
      }
      ..roomInfoResponse = {
        'code': 0,
        'data': {
          'roomInfo': {'hn': '1.2万'},
        },
      };
    final refresher =
        CachedRoomResolver(DouyuRoomResolver(DouyuClient(httpClient: fake)))
            as RoomSummaryRefresher;

    const request = RoomRequest(site: 'douyu', roomIdOrUrl: '9527');
    await refresher.refreshRoomSummary(request);
    final afterFirst = fake.requests.length;
    await refresher.refreshRoomSummary(request);

    expect(
      fake.requests.length,
      greaterThan(afterFirst),
      reason: '刷新必须重新打上游,不能命中 60s 短缓存',
    );
  });

  test('内层未实现刷新能力:抛错(由调用方按条目隔离)', () async {
    final cached = CachedRoomResolver(_PlainResolver());
    await expectLater(
      (cached as RoomSummaryRefresher).refreshRoomSummary(
        const RoomRequest(site: 'douyu', roomIdOrUrl: '9527'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
