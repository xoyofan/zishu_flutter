/// 壳层移动形态对齐测试:平台条(竖屏宫格 / 横屏单行 + ▼ 分类面板)、
/// 底栏项集与顺序、「我的关注」在播头像堆叠。
///
/// 规格真源是 web 源码(`NavPlatformStrip.vue` / `responsive-chrome.css` /
/// `NavSidebar.vue`),不是截图目测:
/// - 竖屏 `.nav-platform-strip__item { flex: 1 1 15% }` → 折行宫格、隐藏文字、不滚动;
/// - 横屏 `flex-wrap: nowrap` + `overflow-x: auto` → 单行横向滚动;
/// - 底栏 = `nav-group--top`(品牌/首页/分类/我的分类)+ `nav-group--tools`
///   (我的关注/搜索/主题/用户);本项目额外保留「动态」入口(产品要求);
/// - `.nav-follow-avatars`:最多 3 个在播头像,`1.48rem` + 32% 重叠,
///   无在播回落星形图标。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line,
          [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

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

/// 空关注列表:验证「无在播时回落星形图标」,同时避免真实存储/网络。
class _EmptyFollowController extends FollowController {
  @override
  List<FollowEntry> build() => const <FollowEntry>[];
}

const double _kBottomNavHeight = AppSpacing.bottomNavHeight;

Future<GoRouter> _pump(
  WidgetTester tester,
  Size size, {
  bool emptyFollows = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        // 只测「无在播回落星形」时注入空关注表;其余用例走 fixture 种子。
        if (emptyFollows) followProvider.overrideWith(_EmptyFollowController.new),
      ],
      child: const WindowsApp(),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
      .read(routerProvider);
}

Future<void> _frames(WidgetTester tester, [int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('平台条:方向决定形态', () {
    testWidgets('竖屏 390×844:折行宫格(两行)+ 每项独立 ▼,不横向滚动', (tester) async {
      await _pump(tester, const Size(390, 844));

      final ids =
          PlatformBrandCatalog.navigationPlatforms.map((b) => b.id).toList();
      for (final id in ids) {
        expect(
          find.byKey(Key('platform-tab-$id')),
          findsOneWidget,
          reason: '平台条缺少平台入口 $id',
        );
        expect(
          find.byKey(Key('platform-strip-cat-$id')),
          findsOneWidget,
          reason: '平台条缺少 ▼ 分类入口 $id',
        );
      }

      // 两行:所有 tab 顶部只出现两种 y。
      final tops = <int>{
        for (final id in ids)
          tester.getTopLeft(find.byKey(Key('platform-tab-$id'))).dy.round(),
      };
      expect(tops.length, 2, reason: '竖屏平台条应为两行宫格');

      // 宫格不由横向滚动容器承载(单行才是)。
      expect(
        find.ancestor(
          of: find.byKey(const Key('platform-tab-douyu')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
        reason: '竖屏宫格不应包在横向滚动容器里',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('横屏 844×390:单行横向滚动(同一 y),标签隐藏', (tester) async {
      await _pump(tester, const Size(844, 390));

      final ids =
          PlatformBrandCatalog.navigationPlatforms.map((b) => b.id).toList();
      final tops = <int>{
        for (final id in ids)
          tester.getTopLeft(find.byKey(Key('platform-tab-$id'))).dy.round(),
      };
      expect(tops.length, 1, reason: '横屏平台条应为单行');

      expect(
        find.ancestor(
          of: find.byKey(const Key('platform-tab-douyu')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsWidgets,
        reason: '横屏单行平台条应由横向滚动容器承载(12 项放不下)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点 ▼ 打开平台分类面板:可关闭、可跳子分类页', (tester) async {
      final router = await _pump(tester, const Size(390, 844));

      await tester.tap(find.byKey(const Key('platform-strip-cat-douyu')));
      await _frames(tester);
      expect(
        find.byKey(const Key('platform-cat-sheet')),
        findsOneWidget,
        reason: '▼ 应打开分类底部面板(web nav-cat-sheet)',
      );

      // 关闭:面板消失,路由不变。
      await tester.tap(find.byKey(const Key('platform-cat-sheet-close')));
      await _frames(tester);
      expect(find.byKey(const Key('platform-cat-sheet')), findsNothing);

      // 再开一次并选一个子分类:面板关闭 + 跳该平台子分类页。
      await tester.tap(find.byKey(const Key('platform-strip-cat-douyu')));
      await _frames(tester);
      // fixture 第一组子分类 cid=1(英雄联盟)。
      await tester.tap(find.byKey(const Key('platform-cat-item-1')));
      await _frames(tester);
      expect(find.byKey(const Key('platform-cat-sheet')), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/douyu/category/1',
        reason: '选分类后应跳到该平台子分类页',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('底栏项集与顺序', () {
    testWidgets('390×844:项序对齐 web(top 组 + tools 组)且保留动态', (tester) async {
      await _pump(tester, const Size(390, 844));

      // web 底栏 = 品牌/首页/分类/我的分类 | 我的关注/搜索/主题/用户;
      // 本项目在工具组保留「动态」(产品要求),去掉 web 的「用户」独立项
      // (登录/设置在顶栏与「我的」入口承担)。
      const order = [
        'nav-brand',
        'nav-home',
        'nav-category',
        'nav-my-category',
        'nav-follow',
        'nav-search',
        'nav-time',
        'nav-theme',
        'nav-settings',
      ];
      for (final id in order) {
        expect(
          find.byKey(Key(id)),
          findsOneWidget,
          reason: '底栏缺少 $id(项集应对齐 web 并保留动态)',
        );
      }

      // 顺序:按 x 递增。
      var lastX = -1.0;
      for (final id in order) {
        final x = tester.getCenter(find.byKey(Key(id))).dx;
        expect(x, greaterThan(lastX), reason: '$id 的位置应在其前一项右侧');
        lastX = x;
      }

      expect(
        find.byKey(const Key('bottom-nav')),
        findsOneWidget,
        reason: '移动端应渲染底栏容器',
      );

      // 全部落在底部导航带内(不被裁剪)。
      final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final bandTop = height - _kBottomNavHeight;
      for (final id in order) {
        final rect = tester.getRect(find.byKey(Key(id)));
        expect(rect.top, greaterThanOrEqualTo(bandTop - 0.01),
            reason: '$id 不在底部导航带内');
        expect(rect.right, lessThanOrEqualTo(390 + 0.01),
            reason: '$id 超出视口右侧(9 项需收敛而不是溢出)');
        expect(rect.bottom, lessThanOrEqualTo(height + 0.01));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「我的分类」:打开管理弹窗(触屏没有 hover 浮层)', (tester) async {
      await _pump(tester, const Size(390, 844));

      await tester.tap(find.byKey(const Key('nav-my-category')));
      await _frames(tester);
      expect(
        find.textContaining('我的分类('),
        findsOneWidget,
        reason: '底栏「我的分类」应打开管理弹窗(与顶栏 hover 里的管理分类同一弹窗)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('1440×900 桌面:不出现移动形态,顶栏保留动态/设置', (tester) async {
      await _pump(tester, const Size(1440, 900));

      expect(
        find.byKey(const Key('platform-strip-cat-douyu')),
        findsNothing,
        reason: '桌面顶栏平台 tab 没有 ▼(那是移动平台条的形态)',
      );
      expect(
        find.byKey(const Key('bottom-nav')),
        findsNothing,
        reason: '桌面不渲染移动底栏',
      );
      // 顶栏仍保留产品要求的两项。
      expect(find.byKey(const Key('nav-time')), findsOneWidget);
      expect(find.byKey(const Key('nav-settings')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('「我的关注」在播头像堆叠', () {
    testWidgets('有在播:顶栏显示最多 3 个头像,且按 32% 重叠', (tester) async {
      await _pump(tester, const Size(1440, 900));

      final avatars = find.byWidgetPredicate(
        (w) =>
            w.key is Key &&
            w.key.toString().contains('nav-follow-avatar-'),
      );
      expect(
        avatars.evaluate().length,
        3,
        reason: 'web NAV_FOLLOW_AVATAR_LIMIT = 3;fixture 有 5 条在播',
      );

      // 重叠:相邻头像左边界间距 = size × (1 - 0.32)。
      final rects = [
        for (final e in avatars.evaluate()) tester.getRect(find.byWidget(e.widget)),
      ]..sort((a, b) => a.left.compareTo(b.left));
      final step = rects[1].left - rects[0].left;
      expect(step, closeTo(23.68 * (1 - 0.32), 0.5),
          reason: '相邻头像间距应为 size×0.68(32% 重叠)');
      expect(rects[1].left, lessThan(rects[0].right),
          reason: '头像必须互相叠住,而不是并排');
      expect(tester.takeException(), isNull);
    });

    testWidgets('无在播:回落星形图标(不显示头像)', (tester) async {
      await _pump(tester, const Size(1440, 900), emptyFollows: true);

      final avatars = find.byWidgetPredicate(
        (w) => w.key is Key && w.key.toString().contains('nav-follow-avatar-'),
      );
      expect(avatars, findsNothing, reason: '没有在播时不应渲染头像堆叠');
      expect(
        find.descendant(
          of: find.byKey(const Key('nav-follow')),
          matching: find.byIcon(Icons.star_border_rounded),
        ),
        findsOneWidget,
        reason: '无在播时回落星形图标(web v-else 分支)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('移动底栏「关注」项同样用头像堆叠', (tester) async {
      await _pump(tester, const Size(390, 844));

      final avatars = find.byWidgetPredicate(
        (w) => w.key is Key && w.key.toString().contains('nav-follow-avatar-'),
      );
      expect(
        avatars.evaluate().length,
        3,
        reason: '底栏关注项也要显示在播头像(web 同一 nav-item--follow)',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
