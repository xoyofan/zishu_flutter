import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_kuaishou_api.dart';

void main() {
  late FakeKuaishouApi fake;
  late KuaishouBrowseRepository browse;

  setUp(() {
    fake = FakeKuaishouApi()
      ..categoryResponse = kuaishouFixtureJson('category.json')
      ..gameboardResponse = kuaishouFixtureJson('gameboard.json')
      ..recommendResponse = kuaishouFixtureJson('recommend.json');
    browse = KuaishouBrowseRepository(ParserHttp(client: fake));
  });

  group('快手浏览', () {
    test('分类:8 个一级分组 + 二级项 + 缓存', () async {
      final result = await browse.fetchCategories('kuaishou');

      expect(result.site, 'kuaishou');
      expect(result.groups, hasLength(kKuaishouTopCategories.length));
      expect(result.groups.first.id, '1');
      expect(result.groups.first.name, '热门');
      expect(
        result.groups.first.items.map((item) => (item.cid, item.name)).toList(),
        [('1001', '英雄联盟'), ('1002', '和平精英')],
      );

      final calls = fake.requests.length;
      await browse.fetchCategories('kuaishou');
      expect(fake.requests.length, calls, reason: '分类索引应命中缓存');
    });

    test('分类房间:gameboard 接口 + 封面补扩展名', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'kuaishou', cid: '1001', page: 1, limit: 30),
      );

      expect(result.rooms, hasLength(1));
      final room = result.rooms.single;
      expect(room.roomId, 'ks_board_1');
      expect(room.anchorName, '板上主播');
      expect(room.title, '游戏板房间');
      expect(room.category, '英雄联盟');
      expect(room.online, '1.2千');
      expect(room.cover, 'https://p1.kuaishou.com/board/1.jpg');
      expect(fake.requests.last.url.path, '/live_api/gameboard/list');
      expect(fake.requests.last.url.queryParameters['gameId'], '1001');

      // 列表来自 RoomSummary:统一记录只映射已提供的统计(audience),
      // 上游列表没有 followers/vip/svip → 保持 null,不编造数字。
      final record = RoomRecord.fromSummary(room);
      expect(record.site, 'kuaishou');
      expect(record.roomId, 'ks_board_1');
      expect(record.audience, '1.2千');
      expect(record.followers, isNull);
      expect(record.vip, isNull);
      expect(record.svip, isNull);
    });

    test('分类房间:长 cid 走 non-gameboard 接口', () async {
      await browse.fetchRooms(
        const RoomListRequest(site: 'kuaishou', cid: '10000001', page: 1, limit: 30),
      );

      expect(fake.requests.last.url.path, '/live_api/non-gameboard/list');
    });

    test('首页推荐:嵌套 gameLiveInfo/liveInfo 展开', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'kuaishou', page: 1, limit: 30),
      );

      expect(result.rooms, hasLength(1));
      final room = result.rooms.single;
      expect(room.roomId, 'ks_home_1');
      expect(room.anchorName, '首页主播');
      expect(room.title, '首页推荐 描述');
      expect(room.category, '王者荣耀');
      expect(room.online, '10.0千');
      expect(room.cover, 'https://p1.kuaishou.com/home/1.jpg');
      expect(result.hasMore, isFalse);
      expect(
        RoomRecord.fromSummary(room).audience,
        '10.0千',
        reason: '精确格式原样保留',
      );
    });
  });
}
