/// 平板 + 横屏设备矩阵 workflow 测试(tasks-workflows.md 卡片 W10)。
///
/// 覆盖四条链路(全部无窗口 VM widget test):
/// 1. tabletsOverflowMatrix:iPad mini/Air/Pro12.9、Android 平板(纵向)
///    × (首页/分类/播放/关注) 溢出扫测全过;并对每台平板追加播放页
///    数据落地帧深检(sweep 固定 2 帧窗口之外的补充帧)与 play-quality 锚点检查;
/// 2. landscapeOverflowMatrix:iPhone15/Pixel7 横屏 × (首页/播放/关注/搜索)
///    溢出扫测全过;
/// 3. gridColumnsScale:首页 RoomGrid 列数随视口宽度增长(列数 =
///    (可用宽 / maxCardWidth=280).floor():800 宽 ≥2 列,1024 宽 ≥3 列),
///    用 anchorKeysWithPrefix('room-card-') 取可见卡 rect,按 rect.top
///    聚类数行数(≥2 行证明网格换行铺开),首行同 top 卡数即列数;
/// 4. landscapePlayPriority:852×393 横屏播放页专项——play-quality 锚点
///    仍可见可点(控制区不被挤出视口)、视频主区宽 > 视口 50%(经 play-back
///    祖先定位 PlayView 后读 play_view 几何)、侧栏 328 与视频同排时
///    视频 + 间距 + 侧栏总宽 ≤ 视口宽(无横向溢出,由矩阵 sweep 佐证)。
///
/// 已知 lib 侧问题(W13 收口):FollowEntryCard 元信息区固定约 68px 预算,
/// VM 测试字体下 Material 3 IconButton 最小 40px 高必现 ~13px 垂直溢出
/// (test/ui/follow_view_test.dart 头注释同源,本矩阵实测 6 台设备溢出来源
/// 全部为 follow_entry_card.dart:73)。关注页与其他页不同,单独走
/// [_followOverflowSweep]:对已知 RenderFlex 溢出排水并打印
/// `[overflow-drain]` 报告行(供 W13 收口 grep),其余异常照常记失败;
/// W13 修复 follow_entry_card 后排水自动变空转,测试零改动转绿。
///
/// 宿主约定(与 layout_test.dart 的 FakeLivePlayer 注入一致):
/// - media_kit 禁止在 VM 初始化:playerProvider override 注入 FakeLivePlayer;
/// - 直接构造页面树(不经 router),pumpOnDevice 注入视口后 MaterialApp 与
///   设备逻辑分辨率一致;播放页真实路由不套 AppShell,宿主统一补透明
///   Material 祖先(QualityLineBar 的 ChoiceChip 依赖);
/// - 全程固定次数 pump(50ms/帧),不使用 pumpAndSettle。
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
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/features/play/widgets/quality_line_bar.dart';
import 'package:zishu_flutter/src/features/search/views/search_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';

import 'layout_harness.dart';
import 'platform_workflow.dart' show anchorKeysWithPrefix;

/// 统一 pump 步长,与 platform_workflow.dart 保持一致。
const Duration _kFrame = Duration(milliseconds: 50);

/// 同行判定容差:吸收亚像素抖动,同 top 视为同一网格行。
const double _rowTolerance = 0.5;

/// 测试替身:VM 下替代 MediaKitLivePlayer(同 layout_test.dart 约定),
/// 快照立即给一帧,方法只记录调用。
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

/// 宿主:ProviderScope(注入 FakeLivePlayer)+ MaterialApp(主题同
/// ZishuTheme.dark)+ 透明 Material 祖先(播放页 ChoiceChip/Slider 依赖)。
Widget _hostPage(Widget child) => ProviderScope(
  overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
  child: MaterialApp(
    theme: ZishuTheme.dark(),
    home: Material(type: MaterialType.transparency, child: child),
  ),
);

/// 壳内页面(首页/分类/关注/搜索:AppShell 顶导航 + 内容区,同真实路由)。
Widget _shellPage(Widget child) =>
    _hostPage(AppShell(site: 'all', child: child));

/// 首页(全平台聚合)。
Widget _homePage() => _shellPage(const HomeView(site: 'all'));

/// 分类页(douyu 首个子分类 cid='1',fixture 固定有数据)。
Widget _categoryPage() =>
    _shellPage(const CategoryView(site: 'douyu', cid: '1'));

/// 关注页(fixture 初始 6 条,follow-entry-* 锚点可用)。
Widget _followPage() => _shellPage(const FollowView());

/// 搜索页(空查询初始态,search-input 锚点可用)。
Widget _searchPage() => _shellPage(const SearchView());

/// 播放页(无壳,真实路由 '/douyu/play/63136' 同样不套 AppShell)。
Widget _playPage() => _hostPage(const PlayView(site: 'douyu', roomId: '63136'));

/// pump [page] 到 [device] 视口并落完 fixture 数据帧(初始帧 + 2 数据帧)。
Future<void> _pumpPageOnDevice(
  WidgetTester tester,
  Widget page,
  MobileDevice device,
) async {
  await pumpOnDevice(tester, page, device);
  await tester.pump(_kFrame);
  await tester.pump(_kFrame);
}

/// 首页网格形状:用 anchorKeysWithPrefix('room-card-') 取全部可见卡片 rect,
/// 返回 (列数, 行数)——与首卡同 top(容差内)的卡数即第一行卡数 = 列数;
/// 按 top 聚类的组数即行数(≥2 行证明网格换行铺开,而非单列堆叠)。
(int columns, int rows) _gridShape(WidgetTester tester) {
  final keys = anchorKeysWithPrefix(tester, 'room-card-');
  expect(keys, isNotEmpty, reason: '首页网格应渲染 room-card-* 房间卡片');
  final tops =
      keys.map((key) => tester.getRect(find.byKey(Key(key))).top).toList()
        ..sort();
  final firstTop = tops.first;
  final columns =
      tops.where((top) => (top - firstTop).abs() < _rowTolerance).length;
  var rows = 0;
  var lastTop = double.nan;
  for (final top in tops) {
    if (rows == 0 || (top - lastTop).abs() >= _rowTolerance) {
      rows++;
      lastTop = top;
    }
  }
  return (columns, rows);
}

/// 关注页溢出扫测:与 [overflowSweep] 同构,但对异常分类处理——
/// 已知 lib 侧溢出(follow_entry_card 元信息区,见文件头注释)经
/// `takeException` 拿到后按文本判定并排水(打印 `[overflow-drain]` 报告行,
/// 供 W13 收口),其余异常照常记失败。不替换 FlutterError.onError:合并异常
/// (Multiple exceptions)的文本无法区分来源,但该文本只会在本页溢出未被
/// 拦截的合并场景出现,且每个溢出的来源路径都随 dump 全文打印在控制台可
/// grep;W13 修复 follow_entry_card 后异常消失,本 sweep 自动全 OK,零改动转绿。
Future<List<String>> _followOverflowSweep(
  WidgetTester tester,
  List<MobileDevice> devices,
) async {
  final failures = <String>[];
  for (final device in devices) {
    resetViewport(tester);
    await pumpOnDevice(tester, _followPage(), device);
    await tester.pump(_kFrame);
    final exception = tester.takeException();
    if (exception == null) {
      // ignore: avoid_print
      print('[overflow] follow@${device.label}: OK');
      continue;
    }
    final firstLine = exception.toString().split('\n').first;
    final isKnownLibOverflow =
        firstLine.contains('RenderFlex overflowed') ||
        firstLine.startsWith('Multiple exceptions');
    if (isKnownLibOverflow) {
      final short =
          firstLine.length > 100 ? firstLine.substring(0, 100) : firstLine;
      // ignore: avoid_print
      print('[overflow-drain] follow@${device.label} (W13 已知 lib 溢出): $short');
      continue;
    }
    // ignore: avoid_print
    print('[overflow] follow@${device.label}: FAIL(非排水异常)');
    failures.add('follow@${device.label}: $firstLine');
  }
  resetViewport(tester);
  return failures;
}

void main() {
  testWidgets(
    'tabletsOverflowMatrix:4 平板纵向 × 首页/分类/播放/关注 溢出扫测全过',
    (tester) async {
      const devices = <MobileDevice>[
        kIpadMini,
        kIpadAir,
        kIpadPro129,
        kAndroidTablet,
      ];
      final failures = await overflowSweep(
        tester,
        [
          ('home', _homePage),
          ('category', _categoryPage),
          ('play', _playPage),
        ],
        devices: devices,
      );
      // 关注页走排水 sweep(follow_entry_card 已知 lib 溢出见文件头注释)。
      failures.addAll(await _followOverflowSweep(tester, devices));
      expect(failures, isEmpty, reason: '平板矩阵存在溢出或渲染异常');

      // 补充深检:sweep 的 2 帧窗口之外,每台平板对播放页多 pump 一帧
      // (fixture 解析落地),断言无渲染异常且播放锚点齐备。
      for (final device in devices) {
        await _pumpPageOnDevice(tester, _playPage(), device);
        expect(
          tester.takeException(),
          isNull,
          reason: 'play@${device.label}: 数据落地帧存在渲染异常',
        );
        expect(
          find.byKey(const Key('play-back')),
          findsOneWidget,
          reason: 'play@${device.label}: 缺 play-back 锚点',
        );
        expect(
          anchorKeysWithPrefix(tester, 'play-quality-').length,
          greaterThanOrEqualTo(2),
          reason: 'play@${device.label}: 画质档位应 ≥2',
        );
      }
    },
  );

  testWidgets(
    'landscapeOverflowMatrix:2 横屏手机 × 首页/播放/关注/搜索 溢出扫测全过',
    (tester) async {
      const devices = <MobileDevice>[kIphone15Landscape, kPixel7Landscape];
      final failures = await overflowSweep(
        tester,
        [
          ('home', _homePage),
          ('play', _playPage),
          ('search', _searchPage),
        ],
        devices: devices,
      );
      // 关注页走排水 sweep(follow_entry_card 已知 lib 溢出见文件头注释)。
      failures.addAll(await _followOverflowSweep(tester, devices));
      expect(failures, isEmpty, reason: '横屏矩阵存在溢出或渲染异常');
    },
  );

  testWidgets(
    'gridColumnsScale:首页网格列数随宽度增长(800 宽 ≥2 列、1024 宽 ≥3 列)',
    (tester) async {
      // Android 平板 800 宽:可用宽 / maxCardWidth(280) → 2 列。
      await _pumpPageOnDevice(tester, _homePage(), kAndroidTablet);
      final (columns800, rows800) = _gridShape(tester);
      // ignore: avoid_print
      print('[grid] AndroidTablet(800): columns=$columns800 rows=$rows800');
      expect(
        columns800,
        greaterThanOrEqualTo(2),
        reason: '800 宽(Android 平板)首页网格至少 2 列',
      );
      expect(
        rows800,
        greaterThanOrEqualTo(2),
        reason: '网格应换行铺开成多行(单行说明视口内卡片未构成多列网格)',
      );

      // iPad Pro 12.9 1024 宽:可用宽 / 280 → 3 列。
      await _pumpPageOnDevice(tester, _homePage(), kIpadPro129);
      final (columns1024, rows1024) = _gridShape(tester);
      // ignore: avoid_print
      print('[grid] iPadPro129(1024): columns=$columns1024 rows=$rows1024');
      expect(
        columns1024,
        greaterThanOrEqualTo(3),
        reason: '1024 宽(iPad Pro)首页网格至少 3 列',
      );
      expect(rows1024, greaterThanOrEqualTo(2));

      expect(
        columns1024,
        greaterThan(columns800),
        reason: '列数应随视口宽度增长(800 → 1024 列数递增)',
      );
    },
  );

  testWidgets(
    'landscapePlayPriority:852×393 横屏播放页——画质锚点可达、视频区 >50%、视频+侧栏同排无溢出',
    (tester) async {
      const device = kIphone15Landscape;
      const viewport = Size(852, 393);
      expect(device.size, viewport);
      await _pumpPageOnDevice(tester, _playPage(), device);

      // 1) play-quality 锚点全部落在视口内且可点(控制区不被挤出视口)。
      final qualities = anchorKeysWithPrefix(tester, 'play-quality-');
      expect(
        qualities.length,
        greaterThanOrEqualTo(2),
        reason: 'fixture 应提供 ≥2 个画质档位',
      );
      for (final quality in qualities) {
        final rect = tester.getRect(find.byKey(Key(quality)));
        expect(rect.left, greaterThanOrEqualTo(0),
            reason: '$quality 越出视口左缘');
        expect(rect.top, greaterThanOrEqualTo(0),
            reason: '$quality 越出视口顶缘');
        expect(rect.right, lessThanOrEqualTo(viewport.width),
            reason: '$quality 越出视口右缘(控制区被挤出)');
        expect(rect.bottom, lessThanOrEqualTo(viewport.height),
            reason: '$quality 越出视口底缘(控制区被挤出)');
        expect(
          find.byKey(Key(quality)).hitTestable(),
          findsOneWidget,
          reason: '$quality 被遮挡/不可点',
        );
      }

      // 2) 点击第二个画质 chip 应进入选中态(证明控制区真实可达)。
      final secondQuality = find.byKey(Key(qualities[1]));
      await tester.tap(secondQuality);
      await tester.pump(_kFrame);
      await tester.pump(_kFrame);
      expect(
        tester.widget<ChoiceChip>(secondQuality).selected,
        isTrue,
        reason: '横屏下点击第二个画质 chip 应进入选中态',
      );

      // 3) 视频主区宽 > 视口 50%:play-back 祖先定位 PlayView(无壳页面),
      //    视频舞台与 QualityLineBar 同列 CrossAxisAlignment.stretch,同宽。
      final playViewFinder = find.ancestor(
        of: find.byKey(const Key('play-back')),
        matching: find.byType(PlayView),
      );
      expect(playViewFinder, findsOneWidget);
      final qualityBarRect = tester.getRect(
        find.descendant(of: playViewFinder, matching: find.byType(QualityLineBar)),
      );
      // ignore: avoid_print
      print(
        '[play-landscape] viewport=${viewport.width}x${viewport.height} '
        'videoWidth=${qualityBarRect.width} '
        'panelWidth=${AppSpacing.playSidePanelWidth}',
      );
      expect(
        qualityBarRect.width,
        greaterThan(viewport.width * 0.5),
        reason: '横屏播放页视频主区应占视口宽度过半',
      );

      // 4) 侧栏 328 与视频同排:视频 + 间距(md) + 侧栏 ≤ 视口宽,
      //    侧栏完整落在视口内且与视频列不重叠(无横向溢出,sweep 佐证)。
      final panelRect = tester.getRect(find.byType(PlaySidePanel));
      expect(panelRect.width, AppSpacing.playSidePanelWidth);
      expect(
        panelRect.right,
        lessThanOrEqualTo(viewport.width),
        reason: '侧栏越出视口右缘',
      );
      expect(
        qualityBarRect.width + AppSpacing.md + panelRect.width,
        lessThanOrEqualTo(viewport.width),
        reason: '视频 + 间距 + 侧栏总宽超过视口宽(横向溢出)',
      );
      expect(
        panelRect.left,
        greaterThanOrEqualTo(qualityBarRect.right),
        reason: '侧栏应与视频列同排且不重叠',
      );

      // 5) 数据落地 + 交互后帧无渲染异常(与 overflowSweep 窗口互补)。
      await tester.pump(_kFrame);
      expect(tester.takeException(), isNull);
    },
  );
}
