/// 设置持久化 workflow 测试:默认值渲染、主题/画质/弹幕/服务器交互,
/// 以及 SharedPreferencesAsync(zishu.settings.*)写盘回读与重建恢复一致性。
///
/// 宿主约定与 test/ui/app_shell_test.dart 一致:ProviderScope + WindowsApp +
/// routerProvider,注入 FakeLivePlayer(VM 下不触碰 media_kit 原生内核)。
/// shared_preferences 异步恢复与 SnackBar 定时器都可能挂 Timer,全程固定次数
/// pump,不使用 pumpAndSettle;hydrated 采用固定间隔轮询。
/// 存储后端注入 InMemorySharedPreferencesAsync(经 shared_preferences 传递依赖
/// 引入的平台接口包),写入与回读共享同一内存存储。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/follow/views/settings_view.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
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
  Future<void> open(StreamLine line) async {}

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

/// 读取当前设置状态(任意页面元素均可定位 ProviderScope)。
SettingsState _readSettings(WidgetTester tester) {
  final element = tester.element(find.byType(SettingsView));
  return ProviderScope.containerOf(element).read(settingsProvider);
}

/// pump WindowsApp 并导航到 /settings,轮询至 settingsProvider hydrated。
Future<GoRouter> _pumpSettings(WidgetTester tester) async {
  _suppressRenderFlexOverflow();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  // 两帧:首页(/all)骨架渲染 + fixture 数据落地。
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  final element = tester.element(find.byType(Scaffold));
  final router = ProviderScope.containerOf(element).read(routerProvider);

  router.go('/settings');
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));

  // 异步 _restore 挂在 microtask + await 之后:固定间隔轮询等待 hydrated。
  for (var attempt = 0; attempt < 10; attempt++) {
    if (_readSettings(tester).hydrated) {
      await tester.pump(const Duration(milliseconds: 50));
      return router;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('settingsProvider 未在限定帧数内完成 hydrated');
}

/// 打开下拉并选中指定文案的选项;固定 pump 推进开/关菜单动画。
Future<void> _selectDropdownOption(
  WidgetTester tester,
  Finder dropdownFinder,
  String label,
) async {
  await tester.ensureVisible(dropdownFinder);
  await tester.tap(dropdownFinder);
  await tester.pump(const Duration(milliseconds: 300)); // 菜单展开动画。
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 300)); // 菜单收起动画。
  await tester.pump(const Duration(milliseconds: 50)); // 状态落地帧。
}

/// 输入服务器地址并点击「保存」,断言 SnackBar,并排空其自动消失 Timer。
Future<void> _saveServerUrl(WidgetTester tester, String url) async {
  await tester.ensureVisible(find.byType(TextField));
  await tester.enterText(find.byType(TextField), url);
  await tester.pump(const Duration(milliseconds: 50));

  await tester.ensureVisible(find.text('保存'));
  await tester.tap(find.text('保存'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.text('服务器地址已保存'), findsOneWidget);

  // SnackBar 的自动消失 Timer 在进入动画完成后才启动:在 FakeAsync 内用足够
  // 时长走完「进入完成 -> Timer 到期 -> 退出动画」,避免用例结束 pending timer。
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(SnackBar), findsNothing);
}

void main() {
  setUp(() {
    // 每个用例独立的内存后端:被测代码与测试中的 SharedPreferencesAsync
    // 共享同一存储,写盘即可同步回读。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('打开 /settings:默认值渲染(hydrated 后仍为出厂默认)',
      (tester) async {
    await _pumpSettings(tester);

    // provider 状态:默认值且已完成恢复(空存储不覆盖默认)。
    final state = _readSettings(tester);
    expect(state.hydrated, isTrue);
    expect(state.themeMode, ThemeModeChoice.system);
    expect(state.defaultQuality, '超清');
    expect(state.danmakuEnabled, isTrue);
    expect(state.serverUrl, SettingsState.defaultServerUrl);

    // 界面控件反映同一组默认值。
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget); // 主题下拉当前值。
    expect(find.text('超清'), findsOneWidget); // 画质下拉当前值。
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'http://127.0.0.1:8787',
    );
  });

  testWidgets('主题模式切到深色:provider 状态更新且下拉控件反映',
      (tester) async {
    await _pumpSettings(tester);

    await _selectDropdownOption(
      tester,
      find.byType(DropdownButton<ThemeModeChoice>),
      '深色',
    );

    expect(_readSettings(tester).themeMode, ThemeModeChoice.dark);
    // 菜单关闭后「深色」仅剩按钮当前值一处。
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('跟随系统'), findsNothing);
  });

  testWidgets('切换弹幕开关:danmakuEnabled 翻转且 Switch 反映',
      (tester) async {
    await _pumpSettings(tester);
    expect(_readSettings(tester).danmakuEnabled, isTrue);

    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_readSettings(tester).danmakuEnabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('改默认画质并保存服务器地址:状态更新 + SnackBar 反馈',
      (tester) async {
    await _pumpSettings(tester);

    await _selectDropdownOption(
      tester,
      find.byType(DropdownButton<String>),
      '蓝光8M',
    );
    expect(_readSettings(tester).defaultQuality, '蓝光8M');
    expect(find.text('蓝光8M'), findsOneWidget);

    await _saveServerUrl(tester, 'http://192.168.1.50:9000');
    expect(_readSettings(tester).serverUrl, 'http://192.168.1.50:9000');
  });

  testWidgets('持久化回读:zishu.settings.* 已写盘,重建 ProviderScope 后恢复一致',
      (tester) async {
    await _pumpSettings(tester);

    // 通过 UI 触发一组变更(即持久化写入)。
    await _selectDropdownOption(
      tester,
      find.byType(DropdownButton<ThemeModeChoice>),
      '深色',
    );
    await _selectDropdownOption(
      tester,
      find.byType(DropdownButton<String>),
      '蓝光8M',
    );
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await _saveServerUrl(tester, 'http://10.0.0.2:7777');

    // 直接从 SharedPreferencesAsync 内存后端读回,断言各键已写入。
    final prefs = SharedPreferencesAsync();
    expect(await prefs.getString('zishu.settings.themeMode'), 'dark');
    expect(await prefs.getString('zishu.settings.defaultQuality'), '蓝光8M');
    expect(await prefs.getBool('zishu.settings.danmakuEnabled'), isFalse);
    expect(await prefs.getString('zishu.settings.serverUrl'),
        'http://10.0.0.2:7777');

    // 重建 ProviderScope(等价重启):同一内存后端,期望完整恢复。
    await _pumpSettings(tester);

    final restored = _readSettings(tester);
    expect(restored.hydrated, isTrue);
    expect(restored.themeMode, ThemeModeChoice.dark);
    expect(restored.defaultQuality, '蓝光8M');
    expect(restored.danmakuEnabled, isFalse);
    expect(restored.serverUrl, 'http://10.0.0.2:7777');

    // 界面控件反映恢复后的值。
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('蓝光8M'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'http://10.0.0.2:7777',
    );
  });
}
