import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/browse.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyu_api.dart';

String _fixtureText(String name) => File('test/fixtures/douyu/$name').readAsStringSync();

void main() {
  late FakeDouyuApi fake;
  late DouyuBrowseRepository browse;

  setUp(() {
    fake = FakeDouyuApi()
      ..mixListByDirectory['0_0'] = jsonDecode(_fixtureText('mix_list_home.json'))
      ..mixListByDirectory['2_1'] = jsonDecode(_fixtureText('mix_list_category_1.json'))
      ..mobileRoomListResponse = jsonDecode(_fixtureText('room_list_mobile.json'));
    browse = DouyuBrowseRepository(ParserHttp(client: fake));
  });

  test('分类索引:按 cate1 分组、pic/icon 容错', () async {
    final result = await browse.fetchCategories('douyu');
    expect(result.site, 'douyu');
    expect(result.groups, hasLength(2));

    final games = result.groups[0];
    expect(games.id, '1');
    expect(games.name, '网游竞技');
    expect(games.items.map((i) => (i.cid, i.name)).toList(), [
      ('1', '英雄联盟'),
      ('2', 'DNF'),
    ]);
    expect(games.items[0].pic, 'https://shf1-ali-douyucdn.cn/cate/1.jpg');

    final fun = result.groups[1];
    expect(fun.name, '娱乐天地');
    expect(fun.items.single.name, '二次元');
    expect(fun.items.single.pic, 'https://shf1-ali-douyucdn.cn/cate/100.jpg');
  });

  test('分类房间列表:2_ 前缀 mixList + cid 过滤 + 角标 + hasMore', () async {
    final result = await browse.fetchRooms(
      const RoomListRequest(site: 'douyu', cid: '1', page: 1, limit: 2),
    );

    expect(result.page, 1);
    expect(result.rooms, hasLength(2), reason: 'cid2 != 目标分类的房间被过滤');
    expect(result.hasMore, isTrue, reason: '上游 3 条截断到 limit=2');

    final first = result.rooms[0];
    expect(first.roomId, '111');
    expect(first.title, '房间A标题');
    expect(first.anchorName, '主播A');
    expect(first.cid, '1');
    expect(first.category, '英雄联盟');
    expect(first.online, '10.2万');
    expect(first.cover, 'https://rpic.douyucdn.cn/a.jpg');
    expect(first.promoTag, '官方赛况');

    expect(result.rooms[1].promoTag, '贵族', reason: 'vipId>0 兜底角标');
    expect(result.rooms[1].online, '999');

    // 列表来自 RoomSummary:统一记录只映射已提供的统计(audience),
    // 上游列表没有 followers/vip/svip → 保持 null,不编造数字。
    final record = RoomRecord.fromSummary(first);
    expect(record.site, 'douyu');
    expect(record.roomId, '111');
    expect(record.audience, '10.2万');
    expect(record.promoTag, '官方赛况');
    expect(record.followers, isNull);
    expect(record.vip, isNull);
    expect(record.svip, isNull);
    expect(
      RoomRecord.fromSummary(result.rooms[1]).audience,
      '999',
      reason: '精确值原样保留',
    );
  });

  test('首页列表:0_0 mixList', () async {
    final result = await browse.fetchRooms(
      const RoomListRequest(site: 'douyu', cid: '0', page: 1, limit: 30),
    );

    expect(result.rooms, hasLength(2));
    expect(result.hasMore, isFalse, reason: '上游 2 条 < limit=30');
    expect(result.rooms[0].online, '6.7万');
    expect(result.rooms[0].promoTag, '高能时刻');
    expect(result.rooms[1].online, '12345.7万');
  });

  test('首页 mixList 失败回退移动端列表', () async {
    fake.mixListByDirectory['0_0'] = 'fail';
    // 888 号房间分类名缺省,走 cate2Names 缓存(先预热分类索引)
    await browse.fetchCategories('douyu');

    final result = await browse.fetchRooms(
      const RoomListRequest(site: 'douyu', cid: null, page: 1, limit: 30),
    );

    expect(result.rooms, hasLength(2));
    expect(result.page, 1);
    expect(result.hasMore, isTrue, reason: 'nowPage=1 < pageCount=5');

    expect(result.rooms[0].roomId, '777');
    expect(result.rooms[0].online, '1.2万', reason: 'hn 已是人类可读格式直接采用');
    expect(result.rooms[1].category, 'DNF', reason: '分类名从缓存按 cid 补全');
    expect(result.rooms[1].online, '850');

    expect(
      fake.requests.any((r) => r.url.contains('/api/room/list?page=1&limit=30')),
      isTrue,
    );
  });
}
