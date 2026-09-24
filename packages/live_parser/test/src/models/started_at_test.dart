import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/twitch_site.dart';
import 'package:test/test.dart';

import '../../support/fake_twitch_api.dart';

void main() {
  test('RoomSummary startedAt roundtrip,旧 JSON 仍为 null', () {
    final at = DateTime(2026, 9, 24, 20, 30);
    final restored = RoomSummary.fromJson(
      RoomSummary(
        site: 'douyu',
        roomId: '1',
        title: '',
        anchorName: '',
        cid: '',
        category: '',
        online: '',
        cover: '',
        startedAt: at,
      ).toJson(),
    );

    expect(restored.startedAt, at);
    expect(RoomSummary.fromJson(const {'site': 'douyu'}).startedAt, isNull);
  });

  test('YY startTime 转为 RoomSummary.startedAt', () {
    final detail = YyRoomDetail(
      sid: '1414787909',
      ssid: '1414787909',
      name: '主播',
      desc: '房间',
      thumb: '',
      avatar: '',
      users: '4.1万',
      uid: '1',
      biz: 'other',
      totalViewer: '4.1万',
      startTime: 1788911253,
    );

    expect(
      detail.startedAt,
      DateTime.fromMillisecondsSinceEpoch(1788911253 * 1000),
    );
  });

  test('Twitch createdAt 归一为 RoomSummary.startedAt', () async {
    final api = FakeTwitchApi()
      ..useLiveResponse = twitchFixtureData('use_live.json')['user'];
    final resolver = TwitchRoomResolver(TwitchClient(httpClient: api));

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
    );

    expect(summary.startedAt, DateTime.parse('2026-09-09T06:12:41Z').toLocal());
  });
}
