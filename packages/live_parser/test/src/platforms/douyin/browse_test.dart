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
      expect(first.online, '1.2万');
      expect(first.cover, 'https://p3.douyinpic.com/cover.jpg');
      expect(result.rooms.last.anchorName, '昵称兜底');
      expect(result.rooms.last.online, '800');
      expect(result.hasMore, isTrue);

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
  });
}
