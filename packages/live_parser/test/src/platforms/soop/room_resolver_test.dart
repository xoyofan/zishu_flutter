import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_soop_api.dart';

void main() {
  late FakeSoopApi fake;
  late SiteRegistration registration;

  setUp(() {
    fake = FakeSoopApi()
      ..detailResponse = soopFixture('detail_live.json')
      ..aidResponse = soopFixture('aid_live.json')
      ..assignResponse = soopFixture('assign_live.json');
    registration = buildSoopRegistration(httpClient: fake);
  });

  group('SOOP 房间解析', () {
    test('在播:详情 + 多画质 + assign/aid 取流', () async {
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(
          site: 'soop',
          roomIdOrUrl: 'https://play.sooplive.co.kr/testbj',
        ),
      );

      expect(payload.site, 'soop');
      expect(payload.roomId, 'testbj');
      expect(payload.sourceUrl, 'https://play.sooplive.co.kr/testbj');
      expect(payload.roomState, RoomState.live);
      expect(payload.anchorName, '测试主播');
      expect(payload.title, 'SOOP 测试直播间');
      expect(payload.category, '英雄联盟');
      expect(payload.cover, startsWith('https://liveimg.sooplive.co.kr/m/12345678'));
      expect(payload.availableQualities.map((q) => q.name).toList(), [
        '原画',
        '高清',
        '标清',
      ]);
      expect(payload.streams, hasLength(3));
      expect(payload.streams.first.rate, 8000000);
      expect(
        payload.streams.first.preferredLine?.url,
        'https://live.sooplive.co.kr/hls/test/playlist.m3u8?aid=test-aid-001',
      );
      expect(payload.streams.first.preferredLine?.format, 'hls');

      // 播放头:CDN 以 Referer/Origin 做防盗链
      final lineHeaders = payload.streams.first.preferredLine?.headers ?? {};
      expect(lineHeaders['origin'], 'https://www.sooplive.co.kr');
      expect(lineHeaders['referer'], 'https://www.sooplive.co.kr/');

      final assign = fake.requests.firstWhere(
        (request) => request.url.path.endsWith('/broad_stream_assign.html'),
      );
      expect(assign.url.queryParameters['return_type'], 'gs_cdn_pc_web');
      expect(
        assign.url.queryParameters['broad_key'],
        '12345678-common-original-hls',
      );

      final aidRequest = fake.requests.firstWhere(
        (request) =>
            request.url.path == '/afreeca/player_live_api.php' &&
            Uri.splitQueryString(request.body)['type'] == 'aid',
      );
      expect(aidRequest.url.queryParameters['bjid'], 'testbj');
      expect(Uri.splitQueryString(aidRequest.body)['quality'], 'original');
      expect(Uri.splitQueryString(aidRequest.body)['bno'], '12345678');
    });

    test('偏好档懒取流:只请求所选档,其余档位空线路占位', () async {
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(
          site: 'soop',
          roomIdOrUrl: 'testbj',
          preferredQuality: '高清',
        ),
      );

      expect(payload.roomState, RoomState.live);
      expect(payload.availableQualities.map((q) => q.name).toList(), [
        '原画',
        '高清',
        '标清',
      ]);
      final hd = payload.streams.firstWhere((stream) => stream.name == '高清');
      expect(hd.lines, isNotEmpty);
      final origin = payload.streams.firstWhere(
        (stream) => stream.name == '原画',
      );
      expect(origin.lines, isEmpty, reason: '未选中的档位不预取线路');

      final assignCount = fake.requests
          .where((request) => request.url.path.endsWith('/broad_stream_assign.html'))
          .length;
      final aidRequests = fake.requests.where(
        (request) =>
            request.url.path == '/afreeca/player_live_api.php' &&
            Uri.splitQueryString(request.body)['type'] == 'aid',
      );
      expect(assignCount, 1, reason: '懒取流只取偏好档');
      expect(aidRequests, hasLength(1));
      expect(Uri.splitQueryString(aidRequests.first.body)['quality'], 'HD');
    });

    test('离线:RESULT=0 返回 offline 且无线路', () async {
      fake.detailResponse = soopFixture('detail_offline.json');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.streams, isEmpty);
      expect(payload.availableQualities, isEmpty);
      expect(payload.error, isNull);
    });

    test('封禁:RESULT=-2 返回 notFound', () async {
      fake.detailResponse = soopFixture('detail_banned.json');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
      );

      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '房间已被封禁');
      expect(payload.streams, isEmpty);
    });

    test('分类名按 CATE 反查中文表,覆盖未本地化的韩文 CATEGORY_TAGS', () {
      // 详情接口 CATEGORY_TAGS 不随 Accept-Language 本地化(实测仍韩文),
      // 依赖分类树(zh_CN)预热的 cid→中文 表按 CATE 覆盖。缓存是进程级
      // 单例:本用例声明在「在播」用例之后,先注册不会污染其断言。
      rememberSoopZhCategory('00040066', '绝地求生');
      final raw = soopFixture('detail_live.json') as Map<String, dynamic>;
      (raw['CHANNEL'] as Map<String, dynamic>)['CATEGORY_TAGS'] = [
        '배틀그라운드',
      ];

      final detail = parseSoopRoomDetail(raw, 'testbj');

      expect(detail.cateNo, '00040066');
      expect(detail.category, '绝地求生');
    });

    test('取流失败不伪报在播', () async {
      fake.assignResponse = const {'view_url': ''};

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.error, '未获取到可播放地址');
    });
  });

  test('SOOP 注册项声明浏览/搜索/弹幕与多线路', () {
    expect(registration.id, 'soop');
    expect(registration.name, 'SOOP');
    expect(registration.resolver, isA<RoomResolver>());
    expect(registration.browse, isA<BrowseRepository>());
    expect(registration.search, isA<SearchRepository>());
    expect(registration.danmaku, isA<DanmakuConnector>());
    expect(registration.capabilities.browse, isTrue);
    expect(registration.capabilities.roomSearch, isTrue);
    expect(registration.capabilities.danmaku, isTrue);
    expect(registration.capabilities.multiQuality, isTrue);
    expect(registration.capabilities.multiLine, isTrue);
  });

  group('SOOP 输入归一', () {
    test('URL/裸 id 均可解析', () {
      expect(normalizeSoopRoomId('testbj'), 'testbj');
      expect(normalizeSoopRoomId('https://play.sooplive.co.kr/testbj'), 'testbj');
      expect(
        normalizeSoopRoomId('https://www.sooplive.co.kr/station/testbj'),
        'testbj',
      );
      expect(normalizeSoopRoomId('bj.afreecatv.com/testbj'), 'testbj');
    });
  });
}
