import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_kuaishou_api.dart';

void main() {
  late FakeKuaishouApi fake;
  late SiteRegistration registration;

  setUp(() {
    fake = FakeKuaishouApi()..roomPage = kuaishouFixture('room_live.html');
    registration = buildKuaishouRegistration(httpClient: fake);
  });

  group('快手房间解析', () {
    test('在播:页面初始状态 + playUrls 画质/线路', () async {
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(
          site: 'kuaishou',
          roomIdOrUrl: 'https://live.kuaishou.com/u/ks_user_1',
        ),
      );

      expect(payload.site, 'kuaishou');
      expect(payload.roomId, 'ks_user_1');
      expect(payload.roomState, RoomState.live);
      expect(payload.anchorName, '快手主播');
      expect(payload.title, '今晚八点开播 不见不散');
      expect(payload.category, '王者荣耀');
      expect(payload.cover, 'https://p1.kuaishou.com/poster.jpg');
      expect(payload.avatar, 'https://p1.kuaishou.com/avatar.png');
      expect(payload.availableQualities.map((q) => q.name).toList(), ['原画', '高清']);
      expect(payload.streams, hasLength(2));

      final best = payload.streams.first;
      expect(best.rate, 4);
      expect(best.preferredLine?.url, 'https://live.kuaishou.com/live/play.m3u8');
      expect(best.preferredLine?.format, 'hls');
      expect(best.preferredLine?.headers['Referer'], 'https://live.kuaishou.com/');
      expect(payload.streams.last.preferredLine?.format, 'flv');
    });

    test('离线:isLiving=false 返回 offline 且保留资料', () async {
      fake.roomPage = kuaishouFixture('room_offline.html');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'kuaishou', roomIdOrUrl: 'ks_user_1'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.anchorName, '快手主播');
      expect(payload.streams, isEmpty);
      expect(payload.availableQualities, isEmpty);
    });

    test('页面缺少初始状态:notFound', () async {
      fake.roomPage = kuaishouFixture('room_missing.html');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'kuaishou', roomIdOrUrl: 'ks_user_1'),
      );

      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '快手房间不存在或已下播');
      expect(payload.streams, isEmpty);
    });

    test('会话 cookie 透传后续房间页请求', () async {
      fake
        ..setCookie = 'did=abc123; Path=/; HttpOnly'
        ..roomPages['ks_a'] = kuaishouFixture('room_offline.html')
        ..roomPages['ks_b'] = kuaishouFixture('room_offline.html');
      final client = KuaishouClient(httpClient: fake);

      await client.fetchRoom('ks_a');
      await client.fetchRoom('ks_b');

      final second = fake.requests.last;
      expect(second.headers['Cookie'], contains('did=abc123'));
      client.close();
    });
  });

  test('快手注册项:浏览/弹幕能力,搜索返回空而非抛错', () async {
    expect(registration.id, 'kuaishou');
    expect(registration.name, '快手');
    expect(registration.capabilities.browse, isTrue);
    expect(registration.capabilities.danmaku, isTrue);
    expect(registration.capabilities.roomSearch, isFalse);
    expect(registration.search, isNotNull);
    expect(
      (await registration.search!.search(
        const SearchRequest(site: 'kuaishou', query: '主播'),
      )).hits,
      isEmpty,
    );
  });

  group('快手输入归一', () {
    test('URL/裸 id 均可解析', () {
      expect(normalizeKuaishouRoomId('ks_user_1'), 'ks_user_1');
      expect(
        normalizeKuaishouRoomId('https://live.kuaishou.com/u/ks_user_1'),
        'ks_user_1',
      );
      expect(
        normalizeKuaishouRoomId('https://live.kuaishou.com/profile/ks_user_1?x=1'),
        'ks_user_1',
      );
    });
  });

  group('快手画质解析', () {
    test('多个 descriptor 的同名档位合并线路并去重', () {
      final qualities = parseKuaishouQualities([
        {
          'adaptationSet': {
            'representation': [
              {
                'url': 'https://cdn.kuaishou.com/a.m3u8',
                'level': 4,
                'name': '原画',
              },
            ],
          },
        },
        {
          'adaptationSet': {
            'representation': [
              {
                'url': 'https://cdn.kuaishou.com/a.m3u8',
                'level': 4,
                'name': '原画',
              },
              {
                'url': 'https://cdn.kuaishou.com/b.flv',
                'level': 4,
                'name': '原画',
              },
            ],
          },
        },
      ]);

      expect(qualities, hasLength(1));
      expect(qualities.single.name, '原画');
      expect(qualities.single.lines.map((line) => line.url).toList(), [
        'https://cdn.kuaishou.com/a.m3u8',
        'https://cdn.kuaishou.com/b.flv',
      ]);
    });
  });
}
