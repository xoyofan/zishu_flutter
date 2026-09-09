import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/iptv/iptv_site.dart';
import 'package:test/test.dart';

const _m3uA = '''
#EXTM3U
#EXTINF:-1 tvg-id="CCTV1.cn" tvg-logo="https://img/cctv1.png" group-title="News",CCTV-1 (1080p)
https://example.com/cctv1.m3u8
#EXTINF:-1 tvg-id="CCTV5.cn@HD" group-title="Sports",CCTV-5
https://example.com/cctv5.ts
#EXTINF:-1 tvg-id="TVB.hk" group-title="Entertainment",TVB Jade
https://example.com/tvb.m3u8
''';

const _m3uB = '''
#EXTM3U
#EXTINF:-1 tvg-id="CCTV1.cn" group-title="General",央视一套(备用源)
https://mirror.example.com/cctv1.m3u8
''';

class FakeM3uApi extends http.BaseClient {
  final requests = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url.toString());
    final body = utf8.encode(request.url.host.contains('mirror') ? _m3uB : _m3uA);
    return http.StreamedResponse(
      Stream.value(body),
      200,
      contentLength: body.length,
    );
  }
}

void main() {
  late FakeM3uApi fake;
  late SiteRegistration registration;

  setUp(() {
    fake = FakeM3uApi();
    registration = buildIptvRegistration(
      parserHttp: ParserHttp(client: fake),
      sources: [
        const IptvSource(id: 'main', name: '主源', url: 'https://playlist.example.com/a.m3u'),
        const IptvSource(id: 'mirror', name: '镜像', m3uContent: _m3uB),
      ],
    );
  });

  test('多源合并:providerId 前缀隔离 + 分组中文化 + accept 检查', () async {
    final rooms = await registration.browse!.fetchRooms(
      const RoomListRequest(site: 'iptv', cid: null, page: 1, limit: 60),
    );

    // main 3 条 + mirror 1 条(CCTV1.cn 同 id 不去重——前缀隔离)
    expect(rooms.rooms.map((r) => r.roomId).toList(), [
      'main:CCTV1.cn',
      'main:CCTV5.cn@HD',
      'main:TVB.hk',
      'mirror:CCTV1.cn',
    ]);
    expect(rooms.rooms[0].category, '新闻', reason: 'News → 新闻');
    expect(rooms.rooms[1].category, '体育', reason: 'Sports → 体育');
    expect(rooms.rooms[0].online, 'TV');
    expect(rooms.rooms[0].cover, 'https://img/cctv1.png');
  });

  test('分类:全部组跨地区合并 + 地区分组计数', () async {
    final categories = await registration.browse!.fetchCategories('iptv');

    expect(categories.groups[0].id, '_all');
    final allNews = categories.groups[0].items.firstWhere((i) => i.cid == '新闻');
    expect(allNews.name, '新闻', reason: '计数为 1 时不追加 (n) 后缀');

    final china = categories.groups.firstWhere((g) => g.id == '中国');
    expect(china.name, '中国');
    expect(china.items.map((i) => i.cid).toList(), ['中国:体育', '中国:新闻', '中国:综合'],
        reason: '镜像源 General → 综合,同样归入中国');

    final hk = categories.groups.firstWhere((g) => g.id == '香港');
    expect(hk.items.single.cid, '香港:娱乐');
  });

  test('频道解析:存在 → 直连线路 + 格式识别', () async {
    final payload = await registration.resolver.resolveRoom(
      const RoomRequest(site: 'iptv', roomIdOrUrl: 'main:CCTV1.cn'),
    );

    expect(payload.roomState, RoomState.live);
    expect(payload.roomId, 'main:CCTV1.cn');
    expect(payload.title, 'CCTV-1 (1080p)');
    expect(payload.category, '新闻');
    expect(payload.streams, hasLength(1));
    expect(payload.streams.single.lines.single.name, '直连');
    expect(payload.streams.single.lines.single.format, 'hls');
    expect(payload.availableQualities.single.name, '直播');
    expect(payload.playUrl, 'https://example.com/cctv1.m3u8');
    expect(payload.source, 'live_parser/iptv');
  });

  test('ts 频道格式识别 + 去前缀容错 + 大小写容错', () async {
    final tsPayload = await registration.resolver.resolveRoom(
      const RoomRequest(site: 'iptv', roomIdOrUrl: 'CCTV5.cn@HD'),
    );
    expect(tsPayload.roomState, RoomState.live);
    expect(tsPayload.streams.single.lines.single.format, 'ts');

    final casePayload = await registration.resolver.resolveRoom(
      const RoomRequest(site: 'iptv', roomIdOrUrl: 'MAIN:cctv1.cn'),
    );
    expect(casePayload.roomState, RoomState.live);
    expect(casePayload.anchorName, 'CCTV-1 (1080p)');
  });

  test('频道不存在:notFound', () async {
    final payload = await registration.resolver.resolveRoom(
      const RoomRequest(site: 'iptv', roomIdOrUrl: 'main:not-exist'),
    );
    expect(payload.roomState, RoomState.notFound);
    expect(payload.error, contains('频道不存在'));
    expect(payload.streams, isEmpty);
  });

  test('搜索:频道名/tvg-id 子串匹配', () async {
    final result = await registration.search!.search(
      const SearchRequest(site: 'iptv', query: 'cctv', limit: 10),
    );
    // 命中 CCTV-1(名称+镜像备用源名"央视一套"不命中)/CCTV-5(tvg-id)
    expect(result.hits, hasLength(3));
    expect(result.hits.every((h) => h.state == SearchHitState.live), isTrue);

    final empty = await registration.search!.search(
      const SearchRequest(site: 'iptv', query: '  ', limit: 10),
    );
    expect(empty.hits, isEmpty);
  });

  test('registry 中 IPTV 能力:浏览/搜索开,弹幕关', () {
    expect(registration.capabilities.browse, isTrue);
    expect(registration.capabilities.roomSearch, isTrue);
    expect(registration.capabilities.danmaku, isFalse);
    expect(registration.danmaku, isNull);
    expect(registration.capabilities.requiresCookie, isFalse);
  });

  test('URL 源拉取带缓存(第二次 loadAll 不再发请求)', () async {
    await registration.browse!.fetchRooms(
      const RoomListRequest(site: 'iptv', cid: null, page: 1, limit: 60),
    );
    final afterFirst = fake.requests.length;
    expect(afterFirst, 1, reason: 'URL 源一次请求,内联源零请求');

    await registration.browse!.fetchRooms(
      const RoomListRequest(site: 'iptv', cid: null, page: 1, limit: 60),
    );
    expect(fake.requests.length, afterFirst, reason: 'TTL 内命中缓存');
  });
}
