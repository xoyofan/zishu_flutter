/// 全屏 / 沉浸 / 网页全屏 / 画中画 workflow test
/// (任务 A5 全屏实装 + A6 沉浸模式;2026-09-13 按 pure_live 三态模型重构)。
///
/// 覆盖:
/// 1. F 键经 playScreenProvider 单源进入全屏:`LivePlayer.setFullscreen(true)`
///    被调用 + 沉浸容器 `play-immersive-stage` 出现,房间头/返回键隐藏;
/// 2. Esc 退出全屏并恢复常态布局(Esc 走全局键盘 handler,不依赖焦点);
/// 3. 控制条全屏按钮与 F 键同源 —— 回归旧实现"点按钮只切窗口、UI 不进沉浸态";
/// 4. 焦点停在控制条内的音量滑杆上时按 F 依然进入沉浸 —— 回归旧实现
///    "控制条内层 CallbackShortcuts 截获 F 键";
/// 5. 网页全屏只做窗口内铺满,不请求系统窗口全屏;
/// 6. 画中画按钮进入小窗(控制条隐藏、PipResizeSurface 挂载);
/// 7. 控制条静止 ~3s 自动淡出、鼠标移动即唤出,且淡出后被 AbsorbPointer 阻断
///    (不可见按钮不再可点、底部条带不再吞掉视频点击);
/// 8. Esc 分派优先级(纯函数):画中画 > 全屏 > 网页全屏 > 返回上一页。
///
/// 注入 FakeLivePlayer(VM 下不初始化 media_kit);呈现态与平台窗口调用解耦,
/// 平台层被替身后 UI 态仍可稳定验证。
///
/// 宿主与 pump 约定同 play_controls_test.dart:固定次数 pump,不用 pumpAndSettle。
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
import 'package:zishu_flutter/src/features/play/application/play_screen_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/pip_surface.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 播放页深链位置(fixture 样例房间,与 layout/controls 基线同房间)。
const String _playLocation = '/douyu/play/63136';

/// 固定 pump 步长,与既有 workflow 测试一致。
const Duration _kFrame = Duration(milliseconds: 50);

/// 测试替身:替代 MediaKitLivePlayer,记录方法调用并按需广播快照。
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

/// 记录播放器替身,便于用例断言调用序列。
late FakeLivePlayer _player;

/// 启动宿主并深链到播放页,返回 router 与 container。
Future<({GoRouter router, ProviderContainer container})> _pumpPlay(
  WidgetTester tester,
) async {
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
  final container = ProviderScope.containerOf(element);
  final router = container.read(routerProvider);
  router.go(_playLocation);
  await _pumpFrames(tester, 3);
  return (router: router, container: container);
}

/// 固定次数 pump(不用 pumpAndSettle:封面图在 VM 中不会真正加载)。
Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 把键盘焦点交给播放页舞台(CallbackShortcuts 沿焦点树冒泡,快捷键才可达)。
Future<void> _focusStage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('play-stage-focus')));
  await _pumpFrames(tester, 2);
  expect(
    tester.binding.focusManager.primaryFocus,
    isNotNull,
    reason: '点击舞台后应有焦点落在播放页内,快捷键才可达',
  );
}

/// 按一次 F 键。
Future<void> _pressF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await _pumpFrames(tester, 2);
}

/// 控制条淡出/命中阻断断言用的包装层。
AnimatedOpacity _controlsWrap(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const Key('play-controls-bar-wrap')));

AbsorbPointer _controlsAbsorber(WidgetTester tester) =>
    tester.widget<AbsorbPointer>(
      find.descendant(
        of: find.byKey(const Key('play-controls-bar-wrap')),
        matching: find.byType(AbsorbPointer),
      ),
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('F 进入全屏:下达 setFullscreen(true) 并挂载沉浸容器', (tester) async {
    await _pumpPlay(tester);
    await _focusStage(tester);
    _player.calls.clear();

    await _pressF(tester);

    // ① 平台层:呈现态是单一真源,窗口全屏是它的下游副作用。
    expect(
      _player.calls,
      contains('fullscreen:true'),
      reason: 'F 应把"进入系统全屏"的目标态下达给播放器',
    );
    // ② UI:沉浸容器出现,房间头/返回键隐藏。
    expect(
      find.byKey(const Key('play-immersive-stage')),
      findsOneWidget,
      reason: '进入全屏后应有沉浸容器',
    );
    expect(
      find.byKey(const Key('play-back')),
      findsNothing,
      reason: '全屏态下房间头(含返回键)应隐藏',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc 退出全屏并恢复房间头(Esc 不依赖焦点)', (tester) async {
    await _pumpPlay(tester);
    await _focusStage(tester);

    await _pressF(tester);
    expect(find.byKey(const Key('play-immersive-stage')), findsOneWidget);
    expect(find.byKey(const Key('play-back')), findsNothing);
    _player.calls.clear();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await _pumpFrames(tester, 2);

    expect(
      find.byKey(const Key('play-immersive-stage')),
      findsNothing,
      reason: 'Esc 退出后沉浸容器应消失',
    );
    expect(
      find.byKey(const Key('play-back')),
      findsOneWidget,
      reason: '退出全屏后房间头(返回键)应恢复',
    );
    expect(
      _player.calls,
      contains('fullscreen:false'),
      reason: '退出全屏应把 false 下达给播放器',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制条全屏按钮与 F 键同源(回归:按钮曾只切窗口不进沉浸态)', (tester) async {
    await _pumpPlay(tester);
    _player.calls.clear();

    await tester.tap(find.byKey(const Key('play-toggle-fullscreen')));
    await _pumpFrames(tester, 2);

    expect(
      find.byKey(const Key('play-immersive-stage')),
      findsOneWidget,
      reason: '点全屏按钮必须同时进入沉浸布局,而不是只把窗口全屏',
    );
    expect(find.byKey(const Key('play-back')), findsNothing);
    expect(_player.calls, contains('fullscreen:true'));

    // 再点一次:退出全屏(图标随态切换为「退出全屏」)。
    await tester.tap(find.byKey(const Key('play-toggle-fullscreen')));
    await _pumpFrames(tester, 2);
    expect(find.byKey(const Key('play-immersive-stage')), findsNothing);
    expect(_player.calls, contains('fullscreen:false'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('焦点在音量滑杆上时按 F 仍进入沉浸(回归:控制条截获快捷键)', (tester) async {
    await _pumpPlay(tester);

    // 宽视口下控制条非 compact,音量滑杆挂载;点它把焦点收进控制条子树。
    expect(
      find.byType(Slider),
      findsOneWidget,
      reason: '宽视口控制条应挂载音量滑杆(用于构造"焦点在控制条内"的场景)',
    );
    await tester.tap(find.byType(Slider));
    await _pumpFrames(tester, 2);
    expect(
      tester.binding.focusManager.primaryFocus,
      isNotNull,
      reason: '点击滑杆后应有焦点落在控制条内',
    );
    _player.calls.clear();

    await _pressF(tester);

    expect(
      find.byKey(const Key('play-immersive-stage')),
      findsOneWidget,
      reason: '控制条不再自带快捷键,焦点在条内时 F 也必须进入沉浸态',
    );
    expect(_player.calls, contains('fullscreen:true'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('网页全屏:铺满窗口但不请求系统窗口全屏', (tester) async {
    await _pumpPlay(tester);
    _player.calls.clear();

    await tester.tap(find.byKey(const Key('play-toggle-widescreen')));
    await _pumpFrames(tester, 2);

    expect(
      find.byKey(const Key('play-immersive-stage')),
      findsOneWidget,
      reason: '网页全屏同样隐藏房间头与侧栏、视频铺满',
    );
    expect(
      _player.calls.contains('fullscreen:true'),
      isFalse,
      reason: '网页全屏不应请求系统窗口全屏',
    );
    expect(_player.calls, contains('fullscreen:false'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('画中画:进入小窗并隐藏控制条', (tester) async {
    await _pumpPlay(tester);
    _player.calls.clear();

    await tester.tap(find.byKey(const Key('play-toggle-pip')));
    await _pumpFrames(tester, 2);

    expect(_player.calls, contains('pip:enter'));
    expect(find.byType(PipResizeSurface), findsOneWidget);
    expect(
      find.byKey(const Key('play-controls-bar-wrap')),
      findsNothing,
      reason: '小窗内不渲染控制条',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制条静止淡出、被 AbsorbPointer 阻断、鼠标移动即唤出', (tester) async {
    await _pumpPlay(tester);
    await _focusStage(tester);

    await _pressF(tester);
    expect(_controlsWrap(tester).opacity, 1.0, reason: '进入全屏控制条应立即可见');
    expect(
      _controlsAbsorber(tester).absorbing,
      isFalse,
      reason: '控制条可见时不应阻断命中',
    );

    // 静止 4s:控制条自动淡出。
    await tester.pump(const Duration(seconds: 4));
    expect(
      _controlsWrap(tester).opacity,
      0.0,
      reason: '全屏静止后控制条应自动淡出(opacity==0)',
    );
    expect(
      _controlsAbsorber(tester).absorbing,
      isTrue,
      reason: '淡出后必须阻断命中,否则不可见按钮仍会被点中、底部条带会吞掉视频点击',
    );

    // 淡出态点全屏按钮:应被阻断,仍停留在全屏。
    await tester.tap(
      find.byKey(const Key('play-toggle-fullscreen')),
      warnIfMissed: false,
    );
    await _pumpFrames(tester, 2);
    expect(
      find.byKey(const Key('play-immersive-stage')),
      findsOneWidget,
      reason: '淡出后按钮不应可点(不退出全屏)',
    );

    // 鼠标移动(悬停控制条区域):立即唤出。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('play-controls-bar-wrap'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(_controlsWrap(tester).opacity, 1.0, reason: '鼠标移动/悬停应立即可见控制条');
    expect(_controlsAbsorber(tester).absorbing, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PiP 中按 Esc:退出小窗并恢复进入前的全屏呈现态', (tester) async {
    await _pumpPlay(tester);
    _player.calls.clear();

    await tester.tap(find.byKey(const Key('play-toggle-fullscreen')));
    await _pumpFrames(tester, 2);
    expect(find.byKey(const Key('play-immersive-stage')), findsOneWidget);

    await tester.tap(find.byKey(const Key('play-toggle-pip')));
    await _pumpFrames(tester, 2);
    expect(find.byType(PipResizeSurface), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await _pumpFrames(tester, 2);

    expect(find.byType(PipResizeSurface), findsNothing);
    expect(find.byKey(const Key('play-immersive-stage')), findsOneWidget);
    expect(_player.calls, contains('pip:exit'));
    expect(_player.calls, contains('fullscreen:true'));
    expect(tester.takeException(), isNull);
  });
  test('Esc 分派优先级:画中画 > 全屏 > 网页全屏 > 返回上一页', () {
    expect(
      resolveEscapePresentationAction(
        pip: true,
        fullscreen: true,
        widescreen: true,
      ),
      EscapePresentationAction.exitPip,
    );
    expect(
      resolveEscapePresentationAction(
        pip: false,
        fullscreen: true,
        widescreen: true,
      ),
      EscapePresentationAction.exitFullscreen,
    );
    expect(
      resolveEscapePresentationAction(
        pip: false,
        fullscreen: false,
        widescreen: true,
      ),
      EscapePresentationAction.exitWidescreen,
    );
    expect(
      resolveEscapePresentationAction(
        pip: false,
        fullscreen: false,
        widescreen: false,
      ),
      EscapePresentationAction.popRoute,
    );
  });
}
