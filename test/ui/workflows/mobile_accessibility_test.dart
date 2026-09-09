/// W11 平台差异矩阵测试(tasks-workflows.md):SafeArea + 大字体 + 高 DPR。
///
/// 四组用例(设备档位/注入/sweep 全部复用 layout_harness.dart,只读):
/// 1. safeAreaNavUnobstructed:iPhone15 insets(47,34) 下首页/关注/设置三页
///    顶导航锚点(nav-home/nav-follow/nav-settings)不被刘海遮挡,底部锚点
///    (播放页 play-quality-*、关注页条目)不被 home indicator 遮挡;
/// 2. proMaxSafeArea:kIphone15ProMax insets(55,34) 关键页抽查(首页 nav +
///    播放页 play-quality 上下沿);
/// 3. textScaleNoOverflow:1.0/1.15/1.3 三档字号 × 首页/关注/设置/播放四页,
///    失败列表为空(如实失败,不 suppress);
/// 4. highDprSpotCheck:kIphone15@3x 与 AndroidSmall@2x 下首页 + 播放页
///    overflowSweep 通过(DPR 物理换算由 harness 注入)。
///
/// 宿主约定(参考 layout_test.dart):
/// - media_kit 禁止在 VM 初始化:统一注入 FakeLivePlayer;
/// - 走 MaterialApp + builder 补 Material 祖先(播放页 Slider/ChoiceChip 依赖),
///   额外补 SafeArea:应用侧移动壳(U9)尚未落地,WindowsApp/AppShell 均无
///   安全区处理,W11 的安全区矩阵以「宿主级 SafeArea + 系统 insets 注入」为
///   契约基准——U9 移动壳实现后应把该 SafeArea 迁入应用壳层,矩阵断言不变;
/// - 全程固定次数 pump,不使用 pumpAndSettle;sweep 失败记录为空即通过。
///
/// bottomSafeAreaSweep 用 print 输出逐页进度(`[safeArea]` 日志可 grep,
/// 与 layout_harness.dart 同一约定),故对整个文件放行 avoid_print。
// ignore_for_file: avoid_print
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_shell.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/browse/views/home_view.dart';
import 'package:zishu_flutter/src/features/follow/views/follow_view.dart';
import 'package:zishu_flutter/src/features/follow/views/settings_view.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'layout_harness.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,快照立即给一帧,方法只记录调用。
class _FakeLivePlayer implements LivePlayer {
  _FakeLivePlayer();

  /// 记录方法调用,便于必要时验证交互链路。
  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line) async => calls.add('open:${line.url}');

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
  void dispose() => calls.add('dispose');
}

/// W11 移动端页面宿主:Material 祖先(播放页 Slider/ChoiceChip 依赖)+
/// 宿主级 SafeArea(安全区契约基准,见文件头注释)。
Widget _mobileHost(Widget page) {
  return ProviderScope(
    overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
    child: MaterialApp(
      theme: ZishuTheme.dark(),
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: SafeArea(child: child ?? const SizedBox.shrink()),
      ),
      home: page,
    ),
  );
}

/// 壳层页(AppShell 顶导航含 nav-* 锚点)。
Widget _shellPage(Widget child) =>
    _mobileHost(AppShell(site: 'all', child: child));

/// 播放页:不套壳,fixture 房间(douyu/63136)经 roomSourceProvider 解析。
Widget _playPage() => _mobileHost(const PlayView(site: 'douyu', roomId: '63136'));

/// 矩阵覆盖的四个页面构造器(每次调用产出一棵全新宿主树)。
final List<(String name, Widget Function() page)> _allPages = [
  ('home', () => _shellPage(const HomeView(site: 'all'))),
  ('follow', () => _shellPage(const FollowView())),
  ('settings', () => _shellPage(const SettingsView())),
  ('play', _playPage),
];

/// 顶部导航锚点(壳层页共有)。
Map<String, Finder> _navAnchors() => {
  'nav-home': find.byKey(const Key('nav-home')),
  'nav-follow': find.byKey(const Key('nav-follow')),
  'nav-settings': find.byKey(const Key('nav-settings')),
};

/// 锚点:首页首张房间卡片(`ValueKey<String>` 前缀 room-card-)。
Finder _roomCardFinder() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith('room-card-'),
);

/// 锚点:播放页画质 chip(`ValueKey<String>` 前缀 play-quality-)。
Finder _playQualityFinder() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith('play-quality-'),
);

/// 锚点:关注页条目(`ValueKey<String>` 前缀 follow-entry-)。
Finder _followEntryFinder() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith('follow-entry-'),
);

void main() {
  setUp(() {
    // settingsProvider 走 SharedPreferencesAsync:注入内存后端,恢复行为确定。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  /// 排空 pending 渲染异常(几何用例卫生)。
  ///
  /// safeArea 类用例只对遮挡几何负责;页面在 VM 测试环境的既有溢出异常
  /// (如 FollowEntryCard 元信息区)由 textScale/overflow sweep 用例如实记账,
  /// 此处排空仅防跨页误归因与用例收尾误报,不属于溢出抑制。
  void drainPendingExceptions(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  /// 底部安全区锚点扫测:逐页 pump,断言全部命中锚点
  /// rect.bottom ≤ 视口高 - bottom inset(home indicator 不遮挡)。
  ///
  /// 与 safeAreaSweep(只查 top)互补;记录格式与 harness 一致,空列表 = 通过。
  Future<List<String>> bottomSafeAreaSweep(
    WidgetTester tester,
    MobileDevice device,
    List<(String name, Widget Function() page)> pages,
    Map<String, Finder> anchors,
  ) async {
    final failures = <String>[];
    final limit = device.size.height - device.safeArea.bottom;
    for (final (name, build) in pages) {
      await pumpOnDevice(tester, build(), device);
      // 两帧数据帧:fixture 数据落地后锚点才挂载(播放页画质条等)。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      for (final MapEntry(key: anchor, value: finder) in anchors.entries) {
        if (finder.evaluate().isEmpty) {
          failures.add('$name/$anchor: 锚点未命中(底部安全区)');
          continue;
        }
        for (final element in finder.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          // 视口外(cacheExtent 预构建)条目不在可见范畴,跳过。
          if (rect.top >= limit) continue;
          // 可见底缘 = min(布局 bottom, 所在滚动视口 bottom):滚动列表的
          // 部分/缓存条目布局矩形可越过视口底(渲染被裁剪),不构成视觉遮挡;
          // 视口底本身受 SafeArea 约束(=limit),失效时此处必然超标被抓。
          final scrollables = find.ancestor(
            of: find.byWidget(element.widget),
            matching: find.byType(Scrollable),
          );
          final visibleBottom = scrollables.evaluate().isEmpty
              ? rect.bottom
              : math.min(rect.bottom, tester.getRect(scrollables.first).bottom);
          if (visibleBottom > limit) {
            failures.add(
              '$name/$anchor: visibleBottom=$visibleBottom > '
              '视口高-bottom inset=$limit',
            );
          }
        }
      }
      print('[safeArea] $name 底部锚点(≤$limit): ${failures.isEmpty ? 'OK' : 'FAIL'}');
      // 排空本轮布局可能产生的既有溢出异常,避免污染后续 sweep 的归因
      // (溢出本身由 textScale/overflow sweep 如实记账)。
      drainPendingExceptions(tester);
    }
    resetViewport(tester);
    return failures;
  }

  testWidgets(
    'safeAreaNavUnobstructed:iPhone15 刘海下顶导航不遮挡,底部锚点不被 home indicator 遮挡',
    (tester) async {
      // 1) 首页/关注/设置三页:nav-* 锚点 rect.top ≥ 47。
      final topFailures = await safeAreaSweep(
        tester,
        _allPages.where((p) => p.$1 != 'play').toList(),
        _navAnchors(),
      );
      drainPendingExceptions(tester);
      expect(topFailures, isEmpty, reason: '顶导航锚点不得进入刘海遮挡区');

      // 2) 底部锚点:播放页 play-quality-*、关注页条目 + 密度切换锚点,
      //    rect.bottom ≤ 852 - 34。
      final bottomFailures = <String>[
        ...await bottomSafeAreaSweep(tester, kIphone15, [
          ('play', _playPage),
        ], {
          'play-quality-*': _playQualityFinder(),
        }),
        ...await bottomSafeAreaSweep(tester, kIphone15, [
          ('follow', () => _shellPage(const FollowView())),
        ], {
          'follow-entry-*': _followEntryFinder(),
          // follow-density-card:SegmentedButton 段 label Text 锚点。
          'follow-density-card': find.byKey(const Key('follow-density-card')),
        }),
      ];
      expect(bottomFailures, isEmpty, reason: '底部锚点不得进入 home indicator 遮挡区');
    },
  );

  testWidgets('proMaxSafeArea:ProMax(55/34) 抽查首页 nav 与播放页 play-quality', (
    tester,
  ) async {
    // 首页:nav-* + room-card-* 顶部 ≥ 55。
    final topFailures = await safeAreaSweep(tester, [
      ('home', () => _shellPage(const HomeView(site: 'all'))),
    ], {
      ..._navAnchors(),
      'room-card-*': _roomCardFinder(),
    }, device: kIphone15ProMax);
    drainPendingExceptions(tester);
    expect(topFailures, isEmpty, reason: 'ProMax 刘海下首页锚点不得被遮挡');

    // 播放页:play-quality-* 顶部 ≥ 55 且底部 ≤ 932 - 34。
    await pumpOnDevice(tester, _playPage(), kIphone15ProMax);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final chips = _playQualityFinder();
    expect(chips, findsWidgets, reason: '播放页应渲染画质 chip 锚点');
    final bottomLimit = kIphone15ProMax.size.height - kIphone15ProMax.safeArea.bottom;
    for (final element in chips.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(
        rect.top,
        greaterThanOrEqualTo(kIphone15ProMax.safeArea.top),
        reason: '画质 chip(${element.widget.key})不得进入刘海遮挡区',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(bottomLimit),
        reason: '画质 chip(${element.widget.key})不得被 home indicator 遮挡',
      );
    }
    drainPendingExceptions(tester);
  });

  testWidgets(
    'textScaleNoOverflow:1.0/1.15/1.3 三档大字体 × 首页/关注/设置/播放无溢出',
    (tester) async {
      final failures = <String>[];
      for (final (name, build) in _allPages) {
        failures.addAll(
          await textScaleSweep(tester, build, name: name, device: kIphone15),
        );
      }
      // 如实失败原则:任何失败记录 = 「大字体溢出,需响应式修复」,
      // 记录格式 `page@textScale <scale>: 异常首行`,不做 RenderFlex 抑制。
      // 注:实测溢出集中在 1.0 基线档(home 右溢 27px / play 右溢 267px),
      // 属既有窄屏布局缺陷在移动矩阵下的暴露,与字号缩放增量无关;
      // 修复时以 highDprSpotCheck 的失败列表为交叉证据。
      expect(failures, isEmpty);
    },
  );

  testWidgets('highDprSpotCheck:kIphone15@3x 与 AndroidSmall@2x 首页+播放页无溢出', (
    tester,
  ) async {
    final failures = await overflowSweep(tester, [
      ('home', () => _shellPage(const HomeView(site: 'all'))),
      ('play', _playPage),
    ], devices: const [kIphone15, kAndroidSmall]);
    expect(failures, isEmpty);
  });
}
