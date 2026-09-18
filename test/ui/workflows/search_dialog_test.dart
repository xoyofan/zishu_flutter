/// 全局搜索弹框 workflow 测试:入口(顶栏 / 移动底栏)、关闭(Esc / 关闭按钮)、
/// 以及「先关框再导航」这条宿主契约。
///
/// 背景:搜索此前是独立页面路由 `/search`;参考实现(SFVideoLive)早已改成
/// `SearchDialog` 弹框 —— 输入与结果都不离开当前页面。本套用例钉住新形态。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> toggleFullscreen() async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}

  @override
  Future<void> exitPictureInPicture() async {}

  @override
  Future<void> stop() async {}

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

const Duration _kFrame = Duration(milliseconds: 50);

Future<void> _pumpFrames(WidgetTester tester, [int times = 2]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 关闭动作要等对话框退场动画(约 150ms)走完,否则 widget 仍在树上。
Future<void> _pumpDialogExit(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<GoRouter> _pumpApp(WidgetTester tester, {Size size = const Size(1280, 900)}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  await _pumpFrames(tester, 2);
  final element = tester.element(find.byType(Navigator).first);
  return ProviderScope.containerOf(element).read(routerProvider);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('顶栏 nav-search 拉起弹框:不切路由,关框后仍在原页', (tester) async {
    final router = await _pumpApp(tester);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-search')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('search-dialog')), findsOneWidget);
    expect(find.byKey(const Key('search-input')), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/all',
      reason: '搜索弹框只开框,不改路由位置',
    );

    await tester.tap(find.byKey(const Key('search-dialog-close')));
    await _pumpDialogExit(tester);

    expect(find.byKey(const Key('search-dialog')), findsNothing);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc 关闭弹框:焦点在搜索框内也能关(不误退路由)', (tester) async {
    final router = await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('nav-search')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('search-dialog')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpDialogExit(tester);

    expect(find.byKey(const Key('search-dialog')), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/all',
      reason: 'Esc 只关框;弹框不在路由栈里,不得把页面 pop 掉',
    );
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动底栏 nav-search 同样拉起弹框', (tester) async {
    await _pumpApp(tester, size: const Size(360, 640));

    expect(find.byKey(const Key('nav-home')), findsOneWidget, reason: '窄屏走底部导航');
    await tester.tap(find.byKey(const Key('nav-search')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('search-dialog')), findsOneWidget);
    expect(find.byKey(const Key('search-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放页里搜索切房:替换而非入栈(不残留旧播放页会话)', (tester) async {
    final router = await _pumpApp(tester);
    // 先进入播放页(经 push 入栈),再从中拉起搜索。
    router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    expect(find.byType(PlayView), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-search')));
    await _pumpFrames(tester);
    // 搜另一个 douyu 房间号(默认搜索平台 douyu,直达项 → /douyu/play/63137)。
    await tester.enterText(find.byKey(const Key('search-input')), '63137');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(_kFrame);
    expect(find.text('进入房间 63137'), findsOneWidget);

    await tester.tap(find.text('进入房间 63137'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byKey(const Key('search-dialog')), findsNothing);
    expect(
      find.byType(PlayView),
      findsOneWidget,
      reason: '播放页里切房必须替换栈顶,不得把旧播放页压在栈下',
    );
    expect(tester.widget<PlayView>(find.byType(PlayView)).roomId, '63137');
    expect(tester.takeException(), isNull);
  });

  testWidgets('点直达项:先关框再进播放页(弹框不压在目标页之上)', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('nav-search')));
    await _pumpFrames(tester);

    // 纯数字 → 房间号直达项;默认搜索平台为 douyu。
    await tester.enterText(find.byKey(const Key('search-input')), '63136');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(_kFrame);
    expect(find.text('进入房间 63136'), findsOneWidget);

    await tester.tap(find.text('进入房间 63136'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byKey(const Key('search-dialog')), findsNothing);
    final play = find.byType(PlayView);
    expect(play, findsOneWidget, reason: '关框后应导航到播放页');
    expect(tester.widget<PlayView>(play).roomId, '63136');
    expect(tester.widget<PlayView>(play).site, 'douyu');
    expect(tester.takeException(), isNull);
  });
}
