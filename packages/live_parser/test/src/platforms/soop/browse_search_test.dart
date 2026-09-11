import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_soop_api.dart';

void main() {
  late FakeSoopApi fake;
  late SoopBrowseRepository browse;
  late SoopSearchRepository search;

  setUp(() {
    fake = FakeSoopApi()
      ..categoryListResponse = soopFixture('category_list.json')
      ..categoryRoomsResponse = soopFixture('category_rooms.json')
      ..recommendResponse = soopFixture('recommend.json')
      ..searchResponse = soopFixture('search.json');
    browse = SoopBrowseRepository(ParserHttp(client: fake));
    search = SoopSearchRepository(ParserHttp(client: fake));
  });

  group('SOOP 浏览', () {
    test('分类:单组「热门」+ 图片协议归一 + 缓存', () async {
      final result = await browse.fetchCategories('soop');

      expect(result.site, 'soop');
      expect(result.groups, hasLength(1));
      expect(result.groups.single.name, '热门');
      expect(
        result.groups.single.items.map((item) => (item.cid, item.name)).toList(),
        [('100', '英雄联盟'), ('200', '绝地求生')],
      );
      expect(
        result.groups.single.items.first.pic,
        'https://img.sooplive.co.kr/cate/lol.jpg',
      );

      final calls = fake.requests.length;
      await browse.fetchCategories('soop');
      expect(fake.requests.length, calls, reason: '分类索引应命中缓存');
    });

    test('首页推荐:broad 列表归一(覆盖 total/sum 计数)', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'soop', page: 1, limit: 30),
      );

      expect(result.rooms, hasLength(2));
      expect(result.rooms.first.roomId, 'rec_a');
      expect(result.rooms.first.anchorName, '推荐A');
      expect(result.rooms.first.online, '5.4万');
      expect(result.rooms.first.cover, 'https://img.sooplive.co.kr/thumb/rec_a.jpg');
      expect(result.rooms.last.online, '900');
    });

    test('分类房间:按 cid 拉取并统计 PC+移动观看数', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'soop', cid: '100', page: 1, limit: 30),
      );

      expect(result.rooms, hasLength(2));
      expect(result.rooms.first.cid, '100');
      expect(result.rooms.first.online, '1.2万');
      expect(result.rooms.last.online, '1.0千');
      final request = fake.requests.last;
      expect(request.url.queryParameters['m'], 'categoryContentsList');
      expect(request.url.queryParameters['szCateNo'], '100');
      expect(request.url.queryParameters['szOrder'], 'view_cnt_desc');
    });
  });

  group('SOOP 搜索', () {
    test('REAL_BROAD 归一为命中项', () async {
      final result = await search.search(
        const SearchRequest(site: 'soop', query: '英雄联盟', limit: 20),
      );

      expect(result.hits, hasLength(1));
      final hit = result.hits.single;
      expect(hit.id, 'search_a');
      expect(hit.anchor, '搜索主播');
      expect(hit.title, '搜索结果房间');
      expect(hit.category, '英雄联盟');
      expect(hit.online, '7.8千');
      expect(hit.state, SearchHitState.live);
      expect(hit.avatar, startsWith('https://stimg.sooplive.co.kr/LOGO/se/'));
    });

    test('空查询不发请求', () async {
      final result = await search.search(
        const SearchRequest(site: 'soop', query: '  ', limit: 20),
      );

      expect(result.hits, isEmpty);
      expect(fake.requests, isEmpty);
    });
  });
}
