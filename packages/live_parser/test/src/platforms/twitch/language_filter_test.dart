/// Twitch 语言 chip 过滤(`lang:<code>`)测试:客户端 best-effort 分页过滤。
///
/// 上游无服务端语言过滤(实测:streams(broadcastLanguage:) Unknown argument;
/// streams(languages:[X]) 被忽略),故验证逐页拉取 + 客户端按
/// broadcastLanguage 过滤 + 最多 5 页 + 语言 chip 可点。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/browse.dart';
import 'package:live_parser/src/platforms/twitch/gql.dart';
import 'package:test/test.dart';

import '../../../support/fake_twitch_api.dart';

Map<String, Object?> _stream(String id, String language) => {
  'id': id,
  'title': '房间 $id',
  'viewersCount': 100,
  'type': 'live',
  'broadcastLanguage': language,
  'game': {'id': '29595', 'name': 'Dota 2', 'tags': const []},
  'broadcaster': {
    'id': 'uid$id',
    'login': id,
    'displayName': '主播 $id',
    'profileImageURL': '',
  },
  'previewImageURL': '',
};

Map<String, Object?> _page(
  List<Map<String, Object?>> streams, {
  required bool hasNextPage,
  required String endCursor,
}) => {
  'pageInfo': {'hasNextPage': hasNextPage, 'endCursor': endCursor},
  'edges': [
    for (final node in streams) {'node': node},
  ],
};

void main() {
  late FakeTwitchApi fake;
  late TwitchBrowseRepository repo;

  setUp(() {
    fake = FakeTwitchApi();
    repo = TwitchBrowseRepository(TwitchGqlClient(httpClient: fake));
  });

  test('lang:RU 只返回俄语房间,其它语言被过滤', () async {
    fake.languagePages.add(
      _page([
        _stream('1', 'RU'),
        _stream('2', 'EN'),
        _stream('3', 'RU'),
      ], hasNextPage: false, endCursor: ''),
    );

    final result = await repo.fetchRooms(
      const RoomListRequest(site: 'twitch', cid: 'lang:RU', limit: 10),
    );

    expect(result.rooms.map((r) => r.roomId), ['1', '3']);
    expect(result.hasMore, isFalse);
  });

  test('跨页收集:第一页没有俄语,第二页才有', () async {
    fake.languagePages
      ..add(
        _page([
          _stream('1', 'EN'),
          _stream('2', 'JA'),
        ], hasNextPage: true, endCursor: 'cursor-1'),
      )
      ..add(
        _page([
          _stream('3', 'RU'),
        ], hasNextPage: false, endCursor: ''),
      );

    final result = await repo.fetchRooms(
      const RoomListRequest(site: 'twitch', cid: 'lang:RU', limit: 10),
    );

    expect(result.rooms.map((r) => r.roomId), ['3']);
    expect(
      fake.gqlOperations.where((op) => op == 'BrowsePage_ByLanguage'),
      hasLength(2),
    );
    expect(fake.gqlVariables.last['after'], 'cursor-1');
  });

  test('最多翻 5 页(上游 best-effort 上限)', () async {
    for (var i = 0; i < 8; i++) {
      fake.languagePages.add(
        _page([
          _stream('$i', 'EN'),
        ], hasNextPage: true, endCursor: 'cursor-$i'),
      );
    }

    final result = await repo.fetchRooms(
      const RoomListRequest(site: 'twitch', cid: 'lang:EN', limit: 10),
    );

    expect(
      fake.gqlOperations.where((op) => op == 'BrowsePage_ByLanguage'),
      hasLength(5),
      reason: 'best-effort 过滤最多翻 5 页',
    );
    expect(result.rooms.map((r) => r.roomId), ['0', '1', '2', '3', '4']);
  });

  test('没有该语言时返回空列表,不抛错', () async {
    fake.languagePages.add(
      _page([
        _stream('1', 'EN'),
      ], hasNextPage: false, endCursor: ''),
    );

    final result = await repo.fetchRooms(
      const RoomListRequest(site: 'twitch', cid: 'lang:KO', limit: 10),
    );

    expect(result.rooms, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('分页:page=2 返回第二页切片', () async {
    fake.languagePages.add(
      _page([
        _stream('1', 'RU'),
        _stream('2', 'RU'),
        _stream('3', 'RU'),
        _stream('4', 'RU'),
      ], hasNextPage: false, endCursor: ''),
    );

    final result = await repo.fetchRooms(
      const RoomListRequest(site: 'twitch', cid: 'lang:RU', page: 2, limit: 2),
    );

    expect(result.rooms.map((r) => r.roomId), ['3', '4']);
    expect(result.page, 2);
  });

  test('语言 chip 带 lang: 前缀且可点', () async {
    // 复用已有 fixture:streams_home.json 含 broadcastLanguage。
    fake.streamsResponse = twitchFixtureData('streams_home.json')['streams'];

    final result = await repo.fetchRooms(
      const RoomListRequest(site: 'twitch', limit: 5),
    );

    final languageChips = [
      for (final room in result.rooms)
        for (final chip in room.chips)
          if (chip.kind == SiteChipKind.language) chip,
    ];
    expect(languageChips, isNotEmpty);
    for (final chip in languageChips) {
      expect(chip.filterCid, 'lang:${chip.id.toUpperCase()}');
      expect(chip.navigable, isTrue, reason: '语言 chip 应可点');
    }
  });
}
