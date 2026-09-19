/// A3 弹幕细粒度设置单测。
///
/// 覆盖三类:
/// 1. DanmakuSettings.clamp 边界(各字段独立 clamp、缺失回退默认);
/// 2. 速度 ↔ 时长映射端点与单调性;
/// 3. danmakuSettingsProvider 持久化(SharedPreferencesAsync 注入
///    InMemorySharedPreferencesAsync,参照 play_controls_test 的 setUp 写法)
///    与写盘回读;
/// 4. 设置面板控件 ↔ provider 联动(滑杆/分段按钮改值 → 状态变,无死控件)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_settings_provider.dart';
import 'package:zishu_flutter/src/features/danmaku/domain/danmaku_settings.dart';
import 'package:zishu_flutter/src/features/danmaku/widgets/danmaku_overlay.dart';
import 'package:zishu_flutter/src/features/danmaku/widgets/danmaku_settings_panel.dart';

/// 固定帧 pump(遵循约定不用 pumpAndSettle)。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 3}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  group('DanmakuSettings.clamp 边界', () {
    test('各字段独立 clamp 到范围,越界被夹', () {
      final s = DanmakuSettings.clamp(
        opacity: 999,
        fontSize: 0,
        speed: -5,
        displayAreaRatio: 2.0,
      );
      expect(s.opacity, DanmakuSettings.kOpacityMax);
      expect(s.fontSize, DanmakuSettings.kFontSizeMin);
      expect(s.speed, DanmakuSettings.kSpeedMin);
      expect(s.displayAreaRatio, 1.0);
    });

    test('缺失字段回退出厂默认,整体等于默认实例', () {
      expect(DanmakuSettings.clamp(), const DanmakuSettings());
      // 仅改一项,其余保持默认。
      final onlySpeed = DanmakuSettings.clamp(speed: 3);
      expect(onlySpeed.speed, 3);
      expect(onlySpeed.opacity, DanmakuSettings.kOpacityDefault);
      expect(onlySpeed.fontSize, DanmakuSettings.kFontSizeDefault);
      expect(onlySpeed.displayAreaRatio, DanmakuSettings.kDisplayAreaDefault);
    });

    test('范围内值原样保留', () {
      final s = DanmakuSettings.clamp(
        opacity: 50,
        fontSize: 24,
        speed: 5,
        displayAreaRatio: 0.5,
      );
      expect(s.opacity, 50);
      expect(s.fontSize, 24);
      expect(s.speed, 5);
      expect(s.displayAreaRatio, 0.5);
    });

    test('显示区域档位顺序为 全屏→1/4 屏(4 档,对齐 web el-select)', () {
      expect(DanmakuSettings.kDisplayAreaRatios, <double>[
        1.0,
        0.75,
        0.5,
        0.25,
      ]);
    });

    test('旧持久化值(1/8 屏 0.125)吸附到最近档', () {
      expect(DanmakuSettings.nearestDisplayAreaRatio(0.125), 0.25);
      expect(DanmakuSettings.nearestDisplayAreaRatio(2.0), 1.0);
    });
  });

  group('danmakuDurationForSpeed 速度↔时长映射', () {
    test('端点精确命中且单调下降', () {
      expect(danmakuDurationForSpeed(1), closeTo(16.0, 1e-9));
      expect(danmakuDurationForSpeed(10), closeTo(3.0, 1e-9));
      for (var s = 1; s < 10; s++) {
        expect(
          danmakuDurationForSpeed(s),
          greaterThan(danmakuDurationForSpeed(s + 1)),
          reason: '速度越大时长应越短',
        );
      }
    });

    test('越界输入安全回退到端点', () {
      expect(danmakuDurationForSpeed(0), 16.0);
      expect(danmakuDurationForSpeed(99), 3.0);
    });

    test('overlay 静态映射与纯函数一致', () {
      expect(DanmakuOverlay.durationForSpeed(7), danmakuDurationForSpeed(7));
    });
  });

  group('danmakuSettingsProvider 持久化', () {
    setUp(() {
      // 每个用例独立内存后端:被测代码与测试共享同一存储,写盘即可回读。
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{});
    });

    test('首次启动返回出厂默认,不打写盘', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // 等待 microtask restore 完成。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(danmakuSettingsProvider), const DanmakuSettings());
    });

    testWidgets('读盘恢复脏值(clamp 后),缺失字段回退默认', (tester) async {
      // 预置越界脏值 + 一个合法值,绕过 clamp 校验模拟旧版本残留。
      // 用与 provider 相同的 SharedPreferencesAsync API 写入,保证落到同一后端。
      // 注意:opacity 出厂默认(100)恰等于上限,种子取 9999 → 夹到 100,
      // 与「根本没读到」无法区分(断言空转);改取 5(越下界)→ 夹到 10 可区分。
      final seed = SharedPreferencesAsync();
      await seed.setInt('zishu.danmaku.opacity', 5); // 越下界
      await seed.setInt('zishu.danmaku.fontSize', 24); // 合法,直通
      // speed / displayArea 缺失
      // 探针:确认种子值确实落到了当前平台后端。
      expect(
        await SharedPreferencesAsync().getInt('zishu.danmaku.fontSize'),
        24,
      );
      await tester.pumpWidget(ProviderScope(child: const SizedBox()));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );
      // restore 是在 provider 首次 build 时才经 microtask 调度的:必须先触发
      // 一次 read,再 flush。**不能用 Future.delayed** —— testWidgets 的
      // FakeAsync 里 timer 只随 tester.pump 推进,裸 await 会把用例挂到
      // 10 分钟超时(实测);pump 既派帧也冲 microtask,与兄弟用例一致。
      container.read(danmakuSettingsProvider);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final s = container.read(danmakuSettingsProvider);
      expect(
        s.opacity,
        DanmakuSettings.kOpacityMin,
        reason: '越下界 opacity 被夹到下限',
      );
      expect(s.fontSize, 24, reason: '合法字号直通,不被 clamp');
      expect(s.speed, DanmakuSettings.kSpeedDefault, reason: '缺失 speed 回退默认');
      expect(s.displayAreaRatio, DanmakuSettings.kDisplayAreaDefault);
    });

    test('写盘后立即可从后端读回(opacity/fontSize/speed/area)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      await container.read(danmakuSettingsProvider.notifier).setOpacity(42);
      await container.read(danmakuSettingsProvider.notifier).setFontSize(28);
      await container.read(danmakuSettingsProvider.notifier).setSpeed(3);
      await container
          .read(danmakuSettingsProvider.notifier)
          .setDisplayAreaRatio(0.25);
      await Future<void>.delayed(Duration.zero);

      // 内存态已更新。
      final state = container.read(danmakuSettingsProvider);
      expect(state.opacity, 42);
      expect(state.fontSize, 28);
      expect(state.speed, 3);
      expect(state.displayAreaRatio, 0.25);

      // 从后端直读,证明已落盘。
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getInt('zishu.danmaku.opacity'), 42);
      expect(await prefs.getInt('zishu.danmaku.fontSize'), 28);
      expect(await prefs.getInt('zishu.danmaku.speed'), 3);
      expect(await prefs.getDouble('zishu.danmaku.displayArea'), 0.25);
    });

    test('读盘失败不抛,保留默认', () async {
      // 不注入后端(平台实例为 null),restore 的 SharedPreferencesAsync 调用
      // 会抛,应被 catch 静默处理,state 保持默认。
      SharedPreferencesAsyncPlatform.instance = null;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(danmakuSettingsProvider), const DanmakuSettings());
    });
  });

  group('DanmakuSettingsPanel 控件 ↔ provider 联动', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{});
    });

    Future<ProviderContainer> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ZishuTheme.dark(),
            home: const Scaffold(body: DanmakuSettingsPanel()),
          ),
        ),
      );
      await _pumpFrames(tester);
      return ProviderScope.containerOf(
        tester.element(find.byType(DanmakuSettingsPanel)),
      );
    }

    testWidgets('默认状态下滑杆与显示区域下拉反映出厂值', (tester) async {
      final container = await pumpPanel(tester);
      final settings = container.read(danmakuSettingsProvider);
      expect(settings.opacity, 100);
      expect(settings.fontSize, 20);
      expect(settings.speed, 5, reason: '默认速度对齐 web(speed=5)');
      expect(settings.displayAreaRatio, 1.0);

      // 首个滑杆(透明度)= 100。
      final opacitySlider = tester.widget<Slider>(find.byType(Slider).first);
      expect(opacitySlider.value, 100);
      // 显示区域下拉选中全屏(1.0)。
      final dropdown = tester.widget<DropdownButton<double>>(
        find.byKey(const Key('danmaku-display-area')),
      );
      expect(dropdown.value, 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('拖动不透明度滑杆 → provider 状态变化且在范围内', (tester) async {
      final container = await pumpPanel(tester);
      final slider = find.byType(Slider).first;
      // 点滑杆轨道中段:Slider 点击即跳到该位置并触发 onChanged。
      final box = tester.renderObject<RenderBox>(slider);
      final center = box.localToGlobal(
        Offset(box.size.width * 0.3, box.size.height / 2),
      );
      await tester.tapAt(center);
      await _pumpFrames(tester);

      final opacity = container.read(danmakuSettingsProvider).opacity;
      expect(opacity, isNot(100), reason: '滑杆拖动应改变不透明度');
      expect(opacity, inInclusiveRange(10, 100));
      // 反向联动:滑杆 UI 值应同步更新。
      expect(tester.widget<Slider>(slider).value, opacity.toDouble());
    });

    testWidgets('选择显示区域下拉(半屏) → provider.displayAreaRatio = 0.5', (
      tester,
    ) async {
      final container = await pumpPanel(tester);
      // DropdownButton 需先展开菜单再点选项。
      await tester.tap(find.byKey(const Key('danmaku-display-area')));
      await _pumpFrames(tester);
      await tester.tap(find.text('半屏').last);
      await _pumpFrames(tester);
      expect(
        container.read(danmakuSettingsProvider).displayAreaRatio,
        0.5,
        reason: '下拉选择应直接写入对应比例',
      );
      final dropdown = tester.widget<DropdownButton<double>>(
        find.byKey(const Key('danmaku-display-area')),
      );
      expect(dropdown.value, 0.5);
    });

    testWidgets('provider 改值后面板滑杆同步(provider → UI 双向)', (tester) async {
      final container = await pumpPanel(tester);
      await container.read(danmakuSettingsProvider.notifier).setFontSize(30);
      await _pumpFrames(tester);
      // 字号滑杆(第二个 Slider)应反映 30。
      final fontSizeSlider = tester.widget<Slider>(find.byType(Slider).at(1));
      expect(fontSizeSlider.value, 30);
    });
  });
}
