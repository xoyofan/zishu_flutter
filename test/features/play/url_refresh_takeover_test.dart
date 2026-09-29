/// 预刷新"接管守卫"回归测试(纯 Dart,无 Widget)。
///
/// 复现 2026-09-29 22:04 真机事故:用户从虎牙播放页跳进斗鱼播放页后,虎牙
/// controller 仍在导航栈存活,其 URL 预刷新定时器到点触发 `_open`,把全局
/// 单例播放器从斗鱼手上抢走(画面被切成虎牙)。修复后:预刷新到点先校验
/// 本 controller 的 open token 是否仍是全局最新,被接管则静默放弃
/// (`url_refresh_abandoned`),当前持有者的预刷新照常工作。
library;

import 'dart:async';

import 'package:flutter/material.dart' show BoxFit, SizedBox, Widget;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart'
    show RoomPayload, RoomState, StreamLine, StreamQuality;
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart'
    show PreferredLineFormat, SettingsController, SettingsState, ThemeModeChoice,
    settingsProvider;
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

class _FakePlayer implements LivePlayer {
  _FakePlayer(this.openedUrls);

  final List<String> openedUrls;

  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async {
    openedUrls.add(line.url);
  }

  @override
  Stream<PlayerSnapshot> get snapshots => const Stream.empty();
  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.shrink();
  @override
  void dispose() {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setFullscreen(bool fullscreen) async {}
  @override
  Future<void> toggleFullscreen() async {}
  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}
  @override
  Future<void> exitPictureInPicture() async {}
  @override
  Widget wrapPipSurface(Widget child) => child;
}

/// resolveRoom 返回首帧线路;recoverRoom 每次返回**新 token** 的 FLV URL
/// (expire=120 → 预刷新排在 96s 后),驱动预刷新的"URL 已轮换"路径。
class _FakeSource implements RoomSource, RoomRecoverer {
  _FakeSource(this.calls);

  final List<String> calls;
  int _resolveToken = 0;
  int _recoverToken = 100;

  RoomPayload _payload(String site, String roomIdOrUrl, String url) {
    return RoomPayload(
      site: site,
      roomId: roomIdOrUrl,
      sourceUrl: 'https://test/$site/$roomIdOrUrl',
      anchorName: '测试主播',
      title: '测试房间',
      cover: '',
      avatar: '',
      category: '测试',
      cid: '1',
      roomState: RoomState.live,
      streams: [
        StreamQuality(
          name: '超清',
          rate: 2,
          lines: [
            StreamLine(name: 'FLV', url: url, format: 'flv'),
          ],
        ),
      ],
      availableQualities: const [],
      source: 'test',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    final token = _resolveToken++;
    calls.add('resolve:$site:$roomIdOrUrl');
    return _payload(
      site,
      roomIdOrUrl,
      'https://$site.test/live.flv?token=$token&expire=120',
    );
  }

  @override
  Future<RoomPayload> recoverRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    final token = _recoverToken++;
    calls.add('recover:$site:$roomIdOrUrl');
    return _payload(
      site,
      roomIdOrUrl,
      'https://$site.test/live.flv?token=$token&expire=120',
    );
  }
}

class _FixedSettings extends SettingsController {
  @override
  SettingsState build() {
    return SettingsState(
      themeMode: ThemeModeChoice.dark,
      defaultQuality: '超清',
      danmakuEnabled: true,
      chatEnabled: true,
      preferredLineFormat: PreferredLineFormat.auto,
      serverUrl: SettingsState.defaultServerUrl,
      translationEnabled: false,
      hydrated: true,
    );
  }
}

void main() {
  test('被接管的房间预刷新到点不抢播放器,当前房间照常刷新', () {
    final openedUrls = <String>[];
    final sourceCalls = <String>[];
    FakeAsync().run((async) {
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWithValue(_FakePlayer(openedUrls)),
          roomSourceProvider.overrideWithValue(_FakeSource(sourceCalls)),
          settingsProvider.overrideWith(_FixedSettings.new),
        ],
      );
      addTearDown(container.dispose);

      // 虎牙页先进房(open huya),再跳进斗鱼页(open douyu,接管播放器)。
      // listen(而非 read)保持 autoDispose 存活:导航栈里的旧播放页就是
      // 这种"无交互但持有订阅"的形态,这是事故的前提。
      // listen(而非 read)保持 autoDispose 存活:导航栈里的旧播放页就是
      // 这种"无交互但持有订阅"的形态,这是事故的前提。build 是纯微任务
      // 链(fake source 立即返回),flushMicrotasks 即可推进到开流完成。
      final keepAlive = <ProviderSubscription<AsyncValue<PlayState>>>[];
      keepAlive.add(
        container.listen(
          playControllerProvider((site: 'huya', roomId: '1')),
          (_, _) {},
        ),
      );
      async.flushMicrotasks();
      keepAlive.add(
        container.listen(
          playControllerProvider((site: 'douyu', roomId: '2')),
          (_, _) {},
        ),
      );
      async.flushMicrotasks();
      expect(
        openedUrls.map((u) => Uri.tryParse(u)?.host).toList(),
        ['huya.test', 'douyu.test'],
        reason: '前置:两房先后开流,斗鱼持有播放器',
      );

      // 快进 100s:两个预刷新(96s)都到点。
      async.elapse(const Duration(seconds: 100));
      async.flushMicrotasks();

      final hosts =
          openedUrls.map((u) => Uri.tryParse(u)?.host).toList();
      expect(
        hosts.where((h) => h == 'huya.test').length,
        1,
        reason: '被接管的虎牙页预刷新到点必须放弃,不得把播放器抢回',
      );
      expect(
        hosts.where((h) => h == 'douyu.test').length,
        2,
        reason: '当前持有者(斗鱼)的预刷新照常轮换新地址',
      );
      expect(
        hosts.last,
        'douyu.test',
        reason: '最后一次 open 必须仍是斗鱼(当前观看的房间)',
      );
    });
  });
}
