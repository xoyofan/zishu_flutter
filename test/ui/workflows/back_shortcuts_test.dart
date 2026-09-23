/// 全局导航快捷键 workflow 测试:后退(Alt+←/侧键X1/Alt+左键)、
/// 前进(Alt+→/侧键X2/Alt+右键)与 Alt+Home,含「Alt 点击独占子组件」的 gate 验证。
///
/// 覆盖真实宿主 [WindowsApp](含 AppNavShortcuts 接线)
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
import 'package:zishu_flutter/src/features/browse/application/browse_provider.dart';
import 'package:zishu_flutter/src/features/browse/views/home_view.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_screen_provider.dart';
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

/// 按住 Alt 再按 →(浏览器前进手势)。
Future<void> _pressAltRight(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await _pumpFrames(tester, 3);
}

/// 按住 Alt 再按 Home(浏览器回首页手势)。
Future<void> _pressAltHome(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.home);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.home);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await _pumpFrames(tester, 3);
}

/// 鼠标前进侧键(XBUTTON2 → kForwardMouseButton)。
Future<void> _clickForwardMouseButton(WidgetTester tester) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.down(const Offset(120, 200), buttons: kForwardMouseButton),
  );
  await _pumpFrames(tester, 3);
  await tester.sendEventToBinding(pointer.up());
  await _pumpFrames(tester, 2);
}

/// F5:浏览器式刷新(平台首页重拉列表 / 播放页重开当前线路)。
Future<void> _pressF5(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
  await _pumpFrames(tester, 4);
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
                (widget.key as ValueKey<String>).value.startsWith(
                  'play-recommend-room-',
                ),
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

  testWidgets('Alt+→ :后退后前进,回到原播放页', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    expect(_visiblePage(tester), '/douyu/play/63136');

    await _pressAltLeft(tester);
    expect(_visiblePage(tester), '/all', reason: '先验证后退');

    await _pressAltRight(tester);
    expect(
      _visiblePage(tester),
      '/douyu/play/63136',
      reason: 'Alt+→ 应回到刚被后退掉的页面(go_router 无 forward,由宿主前进栈提供)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('鼠标前进侧键(X2):后退后前进', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);

    await _clickBackMouseButton(tester);
    expect(_visiblePage(tester), '/all', reason: 'X1 后退');

    await _clickForwardMouseButton(tester);
    expect(_visiblePage(tester), '/douyu/play/63136', reason: 'X2 前进');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Alt 状态残留时普通点击仍可进入房间', (tester) async {
    await _pumpApp(tester);
    await _pumpFrames(tester, 3);

    // 模拟 Windows 切窗/Alt-Tab 后 Flutter 未收到 Alt keyup：全局键盘状态
    // 仍报告 Alt 按下，但普通鼠标点击绝不能因此失去命中能力。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final card = find.byKey(const Key('room-card-douyu-63136'));
    await tester.ensureVisible(card);
    await _pumpFrames(tester, 2);
    await tester.tap(card);
    await _pumpFrames(tester, 4);

    expect(_visiblePage(tester), '/douyu/play/63136');
    expect(tester.takeException(), isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  });

  testWidgets('Alt+Home:回首页;没后退过则无可前进点,后退过的前进栈不受影响', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);

    // 没后退过:Alt+Home 后前进栈为空,Alt+→ 静默(浏览器同款 ——
    // 前进点只来自「已后退的历史」)。
    await _pressAltHome(tester);
    expect(_visiblePage(tester), '/all', reason: 'Alt+Home 回首页');
    await _pressAltRight(tester);
    expect(_visiblePage(tester), '/all', reason: '没后退过则无前进点,静默');

    // 从非首页出发:后退留下前进栈 → Alt+Home(go 重置路由栈)不得清掉它。
    app.router.go('/douyu');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    await _pressAltLeft(tester);
    expect(_visiblePage(tester), '/douyu', reason: '后退到 /douyu');

    await _pressAltHome(tester);
    expect(_visiblePage(tester), '/all', reason: 'Alt+Home 从任意页回首页');

    await _pressAltRight(tester);
    expect(
      _visiblePage(tester),
      '/douyu/play/63136',
      reason: 'Alt+Home 不清前进栈,Alt+→ 仍能回到刚才的房间',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+F:全局拉起搜索框,重复按不叠层', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);

    Future<void> pressCtrlF() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _pumpFrames(tester, 4);
    }

    await pressCtrlF();
    expect(
      find.byKey(const Key('search-dialog')),
      findsOneWidget,
      reason: 'Ctrl+F 应在任意页面打开搜索框',
    );

    // 防重入:openSearchDialog 本身不防叠,连按两次会开两层、得关两次。
    await pressCtrlF();
    expect(
      find.byKey(const Key('search-dialog'), skipOffstage: false),
      findsOneWidget,
      reason: '重复 Ctrl+F 不得叠出第二个对话框',
    );

    await tester.tap(find.byKey(const Key('search-dialog-close')));
    // 对话框退场动画约 150ms,按固定步长推够时间(不使用 pumpAndSettle)。
    await _pumpFrames(tester, 10);
    expect(find.byKey(const Key('search-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自行导航清空前进栈:此后 Alt+→ 静默不动作', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 3);
    await _pressAltLeft(tester);
    expect(_visiblePage(tester), '/all', reason: '后退后前进栈非空');

    // 用户自己导航(等价点菜单/切平台):前进语义失效,浏览器同款清栈。
    app.router.go('/douyu');
    await _pumpFrames(tester, 3);
    await _pressAltRight(tester);
    expect(_visiblePage(tester), '/douyu', reason: '自行导航后 Alt+→ 不得跳回旧页面');
    expect(tester.takeException(), isNull);
  });

  testWidgets('F5:平台首页刷新当前列表(浏览器式刷新)', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);

    var refreshes = 0;
    app.container.listen(
      browseRoomsProvider(const BrowseRoomQuery(site: 'all')),
      (_, _) => refreshes++,
    );

    await _pressF5(tester);
    await _pumpFrames(tester, 8);

    expect(refreshes, greaterThan(0), reason: 'F5 应触发首页房间列表刷新');
    expect(_visiblePage(tester), '/all', reason: '刷新不改变路由');
    expect(tester.takeException(), isNull);
  });

  testWidgets('F5:播放页重开当前线路(retry 通路,不改路由)', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);

    // retry 通路:payload 就位时 bump 代际(重开当前线路),fixture 房间
    // 不走真实 open,故断言代际而非 open 次数。
    const params = (site: 'douyu', roomId: '63136');
    final before = app.container
        .read(playControllerProvider(params))
        .requireValue
        .generation;

    await _pressF5(tester);
    await _pumpFrames(tester, 10);

    final after = app.container
        .read(playControllerProvider(params))
        .requireValue
        .generation;
    expect(after, greaterThan(before), reason: 'F5 应 bump 代际重开当前线路');
    expect(_visiblePage(tester), '/douyu/play/63136', reason: '刷新不改变路由');
    expect(tester.takeException(), isNull);
  });

  testWidgets('全屏态仍可后退/前进(Alt+← / Alt+→)', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);
    app.router.push('/douyu/play/63136');
    await _pumpFrames(tester, 4);

    // 焦点给舞台 → F 进全屏(播放页收 chrome)。
    await tester.tap(find.byKey(const Key('play-stage-focus')));
    await _pumpFrames(tester, 7);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await _pumpFrames(tester, 5);
    expect(
      app.container.read(playScreenProvider).hidesChrome,
      isTrue,
      reason: '已进入全屏态(chrome 收起)',
    );

    // Alt+←:全屏态后退到浏览页(快捷键在 builder 层,焦点链不受 chrome 影响)。
    await _pressAltLeft(tester);
    expect(_visiblePage(tester), '/all', reason: '全屏态 Alt+← 应后退');

    // Alt+→:前进回播放页。
    await _pressAltRight(tester);
    expect(
      _visiblePage(tester),
      '/douyu/play/63136',
      reason: 'Alt+→ 应回到刚后退掉的播放页',
    );
    expect(tester.takeException(), isNull);
  });
}
