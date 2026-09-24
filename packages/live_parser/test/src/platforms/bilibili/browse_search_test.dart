import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/browse.dart';
import 'package:live_parser/src/platforms/bilibili/search.dart';
import 'package:live_parser/src/platforms/bilibili/wbi.dart';
import 'package:test/test.dart';

import '../../../support/fake_bilibili_api.dart';

String _fixture(String name) => File('test/fixtures/bilibili/$name').readAsStringSync();

Object? _json(String name) => jsonDecode(_fixture(name));

void main() {
  late FakeBilibiliApi fake;
  late BilibiliBrowseRepository browse;
  late BilibiliSearchRepository search;

  setUp(() {
    fake = FakeBilibiliApi()
      ..areaListResponse = _json('area_list.json')
      ..roomListResponse = _json('room_list.json')
      ..webMainListResponse = _json('web_main.json')
      ..spiResponse = {
        'code': 0,
        'data': {'b_3': 'buvid-xyz'},
      }
      ..navResponse = {
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/bfs/wbi/abc123.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/def456.png',
          },
        },
      };
    final parserHttp = ParserHttp(client: fake);
    final credentials = BilibiliCredentials();
    browse = BilibiliBrowseRepository(parserHttp, credentials);
    search = BilibiliSearchRepository(parserHttp, credentials);
  });

  test('分类:getList 分组,空分组过滤,pic 归一', () async {
    final result = await browse.fetchCategories('bilibili');
    expect(result.site, 'bilibili');
    expect(result.groups, hasLength(1));

    final games = result.groups[0];
    expect(games.name, '网游');
    expect(games.items[0].pic, 'https://i0.hdslb.com/bfs/area/lol.jpg');
    expect(games.items[1].pic, '');
  });

  test('分类列表:getRoomList 归一 + 角标', () async {
    fake.roomListResponse = _json('room_list.json');
    final result = await browse.fetchRooms(
      const RoomListRequest(site: 'bilibili', cid: '325', page: 1, limit: 30),
    );

    expect(result.rooms, hasLength(2));
    final first = result.rooms[0];
    expect(first.roomId, '111');
    expect(first.title, '房间A标题');
    expect(first.online, '10.2万');
    expect(first.promoTag, '知名游戏UP', reason: 'TS truncatePromoTag 同样按 6 字截断');
    expect(result.rooms[1].promoTag, 'PK中');
    expect(result.rooms[1].cover, 'https://i0.hdslb.com/b.jpg');

    // 浏览目录 live-only(6sol 裁决,Task 4a-i):状态真源显式为 live,
    // 不再回落默认 offline(fixture live_status 全为 1)。
    expect(
      RoomRecord.fromSummary(first).roomState,
      RoomState.live,
      reason: 'getRoomList 分区目录条目来自直播列表,roomState 应为 live',
    );
  });

  test('首页:getRoomList + webMain 推荐合并去重', () async {
    fake.webMainListResponse = _json('web_main.json');
    final result = await browse.fetchRooms(
      const RoomListRequest(site: 'bilibili', cid: null, page: 1, limit: 30),
    );
    // broad 2 条 + webMain 新增 333(111 重复) = 3
    expect(result.rooms.map((r) => r.roomId).toList(), ['111', '222', '333']);

    // 浏览目录 live-only(6sol 裁决,Task 4a-i):合并推荐位后同为 live。
    expect(
      RoomRecord.fromSummary(result.rooms.first).roomState,
      RoomState.live,
      reason: 'getRoomList + webMain 推荐合并列表,状态真源为 live',
    );
  });

  test('搜索:主播与房间合并去重,em 高亮剥离', () async {
    // 两个 search_type 按请求顺序返回不同 fixture:第一次 bili_user,第二次 live
    var searchCalls = 0;
    fake.routeInterceptor = (path) {
      if (path.contains('/search/type')) {
        searchCalls++;
        return searchCalls == 1 ? _json('search_user.json') : _json('search_live.json');
      }
      return null;
    };

    final result = await search.search(
      const SearchRequest(site: 'bilibili', query: '测试', limit: 20),
    );

    expect(result.hits, hasLength(2));
    expect(result.hits.map((h) => h.id).toList(), ['4444', '9527']);
    expect(result.hits[1].anchor, '测试主播');
    expect(result.hits[1].fans, '123456', reason: '粉丝数用 formatExactCount');
    expect(result.hits[0].title, '测试赛况', reason: 'em 高亮标签被剥离');
    expect(searchCalls, 2);
  });
}
