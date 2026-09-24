import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/browse.dart';
import 'package:live_parser/src/platforms/huya/search.dart';
import 'package:test/test.dart';

import '../../../support/fake_huya_api.dart';

String _fixture(String name) => File('test/fixtures/huya/$name').readAsStringSync();

void main() {
  late FakeHuyaApi fake;
  late HuyaBrowseRepository browse;
  late HuyaSearchRepository search;

  setUp(() {
    fake = FakeHuyaApi()
      ..gameListResponse = jsonDecode(_fixture('game_list.json'))
      ..liveListResponse = jsonDecode(_fixture('live_list.json'))
      ..searchResponse = jsonDecode(_fixture('search.json'))
      ..profileRoomResponse = jsonDecode(_fixture('profile_room_live.json'));
    browse = HuyaBrowseRepository(ParserHttp(client: fake));
    search = HuyaSearchRepository(ParserHttp(client: fake));
  });

  group('浏览', () {
    test('分类:gameList 按 bussType 分组,isHide/空名过滤', () async {
      final result = await browse.fetchCategories('huya');
      expect(result.site, 'huya');
      expect(result.groups, hasLength(2));

      final pc = result.groups[0];
      expect(pc.id, '1');
      expect(pc.name, '网游');
      expect(pc.items.map((i) => (i.cid, i.name)).toList(), [
        ('1', '英雄联盟'),
        ('2', 'DNF'),
      ]);
      expect(pc.items[0].pic, 'https://huyaimg.msstatic.com/cdnimage/game/1-MS.jpg');

      final mobile = result.groups[1];
      expect(mobile.name, '手游');
      expect(mobile.items.single.name, '王者荣耀');
    });

    test('gameList 失败回退兜底热门分区', () async {
      fake.gameListResponse = {'status': 500};
      final result = await browse.fetchCategories('huya');
      expect(result.groups, hasLength(1));
      expect(result.groups.single.name, '热门');
      expect(result.groups.single.items.map((i) => i.name), contains('英雄联盟'));
    });

    test('分类房间列表:getLiveList 归一 + hasMore', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'huya', cid: '1', page: 2, limit: 120),
      );

      expect(result.page, 2);
      expect(result.hasMore, isTrue, reason: 'page=2 < iTotalPage=3');
      expect(result.rooms, hasLength(2));

      final first = result.rooms[0];
      expect(first.roomId, '111');
      expect(first.title, '房间A标题');
      expect(first.anchorName, '主播A');
      expect(first.cid, '1');
      expect(first.category, '英雄联盟');
      expect(first.online, '10.2万');
      expect(first.promoTag, '官方赛况');

      expect(result.rooms[1].cover, 'https://img.huya.com/b.jpg', reason: '// 补 https');
      expect(result.rooms[1].online, '999');

      // 浏览目录 live-only(6sol 裁决,Task 4a-i):状态真源显式为 live。
      expect(
        RoomRecord.fromSummary(first).roomState,
        RoomState.live,
        reason: 'getLiveList 分类目录条目来自直播列表,roomState 应为 live',
      );
    });
  });

  group('搜索', () {
    test('主播分区 + 在播房间分区合并去重排序', () async {
      final result = await search.search(
        const SearchRequest(site: 'huya', query: '测试', limit: 20),
      );

      // 分区1:9527/3002;分区3:4444 新增、9527 重复跳过 → 3 条
      expect(result.hits, hasLength(3));
      expect(result.hits.map((h) => h.id).toList(), ['4444', '9527', '3002']);

      final anchorHit = result.hits[1];
      expect(anchorHit.title, '测试主播的房间');
      expect(anchorHit.state, SearchHitState.live);
      expect(anchorHit.avatar, 'https://huyaimg.msstatic.com/avatar.jpg');
      expect(anchorHit.online, '15万');
      expect(anchorHit.fans, '12.3万');

      expect(result.hits[0].state, SearchHitState.live, reason: '4444 标题前缀命中 80 分');
      expect(result.hits[2].state, SearchHitState.offline);

      final request = fake.requests.firstWhere((r) => r.url.contains('search.cdn.huya.com'));
      expect(request.url, contains('q=%E6%B5%8B%E8%AF%95'));
      expect(request.url, contains('rows=20'));
      expect(request.url, contains('typ=-5'));

      final empty = await search.search(const SearchRequest(site: 'huya', query: ' '));
      expect(empty.hits, isEmpty);
    });

    test('type=rooms 分流:v=4 仅取在播房间分区(3),标题走 game_roomName', () async {
      final result = await search.search(
        const SearchRequest(site: 'huya', query: '测试', limit: 20, type: SearchType.rooms),
      );

      // 只解析分区(3):4444 + 9527;主播分区(1)的 3002(offline)不出现。
      expect(result.hits.map((h) => h.id), unorderedEquals(['4444', '9527']));
      expect(result.hits.map((h) => h.state), everyElement(SearchHitState.live));
      // 标题口径对齐 web searchHuyaRooms(game_roomName),而非主播档的 live_intro。
      expect(
        result.hits.map((h) => h.title),
        unorderedEquals(['4444的房间名', '9527的房间名']),
      );

      final request = fake.requests.firstWhere((r) => r.url.contains('search.cdn.huya.com'));
      expect(request.url, contains('v=4'), reason: '房间档走 v=4(对齐 web searchHuyaRooms)');
      expect(request.url, isNot(contains('v=1')));

      // 主播档与缺省(混合)仍走 v=1:主播分区 + 在播房间分区合并。
      fake.requests.clear();
      final anchors = await search.search(
        const SearchRequest(site: 'huya', query: '测试', limit: 20, type: SearchType.anchors),
      );
      expect(
        fake.requests.single.url.contains('v=1'),
        isTrue,
        reason: '主播档走 v=1(对齐 web searchHuyaAnchors)',
      );
      expect(anchors.hits.map((h) => h.id), contains('3002'));
    });
  });
}
