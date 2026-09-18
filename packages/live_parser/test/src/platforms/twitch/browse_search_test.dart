import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/browse.dart';
import 'package:live_parser/src/platforms/twitch/gql.dart';
import 'package:live_parser/src/platforms/twitch/search.dart';
import 'package:live_parser/src/platforms/twitch/twitch_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_twitch_api.dart';

void main() {
  late FakeTwitchApi api;

  setUp(() {
    api = FakeTwitchApi()
      ..gamesResponse = twitchFixtureData('games.json')['games']
      ..streamsResponse = twitchFixtureData('streams_home.json')['streams']
      ..gameResponse = twitchFixtureData('game_streams.json')['game']
      ..searchResponse = twitchFixtureData('search_channels.json')['searchFor'];
  });

  TwitchGqlClient gqlFor() => TwitchGqlClient(httpClient: api);

  group('分类索引', () {
    test('games 输出单一分组,cid 为 game id', () async {
      final result = await TwitchBrowseRepository(gqlFor()).fetchCategories('twitch');
      expect(result.site, 'twitch');
      expect(result.groups, hasLength(1));
      final items = result.groups.single.items;
      expect(items.map((e) => e.cid).toList(), ['509658', '263490', '32399']);
      expect(items.first.name, '聊天', reason: '海外平台分类名经 remap 表中文化(Just Chatting→聊天)');
      expect(items.first.pic, isNot(contains('{width}')));
      expect(items.first.pic, contains('285x380'));
    });

    test('分类结果带缓存,二次调用不再请求上游', () async {
      final browse = TwitchBrowseRepository(gqlFor());
      await browse.fetchCategories('twitch');
      final calls = api.gqlOperations.length;
      await browse.fetchCategories('twitch');
      expect(api.gqlOperations.length, calls);
    });
  });

  group('房间列表', () {
    test('首页房间归一化', () async {
      final result = await TwitchBrowseRepository(gqlFor()).fetchRooms(
        const RoomListRequest(site: 'twitch', limit: 10),
      );
      expect(result.rooms.map((r) => r.roomId).toList(), [
        'kato_junichi0817',
        'fps_shaka',
      ]);
      expect(result.rooms.first.site, 'twitch');
      expect(result.rooms.first.title, 'Shadowverse Premier Series 26-27');
      expect(result.rooms.first.anchorName, '加藤純一');
      expect(result.rooms.first.category, 'Shadowverse: Worlds Beyond');
      expect(result.rooms.first.cover, contains('640x360'));
      expect(result.rooms.first.online, '2.5万');
      expect(result.hasMore, isFalse, reason: '结果不足 limit 即无更多');
    });

    test('分类房间走 game(id:) 并带上 cid', () async {
      final result = await TwitchBrowseRepository(gqlFor()).fetchRooms(
        const RoomListRequest(site: 'twitch', cid: '263490', limit: 2),
      );
      expect(result.rooms.map((r) => r.roomId).toList(), ['fps_shaka', 'sasatikk']);
      expect(result.rooms.first.cid, '263490');
      expect(result.rooms.first.category, '失控进化-RUST', reason: '房间分类同样 remap(Rust→失控进化-RUST)');
      expect(result.hasMore, isTrue);
      expect(api.gqlOperations, contains('DirectoryPage_Game'));
    });

    test('分类不存在时抛出 GQL 错误', () async {
      api.gameResponse = null;
      expect(
        TwitchBrowseRepository(gqlFor()).fetchRooms(
          const RoomListRequest(site: 'twitch', cid: 'nope'),
        ),
        throwsA(isA<TwitchGqlException>()),
      );
    });
  });

  group('搜索', () {
    test('频道搜索区分在播与离线', () async {
      final result = await TwitchSearchRepository(gqlFor()).search(
        const SearchRequest(site: 'twitch', query: 'shroud'),
      );
      expect(result.site, 'twitch');
      expect(result.hits.map((h) => h.id).toList(), ['shroud', 'shrood']);
      expect(result.hits.first.state, SearchHitState.offline);
      expect(result.hits.last.state, SearchHitState.live);
      expect(result.hits.last.anchor, 'shrood');
      expect(result.hits.last.title, 'Always On 配信');
      expect(result.hits.last.category, 'Just Chatting');
      expect(result.hits.last.online, '295');
      expect(result.hits.last.cover, contains('640x360'));
      expect(result.hits.first.avatar, contains('300x300'));
    });

    test('limit 生效', () async {
      final result = await TwitchSearchRepository(gqlFor()).search(
        const SearchRequest(site: 'twitch', query: 'shroud', limit: 1),
      );
      expect(result.hits, hasLength(1));
    });
  });

  group('注册项', () {
    test('Twitch 能力声明与仓库齐备', () {
      final registration = buildTwitchRegistration(httpClient: api);
      expect(registration.id, 'twitch');
      expect(registration.name, 'Twitch');
      expect(registration.browse, isA<BrowseRepository>());
      expect(registration.search, isA<SearchRepository>());
      expect(registration.capabilities.browse, isTrue);
      expect(registration.capabilities.roomSearch, isTrue);
      expect(registration.capabilities.anchorSearch, isTrue);
      expect(registration.capabilities.multiQuality, isTrue);
      expect(registration.capabilities.multiLine, isFalse, reason: '每档仅一条 HLS 线路');
      expect(registration.capabilities.danmaku, isFalse, reason: '弹幕 IRC 尚未接入');
      expect(registration.capabilities.requiresCookie, isFalse);
      expect(registration.resolver, isA<RoomResolver>());
    });
  });
}
