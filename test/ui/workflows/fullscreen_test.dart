/// 全屏 / 沉浸模式 workflow test(任务 A5 全屏实装 + A6 沉浸模式)。
///
/// 覆盖:
/// 1. F 键调用 [LivePlayer.toggleFullscreen](fake 记录 `fullscreen`)并进入
///    本地沉浸态(全屏容器 `play-immersive-stage` 出现);
/// 2. Esc 在沉浸态触发退出,回到带房间头/返回键的常态布局;
/// 3. 全屏后 `_RoomHeader` 不渲染、`play-back` 不可见,退出后恢复;
/// 4. 控制条静止 ~3s 自动淡出(opacity==0),鼠标移动/悬停即唤出(opacity==1)。
///
/// 注入 FakeLivePlayer(VM 下不初始化 media_kit);全屏实现刻意「按键切本地
/// 沉浸态 + try/catch 调平台层」,不依赖 window_manager 返回值,故可在 VM 中验证。
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
  Future<void> open(StreamLine line, [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async => calls.add('open:${line.url}');

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
  Future<void> stop() async => calls.add('stop');

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

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('F enters immersive mode and calls toggleFullscreen', (tester) async {
    await _pumpPlay(tester);
    await _focusStage(tester);
    _player.calls.clear();

    // F 键:平台层窗口全屏被调用(本地记录),同时进入本地沉浸态。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await _pumpFrames(tester, 2);

    // ① 调用记录:平台层 toggleFullscreen 被触发。
    expect(
      _player.calls,
      contains('fullscreen'),
      reason: 'F 应调用 toggleFullscreen',
    );
    // 进入沉浸态:全屏容器出现,房间头/返回键不可见。
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

  testWidgets('Esc exits immersive mode and restores header', (tester) async {
    await _pumpPlay(tester);
    await _focusStage(tester);

    // 进入全屏。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await _pumpFrames(tester, 2);
    expect(find.byKey(const Key('play-immersive-stage')), findsOneWidget);
    expect(find.byKey(const Key('play-back')), findsNothing);
    _player.calls.clear();

    // ② Esc 在沉浸态触发退出回调:回到带头部/返回键的常态布局。
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
    // 进出各调一次平台层全屏。
    expect(
      _player.calls.where((c) => c == 'fullscreen').length,
      1,
      reason: '退出全屏应再调一次平台层 toggleFullscreen',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('controls bar fades out when idle and returns on mouse move', (
    tester,
  ) async {
    await _pumpPlay(tester);
    await _focusStage(tester);

    // 进入全屏:控制条初始可见。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await _pumpFrames(tester, 2);
    final wrap0 = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('play-controls-bar-wrap')),
    );
    expect(wrap0.opacity, 1.0, reason: '进入全屏控制条应立即可见');

    // ④ 静止 4s:控制条自动淡出(opacity==0)。
    await tester.pump(const Duration(seconds: 4));
    final wrapHidden = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('play-controls-bar-wrap')),
    );
    expect(
      wrapHidden.opacity,
      0.0,
      reason: '全屏静止后控制条应自动淡出(opacity==0)',
    );

    // 鼠标移动(悬停控制条区域):立即唤出(opacity==1)。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    final center = tester.getCenter(
      find.byKey(const Key('play-controls-bar-wrap')),
    );
    await gesture.moveTo(center);
    await tester.pump(const Duration(milliseconds: 300));
    final wrapShown = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('play-controls-bar-wrap')),
    );
    expect(
      wrapShown.opacity,
      1.0,
      reason: '鼠标移动/悬停应立即可见控制条',
    );
    expect(tester.takeException(), isNull);
  });
}
