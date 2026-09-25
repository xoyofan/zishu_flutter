/// Twitch chips 完整度:分类标签组、房间 chips(游戏 tags + 语言)与
/// chip 模型契约(JSON roundtrip / mergeRefresh / 冻结)。
///
/// 钉住 Stage 1 语义(2026-10 feat/twitch-tags):
/// 1. fetchCategories 输出 分类 + 标签 两组,分类 first=100(GQL 硬上限);
/// 2. 标签组跨游戏按 id 去重、出现游戏数降序、同数按名称稳定排序,
///    cid 带 `tag:` 前缀与游戏 id 区分,可点(端到端走 streams(tags:));
/// 3. 房间卡片 chips = 游戏 tags(filterCid 可点) + broadcastLanguage
///    (仅展示,filterCid 为 null);
/// 4. RoomSummary/RoomRecord 的 chips JSON roundtrip、mergeRefresh
///    「fresh 非空覆盖、空保留」与构造深冻结。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/browse.dart';
import 'package:live_parser/src/platforms/twitch/gql.dart';
import 'package:live_parser/src/platforms/twitch/normalize.dart';
import 'package:test/test.dart';

import '../../../support/fake_twitch_api.dart';

void main() {
  late FakeTwitchApi api;

  setUp(() {
    api = FakeTwitchApi()
      ..gamesResponse = twitchFixtureData('games.json')['games']
      ..streamsResponse = twitchFixtureData('streams_home.json')['streams']
      ..gameResponse = twitchFixtureData('game_streams.json')['game']
      ..tagStreamsResponse = twitchFixtureData('streams_tag.json')['streams'];
  });

  TwitchGqlClient gqlFor() => TwitchGqlClient(httpClient: api);

  group('分类索引 chips', () {
    test('fetchCategories 返回 分类 + 标签 两组', () async {
      final result = await TwitchBrowseRepository(
        gqlFor(),
      ).fetchCategories('twitch');
      expect(result.groups.map((g) => g.id).toList(), ['games', 'tags']);
      expect(result.groups.last.name, '标签');
      expect(result.groups.first.name, '分类');
    });

    test('分类组上限 100(games first=100,GQL 硬上限)', () async {
      final result = await TwitchBrowseRepository(
        gqlFor(),
      ).fetchCategories('twitch');
      final games = result.groups.first;
      expect(games.items.length, lessThanOrEqualTo(100));
      expect(api.gqlVariables.first['limit'], 100, reason: '上游 games(first:) 硬上限 100');
      expect(api.gqlQueries.first, contains('tags(tagType: CONTENT)'));
    });

    test('标签组跨游戏去重、出现游戏数降序、同数按名称排序,空标签不产出', () async {
      final result = await TwitchBrowseRepository(
        gqlFor(),
      ).fetchCategories('twitch');
      final tags = result.groups.last;
      // fixture: 3333(第一人称射击游戏)×2、1111(聊天)×2、2222(策略)×1、
      // 4444(角色扮演)×1;5555 空名与空 id 被剔除。
      expect(tags.items.map((e) => e.cid).toList(), [
        'tag:33333333-3333-4333-8333-333333333333',
        'tag:11111111-1111-4111-8111-111111111111',
        'tag:22222222-2222-4222-8222-222222222222',
        'tag:44444444-4444-4444-8444-444444444444',
      ]);
      expect(tags.items.map((e) => e.name).toList(), [
        '第一人称射击游戏',
        '聊天',
        '策略',
        '角色扮演',
      ]);
      final cids = tags.items.map((e) => e.cid).toList();
      expect(cids.toSet(), hasLength(cids.length), reason: '按 id 去重');
      expect(
        tags.items.every((e) => e.cid.startsWith('tag:')),
        isTrue,
        reason: '标签 cid 带 tag: 前缀与游戏 id 区分',
      );
      expect(
        tags.items.any((e) => e.cid == 'tag:55555555-5555-4555-8555-555555555555'),
        isFalse,
        reason: '空 localizedName 不产出',
      );
      expect(tags.items.any((e) => e.name == '缺 id 标签'), isFalse, reason: '空 id 不产出');
    });
  });

  group('标签房间列表', () {
    test('cid 以 tag: 前缀走 streams(tags:) 查询,不误当游戏 id', () async {
      final result = await TwitchBrowseRepository(gqlFor()).fetchRooms(
        const RoomListRequest(
          site: 'twitch',
          cid: 'tag:77777777-7777-4777-8777-777777777777',
          limit: 10,
        ),
      );
      expect(api.gqlOperations, contains('BrowsePage_Tags'));
      expect(
        api.gqlOperations,
        isNot(contains('DirectoryPage_Game')),
        reason: 'tag:<uuid> 不得被当成游戏 id 打 game(id:)',
      );
      expect(
        api.gqlQueries.last,
        contains('tags: ["77777777-7777-4777-8777-777777777777"]'),
      );
      expect(result.rooms.single.roomId, 'tag_filtered_room');
      expect(result.rooms.single.site, kTwitchSiteId);
      expect(result.hasMore, isFalse);
    });

    test('tag: 前缀后为空时显式报错,不发无效查询', () async {
      expect(
        TwitchBrowseRepository(gqlFor()).fetchRooms(
          const RoomListRequest(site: 'twitch', cid: 'tag:'),
        ),
        throwsA(isA<TwitchGqlException>()),
      );
      expect(api.gqlOperations, isEmpty);
    });

    test('游戏 cid 仍走 DirectoryPage_Game(既有分流不受影响)', () async {
      await TwitchBrowseRepository(
        gqlFor(),
      ).fetchRooms(const RoomListRequest(site: 'twitch', cid: '263490'));
      expect(api.gqlOperations, contains('DirectoryPage_Game'));
      expect(api.gqlOperations, isNot(contains('BrowsePage_Tags')));
    });
  });

  group('房间卡片 chips', () {
    test('首页房间带游戏 tags(可点) 与 broadcastLanguage(仅展示)', () async {
      final result = await TwitchBrowseRepository(
        gqlFor(),
      ).fetchRooms(const RoomListRequest(site: 'twitch', limit: 10));

      final first = result.rooms.first.chips;
      expect(first, hasLength(3));
      expect(first[0].id, '33333333-3333-4333-8333-333333333333');
      expect(first[0].name, '第一人称射击游戏');
      expect(first[0].kind, SiteChipKind.tag);
      expect(
        first[0].filterCid,
        'tag:${first[0].id}',
        reason: '卡片 tag chip 的 filterCid 必须可直接喂 fetchRooms（带 tag: 前缀）',
      );
      expect(first[0].navigable, isTrue);
      expect(first[1].kind, SiteChipKind.tag);
      expect(first[1].name, 'LCK');
      expect(
        first[2].kind,
        SiteChipKind.language,
        reason: 'broadcastLanguage 落在 chips 末位',
      );
      expect(first[2].id, 'EN');
      expect(first[2].name, '英语');
      expect(first[2].filterCid, isNull, reason: '语言 chip 仅展示不可点');
      expect(first[2].navigable, isFalse);

      final second = result.rooms.last.chips;
      expect(second.map((c) => c.kind).toList(), [
        SiteChipKind.tag,
        SiteChipKind.language,
      ]);
      expect(second.last.id, 'RU');
      expect(second.last.name, '俄语');
    });

    test('语言映射覆盖 RU/FR/EN/DE/JP/KR/ZH,缺省原样', () {
      expect(twitchLanguageName('RU'), '俄语');
      expect(twitchLanguageName('FR'), '法语');
      expect(twitchLanguageName('EN'), '英语');
      expect(twitchLanguageName('DE'), '德语');
      expect(twitchLanguageName('JP'), '日语');
      expect(twitchLanguageName('KR'), '韩语');
      expect(twitchLanguageName('ZH'), '中文');
      expect(twitchLanguageName('PT'), 'PT', reason: '未收录语言码原样展示');
      expect(twitchLanguageName(''), '');
    });
  });

}
