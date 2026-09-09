import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../support/fake_browse.dart';

SiteRegistry _registryWith({
  required Map<String, FakeBrowseRepository> browses,
  List<String> siteIds = const ['douyu', 'huya', 'bilibili'],
  CrossMergeMode mergeMode = CrossMergeMode.interleaved,
}) {
  final registry = SiteRegistry();
  for (final entry in browses.entries) {
    registry.register(fakeSiteRegistration(site: entry.key, browse: entry.value));
  }
  registry.register(
    buildCrossRegistration(registry: registry, siteIds: siteIds, mergeMode: mergeMode),
  );
  return registry;
}

void main() {
  group('全平台首页聚合', () {
    test('三平台轮流混排,不被单平台霸屏', () async {
      final douyu = FakeBrowseRepository(
        site: 'douyu',
        rooms: [fakeRoom('douyu', 'd1'), fakeRoom('douyu', 'd2')],
        hasMore: true,
      );
      final huya = FakeBrowseRepository(
        site: 'huya',
        rooms: [fakeRoom('huya', 'h1'), fakeRoom('huya', 'h2')],
      );
      final bilibili = FakeBrowseRepository(
        site: 'bilibili',
        rooms: [fakeRoom('bilibili', 'b1'), fakeRoom('bilibili', 'b2')],
      );
      final registry = _registryWith(browses: {
        'douyu': douyu,
        'huya': huya,
        'bilibili': bilibili,
      });

      final result = await registry['all']!.browse!.fetchRooms(
        const RoomListRequest(site: 'all', limit: 30),
      );

      expect(
        result.rooms.map((r) => r.roomId).toList(),
        ['d1', 'h1', 'b1', 'd2', 'h2', 'b2'],
      );
      expect(result.hasMore, isTrue, reason: '任一平台 hasMore 即整体 hasMore');
      expect(result.page, 1);
    });

    test('byPopularity 按在线人数全局降序', () async {
      final registry = _registryWith(
        browses: {
          'douyu': FakeBrowseRepository(
            site: 'douyu',
            rooms: [fakeRoom('douyu', 'd1', online: '1.2万')],
          ),
          'huya': FakeBrowseRepository(
            site: 'huya',
            rooms: [fakeRoom('huya', 'h1', online: '3.4千')],
          ),
          'bilibili': FakeBrowseRepository(
            site: 'bilibili',
            rooms: [fakeRoom('bilibili', 'b1', online: '98000')],
          ),
        },
        mergeMode: CrossMergeMode.byPopularity,
      );

      final result = await registry['all']!.browse!.fetchRooms(
        const RoomListRequest(site: 'all'),
      );
      expect(result.rooms.map((r) => r.roomId).toList(), ['b1', 'd1', 'h1']);
    });

    test('单平台失败被隔离,其余平台照常返回', () async {
      final registry = _registryWith(browses: {
        'douyu': FakeBrowseRepository(site: 'douyu', fail: true),
        'huya': FakeBrowseRepository(site: 'huya', rooms: [fakeRoom('huya', 'h1')]),
        'bilibili': FakeBrowseRepository(
          site: 'bilibili',
          rooms: [fakeRoom('bilibili', 'b1')],
        ),
      });

      final result = await registry['all']!.browse!.fetchRooms(
        const RoomListRequest(site: 'all'),
      );
      expect(result.rooms.map((r) => r.roomId).toList(), ['h1', 'b1']);
      expect(result.hasMore, isFalse);
    });

    test('超过 limit 时截断;未注册平台被跳过', () async {
      final registry = _registryWith(
        browses: {
          'douyu': FakeBrowseRepository(
            site: 'douyu',
            rooms: List.generate(5, (i) => fakeRoom('douyu', 'd$i')),
          ),
          'huya': FakeBrowseRepository(
            site: 'huya',
            rooms: List.generate(5, (i) => fakeRoom('huya', 'h$i')),
          ),
        },
        siteIds: ['douyu', 'huya', 'bilibili'],
      );

      final result = await registry['all']!.browse!.fetchRooms(
        const RoomListRequest(site: 'all', limit: 4),
      );
      expect(result.rooms, hasLength(4));
      expect(result.rooms.map((r) => r.roomId).toList(), ['d0', 'h0', 'd1', 'h1']);
    });

    test('全平台无可用源时返回空列表', () async {
      final registry = _registryWith(
        browses: const {},
        siteIds: ['douyu'],
      );
      final result = await registry['all']!.browse!.fetchRooms(
        const RoomListRequest(site: 'all'),
      );
      expect(result.rooms, isEmpty);
      expect(result.hasMore, isFalse);
    });
  });

  group('跨平台分类房间', () {
    test('按 cross key 过滤,并用平台原生 cid 拉取', () async {
      final douyu = FakeBrowseRepository(
        site: 'douyu',
        rooms: [
          fakeRoom('douyu', 'd1', cid: '1', category: '英雄联盟'),
          fakeRoom('douyu', 'd2', cid: '9', category: '其他游戏'),
        ],
      );
      final huya = FakeBrowseRepository(
        site: 'huya',
        rooms: [
          fakeRoom('huya', 'h1', cid: '1', category: '英雄联盟'),
          fakeRoom('huya', 'h2', cid: '5485', category: 'lol云顶之弈'),
        ],
      );
      final bilibili = FakeBrowseRepository(
        site: 'bilibili',
        rooms: [
          fakeRoom('bilibili', 'b1', cid: '86', category: '英雄联盟'),
          fakeRoom('bilibili', 'b2', cid: '371', category: '生活'),
        ],
      );
      final registry = _registryWith(browses: {
        'douyu': douyu,
        'huya': huya,
        'bilibili': bilibili,
      });

      final result = await registry['all']!.browse!.fetchRooms(
        const RoomListRequest(site: 'all', cid: 'lol'),
      );

      expect(result.rooms.map((r) => r.roomId).toList(), ['d1', 'h1', 'b1']);
      expect(douyu.lastRequest?.cid, '1', reason: '斗鱼用 cid2=1 直接拉分类房间');
      expect(huya.lastRequest?.cid, '1');
      expect(bilibili.lastRequest?.cid, isNull, reason: 'B站未登记 cid,走名称过滤');
      expect(douyu.lastRequest?.limit, 60, reason: '分类模式放大单平台取量');
    });

    test('过滤后无命中时返回空列表', () async {
      final registry = _registryWith(browses: {
        'douyu': FakeBrowseRepository(
          site: 'douyu',
          rooms: [fakeRoom('douyu', 'd1', cid: '9', category: '其他游戏')],
        ),
      }, siteIds: ['douyu']);

      final result = await registry['all']!.browse!.fetchRooms(
        const RoomListRequest(site: 'all', cid: 'valorant'),
      );
      expect(result.rooms, isEmpty);
    });

    test('cid 为 0/空等价于全平台首页', () async {
      final douyu = FakeBrowseRepository(
        site: 'douyu',
        rooms: [fakeRoom('douyu', 'd1', cid: '9', category: '其他游戏')],
      );
      final registry = _registryWith(browses: {'douyu': douyu}, siteIds: ['douyu']);

      for (final cid in ['0', '']) {
        final result = await registry['all']!.browse!.fetchRooms(
          RoomListRequest(site: 'all', cid: cid),
        );
        expect(result.rooms, hasLength(1), reason: 'cid=$cid 视为不过滤');
        expect(douyu.lastRequest?.cid, isNull);
      }
    });
  });

  group('全平台分类索引与能力', () {
    test('fetchCategories 返回跨平台分类', () async {
      final registry = _registryWith(browses: {}, siteIds: []);
      final result = await registry['all']!.browse!.fetchCategories('all');
      expect(result.site, 'all');
      expect(result.groups.single.items.map((e) => e.cid), contains('lol'));
    });

    test('聚合站点不提供房间解析', () async {
      final registry = _registryWith(browses: {}, siteIds: []);
      final all = registry['all']!;
      expect(all.name, '全平台');
      expect(all.capabilities.browse, isTrue);
      expect(all.capabilities.danmaku, isFalse);
      expect(all.search, isNull);
      expect(
        all.resolver.resolveRoom(
          const RoomRequest(site: 'all', roomIdOrUrl: '123'),
        ),
        throwsA(isA<UnsupportedSiteFeature>()),
      );
    });
  });
}
