import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyin_api.dart';

void main() {
  late FakeDouyinApi fake;
  late DouyinBrowseRepository browse;

  setUp(() {
    fake = FakeDouyinApi()
      ..homeHtml = douyinHtmlFixture('home.html')
      ..partitionResponse = douyinFixture('partition_rooms.json');
    browse = DouyinBrowseRepository(DouyinClient(httpClient: fake));
  });

  group('抖音浏览', () {
    test('分类:游戏树 + 娱乐 tab,图片留空', () async {
      final result = await browse.fetchCategories('douyin');

      expect(result.site, 'douyin');
      expect(result.groups, hasLength(3));
      expect(result.groups[0].id, '1');
      expect(result.groups[0].name, '射击游戏');
      expect(
        result.groups[0].items.map((item) => (item.cid, item.name)).toList(),
        [('1010032', '和平精英'), ('1010003', 'CSGO')],
      );
      expect(result.groups[1].items.single.cid, '1010045');
      final entertainment = result.groups.last;
      expect(entertainment.id, 'yule');
      expect(entertainment.name, '娱乐');
      expect(
        entertainment.items.map((item) => item.name).toList(),
        ['聊天', '音乐'],
      );

      final calls = fake.requests.length;
      await browse.fetchCategories('douyin');
      expect(fake.requests.length, calls, reason: '分类索引应命中缓存');
    });

    test('推荐:使用 live feed 并透传登录 Cookie', () async {
      fake.feedResponse = douyinFixture('feed_rooms.json');
      final loggedInBrowse = DouyinBrowseRepository(
        DouyinClient(
          httpClient: fake,
          cookieOverride: 'UIFID=test-user; passport_csrf_token=test-token',
        ),
      );

      final result = await loggedInBrowse.fetchRooms(
        const RoomListRequest(site: 'douyin', page: 1, limit: 15),
      );

      expect(result.rooms, hasLength(1));
      final room = result.rooms.single;
      expect(room.roomId, '123456');
      expect(room.title, '当前推荐直播');
      expect(room.anchorName, '推荐主播');
      expect(room.audience, '1.2万');
      expect(room.cover, 'https://p3.douyinpic.com/recommend-cover.jpg');
      expect(room.avatar, 'https://p3.douyinpic.com/recommend-avatar.jpg');
      expect(room.category, '游戏推荐');
      expect(room.roomState, RoomState.live);
      expect(result.hasMore, isTrue);

      final request = fake.requests.last;
      expect(request.url.path, '/webcast/feed/');
      expect(request.url.queryParameters['aid'], '6383');
      expect(request.url.queryParameters['live_id'], '1');
      expect(request.url.queryParameters['enter_from'], 'link_share');
      expect(request.url.queryParameters['custom_count'], '50');
      expect(request.url.queryParameters['action'], 'load_more');
      expect(request.url.queryParameters['action_type'], 'loadmore');
      expect(request.url.queryParameters['is_ssr'], 'true');
      expect(request.url.queryParameters['maxtime'], '0');
      expect(
        request.url.queryParameters['source_key'],
        'web_homepage_hot_web_live_card',
      );
      expect(request.url.queryParameters['a_bogus'], isNotEmpty);
      expect(
        request.headers['Cookie'],
        'UIFID=test-user; passport_csrf_token=test-token',
      );
    });

    test('推荐:按 extra.has_more 加载下一页', () async {
      fake.feedResponse = douyinFixture('feed_rooms.json');
      fake.feedNextResponse = douyinFixture('feed_rooms_page2.json');
      final first = await browse.fetchRooms(
        const RoomListRequest(site: 'douyin', page: 1, limit: 15),
      );
      final second = await browse.fetchRooms(
        const RoomListRequest(site: 'douyin', page: 2, limit: 15),
      );

      expect(first.hasMore, isTrue);
      expect(second.page, 2);
      expect(second.rooms.single.roomId, '654321');
      expect(second.hasMore, isFalse);
      expect(fake.requests.last.url.queryParameters['custom_count'], '8');
      expect(fake.requests.last.url.queryParameters['maxtime'], isNull);
    });

    test('关注直播:一次接口返回当前直播中的关注房间', () async {
      fake.followLiveResponse = douyinFixture('follow_live_rooms.json');
      final result = await fetchDouyinFollowLiveRooms(
        DouyinClient(
          httpClient: fake,
          cookieOverride: 'UIFID=follow-user; sessionid=follow-session',
        ),
      );

      expect(result.complete, isTrue);
      expect(result.rooms, hasLength(1));
      expect(result.rooms.single.roomId, 'follow-live-1');
      expect(result.rooms.single.roomState, RoomState.live);
      expect(result.rooms.single.audience, '2.3万');

      final request = fake.requests.last;
      expect(request.url.path, '/webcast/feed/follow_top/');
      expect(request.url.queryParameters['enter_source'], 'homepage_pc_followtop');
      expect(request.url.queryParameters['source_key'], 'web_homepage_follow_top');
      expect(request.url.queryParameters['follow_session_id'], '0');
      expect(request.url.queryParameters['maxtime'], '0');
      expect(request.url.queryParameters['a_bogus'], isNotEmpty);
      expect(
        request.headers['Cookie'],
        'UIFID=follow-user; sessionid=follow-session',
      );
    });

    test('注册表:抖音 Cookie 注入首页真实请求', () async {
      final fake = FakeDouyinApi()
        ..feedResponse = douyinFixture('feed_rooms.json');
      final registry = buildSiteRegistry(
        douyinCookie: 'UIFID=registry-user; passport_csrf_token=registry-token',
        douyinHttpClient: fake,
      );

      await registry['douyin']!.browse!.fetchRooms(
        const RoomListRequest(site: 'douyin', page: 1, limit: 15),
      );

      expect(
        fake.requests.last.headers['Cookie'],
        'UIFID=registry-user; passport_csrf_token=registry-token',
      );
    });

    test('分类房间:娱乐 cid 走 partition_type=4', () async {
      await browse.fetchRooms(
        const RoomListRequest(site: 'douyin', cid: '101', page: 2, limit: 15),
      );

      final request = fake.requests.last;
      expect(request.url.queryParameters['partition'], '101');
      expect(request.url.queryParameters['partition_type'], '4');
      expect(request.url.queryParameters['offset'], '15');
    });

    test('分类房间:chip 从分类缓存反查分区名(而非留空)', () async {
      // 先加载分类树(缓存 cid→name),再拉分类页房间。
      await browse.fetchCategories('douyin');
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'douyin', cid: '1010032', page: 1, limit: 15),
      );

      expect(result.rooms.first.category, '和平精英',
          reason: '分类页房间 chip 应为当前分区名,不能空');
    });

    test('分类房间:未命中分类缓存时 chip 无值(不额外发请求)', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'douyin', cid: '999999', page: 1, limit: 15),
      );

      // RoomSummary 空串经 fromSummary 归一为 null(统一契约 4a-ii)。
      expect(result.rooms.first.category, isNull);
      expect(
        fake.requests.any((r) => r.url.path.contains('category')),
        isFalse,
        reason: '反查只读缓存,不得触发分类索引请求',
      );
    });
  });
}
