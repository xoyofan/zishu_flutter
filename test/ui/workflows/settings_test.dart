/// 设置持久化 workflow 测试:默认值渲染、主题/画质/弹幕交互,
/// 以及 SharedPreferencesAsync(zishu.settings.*)写盘回读与重建恢复一致性。
///
/// 服务器(streaming-server 地址)组已从设置页移除:state 字段与持久化仍保留
/// (Web 端后续接入),用例只断言 UI 文案不再出现。
///
/// 宿主约定与 test/ui/app_shell_test.dart 一致:ProviderScope + WindowsApp +
/// routerProvider,注入 FakeLivePlayer(VM 下不触碰 media_kit 原生内核)。
/// shared_preferences 异步恢复挂在 microtask/await 之后,全程固定次数
/// pump,不使用 pumpAndSettle;hydrated 采用固定间隔轮询。
/// 存储后端注入 InMemorySharedPreferencesAsync(经 shared_preferences 传递依赖
/// 引入的平台接口包),写入与回读共享同一内存存储。
library;

import 'dart:convert';

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
import 'package:zishu_flutter/src/shared/application/auth_provider.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';

/// 测试替身:登录态固定匿名。真实 AuthController 的启动链在「有存储后端 +
/// 无缓存凭据」时会向 data-server 发起默认账号登录,fake_async 测试环境
/// 不允许真实 HTTP,这里整体替换掉登录态。
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
  Future<void> open(StreamLine line, [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

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

void main() {
  setUp(() {
    // 每个用例独立的内存后端:被测代码与测试中的 SharedPreferencesAsync
    // 共享同一存储,写盘即可同步回读。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  test('平台默认档:soop/twitch/youtube 取高清,档位列表为平台原生', () {
    expect(SettingsState.platformDefaultQuality['soop'], '高清');
    expect(SettingsState.platformDefaultQuality['twitch'], '720p');
    expect(SettingsState.platformDefaultQuality['youtube'], '720p');
    expect(
      SettingsState.qualityOptionsForSite('soop'),
      contains('高清'),
      reason: 'soop 设置页应列出原生档位(含高清)',
    );
    expect(SettingsState.qualityOptionsForSite('twitch'), contains('720p'));
    expect(
      SettingsState.qualityOptionsForSite('unknown_site'),
      SettingsState.qualityOptions,
      reason: '未收录平台回落通用预设',
    );

    const state = SettingsState(
      themeMode: ThemeModeChoice.system,
      defaultQuality: '超清',
      danmakuEnabled: true,
      chatEnabled: true,
      preferredLineFormat: PreferredLineFormat.auto,
      serverUrl: SettingsState.defaultServerUrl,
    );
    expect(state.effectiveDefaultQuality('soop'), '高清');
    expect(state.effectiveDefaultQuality('twitch'), '720p');
    expect(state.effectiveDefaultQuality('douyu'), '超清');
    expect(
      state
          .copyWith(defaultQualityBySite: const {'soop': '原画'})
          .effectiveDefaultQuality('soop'),
      '原画',
      reason: '平台单独配置优先于平台默认档',
    );
  });

  testWidgets('打开 /settings:默认值渲染(hydrated 后仍为出厂默认)', (tester) async {
    await _pumpSettings(tester);

    // provider 状态:默认值且已完成恢复(空存储不覆盖默认)。
    final state = _readSettings(tester);
    expect(state.hydrated, isTrue);
    expect(
      state.themeMode,
      ThemeModeChoice.dark,
      reason: '桌面端基线为深色(浅色/跟随系统为显式选择项)',
    );
    expect(state.defaultQuality, '超清');
    expect(state.danmakuEnabled, isTrue);

    // 界面控件反映同一组默认值。
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('深色'), findsWidgets); // 主题下拉当前值(至少下拉内一处)。
    expect(find.text('超清'), findsOneWidget); // 画质下拉当前值。
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('settings-danmaku-toggle')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('settings-translation-toggle')))
          .value,
      isTrue,
      reason: '翻译开关出厂默认为开',
    );

    // 服务器组已移除:UI 不再出现地址录入(字段保留在 state 层);
    // 翻译组的自定义实例地址输入(2026-09-20 新增)是页面唯一的 TextField。
    expect(find.text('streaming-server 地址'), findsNothing);
    expect(
      find.byKey(const Key('settings-translation-endpoint')),
      findsOneWidget,
    );
  });

  testWidgets('硬件解码开关可关闭并持久化', (tester) async {
    await _pumpSettings(tester);
    final hwdecSwitch = find.byKey(const Key('settings-hwdec-toggle'));
    expect(hwdecSwitch, findsOneWidget);
    expect(_readSettings(tester).videoHardwareAcceleration, isTrue);

    await tester.ensureVisible(hwdecSwitch);
    await tester.tap(hwdecSwitch);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_readSettings(tester).videoHardwareAcceleration, isFalse);
    expect(
      await SharedPreferencesAsync().getBool(
        'zishu.settings.videoHardwareAcceleration',
      ),
      isFalse,
    );

    await _pumpSettings(tester);
    expect(_readSettings(tester).videoHardwareAcceleration, isFalse);
    expect(
      tester.widget<Switch>(hwdecSwitch).value,
      isFalse,
    );
  });

  testWidgets('主题模式切到深色:provider 状态更新且下拉控件反映', (tester) async {
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

  testWidgets('切换弹幕开关:danmakuEnabled 翻转且 Switch 反映', (tester) async {
    await _pumpSettings(tester);
    expect(_readSettings(tester).danmakuEnabled, isTrue);

    final danmakuSwitch = find.byKey(const Key('settings-danmaku-toggle'));
    await tester.ensureVisible(danmakuSwitch);
    await tester.tap(danmakuSwitch);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_readSettings(tester).danmakuEnabled, isFalse);
    expect(tester.widget<Switch>(danmakuSwitch).value, isFalse);
  });

  testWidgets('改默认画质:provider 状态更新且下拉控件反映', (tester) async {
    await _pumpSettings(tester);

    await _selectDropdownOption(
      tester,
      find.byType(DropdownButton<String>),
      '蓝光8M',
    );
    expect(_readSettings(tester).defaultQuality, '蓝光8M');
    expect(find.text('蓝光8M'), findsOneWidget);
  });

  testWidgets('持久化回读:zishu.settings.* 已写盘,重建 ProviderScope 后恢复一致', (
    tester,
  ) async {
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
    final danmakuSwitch = find.byKey(const Key('settings-danmaku-toggle'));
    await tester.ensureVisible(danmakuSwitch);
    await tester.tap(danmakuSwitch);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 直接从 SharedPreferencesAsync 内存后端读回,断言各键已写入。
    final prefs = SharedPreferencesAsync();
    expect(await prefs.getString('zishu.settings.themeMode'), 'dark');
    expect(await prefs.getString('zishu.settings.defaultQuality'), '蓝光8M');
    expect(await prefs.getBool('zishu.settings.danmakuEnabled'), isFalse);

    // 重建 ProviderScope(等价重启):同一内存后端,期望完整恢复。
    await _pumpSettings(tester);

    final restored = _readSettings(tester);
    expect(restored.hydrated, isTrue);
    expect(restored.themeMode, ThemeModeChoice.dark);
    expect(restored.defaultQuality, '蓝光8M');
    expect(restored.danmakuEnabled, isFalse);

    // 界面控件反映恢复后的值。
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('蓝光8M'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('settings-danmaku-toggle')))
          .value,
      isFalse,
    );
  });

  testWidgets('按平台默认画质:平台覆盖优先于全平台默认,清除后回落', (tester) async {
    await _pumpSettings(tester);

    // 折叠态不构建平台下拉:DropdownButton<String> 只命中「全平台默认画质」。
    expect(
      find.byType(DropdownButton<String>),
      findsOneWidget,
      reason: '折叠态应只有全平台默认画质一个下拉',
    );

    // 展开后为各平台(除 all)各渲染一个下拉。
    await tester.ensureVisible(
      find.byKey(const Key('settings-toggle-platform-quality')),
    );
    await tester.tap(find.byKey(const Key('settings-toggle-platform-quality')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final platformCount = PlatformBrandCatalog.navPlatforms
        .where((brand) => brand.id != 'all')
        .length;
    expect(
      find.byType(DropdownButton<String>),
      findsNWidgets(platformCount + 1),
    );

    // 给斗鱼单独配置「蓝光8M」(按平台锚点寻址,不依赖文案祖先链)。
    final douyuDropdown = find.byKey(const Key('settings-quality-douyu'));
    expect(douyuDropdown, findsOneWidget);
    await _selectDropdownOption(tester, douyuDropdown, '蓝光8M');

    // 内存态:平台覆盖生效,未配置平台回落全平台默认。
    final state = _readSettings(tester);
    expect(state.defaultQualityBySite['douyu'], '蓝光8M');
    expect(state.effectiveDefaultQuality('douyu'), '蓝光8M');
    expect(state.effectiveDefaultQuality('huya'), '超清');

    // 已写盘(JSON Map<String,String>)。
    final prefs = SharedPreferencesAsync();
    final stored = await prefs.getString('zishu.settings.defaultQualityBySite');
    expect((jsonDecode(stored!) as Map<String, Object?>)['douyu'], '蓝光8M');

    // 选「跟随平台默认」→ 覆盖被清除。仍在同一展开态内完成,避免「重启后
    // State 折叠、需二次展开」的时序耦合。
    await _selectDropdownOption(tester, douyuDropdown, '跟随平台默认');
    expect(
      _readSettings(tester).defaultQualityBySite.containsKey('douyu'),
      isFalse,
      reason: '选「跟随平台默认」应清除平台覆盖',
    );
    expect(
      _readSettings(tester).effectiveDefaultQuality('douyu'),
      '超清',
      reason: '斗鱼无平台默认档,清除覆盖后回落全平台默认',
    );
    final cleared = await prefs.getString('zishu.settings.defaultQualityBySite');
    expect(
      jsonDecode(cleared!),
      <String, Object?>{},
      reason: '空覆盖应写回空 Map',
    );

    // 重建 ProviderScope(等价重启):空覆盖持久化,回落全平台默认。
    await _pumpSettings(tester);
    final restored = _readSettings(tester);
    expect(restored.defaultQualityBySite, isEmpty);
    expect(restored.effectiveDefaultQuality('douyu'), '超清');
  });
}
