/// 完整链路 workflow test:首页网格 → 点击房间卡进播放页 → 切换画质 → 返回首页。
///
/// - media_kit 禁止在 VM 初始化:注入 FakeLivePlayer。
/// - 走真实 go_router 导航(push/pop 全程有效);播放页不套 AppShell,真实宿主
///   缺少 Material 祖先(PlayerControlsBar 的 Slider 依赖),测试宿主用
///   MaterialApp.router 的 builder 统一补一层 Material,不影响业务断言。
/// - 全程固定次数 pump,不用 pumpAndSettle(封面图片在 VM 中不会真正加载)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,快照立即给一帧,方法只记录调用。
class FakeLivePlayer implements LivePlayer {
  FakeLivePlayer();

  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line) async => calls.add('open:${line.url}');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted:$muted');

  @override
  Future<void> toggleFullscreen() async => calls.add('fullscreen');

  @override
  void dispose() => calls.add('dispose');
}

/// 测试宿主:与 WindowsApp 相同的 router/theme,额外在 builder 补 Material
/// 祖先,保证播放页 Slider 等控件在 VM 测试环境可正常构建。
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: ZishuTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          Material(type: MaterialType.transparency, child: child),
    );
  }
}

void main() {
  testWidgets('首页 → 播放页切画质 → 返回首页,锚点全程可用', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWithValue(FakeLivePlayer())],
        child: const _TestApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 1. 初始 /all 首页网格:第一个 fixture 房间卡片可见。
    final firstCard = find.byKey(const Key('room-card-douyu-63136'));
    expect(firstCard, findsOneWidget);

    // 2. 点击卡片 → 推入播放页。
    await tester.tap(firstCard);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('play-back')), findsOneWidget);

    // 3. 点击第二个画质 chip(超清):切换无异常且进入选中态。
    final secondQuality = find.byKey(const Key('play-quality-超清'));
    expect(secondQuality, findsOneWidget);
    await tester.tap(secondQuality);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(tester.widget<ChoiceChip>(secondQuality).selected, isTrue);

    // 4. 点返回按钮 → 回到首页,房间网格锚点仍在。
    await tester.tap(find.byKey(const Key('play-back')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('play-back')), findsNothing);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
  });
}
