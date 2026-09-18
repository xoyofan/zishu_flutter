/// 分类页(CategoryView)widget test:分组 tab 与子分类 tile 锚点验证。
/// 无窗口后台验证:VM 中直接 pump WindowsApp,fixture 数据源走默认 provider。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/widgets/browse_sidebar.dart';

void main() {
  /// pump WindowsApp 并返回 router,便于导航到目标路由。
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WindowsApp()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final element = tester.element(find.byType(Scaffold));
    return ProviderScope.containerOf(element).read(routerProvider);
  }

  /// 统计当前树上满足前缀条件的锚点数量。
  int keyCount(WidgetTester tester, String prefix) {
    return tester
        .widgetList(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith(prefix),
          ),
        )
        .length;
  }

  testWidgets('分类页桌面常驻目录栏:>=768 出现 BrowseSidebar,手机(<768)不出现', (tester) async {
    // 参考实现:CategoryIndexView/CategoryRoomsView 都包在 AppLayout 里,而
    // AppLayout.usesDrawerLayout 含 category-index/category-rooms —— 分类页与
    // 首页共用同一条左侧抽屉栏(drawerEligible 只在播放页关闭)。
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;

    tester.view.physicalSize = const Size(1280, 900);
    var router = await pumpApp(tester);
    router.go('/douyu/category');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byType(BrowseSidebar),
      findsOneWidget,
      reason: '桌面分类页应挂左侧目录栏',
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(390, 844);
    router = await pumpApp(tester);
    router.go('/douyu/category');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byType(BrowseSidebar),
      findsNothing,
      reason: '手机端平台切换由平台条承担,不挂目录栏',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('/douyu/category:分组 tab 锚点 >0,点击分组后子分类 tile 出现',
      (tester) async {
    final router = await pumpApp(tester);
    // 路由表为 /:site/category/:cid,样例子分类 cid '1' 属于第一组「网游竞技」。
    router.go('/douyu/category/1');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 左侧分组锚点存在(fixture 3 组)。
    expect(keyCount(tester, 'category-group-'), greaterThan(0));

    // 点击第一个分组(fixture 第一组 id '1')。
    await tester.tap(find.byKey(const Key('category-group-1')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 右侧出现子分类 tile 锚点:第一组为 英雄联盟(1)/无畏契约(8)/云顶之弈(3203)。
    expect(keyCount(tester, 'category-item-'), greaterThan(0));
    expect(find.byKey(const Key('category-item-1')), findsOneWidget);
    expect(find.byKey(const Key('category-item-8')), findsOneWidget);
    expect(find.byKey(const Key('category-item-3203')), findsOneWidget);
  });

  testWidgets('点击子分类 tile:选中态切换且不抛异常', (tester) async {
    final router = await pumpApp(tester);
    router.go('/douyu/category/1');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('category-group-1')));
    await tester.pump(const Duration(milliseconds: 50));

    // 切到第二组再点其中的子分类,验证 tile 可交互且无异常。
    await tester.tap(find.byKey(const Key('category-group-2')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('category-item-16')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    // 第二组「娱乐天地」的子分类 tile 仍在(选择动作只影响房间区,不销毁 tiles)。
    expect(find.byKey(const Key('category-item-16')), findsOneWidget);
  });
}
