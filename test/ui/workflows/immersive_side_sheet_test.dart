/// 沉浸态右缘侧抽屉 workflow test(对齐 web PlayImmersiveSideSheet)。
///
/// 参考:`SFVideoLive/apps/web/src/components/play/PlayImmersiveSideSheet.vue`
/// + `composables/useImmersiveMode.ts` + `views/PlayView.vue` 的 onPlayFrameClick。
///
/// web 真源语义(逐条对应用例):
/// 1. 沉浸态(全屏/网页全屏)点击舞台右缘热区(x/width >= PLAY_IMMERSIVE_TAP_ZONE
///    = 2/3)→ 打开侧抽屉并隐藏控制条;
/// 2. 点击左缘(热区外)→ 仅唤醒控制条,不开抽屉;
/// 3. 抽屉开着时点击背景 → 关抽屉 + 唤醒控制条;
/// 4. toggle 把手点击 → 收起;
/// 5. 打开后 3s 无交互自动收起;面板内交互重置计时;
/// 6. 进入沉浸态后有 720ms 防抖锁,锁内点击右缘不开抽屉;
/// 7. 沉浸态下舞台点击不切换播放/暂停(web onPlayFrameClick 直接 return);
/// 8. 退出沉浸态(Esc)抽屉随沉浸容器一起卸载。
///
/// 宿主与 pump 约定同 fullscreen_test.dart:固定次数 pump,不用 pumpAndSettle。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 播放页深链位置(fixture 样例房间,与 fullscreen 基线同房间)。
const String _playLocation = '/douyu/play/63136';

/// 固定 pump 步长,与既有 workflow 测试一致。
const Duration _kFrame = Duration(milliseconds: 50);

/// 测试替身:替代 MediaKitLivePlayer,记录方法调用。
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
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async => calls.add('open:${line.url}');

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
  Future<void> setFullscreen(bool fullscreen) async =>
      calls.add('fullscreen:$fullscreen');

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async =>
      calls.add('pip:enter');

  @override
  Future<void> exitPictureInPicture() async => calls.add('pip:exit');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() => calls.add('dispose');
}

/// 测试宿主:与 WindowsApp 相同的 router/theme,补一层透明 Material。
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

late FakeLivePlayer _player;

Future<void> _pumpPlay(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  _player = FakeLivePlayer();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_player)],
      child: const _TestApp(),
    ),
  );
  await _pumpFrames(tester, 2);

  final element = tester.element(find.byType(Navigator).first);
  final router = ProviderScope.containerOf(element).read(routerProvider);
  router.go(_playLocation);
  await _pumpFrames(tester, 3);
}

Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

Future<void> _pressF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await _pumpFrames(tester, 2);
}

Future<void> _pressEscape(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
  await _pumpFrames(tester, 2);
}

/// 进入沉浸态并越过 720ms 防抖锁。
Future<void> _enterImmersive(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('play-stage-focus')));
  await _pumpFrames(tester, 2);
  await _pressF(tester);
  expect(
    find.byKey(const Key('play-immersive-stage')),
    findsOneWidget,
    reason: '前置:应已进入沉浸态',
  );
  // 越过 720ms 防抖锁。
  await tester.pump(const Duration(milliseconds: 800));
}

/// 抽屉遮罩层 opacity(open 状态代理断言)。
AnimatedOpacity _sheetFade(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const Key('play-immersive-sheet')),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .first;

/// 控制条包装层(opacity/absorbing 断言)。
AnimatedOpacity _controlsWrap(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const Key('play-controls-bar-wrap')));

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('沉浸态点击右缘热区:抽屉滑出且控制条立即隐藏', (tester) async {
    await _pumpPlay(tester);
    await _enterImmersive(tester);

    // 右缘 1/3(1600 宽,热区分界 x≈1066):点 x=1500。
    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 6);

    expect(
      find.byKey(const Key('play-immersive-sheet')),
      findsOneWidget,
      reason: '右缘热区点击应挂载沉浸侧抽屉',
    );
    expect(_sheetFade(tester).opacity, 1.0, reason: '抽屉应处于展开态');
    expect(
      _controlsWrap(tester).opacity,
      0.0,
      reason: 'web openImmersiveSidePanel 同步 showControls=false:开抽屉即藏控制条',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('沉浸态点击左缘(热区外):只唤醒控制条,不开抽屉', (tester) async {
    await _pumpPlay(tester);
    await _enterImmersive(tester);
    // 先让控制条淡出,验证"唤醒"。
    await tester.pump(const Duration(seconds: 4));
    expect(_controlsWrap(tester).opacity, 0.0);

    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(300, 400));
    await _pumpFrames(tester, 4);

    // sheet 在沉浸期间常驻挂载(web v-show),开合状态以动画目标值断言。
    expect(
      _sheetFade(tester).opacity,
      0.0,
      reason: '热区外点击不应展开抽屉',
    );
    expect(
      _controlsWrap(tester).opacity,
      1.0,
      reason: '热区外点击应唤醒控制条(revealControls)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('抽屉开着点背景:关抽屉 + 唤醒控制条', (tester) async {
    await _pumpPlay(tester);
    await _enterImmersive(tester);

    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 6);
    expect(_sheetFade(tester).opacity, 1.0, reason: '前置:抽屉应已展开');

    // 点背景(左缘)。
    await tester.tapAt(origin + const Offset(300, 400));
    await _pumpFrames(tester, 6);
    expect(
      _sheetFade(tester).opacity,
      0.0,
      reason: '点背景应关闭抽屉(web onBackdropClick)',
    );
    expect(
      _controlsWrap(tester).opacity,
      1.0,
      reason: '关闭抽屉应同时唤醒控制条',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggle 把手点击收起抽屉', (tester) async {
    await _pumpPlay(tester);
    await _enterImmersive(tester);

    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 6);
    expect(_sheetFade(tester).opacity, 1.0, reason: '前置:抽屉应已展开');

    await tester.tap(find.byKey(const Key('play-immersive-toggle')));
    await _pumpFrames(tester, 6);
    expect(
      _sheetFade(tester).opacity,
      0.0,
      reason: 'toggle 应收起抽屉(web __toggle @click=close)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开 3s 无交互自动收起;面板内交互重置计时', (tester) async {
    await _pumpPlay(tester);
    await _enterImmersive(tester);

    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 6);
    expect(_sheetFade(tester).opacity, 1.0);

    // 面板内指针交互:重置自动收起计时。
    final panelCenter = tester.getCenter(
      find.byKey(const Key('play-immersive-panel')),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: panelCenter);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(panelCenter + const Offset(2, 2));

    await tester.pump(const Duration(seconds: 2, milliseconds: 500));
    expect(
      _sheetFade(tester).opacity,
      1.0,
      reason: '面板交互后 3s 计时应被重置(2.5s 时仍应展开)',
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      _sheetFade(tester).opacity,
      0.0,
      reason: '重置后再过 3s 无交互应自动收起(IMMERSIVE_SIDE_IDLE_MS=3000)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('进入沉浸态 720ms 防抖锁内点击右缘不开抽屉', (tester) async {
    await _pumpPlay(tester);
    await tester.tap(find.byKey(const Key('play-stage-focus')));
    await _pumpFrames(tester, 2);
    await _pressF(tester);
    // 不越过防抖锁,立即点击右缘。
    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 4);
    expect(
      _sheetFade(tester).opacity,
      0.0,
      reason: '进入沉浸后的 720ms 锁内,右缘点击不应开抽屉',
    );

    // 越过锁后再点:可正常打开。
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 6);
    expect(_sheetFade(tester).opacity, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沉浸态舞台点击不切换播放/暂停', (tester) async {
    await _pumpPlay(tester);
    await _enterImmersive(tester);
    _player.calls.clear();

    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(300, 400));
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 4);

    expect(
      _player.calls.where((c) => c == 'pause' || c == 'play'),
      isEmpty,
      reason: 'web onPlayFrameClick 在沉浸态直接 return:点击只管理控制条/抽屉,不切播放',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc 退出沉浸态:抽屉随沉浸容器一起卸载', (tester) async {
    await _pumpPlay(tester);
    await _enterImmersive(tester);

    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 6);
    expect(_sheetFade(tester).opacity, 1.0, reason: '前置:抽屉应已展开');

    await _pressEscape(tester);
    expect(
      find.byKey(const Key('play-immersive-stage')),
      findsNothing,
      reason: '前置:Esc 应退出沉浸态',
    );
    expect(
      find.byKey(const Key('play-immersive-sheet')),
      findsNothing,
      reason: 'web watch(isFullscreenSideHidden) 退出即 closeImmersiveSide',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('网页全屏同样支持右缘热区抽屉', (tester) async {
    await _pumpPlay(tester);
    await tester.tap(find.byKey(const Key('play-stage-focus')));
    await _pumpFrames(tester, 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await _pumpFrames(tester, 2);
    await tester.pump(const Duration(milliseconds: 800));

    final origin = tester.getTopLeft(
      find.byKey(const Key('play-immersive-stage')),
    );
    await tester.tapAt(origin + const Offset(1500, 400));
    await _pumpFrames(tester, 6);
    expect(
      find.byKey(const Key('play-immersive-sheet')),
      findsOneWidget,
      reason: '网页全屏(isFullscreenSideHidden 同真)也应有沉浸抽屉',
    );
    expect(_sheetFade(tester).opacity, 1.0);
    expect(tester.takeException(), isNull);
  });
}
