import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_yy_api.dart';

void main() {
  late FakeYyApi fake;
  late YyBrowseRepository browse;
  late YySearchRepository search;

  setUp(() {
    fake = FakeYyApi()
      ..headerResponse = yyFixture('header.json')
      ..categoryResponses['1'] = yyFixture('category_1.json')
      ..categoryResponses['2'] = const {'data': []}
      ..categoryPages['https://www.yy.com/music/'] =
          'window.__CONFIG__ = {moduleId: 308, biz: "sing", subBiz: "idx"};'
      ..categoryPages['https://www.yy.com/show/'] =
          'window.__CONFIG__ = {moduleId: 328, biz: "talk", subBiz: "idx"};'
      ..recommendResponse = yyFixture('recommend.json');
    final http = ParserHttp(client: fake);
    browse = YyBrowseRepository(http);
    search = YySearchRepository(http);
  });

  group('YY 浏览', () {
    test('分类：header + 子分类，图片协议归一并缓存分类参数', () async {
      final result = await browse.fetchCategories('yy');

      expect(result.site, 'yy');
      expect(result.groups, hasLength(1));
      expect(result.groups.single.id, '1');
      expect(result.groups.single.name, '娱乐');
      expect(result.groups.single.items.map((item) => (item.cid, item.name)).toList(), [
        ('7', '音乐'),
        ('8', '脱口秀'),
      ]);
      expect(result.groups.single.items.first.pic, 'https://img.yy.com/music.jpg');

      final pageRequests = fake.requests.where(
        (request) => request.url.path == '/music/' || request.url.path == '/show/',
      );
      expect(pageRequests.length, 2);
    });

    test('分类缓存：二次请求不再访问 header 与子分类', () async {
      await browse.fetchCategories('yy');
      final firstCalls = fake.requests.length;
      final second = await browse.fetchCategories('yy');

      expect(second.groups.single.items, hasLength(2));
      expect(fake.requests.length, firstCalls);
    });

    test('首页推荐：more/page.action 归一房间、热度和 hasMore', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'yy', page: 1, limit: 2),
      );

      expect(result.page, 1);
      expect(result.rooms, hasLength(2));
      expect(result.hasMore, isTrue);
      expect(result.rooms.first.roomId, '1414787909');
      expect(result.rooms.first.anchorName, '莉莉');
      expect(result.rooms.first.title, '永远都是小女孩');
      expect(result.rooms.first.online, '4.1万');
      expect(result.rooms.first.cover, 'https://img.yy.com/cover.jpg');
      // 推荐流 biz='other' 无分类语义 → 回退「推荐」。
      expect(result.rooms.first.category, '推荐');

      // 列表来自 RoomSummary:统一记录只映射已提供的统计(audience),
      // 上游列表没有 followers/vip/svip → 保持 null,不编造数字。
      final record = RoomRecord.fromSummary(result.rooms.first);
      expect(record.site, 'yy');
      expect(record.roomId, '1414787909');
      // 浏览目录 live-only(6sol 裁决,Task 4a-i):状态真源显式为 live。
      expect(
        record.roomState,
        RoomState.live,
        reason: 'more/page.action 直播目录条目,roomState 应为 live',
      );
      expect(record.audience, '4.1万');
      expect(record.followers, isNull);
      expect(record.vip, isNull);
      expect(record.svip, isNull);

      final request = fake.requests.singleWhere((item) => item.url.path == '/more/page.action');
      expect(request.url.queryParameters['biz'], 'other');
      expect(request.url.queryParameters['subBiz'], 'idx');
      expect(request.url.queryParameters['moduleId'], '-1');
    });

    test('分类列表：使用分类页参数请求 more/page.action 并保留 cid', () async {
      await browse.fetchCategories('yy');
      fake.recommendResponse = {
        'data': {
          'data': [
            {
              'sid': '100',
              'ssid': '100',
              'name': '分类主播',
              'desc': '分类房间',
              'users': 1200,
              'thumb2': '//img.yy.com/category.jpg',
              'biz': 'sing',
            },
          ],
        },
      };

      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'yy', cid: '7', page: 2, limit: 30),
      );

      expect(result.page, 2);
      expect(result.rooms.single.cid, '7');
      // biz 反查分类中文名(fetchCategories 时登记的 sing→音乐)。
      expect(result.rooms.single.category, '音乐');
      expect(result.rooms.single.online, '1.2千');
      expect(
        RoomRecord.fromSummary(result.rooms.single).audience,
        '1.2千',
        reason: '精确格式原样保留',
      );
      final request = fake.requests.last;
      expect(request.url.queryParameters['moduleId'], '308');
      expect(request.url.queryParameters['biz'], 'sing');
      expect(request.url.queryParameters['subBiz'], 'idx');
    });

    test('未知分类无参数时返回空页，不误请求首页', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'yy', cid: '999'),
      );

      expect(result.rooms, isEmpty);
      expect(fake.requests.where((request) => request.url.path == '/more/page.action'), isEmpty);
    });
  });

  group('YY 搜索', () {
    test('主播与房间搜索合并、状态和图片归一', () async {
      fake.searchResponses['120'] = {
        'data': {
          'searchResult': {
            'response': {
              '120': {
                'docs': [
                  {
                    'sid': '120',
                    'name': '测试主播',
                    'channelName': '测试房间',
                    'posterurl': '//img.yy.com/poster.jpg',
                    'headurl': 'http://img.yy.com/head.jpg',
                    'biz': '游戏',
                    'users': '12000',
                    'liveOn': '1',
                  },
                ],
              },
            },
          },
        },
      };
      fake.searchResponses['1'] = {
        'data': {
          'searchResult': {
            'response': {
              '1': {
                'docs': [
                  {
                    'sid': '121',
                    'name': '离线主播',
                    'stageName': '离线频道',
                    'headurl': '//img.yy.com/offline.jpg',
                    'liveOn': 0,
                  },
                ],
              },
            },
          },
        },
      };

      final result = await search.search(
        const SearchRequest(site: 'yy', query: '测试', limit: 20),
      );

      expect(result.site, 'yy');
      expect(result.hits, hasLength(2));
      expect(result.hits.first.id, '120');
      expect(result.hits.first.state, SearchHitState.live);
      expect(result.hits.first.online, '1.2万');
      expect(result.hits.first.avatar, 'https://img.yy.com/head.jpg');
      expect(result.hits.first.cover, 'https://img.yy.com/poster.jpg');
      expect(result.hits.last.state, SearchHitState.offline);
      expect(result.hits.last.title, '离线频道');
      expect(result.hits.last.avatar, 'https://img.yy.com/offline.jpg');
    });

    test('空查询不访问网络，limit 生效', () async {
      final empty = await search.search(
        const SearchRequest(site: 'yy', query: '  ', limit: 1),
      );
      expect(empty.hits, isEmpty);
      expect(fake.requests, isEmpty);
    });
  });
}
