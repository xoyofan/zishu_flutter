/// W9 手机纵向溢出矩阵测试(tasks-workflows.md W9 卡)。
///
/// 5 档手机竖屏(harness 设备表手机子集:AndroidSmall 360x640、iPhoneSE
/// 375x667、iPhone15 393x852、Pixel7 412x915、iPhone15ProMax 430x932)×
/// 6 页面(首页/分类/播放/关注/搜索/设置)全扫:
/// - pagesOverflowMatrix:无 RenderFlex overflow(layout_harness.overflowSweep
///   逐组合收集,逐条打印 `[overflow] page@device` 报告行);
/// - navVisibleOnPhones:nav-home / nav-follow / nav-settings 锚点 rect 完整
///   落在根 Scaffold 的真实渲染视口内(与 layout_test 同款视口取法);
/// - playVideoNotSqueezed:窄屏(360x640、375x667)播放页视频舞台宽 >
///   视口宽 60%,且侧栏不与视频同行(竖屏下 PlaySidePanel rect.top 应大于
///   画质条 rect.top,即堆叠在视频下方);
/// - firstCardBelowNav:各尺寸首页首张 room-card rect.top ≥ 顶导航 rect.bottom。
///
/// ### 历史缺口(2026-09-09 W13 + U9 已全部修复,留档供追溯)
/// 以下均为 lib 侧布局缺口(非本测试宿主构造问题),修复后本文件自动转绿:
/// - 顶导航固定内容(Logo + nav-home/分类 + 3 IconButton)在渲染上恒定占据
///   x=16..404(内容宽约 388px):`home@AndroidSmall(360x640)` 报 RenderFlex
///   overflow 60px;360/375/393 宽下 nav-settings rect.right=404 超出渲染
///   视口右缘(navVisibleOnPhones 复现,412/430 起完整可见)。U9「窄屏底部
///   导航」未实现(W12 占位)。
/// - 播放页视频行 = Expanded + 固定 328px 侧栏同行,`play@` 全 5 尺寸溢出:
///   360 下 Row(play_view.dart:56)溢出 12px;375~430 下视频列被挤到
///   3~58px(实测 375 视频舞台宽 3.0px),连带 PlayerControlsBar/QualityLineBar
///   内部 Row 溢出 230~285px,且每尺寸另报 2 个 11px 垂直溢出。侧栏与视频
///   同行(panel.top=44 < quality.top=611)。U9「播放页侧栏堆叠」未实现(W12 占位)。
/// - `category@375/393/412`:内容区垂直溢出 2~3 处(14/9.4/4.5px,宽度越大
///   溢出越小);360x640 与 430x932 恰好无溢出。
/// - `follow@` 全 5 尺寸:FollowEntryCard 内容超出网格格高约 11px,每卡一个
///   异常(fixture 2 条 → 成对出现,takeException 首行为 "Multiple exceptions",
///   故 harness 归类非溢出异常)。
/// - room-card 0.6px 文本预算已修(68→72):home 网格在 375~430 各尺寸均无溢出。
///
/// 宿主约定(与 layout_test.dart / platform_workflow.dart 一致):
/// - media_kit 禁止在 VM 初始化:自带一份 FakeLivePlayer,经
///   playerProvider.overrideWithValue 注入,误入播放路径也不触原生内核;
/// - MaterialApp + ZishuTheme.dark + 透明 Material 祖先(播放页 QualityLineBar
///   的 ChoiceChip / 控制条 Slider 需要);
/// - 页面按 app_router.dart 路由对应关系**直接构造**(壳层页 = AppShell 包页,
///   播放页无壳),与真实路由渲染等价;这样 overflowSweep 的每页独立 pump
///   无需路由导航时序,初始即目标页面;
/// - 全程固定次数 pump,不使用 pumpAndSettle。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_shell.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/browse/views/category_view.dart';
import 'package:zishu_flutter/src/features/browse/views/home_view.dart';
import 'package:zishu_flutter/src/features/follow/views/follow_view.dart';
import 'package:zishu_flutter/src/features/follow/views/settings_view.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/features/play/widgets/player_controls.dart';
import 'package:zishu_flutter/src/features/search/views/search_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';

import 'layout_harness.dart';

// ignore_for_file: avoid_print

/// W9 的 5 档手机竖屏设备(窄 → 宽排列,取 kMobileDevices 手机子集)。
const List<MobileDevice> kPhones = <MobileDevice>[
  kAndroidSmall, // 360x640@2x
  kIphoneSe, // 375x667@2x
  kIphone15, // 393x852@3x
  kPixel7, // 412x915@2.625
  kIphone15ProMax, // 430x932@3x
];

/// 测试替身:VM 下替代 MediaKitLivePlayer,快照立即给一帧,方法只记录调用。
class _FakeLivePlayer implements LivePlayer {
  _FakeLivePlayer();

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

/// 页面宿主:ProviderScope(注入 FakeLivePlayer)+ MaterialApp(ZishuTheme +
/// 透明 Material 祖先)。与 layout_test/_TestApp 同约定,页面即路由页内容。
Widget _pageHost(Widget page) {
  return ProviderScope(
    overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
    child: MaterialApp(
      theme: ZishuTheme.dark(),
      home: Material(type: MaterialType.transparency, child: page),
    ),
  );
}

/// W9 页面集合:name 到路由等价页面构造器的记录列表。
/// 路由映射见 app_router.dart:`/all`、`/douyu/category/1`、
/// `/douyu/play/63136`(无壳)、`/follow`、`/search`、`/settings`。
List<(String, Widget Function())> _pages() => [
  ('home', () => _pageHost(_homePage())),
  ('category', () => _pageHost(_categoryPage())),
  ('play', () => _pageHost(_playPage())),
  ('follow', () => _pageHost(_followPage())),
  ('search', () => _pageHost(_searchPage())),
  ('settings', () => _pageHost(_settingsPage())),
];

/// `/all` 等价:应用壳层 + 全平台首页。
Widget _homePage() => const AppShell(
  site: 'all',
  child: HomeView(site: 'all'),
);

/// `/douyu/category/1` 等价:应用壳层 + 斗鱼分类页(fixture 首组 cid='1')。
Widget _categoryPage() => const AppShell(
  site: 'douyu',
  child: CategoryView(site: 'douyu', cid: '1'),
);

/// `/douyu/play/63136` 等价:播放页不套壳层。
Widget _playPage() => const PlayView(site: 'douyu', roomId: '63136');

/// `/follow` 等价。
Widget _followPage() => const AppShell(site: 'all', child: FollowView());

/// `/search` 等价。
Widget _searchPage() => const AppShell(site: 'all', child: SearchView());

/// `/settings` 等价。
Widget _settingsPage() => const AppShell(site: 'all', child: SettingsView());

/// room-card-* 房间卡片锚点(key 均为 `ValueKey<String>`,前缀匹配)。
Finder _roomCardFinder() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith('room-card-'),
);

/// play-quality-* 画质 chip 锚点(树序第一个)。
Finder _firstQualityFinder() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith('play-quality-'),
);

/// 顶部导航容器:_TopNav 的 topNavHeight 高 Container(nav-home 祖先),
/// 与 layout_test 同款定位。
Finder _topNavFinder() => find.ancestor(
  of: find.byKey(const Key('nav-home')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.constraints?.minHeight == AppSpacing.topNavHeight &&
        widget.constraints?.maxHeight == AppSpacing.topNavHeight,
  ),
);

/// 根 Scaffold 的真实渲染 rect(真实视口取法,与 layout_test 一致)。
Rect _viewportRect(WidgetTester tester) {
  final scaffoldElement = tester.element(find.byType(Scaffold).first);
  return tester.getRect(find.byWidget(scaffoldElement.widget));
}

/// pump 固定帧数(初始帧 + 2 个 50ms 数据帧),返回窗口内异常首行(null = 无)。
Future<String?> _pumpDataFrames(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  final exception = tester.takeException();
  return exception?.toString().split('\n').first;
}

void main() {
  testWidgets('pagesOverflowMatrix:5 手机尺寸 × 6 页面无 RenderFlex overflow', (
    tester,
  ) async {
    // harness overflowSweep 逐 (设备, 页面) 打印 `[overflow] page@device: OK/FAIL`,
    // 此处聚合断言失败记录为空。
    final failures = await overflowSweep(tester, _pages(), devices: kPhones);
    expect(failures, isEmpty, reason: '手机纵向矩阵存在溢出/异常:\n${failures.join('\n')}');
  });

  testWidgets('navVisibleOnPhones:5 尺寸下 nav-home/follow/settings 完整在视口内', (
    tester,
  ) async {
    final failures = <String>[];
    for (final device in kPhones) {
      resetViewport(tester);
      await pumpOnDevice(tester, _pageHost(_homePage()), device);
      final error = await _pumpDataFrames(tester);
      if (error != null) {
        failures.add('${device.label}: 渲染异常 $error');
      }

      // 渲染视口 = 根 Scaffold 真实 rect(pumpOnDevice 注入的物理视口与布局
      // 坐标一致,但仍按真实渲染 rect 求交,防 setSurfaceSize 类错位)。
      final viewport = _viewportRect(tester);
      for (final id in const ['nav-home', 'nav-follow', 'nav-settings']) {
        final anchor = find.byKey(Key(id));
        if (anchor.evaluate().isEmpty) {
          failures.add('${device.label}/$id: 锚点未命中');
          continue;
        }
        final rect = tester.getRect(anchor.first);
        // 求交判完整可见:锚点 rect 与视口 rect 的交集必须等于锚点自身。
        final hit = viewport.intersect(rect);
        final fullyVisible =
            hit.left >= rect.left - 0.01 &&
            hit.top >= rect.top - 0.01 &&
            hit.right <= rect.right + 0.01 &&
            hit.bottom <= rect.bottom + 0.01 &&
            rect.left >= viewport.left - 0.01 &&
            rect.top >= viewport.top - 0.01 &&
            rect.right <= viewport.right + 0.01 &&
            rect.bottom <= viewport.bottom + 0.01;
        if (fullyVisible) {
          print('[navVisible] ${device.label}/$id: OK');
        } else {
          print('[navVisible] ${device.label}/$id: FAIL');
          failures.add('${device.label}/$id: rect=$rect 超出视口 $viewport');
        }
      }
      resetViewport(tester);
    }
    expect(failures, isEmpty, reason: '顶导航锚点被裁切:\n${failures.join('\n')}');
  });

  testWidgets('playVideoNotSqueezed:窄屏播放页视频不被侧栏挤占/同行', (tester) async {
    // 360x640(AndroidSmall)与 375x667(iPhoneSE)两档窄竖屏。
    final failures = <String>[];
    for (final device in const [kAndroidSmall, kIphoneSe]) {
      resetViewport(tester);
      await pumpOnDevice(tester, _pageHost(_playPage()), device);

      // 逐帧泵到画质锚点挂载(fixture 解析在 2-3 帧内落地,上限 30 帧兜底)。
      var frames = 0;
      while (_firstQualityFinder().evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 50));
        frames++;
        if (frames > 30) break;
      }

      final qualityChip = _firstQualityFinder();
      if (qualityChip.evaluate().isEmpty) {
        failures.add('${device.label}: 30 帧内未出现 play-quality-* 锚点');
        resetViewport(tester);
        continue;
      }

      final error = tester.takeException();
      if (error != null) {
        failures.add(
          '${device.label}: 渲染异常 ${error.toString().split('\n').first}',
        );
      }

      // 渲染视口 = 播放页根 Column 的真实 rect(播放页无壳无 Scaffold,
      // 根布局即全视口)。
      final viewport = tester.getRect(find.byType(PlayView));

      // 视频舞台几何:控制条 PlayerControlsBar 与 Expanded(_VideoStage) 同列
      // (视频列 Column 内:视频舞台 Expanded → 控制条),列宽 =
      // 视频舞台宽,故取控制条祖先列的宽度度量视频舞台。
      final controlsBar = find.byType(PlayerControlsBar);
      final videoColumn = find
          .ancestor(of: controlsBar.first, matching: find.byType(Column))
          .first;
      final videoRect = tester.getRect(videoColumn);
      final qualityRect = tester.getRect(controlsBar.first);

      // 断言 1:视频舞台宽 > 视口宽的 60%。
      final minWidth = viewport.width * 0.6;
      if (videoRect.width > minWidth) {
        print(
          '[playSqueeze] ${device.label}/videoWidth: OK '
          '(${videoRect.width} > 60% x ${viewport.width})',
        );
      } else {
        print('[playSqueeze] ${device.label}/videoWidth: FAIL');
        failures.add(
          '${device.label}: 视频舞台宽 ${videoRect.width} 未超过 '
          '视口宽 60%($minWidth,视口 $viewport)',
        );
      }

      // 断言 2:侧栏不与视频同行——竖屏下侧栏应堆叠在视频下方,
      // 即 PlaySidePanel rect.top > 画质条 rect.top。
      final panel = find.byType(PlaySidePanel);
      if (panel.evaluate().isEmpty) {
        print('[playSqueeze] ${device.label}/sidePanelBelow: OK(侧栏已收起)');
      } else {
        final panelRect = tester.getRect(panel.first);
        if (panelRect.top > qualityRect.top) {
          print('[playSqueeze] ${device.label}/sidePanelBelow: OK');
        } else {
          print('[playSqueeze] ${device.label}/sidePanelBelow: FAIL');
          failures.add(
            '${device.label}: 侧栏与视频同行(panel.top=${panelRect.top} '
            '<= quality.top=${qualityRect.top})',
          );
        }
      }
      resetViewport(tester);
    }
    expect(failures, isEmpty, reason: '窄屏播放页视频被挤占:\n${failures.join('\n')}');
  });

  testWidgets('firstCardBelowNav:首卡不与顶导航重叠(>=768);<768 U9 无顶导航,首卡正常起排', (
    tester,
  ) async {
    final failures = <String>[];
    for (final device in kPhones) {
      resetViewport(tester);
      await pumpOnDevice(tester, _pageHost(_homePage()), device);
      final error = await _pumpDataFrames(tester);
      if (error != null) {
        failures.add('${device.label}: 渲染异常 $error');
      }

      final topNav = _topNavFinder();
      final cards = _roomCardFinder();
      final cardWidgets = tester.widgetList(cards).toList();
      if (cardWidgets.isEmpty) {
        failures.add('${device.label}: 首页未渲染房间卡片');
        resetViewport(tester);
        continue;
      }

      // 全部卡片中最早的 top(即首卡)不得越过顶导航底部。
      // U9 后 <768 顶导航不渲染(nav-* 迁移至底部导航),此时断言退化为
      // 首卡从内容区顶部正常起排(top >= 0),底部导航由 Scaffold 托底。
      var minTop = double.infinity;
      for (final widget in cardWidgets) {
        minTop = _min(minTop, tester.getRect(find.byWidget(widget)).top);
      }
      if (!tester.any(topNav)) {
        if (minTop >= 0) {
          print(
            '[firstCard] ${device.label}: OK '
            '(U9 无顶导航, card.top=$minTop)',
          );
        } else {
          print('[firstCard] ${device.label}: FAIL');
          failures.add('${device.label}: 首卡 top=$minTop < 0');
        }
      } else {
        final navRect = tester.getRect(topNav);
        if (minTop >= navRect.bottom) {
          print(
            '[firstCard] ${device.label}: OK '
            '(card.top=$minTop >= nav.bottom=${navRect.bottom})',
          );
        } else {
          print('[firstCard] ${device.label}: FAIL');
          failures.add(
            '${device.label}: 首卡 top=$minTop < 顶导航 bottom=${navRect.bottom}',
          );
        }
      }
      resetViewport(tester);
    }
    expect(failures, isEmpty, reason: '首页首卡与顶导航重叠:\n${failures.join('\n')}');
  });
}

/// dart:math 之外的本地 min(double, double),避免额外 import。
double _min(double a, double b) => a < b ? a : b;
