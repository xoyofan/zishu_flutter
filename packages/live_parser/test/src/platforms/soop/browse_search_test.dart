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

    test('分类名中文化:房间流按 broad_cate_no 反查,且收口上游直出的英文分类', () async {
      // 回归(实测 2026-09-26):房间列表项**只有 `broad_cate_no`,没有
      // `category_no`**,旧实现读 `category_no` 恒得空串 → cid→中文反查
      // 永远 miss → 房间卡片一直显示韩文。
      // 另:categoryList 本身返中文(与 lang 无关),但 `00130000` 直出英文
      // `Talk/Cam`,需由内置覆盖收口。
      // FakeSoopApi 的响应字段要的是**已解码对象**(与 soopFixture 同构),
      // 直接给 JSON 字符串会被 ParserHttp 判为「非对象 JSON」。
      final catJson = <String, Object?>{
        'data': <String, Object?>{
          'list': <Object?>[
            <String, Object?>{'category_no': '00130000', 'category_name': 'Talk/Cam'},
            <String, Object?>{'category_no': '00040019', 'category_name': '英雄联盟'},
          ],
        },
      };
      final roomJson = <String, Object?>{
        'broad': <Object?>[
          <String, Object?>{
            'user_id': 'r1',
            'broad_title': '聊天房',
            'user_nick': 'A',
            'broad_cate_no': '00130000',
            'category_name': '토크/캠방',
            'view_cnt': '10',
          },
          <String, Object?>{
            'user_id': 'r2',
            'broad_title': 'LOL 房',
            'user_nick': 'B',
            'broad_cate_no': '00040019',
            'category_name': '리그 오브 레전드',
            'view_cnt': '20',
          },
        ],
      };
      final f = FakeSoopApi()
        ..categoryListResponse = catJson
        ..recommendResponse = roomJson
        ..categoryRoomsResponse = roomJson;
      final repo = SoopBrowseRepository(ParserHttp(client: f));

      // 先拉分类树填中文反查表,再拉房间流。
      await repo.fetchCategories('soop');
      final rooms = await repo.fetchRooms(
        const RoomListRequest(site: 'soop', page: 1, limit: 30),
      );

      expect(rooms.rooms, hasLength(2));
      expect(
        rooms.rooms[0].category,
        '聊天/秀场',
        reason: 'broad_cate_no=00130000 应反查中文(上游英文 Talk/Cam 经 remap 收口)',
      );
      expect(
        rooms.rooms[1].category,
        '英雄联盟',
        reason: 'broad_cate_no=00040019 应反查中文,不得回落韩文原名',
      );
    });

    test('分类名中文化:未先进分类页时,英文覆盖分类仍不漏英文', () async {
      // 覆盖表在**查表时**生效,与分类树是否已加载无关。
      final roomJson = <String, Object?>{
        'broad': <Object?>[
          <String, Object?>{
            'user_id': 'r1',
            'broad_title': '聊天房',
            'user_nick': 'A',
            'broad_cate_no': '00130000',
            'category_name': '토크/캠방',
            'view_cnt': '10',
          },
        ],
      };
      final f = FakeSoopApi()
        ..recommendResponse = roomJson
        ..categoryRoomsResponse = roomJson;
      final repo = SoopBrowseRepository(ParserHttp(client: f));

      final rooms = await repo.fetchRooms(
        const RoomListRequest(site: 'soop', page: 1, limit: 30),
      );
      expect(rooms.rooms.single.category, '聊天/秀场');
    });

    test('首页推荐:broad 列表归一(覆盖 total/sum 计数)', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'soop', page: 1, limit: 30),
      );

      expect(result.rooms, hasLength(2));
      expect(result.rooms.first.roomId, 'rec_a');
      expect(result.rooms.first.anchorName, '推荐A');
      expect(result.rooms.first.audience, '5.4万');
      expect(result.rooms.first.cover, 'https://img.sooplive.co.kr/thumb/rec_a.jpg');
      expect(result.rooms.last.audience, '900');

      // 统一记录:fromSummary 映射列表 fixture 真值(audience);上游列表
      // 没有 followers/vip/svip → 保持 null,不编造数字。
      // 浏览目录 live-only(6sol 裁决,Task 4a-i):状态真源显式为 live。
      final record = result.rooms.first;
      expect(record.site, 'soop');
      expect(record.roomId, 'rec_a');
      expect(
        record.roomState,
        RoomState.live,
        reason: 'main_broad_list 直播推荐目录,roomState 应为 live',
      );
      expect(record.audience, '5.4万', reason: 'view_cnt=54321 → online 透传');
      expect(record.followers, isNull);
      expect(record.vip, isNull);
      expect(record.svip, isNull);
    });

    test('分类房间:按 cid 拉取并统计 PC+移动观看数', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'soop', cid: '100', page: 1, limit: 30),
      );

      expect(result.rooms, hasLength(2));
      expect(result.rooms.first.cid, '100');
      expect(result.rooms.first.audience, '1.2万');
      expect(result.rooms.last.audience, '1.0千');

      // 统一记录:分类列表同口径(6sol 裁决,Task 4a-i):live-only 目录
      // 状态真源显式为 live。
      final record = result.rooms.first;
      expect(record.site, 'soop');
      expect(record.roomId, 'room_a');
      expect(
        record.roomState,
        RoomState.live,
        reason: 'categoryContentsList(szType=live) 分类目录状态真源为 live',
      );
      expect(record.audience, '1.2万');
      expect(record.followers, isNull);
      expect(record.vip, isNull);
      expect(record.svip, isNull);
      final request = fake.requests.last;
      expect(request.url.queryParameters['m'], 'categoryContentsList');
      expect(request.url.queryParameters['szCateNo'], '100');
      expect(request.url.queryParameters['szOrder'], 'view_cnt_desc');
    });
  });

  group('SOOP 搜索', () {
    test('分类请求带 Accept-Language:zh-CN(缺该头时上游直出韩文)', () async {
      final registration = buildSoopRegistration(httpClient: fake);
      await registration.browse!.fetchCategories('soop');
      expect(
        fake.requests.last.headers['accept-language'],
        'zh-CN,zh;q=0.9',
        reason: 'lang=zh_CN 参数需搭配 Accept-Language 头上游才返回中文分类名',
      );
    });


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
