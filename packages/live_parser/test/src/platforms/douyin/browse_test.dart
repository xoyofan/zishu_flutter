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

    test('推荐:partition=0,字段映射与人数格式化', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'douyin', page: 1, limit: 15),
      );

      expect(result.rooms, hasLength(2));
      final first = result.rooms.first;
      expect(first.roomId, '123456');
      expect(first.title, '分区房间');
      expect(first.anchorName, '分区主播');
      expect(first.audience, '1.2万');
      expect(first.cover, 'https://p3.douyinpic.com/cover.jpg');
      expect(result.rooms.last.anchorName, '昵称兜底');
      expect(result.rooms.last.audience, '800');
      expect(result.hasMore, isTrue);

      // 列表来自 RoomSummary:统一记录只映射已提供的统计(audience),
      // 上游列表没有 followers/vip/svip → 保持 null,不编造数字。
      final record = first;
      expect(record.site, 'douyin');
      expect(record.roomId, '123456');
      // 浏览目录 live-only(6sol 裁决,Task 4a-i):状态真源显式为 live。
      expect(
        record.roomState,
        RoomState.live,
        reason: 'partition/detail/room/v2 是直播分区目录,roomState 应为 live',
      );
      expect(record.audience, '1.2万');
      expect(record.followers, isNull);
      expect(record.vip, isNull);
      expect(record.svip, isNull);
      expect(
        result.rooms.last.audience,
        '800',
        reason: '精确值原样保留',
      );

      final request = fake.requests.last;
      expect(
        request.url.path,
        '/webcast/web/partition/detail/room/v2/',
      );
      expect(request.url.queryParameters['partition'], '0');
      expect(request.url.queryParameters['partition_type'], '1');
      expect(request.url.queryParameters['a_bogus'], isNotEmpty);
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
