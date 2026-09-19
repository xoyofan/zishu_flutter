/// 「我的分类」收藏星接线测试:分类页子分类 tile + 播放页头部。
///
/// 参考实现两处都有收藏入口(`CategoryGrid.vue` 的 `favoritable`、`PlayHeader.vue`
/// 的 `categoryFavoritable`),本仓此前只有顶栏「我的分类」管理弹窗,页面上没有
/// 快捷收藏;本套用例钉住两条入口与持久化写入。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/application/my_category_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

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

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

Future<void> _frames(WidgetTester tester, [int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

bool _isFavorited(ProviderContainer c, String site, String cid) =>
    c.read(myCategoriesProvider).any((e) => e.site == site && e.cid == cid);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('分类页:点 tile 收藏星 → 写入「我的分类」,再点移除', (tester) async {
    final container = await _pumpApp(tester);
    // 用户口径 2026-09-19:子分类网格在「裸分类索引」路由渲染(带 cid 直达
    // 房间列表)。tile '1' 属第一组,裸路由默认展示第一组。
    container.read(routerProvider).go('/douyu/category');
    await _frames(tester);

    final star = find.byKey(const Key('category-favorite-1'));
    expect(star, findsOneWidget, reason: '子分类 tile 应带收藏星');
    expect(_isFavorited(container, 'douyu', '1'), isFalse);

    await tester.tap(star);
    await _frames(tester);
    expect(_isFavorited(container, 'douyu', '1'), isTrue);
    // 收藏后星标为实心(选中态)。
    expect(
      tester.widget<Icon>(
        find.descendant(of: star, matching: find.byType(Icon)),
      ).icon,
      Icons.star_rounded,
    );

    await tester.tap(star);
    await _frames(tester);
    expect(_isFavorited(container, 'douyu', '1'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类页:点收藏星只收藏,不触发 tile 路由跳转', (tester) async {
    final container = await _pumpApp(tester);
    // 2026-09-20 口径:索引页 tile 点击是路由跳转,收藏星必须自己命中,
    // 不得穿透到 tile 把页面带去房间路由。
    final router = container.read(routerProvider);
    router.go('/douyu/category');
    await _frames(tester);

    await tester.tap(find.byKey(const Key('category-favorite-8')));
    await _frames(tester);

    expect(_isFavorited(container, 'douyu', '8'), isTrue);
    // 仍停留在分类索引页:路由未变,tile 网格还在。
    expect(
      router.routeInformationProvider.value.uri.path,
      '/douyu/category',
    );
    expect(find.byKey(const Key('category-item-8')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放页头部:收藏当前分类星标可切换(有 cid 才渲染)', (tester) async {
    final container = await _pumpApp(tester);
    // fixture 房间 63136:cid '1'、分类「英雄联盟」。
    container.read(routerProvider).go('/douyu/play/63136');
    await _frames(tester, 5);

    final star = find.byKey(const Key('play-category-favorite'));
    expect(star, findsOneWidget, reason: '房间带分类上下文时应显示收藏星');

    Icon starIcon() => tester.widget<Icon>(
          find.descendant(of: star, matching: find.byType(Icon)),
        );

    await tester.tap(star);
    await _frames(tester);
    expect(_isFavorited(container, 'douyu', '1'), isTrue);
    expect(
      starIcon().icon,
      Icons.star_rounded,
      reason: '收藏后星标应实心(星标已内嵌进分类徽标,web PlayHeader 同款)',
    );

    await tester.tap(star);
    await _frames(tester);
    expect(_isFavorited(container, 'douyu', '1'), isFalse);
    expect(starIcon().icon, Icons.star_border_rounded);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏上限 12:超出后不再增加且不抛异常', (tester) async {
    final container = await _pumpApp(tester);
    // 故意不等 _restore microtask:恢复完成前连续收藏不得被存储回放覆盖
    // (回归:restore 竞态曾静默丢条目)。
    final notifier = container.read(myCategoriesProvider.notifier);
    for (var i = 0; i < MyCategoryController.maxCount; i++) {
      await notifier.toggle(
        MyCategoryEntry(site: 'douyu', cid: 'seed$i', name: '种子$i'),
      );
    }
    expect(container.read(myCategoriesProvider), hasLength(MyCategoryController.maxCount));

    final ok = await notifier.toggle(
      const MyCategoryEntry(site: 'douyu', cid: 'overflow', name: '溢出'),
    );
    expect(ok, isFalse, reason: '已达上限应拒绝新增');
    expect(container.read(myCategoriesProvider), hasLength(MyCategoryController.maxCount));
  });
}
