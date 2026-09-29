import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/xhs/signing.dart' show XhsSigner;
import 'package:test/test.dart';

import '../../../support/fake_xhs_api.dart';

void main() {
  late FakeXhsApi fake;
  late XhsBrowseRepository browse;

  XhsBrowseRepository buildBrowse({XhsSigner? signer}) => XhsBrowseRepository(
    XhsClient(httpClient: fake, signer: signer),
  );

  setUp(() {
    fake = FakeXhsApi()
      ..categoryResponse = xhsFixtureJson('category.json')
      ..squarefeedResponse = xhsFixtureJson('squarefeed.json');
    browse = buildBrowse(signer: StubXhsSigner());
  });

  group('小红书浏览', () {
    test('分类:扁平列表放单组平铺,desc 即展示名;命中缓存零重复请求', () async {
      final result = await browse.fetchCategories('xhs');

      expect(result.site, 'xhs');
      expect(result.groups, hasLength(1), reason: '扁平分类单组平铺(UI 据此走平铺渲染)');
      final group = result.groups.single;
      expect(group.id, '');
      expect(group.name, '');
      expect(
        group.items.map((item) => (item.cid, item.name)).toList(),
        [('101', '恋爱'), ('102', '颜值'), ('103', '聊天/秀场')],
      );

      final calls = fake.requests.length;
      await browse.fetchCategories('xhs');
      expect(fake.requests.length, calls, reason: '分类索引应命中缓存');
    });

    test('分类房间:字段映射 + live 过滤 + 签名请求头透传', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'xhs', cid: '101', page: 1, limit: 2),
      );

      expect(result.page, 1);
      expect(result.hasMore, isTrue, reason: '去重后 2 条已覆盖 1×2 窗口');
      expect(result.rooms, hasLength(2));

      final first = result.rooms.first;
      expect(first.roomId, '660100000000000001');
      expect(first.title, '房间A的直播');
      expect(first.anchorName, '主播A');
      expect(first.audience, '12300', reason: 'display_count 原样字符串,不二次格式化');
      expect(first.cover, 'https://sns-cover.xhscdn.com/a.jpg');
      expect(first.avatar, 'https://sns-avatar.xhscdn.com/a.jpg');
      expect(first.cid, '101');
      expect(first.category, isNull, reason: '未加载分类索引时反查为空,归一为 null');
      expect(first.roomState, RoomState.live, reason: 'squarefeed 目录 live-only');

      final second = result.rooms.last;
      expect(second.roomId, '660100000000000002', reason: 'room_id_str 缺失回退 room_id');
      expect(second.audience, '456', reason: 'display_count 缺失回退 member_count');

      // 第三条 feed 无 live 字段(笔记)被过滤。
      expect(
        result.rooms.map((room) => room.roomId),
        everyElement(isNot('')),
      );

      // squarefeed 参数与签名头(桩签名不校验签名值,只验接线)。
      final request = fake.squarefeedRequests.single;
      expect(request.url.path, '/api/sns/red/live/web/feed/v1/squarefeed');
      expect(request.url.queryParameters['category'], '101');
      expect(request.url.queryParameters['cursorScore'], '0');
      expect(request.url.queryParameters['source'], '13');
      expect(request.url.queryParameters['size'], '2');
      expect(request.headers['Cookie'], contains('web_session=wstest'));
    });

    test('分类名反查:先加载分类索引,列表行补中文分类名', () async {
      await browse.fetchCategories('xhs');

      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'xhs', cid: '101', page: 1, limit: 2),
      );

      expect(result.rooms.first.category, '恋爱');
    });

    test('分页:page N 链式重放 N 次游标请求,返回第 N 个窗口并按 roomId 去重', () async {
      fake.squarefeedByCursor
        ..['0'] = xhsFixtureJson('squarefeed.json')
        ..['0.7'] = xhsFixtureJson('squarefeed_page2.json');

      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'xhs', cid: '101', page: 2, limit: 2),
      );

      // 第 1 页:主播A + 主播B;第 2 页:主播A(重复,去重)+ 主播C。
      // page=2 → 第 2 个窗口 = 累计去重列表 [A, B, C] 的第 3 条。
      expect(fake.squarefeedRequests, hasLength(2));
      expect(fake.squarefeedRequests[0].url.queryParameters['cursorScore'], '0');
      expect(fake.squarefeedRequests[1].url.queryParameters['cursorScore'], '0.7');
      expect(result.rooms.map((room) => room.roomId).toList(), ['660100000000000003']);
      expect(result.page, 2);
      expect(result.hasMore, isFalse, reason: '去重后 3 条未覆盖 2×2 窗口');
    });

    test('首页推荐(cid 空)= squarefeed 带 category=0,cid 留空', () async {
      final result = await browse.fetchRooms(
        const RoomListRequest(site: 'xhs', page: 1, limit: 30),
      );

      final request = fake.squarefeedRequests.single;
      expect(request.url.queryParameters['category'], '0');
      expect(
        result.rooms.map((room) => room.cid),
        everyElement(isNull),
        reason: '首页推荐流无分类归属,空 cid 经统一记录归一为 null',
      );
      expect(result.hasMore, isFalse, reason: '2 条不足一页(30)');
    });

    test('Cookie 过期(-101):分类与列表抛专用异常', () async {
      fake
        ..categoryResponse = xhsFixtureJson('squarefeed_expired.json')
        ..squarefeedResponse = xhsFixtureJson('squarefeed_expired.json');

      await expectLater(
        browse.fetchCategories('xhs'),
        throwsA(
          isA<XhsCookieExpiredException>().having(
            (error) => error.message,
            'message',
            contains('Cookie 已过期'),
          ),
        ),
      );
      await expectLater(
        browse.fetchRooms(const RoomListRequest(site: 'xhs', cid: '101')),
        throwsA(isA<XhsCookieExpiredException>()),
      );
    });

    test('未配置 Cookie:请求前即抛专用异常,不打网络', () async {
      final anonymous = buildBrowse();

      await expectLater(
        anonymous.fetchCategories('xhs'),
        throwsA(
          isA<XhsCookieExpiredException>().having(
            (error) => error.message,
            'message',
            contains('未配置'),
          ),
        ),
      );
      expect(fake.requests, isEmpty, reason: '未配置 Cookie 不应发出任何请求');
    });
  });
}
