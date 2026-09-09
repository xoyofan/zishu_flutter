/// 首页(HomeView)widget test:平台切换与房间网格锚点验证。
/// 无窗口后台验证:VM 中直接 pump WindowsApp,fixture 数据源走默认 provider。
///
/// 注意:封面用 CachedNetworkImage,VM 中请求会被测试 binding 拦成 400,
/// 渲染 errorWidget 占位;因此全程不做图片断言,也不用 pumpAndSettle
/// (避免 pending timer),统一固定次数 pump。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/shared/application/fixture_sources.dart';

void main() {
  /// pump WindowsApp 并返回 router,便于导航到目标路由。
  ///
  /// 网格(GridView.builder)按视口惰性挂载卡片:默认 800x600 只渲染 4 张,
  /// 放大 surface 保证 10 个 fixture 卡片全部挂载,断言锚点总数才有意义。
  /// 断点几何直接写 tester.view(dpr=1):setSurfaceSize 只更新渲染 surface,
  /// MediaQuery 仍报默认 800×600,U9 后首页 chips key 随断点切换会误判。
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: WindowsApp()));
    // 两帧:首页(/all)骨架渲染 + fixture 数据落地。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final element = tester.element(find.byType(Scaffold));
    return ProviderScope.containerOf(element).read(routerProvider);
  }

  /// 统计当前树上 room-card-* 锚点数量。
  int roomCardCount(WidgetTester tester) {
    return tester
        .widgetList(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith('room-card-'),
          ),
        )
        .length;
  }

  testWidgets('初始 /douyu:渲染全部 fixture 房间卡片', (tester) async {
    final router = await pumpApp(tester);
    router.go('/douyu');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 每个样例房间都有唯一 room-card 锚点(等价于锚点总数 == kFixtureRooms.length)。
    for (final room in kFixtureRooms) {
      expect(
        find.byKey(Key('room-card-${room.site}-${room.roomId}')),
        findsOneWidget,
        reason: '缺少房间卡片锚点 ${room.site}/${room.roomId}',
      );
    }
    expect(roomCardCount(tester), kFixtureRooms.length);
  });

  testWidgets('点击 platform-tab-bilibili:路径切换后仍在房间网格,chip 进入选中态',
      (tester) async {
    final router = await pumpApp(tester);

    await tester.tap(find.byKey(const Key('home-platform-chip-bilibili')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 路由已切到 /bilibili(fixture 数据源不按 site 过滤,网格仍渲染全部样例)。
    expect(router.routeInformationProvider.value.uri.path, '/bilibili');
    expect(roomCardCount(tester), kFixtureRooms.length);
    for (final room in kFixtureRooms) {
      expect(
        find.byKey(Key('room-card-${room.site}-${room.roomId}')),
        findsOneWidget,
      );
    }
    // 当前平台 chip 为选中态(非 all 聚合时不显示平台角标,由实现内部处理)。
    final chip = tester.widget<FilterChip>(
      find.byKey(const Key('home-platform-chip-bilibili')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('鼠标 hover 房间卡片:不抛异常(hover 态不做像素断言)', (tester) async {
    await pumpApp(tester);

    final card = find.byKey(const Key('room-card-douyu-63136'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });
}
