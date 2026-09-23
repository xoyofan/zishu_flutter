/// 顶栏主题切换(nav-theme)workflow 测试:点击在「深色 ⇄ 浅色」间切换
/// settingsProvider.themeMode,并驱动 MaterialApp 实际主题同步变化。
///
/// 覆盖口径:
/// 1. 初始默认深色:label/icon 表示「点击后切到浅色」,tooltip 保持「切换主题」;
/// 2. 点击 → provider 变 light、MaterialApp.themeMode 变 light、
///    页面实际 Theme.brightness 变 light,label/icon 翻转为「深色」;
/// 3. 再点击 → 回到 dark(同上三处同步)。
///
/// 宿主约定照抄 test/ui/workflows/settings_test.dart 的 _pumpSettings:
/// ProviderScope + WindowsApp + FakeLivePlayer(VM 下不触碰 media_kit 原生内核),
/// 全程固定次数 pump(不用 pumpAndSettle),hydrated 采用固定间隔轮询;
/// 存储后端注入 InMemorySharedPreferencesAsync。
/// 视口固定为桌面宽(>=1366)以便顶栏渲染 label 文案。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/auth_provider.dart';

/// 测试替身:登录态固定匿名(真启动链在无缓存凭据时会发真实 HTTP)。
class _AnonymousAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(phase: AuthPhase.anonymous);
}

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

/// VM 测试字体取整可能带来既有布局的 RenderFlex 溢出,只放行该类渲染错误。
void _suppressRenderFlexOverflow() {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    originalOnError?.call(details);
  };
}

/// 桌面视口(宽 >= AppBreakpoints.desktop=1366),顶栏渲染 label。
const Size _kDesktopLogicalSize = Size(1400, 900);

/// 读取当前设置状态(任意页面元素均可定位 ProviderScope)。
SettingsState _readSettings(WidgetTester tester) {
  final element = tester.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(element).read(settingsProvider);
}

/// nav-settings 锚点(常驻)处生效的主题亮度(Theme 由 MaterialApp 按 themeMode 解析)。
Brightness _themeBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byKey(const Key('nav-settings')))).brightness;

/// MaterialApp 上配置的 themeMode。
ThemeMode _materialAppThemeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

/// 在打开的设置对话框内选择「主题模式」下拉的某一项(菜单开合各推 300ms)。
Future<void> _selectThemeMode(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownButton<ThemeModeChoice>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pump(const Duration(milliseconds: 300)); // 菜单展开。
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 300)); // 菜单收起。
  await tester.pump(const Duration(milliseconds: 50)); // 状态落地。
}

/// pump WindowsApp(桌面视口)并轮询至 settingsProvider hydrated。
Future<void> _pumpApp(WidgetTester tester) async {
  _suppressRenderFlexOverflow();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _kDesktopLogicalSize;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        authProvider.overrideWith(_AnonymousAuthController.new),
      ],
      child: const WindowsApp(),
    ),
  );
  // 两帧:首页(/all)骨架渲染 + fixture 数据落地。
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));

  // 异步 _restore 挂在 microtask + await 之后:固定间隔轮询等待 hydrated。
  for (var attempt = 0; attempt < 10; attempt++) {
    if (_readSettings(tester).hydrated) {
      await tester.pump(const Duration(milliseconds: 50));
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('settingsProvider 未在限定帧数内完成 hydrated');
}

void main() {
  setUp(() {
    // 每个用例独立的内存后端:被测代码与测试中的 SharedPreferencesAsync
    // 共享同一存储,写盘即可同步回读。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('顶栏主题按钮已移除:设置对话框内完成主题切换,provider 与 MaterialApp 同步', (
    tester,
  ) async {
    await _pumpApp(tester);

    // 新契约(2026-09-23):顶栏不再有主题快捷按钮,浅色/主题收进设置对话框。
    expect(find.byKey(const Key('nav-theme')), findsNothing);
    expect(find.byTooltip('切换主题'), findsNothing);

    // 初始:出厂默认深色。
    expect(_readSettings(tester).themeMode, ThemeModeChoice.dark);
    expect(_materialAppThemeMode(tester), ThemeMode.dark);
    expect(_themeBrightness(tester), Brightness.dark);

    // 点顶栏设置 → 对话框(而非整页)。
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    expect(find.byKey(const Key('settings-dialog-close')), findsOneWidget);

    // 对话框内切到浅色:provider、MaterialApp themeMode、亮度、写盘四断言。
    await _selectThemeMode(tester, '浅色');
    // 主题切换走 MaterialApp 的 AnimatedTheme(200ms):先落一帧再推过时长。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_readSettings(tester).themeMode, ThemeModeChoice.light);
    expect(_materialAppThemeMode(tester), ThemeMode.light);
    expect(_themeBrightness(tester), Brightness.light);
    expect(
      await SharedPreferencesAsync().getString('zishu.settings.themeMode'),
      'light',
      reason: '切换即写盘',
    );

    // 切回深色(light↔dark 往返闭环)。
    await _selectThemeMode(tester, '深色');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_readSettings(tester).themeMode, ThemeModeChoice.dark);
    expect(_materialAppThemeMode(tester), ThemeMode.dark);
    expect(
      await SharedPreferencesAsync().getString('zishu.settings.themeMode'),
      'dark',
    );

    // 关闭对话框(退场动画约 150ms,推够帧后应从树中移除)。
    await tester.tap(find.byKey(const Key('settings-dialog-close')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(const Key('settings-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('themeMode=system:设置对话框内切到与当前生效相反的显式值', (
    tester,
  ) async {
    // 系统亮度设为深色:system 档下当前生效主题即深色。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpApp(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(settingsProvider.notifier).setThemeMode(
      ThemeModeChoice.system,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // system + 平台深色 → MaterialApp 走 system 档,当前生效深色。
    expect(_materialAppThemeMode(tester), ThemeMode.system);
    expect(_themeBrightness(tester), Brightness.dark);

    // 打开设置对话框,选与当前生效相反的显式值「浅色」。
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);

    await _selectThemeMode(tester, '浅色');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));

    // 不再停留在 system,落到显式 light。
    expect(_readSettings(tester).themeMode, ThemeModeChoice.light);
    expect(_materialAppThemeMode(tester), ThemeMode.light);
    expect(_themeBrightness(tester), Brightness.light);
    expect(tester.takeException(), isNull);
  });
}
