/// 云端关注回拉(`FollowController.pullRemote`)契约单测。
///
/// 覆盖整表以远端为准时的四条口径(用户确认的 Windows 回归 bug,2026-09-24):
/// 1. **同 key 本地已知统计/房间元信息保留**:云端契约只带关注状态与基础
///    展示字段,不含 followers/vip/diamondFans/online/roomState/category 等
///    —— 全量替换不得把已知本地值抹成空,保留至下一轮 `refreshStatuses` 刷新;
/// 2. **远端决定条目集合与关注维度标记**:isSpecial/remindOn/followedAt
///    以远端为准;已在远端删除的本地条目不复活;
/// 3. **未知保持空**:远端新增(本地无记录)条目的统计字段为空串,
///    展示层据此显示「—」,不伪造 0;
/// 4. 「上次开播」类时间戳与本地取 max(既有口径,防回退)。
///
/// 测试 seam(主管确认的方案 C):`FollowController` 可选构造参数注入
/// `DataServerApi`,经 `followProvider.overrideWith` 携带脚本化 API 进入;
/// 登录态用 `authProvider.overrideWith` 的测试替身提供 token。
/// 全程零真实网络。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show RoomState;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/shared/application/auth_provider.dart';
import 'package:zishu_flutter/src/shared/application/data_server_api.dart';

/// 脚本化 data-server API:fetchFollows 返回远端快照,pushFollows 只记账。
class _FakeDataServerApi extends DataServerApi {
  _FakeDataServerApi({this.remote = const []});

  /// 远端关注快照(GET /api/me/follows 的 follows)。
  final List<RemoteFollow> remote;

  /// pushFollows 调用记录(远端非空时不应发生推送)。
  final List<List<RemoteFollow>> pushes = [];

  @override
  Future<List<RemoteFollow>> fetchFollows(String token) async => remote;

  @override
  Future<void> pushFollows(String token, List<RemoteFollow> items) async {
    pushes.add(items);
  }
}

/// 假登录态:直接进入已登录,供 FollowController._authToken 取 token。
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => AuthState(
    phase: AuthPhase.authenticated,
    session: DataSession(
      token: 'test-token',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 3600_000,
      userId: 1,
      username: 'tester',
    ),
  );
}

/// 本地种子条目(带已知统计与房间元信息)。
Map<String, Object> _localEntry({
  required String roomId,
  String site = 'douyu',
  String online = '',
  String followers = '',
  String vip = '',
  String diamondFans = '',
  String category = '',
  String cid = '',
  bool isSpecial = false,
}) => {
  'site': site,
  'roomId': roomId,
  'title': '本地标题$roomId',
  'uname': '本地主播$roomId',
  'cover': 'https://cdn/local.jpg',
  'avatar': 'https://cdn/local-avatar.jpg',
  'cid': cid,
  'category': category,
  'online': online,
  'roomState': 'live',
  'startedAt': '2026-09-20T08:00:00.000Z',
  'followers': followers,
  'vip': vip,
  'diamondFans': diamondFans,
  'isSpecial': isSpecial,
  'remindOn': false,
  'followedAt': '2026-09-01T00:00:00.000Z',
  'lastLiveAt': 1700000000000,
};

/// 远端条目:契约只有关注状态与基础展示字段,**不含统计/分类/在播**。
RemoteFollow _remoteEntry({
  required String id,
  String site = 'douyu',
  bool superFollow = false,
  bool liveNotify = false,
}) => RemoteFollow(
  site: site,
  id: id,
  title: '远端标题$id',
  anchor: '远端主播$id',
  cover: 'https://cdn/remote.jpg',
  avatar: '',
  addedAt: DateTime(2026, 9, 2).millisecondsSinceEpoch,
  superFollow: superFollow,
  liveNotify: liveNotify,
  clientUpdatedAt: 1,
  lastLiveAt: 0,
  liveStartAt: 0,
);

Future<({ProviderContainer container, _FakeDataServerApi api})> _container({
  required List<Map<String, Object>> localSeed,
  required List<RemoteFollow> remote,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(<String, Object>{
        'zishu.follow.list': jsonEncode(localSeed),
      });
  final api = _FakeDataServerApi(remote: remote);
  final container = ProviderContainer(
    overrides: [
      followProvider.overrideWith(() => FollowController(api: api)),
      authProvider.overrideWith(_FakeAuthController.new),
    ],
  );
  addTearDown(container.dispose);
  // 等 _restore 从存储灌入本地种子。
  for (var i = 0; i < 20; i++) {
    if (container.read(followProvider).length == localSeed.length) break;
    await Future<void>.delayed(Duration.zero);
  }
  return (container: container, api: api);
}

void main() {
  group('pullRemote 整表以远端为准', () {
    test('同 key 本地已知统计/房间元信息保留,不被云端空统计抹掉', () async {
      final (:container, :api) = await _container(
        localSeed: [
          _localEntry(
            roomId: '1001',
            online: '1.2万',
            followers: '123456',
            vip: '321',
            diamondFans: '1300',
            category: '网游',
            cid: 'cid-local',
          ),
        ],
        // 云端返回同 key,但契约里没有任何统计字段。
        remote: [_remoteEntry(id: '1001', superFollow: true, liveNotify: true)],
      );
      container.read(authProvider); // 触发假登录态,供 _authToken 取 token。

      await container.read(followProvider.notifier).pullRemote();

      final entries = container.read(followProvider);
      expect(entries, hasLength(1), reason: '前置:远端决定条目集合');
      final entry = entries.single;
      expect(entry.key, 'douyu:1001');
      // 远端决定关注维度标记。
      expect(entry.isSpecial, isTrue, reason: 'isSpecial 以远端为准');
      expect(entry.remindOn, isTrue, reason: 'remindOn 以远端为准');
      // 同 key 的本地已知统计/房间元信息必须保留到下一轮刷新。
      expect(
        entry.room.followers,
        '123456',
        reason: '云端不带 followers,不得把本地已知值抹成空',
      );
      expect(entry.room.vip, '321', reason: '云端不带 vip,本地值保留');
      expect(entry.room.diamondFans, '1300', reason: '云端不带 diamondFans,本地值保留');
      expect(entry.room.online, '1.2万', reason: '开播/在线状态远端不回传,本地已知值保留(不得闪离线)');
      expect(entry.room.category, '网游', reason: '分类远端不回传,本地值保留');
      expect(entry.room.cid, 'cid-local', reason: '跳转上下文 cid 本地保留');
      expect(
        entry.room.avatar,
        'https://cdn/local-avatar.jpg',
        reason: '头像远端为扩展字段(zishu 侧置空),本地值保留',
      );
      expect(
        entry.room.roomState,
        RoomState.live,
        reason: 'roomState 本地保留,不被重置为 offline',
      );
      expect(
        entry.room.startedAt,
        DateTime.utc(2026, 9, 20, 8),
        reason: '开播时间本地保留',
      );
      // 时间戳 max 合并:本地 lastLiveAt 不被远端 0 抹掉。
      expect(
        entry.lastLiveAt,
        1700000000000,
        reason: '远端为 0 时本地跃迁记录保留(max 合并)',
      );
      // 远端非空 → 只拉不推。
      expect(api.pushes, isEmpty, reason: '远端非空走拉取分支,不应触发整表推送');
    });

    test('远端新增条目统计保持空串(展示「—」,不伪造 0)', () async {
      final (:container, :api) = await _container(
        localSeed: [
          _localEntry(roomId: '1001', online: '1.2万', followers: '123456'),
        ],
        remote: [
          _remoteEntry(id: '1001'),
          _remoteEntry(id: '2001', site: 'huya'),
        ],
      );
      container.read(authProvider);

      await container.read(followProvider.notifier).pullRemote();

      final entries = container.read(followProvider);
      expect(entries.map((e) => e.key).toSet(), {
        'douyu:1001',
        'huya:2001',
      }, reason: '远端决定条目集合');
      final added = entries.singleWhere((e) => e.key == 'huya:2001');
      expect(added.room.followers, '', reason: '本地无记录 → 未知保持空(「—」)');
      expect(added.room.online, '', reason: '开播状态待真实解析链路回填');
      expect(added.isSpecial, isFalse);
      expect(api.pushes, isEmpty);
    });

    test('已在远端删除的本地条目不复活', () async {
      final (:container, :api) = await _container(
        localSeed: [
          _localEntry(roomId: '1001', online: '1.2万', followers: '123456'),
          _localEntry(roomId: '1002', online: '3千', followers: '654'),
        ],
        // 远端只剩 1001:1002 已在云端删除。
        remote: [_remoteEntry(id: '1001')],
      );
      container.read(authProvider);

      await container.read(followProvider.notifier).pullRemote();

      final entries = container.read(followProvider);
      expect(entries.map((e) => e.key), [
        'douyu:1001',
      ], reason: '远端删除的条目不得被本地残留复活');
      expect(
        entries.single.room.followers,
        '123456',
        reason: '保留的同 key 条目统计仍在',
      );
      expect(api.pushes, isEmpty);
    });
  });
}
