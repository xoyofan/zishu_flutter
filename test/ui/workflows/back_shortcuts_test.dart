/// 全局返回快捷键 workflow 测试:鼠标侧键(后退)与 Alt+←。
///
/// 覆盖三条链路,全部走真实宿主 [WindowsApp](含 AppBackShortcuts 接线)
/// + 注入 FakeLivePlayer(VM 下禁止初始化 media_kit);存储后端注入
/// InMemorySharedPreferencesAsync,与 side_panel_features_test 宿主写法一致:
/// 固定次数 pump,不用 pumpAndSettle(封面图在 VM 中不会真正加载)。
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
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/views/home_view.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 测试替身:替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class FakeLivePlayer implements LivePlayer {
  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line,
          [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async =>
      calls.add('open:${line.url}');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted:$muted');

  @override
  Future<void> toggleFullscreen() async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}

  @override
  Future<void> exitPictureInPicture() async {}

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

const Duration _kFrame = Duration(milliseconds: 50);

Future<void> _pumpFrames(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 启动真实宿主并返回 router。
Future<({GoRouter router, ProviderContainer container})> _pumpApp(
  WidgetTester tester,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  await _pumpFrames(tester, 2);
  final element = tester.element(find.byType(Navigator).first);
  final container = ProviderScope.containerOf(element);
  return (router: container.read(routerProvider), container: container);
}

/// 当前**可见**页面路径。
///
/// 不用 `routeInformationProvider.value.uri`:命令式 push 之后它报告的是 base
/// 位置(栈底那条声明式路由),不是真实栈顶 —— 用它断言会得到「推了却还说在
/// 首页」的假结论。这里直接按渲染出的页面判定,与用户所见一致。
String _visiblePage(WidgetTester tester) {
  final play = find.byType(PlayView);
  if (play.evaluate().isNotEmpty) {
    final view = tester.widget<PlayView>(play);
    return '/${view.site}/play/${view.roomId}';
  }
  final home = find.byType(HomeView);
  if (home.evaluate().isNotEmpty) {
    final view = tester.widget<HomeView>(home);
    return view.site == 'all' ? '/all' : '/${view.site}';
  }
  return '(unknown)';
}

/// 按住 Alt 再按 ←(浏览器后退手势)。
Future<void> _pressAltLeft(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await _pumpFrames(tester, 3);
}

/// 鼠标后退侧键(XBUTTON1 → kBackMouseButton)。
Future<void> _clickBackMouseButton(WidgetTester tester) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.down(const Offset(120, 200), buttons: kBackMouseButton),
  );
  await _pumpFrames(tester, 3);
  await tester.sendEventToBinding(pointer.up());
  await _pumpFrames(tester, 2);
}

void main() {
  setUp(() {
    // 桌面壳里有内存存储/登录恢复链路,注入内存后端避免碰平台通道。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('Alt+← :播放页返回上一层浏览页', (tester) async {
    final app = await _pumpApp(tester);
    // 先落到首页,再 push 进播放页 —— 栈 = [首页, 播放页]。
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    expect(_visiblePage(tester), '/douyu/play/63136');

    await _pressAltLeft(tester);

    expect(_visiblePage(tester), '/all', reason: 'Alt+← 应回退到上一层浏览页');
    expect(tester.takeException(), isNull);
  });

  testWidgets('鼠标侧键后退:播放页返回上一层浏览页', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/douyu');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    expect(_visiblePage(tester), '/douyu/play/63136');

    await _clickBackMouseButton(tester);

    expect(_visiblePage(tester), '/douyu', reason: '鼠标后退键应回退到上一层浏览页');
    expect(tester.takeException(), isNull);
  });

  testWidgets('栈底无上一页:快捷键静默不动作,不抛 GoError', (tester) async {
    final app = await _pumpApp(tester);
    // 直达播放页(栈底),此时没有可 pop 的上一页。
    app.router.go('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    expect(_visiblePage(tester), '/douyu/play/63136');

    await _pressAltLeft(tester);
    expect(_visiblePage(tester), '/douyu/play/63136');
    expect(
      tester.takeException(),
      isNull,
      reason: '栈底按后退应静默,不得抛 GoError: There is nothing to pop',
    );

    await _clickBackMouseButton(tester);
    expect(_visiblePage(tester), '/douyu/play/63136');
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放页左上角返回:栈顶 pop,回到上一页', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);

    await tester.tap(find.byKey(const Key('play-back')));
    await _pumpFrames(tester, 3);

    expect(_visiblePage(tester), '/all');
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏推荐条目切房:返回仍能回到进入播放页前的浏览页', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);

    // 切到推荐 tab,点一条推荐房(切房用 pushReplacement,不能把整栈换掉)。
    await tester.tap(find.byKey(const Key('play-side-tab-recommend')));
    await _pumpFrames(tester, 8);
    final anchors = tester
        .widgetList(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>)
                    .value
                    .startsWith('play-recommend-room-'),
          ),
        )
        .map((w) => (w.key as ValueKey<String>).value)
        .toList();
    expect(anchors, isNotEmpty);
    final target = anchors.firstWhere(
      (key) => !key.endsWith('-63136'),
      orElse: () => anchors.first,
    );
    await tester.ensureVisible(find.byKey(Key(target)));
    await tester.tap(find.byKey(Key(target)));
    await _pumpFrames(tester, 4);

    final match = RegExp(r'play-recommend-room-(.+)-(.+)$').firstMatch(target)!;
    expect(_visiblePage(tester), '/${match.group(1)}/play/${match.group(2)}');

    // 关键回归:切房后「返回」必须还能回浏览页(旧实现 go 重置整栈 → 无栈可回)。
    await tester.tap(find.byKey(const Key('play-back')));
    await _pumpFrames(tester, 4);
    expect(_visiblePage(tester), '/all', reason: '切房后返回应回到进入播放页前的浏览页');
    expect(tester.takeException(), isNull);
  });
}
