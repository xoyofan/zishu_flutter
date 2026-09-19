/// 播放器广告过滤接线单测:Twitch 线路在 open 时被改写为本地过滤地址,
/// 其余平台线路保持原样直达 mpv。
///
/// 驱动方式与 media_kit_player_fence_test 相同:注入 `PlatformPlayer`
/// 替身,断言"底层到底打开了谁"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:media_kit/media_kit.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/twitch_ad_filter.dart';

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  final List<String> calls = <String>[];

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final medias = playable is Playlist ? playable.medias : <Media>[playable as Media];
    calls.add(
      medias.map((media) => Uri.tryParse(media.uri)?.host ?? media.uri).join(','),
    );
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async {}
}

void main() {
  late _FakePlatformPlayer fake;
  late MediaKitLivePlayer player;

  const twitchLine = StreamLine(
    name: '480p',
    url: 'https://apn12.playlist.ttvnw.net/v1/playlist/abc.m3u8',
    format: 'hls',
  );
  const otherLine = StreamLine(
    name: 'HLS',
    url: 'https://a.example.com/live.m3u8',
    format: 'hls',
  );

  setUp(() {
    fake = _FakePlatformPlayer();
    player = MediaKitLivePlayer(
      player: Player(platformPlayer: fake),
      adFilter: TwitchAdFilter(), // 默认按 .ttvnw.net 判定。
    );
  });

  tearDown(() async {
    player.dispose();
  });

  test('Twitch 线路改写为本地回环地址后进入 mpv', () async {
    await player.open(twitchLine);
    expect(fake.calls, contains('127.0.0.1'));
  });

  test('回退线路一并改写(整组进 mpv 播放列表)', () async {
    await player.open(twitchLine, const [twitchLine]);
    expect(fake.calls, contains('127.0.0.1,127.0.0.1'));
  });

  test('非 Twitch 线路不改写', () async {
    await player.open(otherLine);
    expect(fake.calls, contains('a.example.com'));
  });
}
