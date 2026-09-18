/// 搜索弹框(SearchView 宿主于对话框)widget test:输入防抖后的结果行与直达项验证。
/// 无窗口后台验证:VM 中直接 pump WindowsApp,点顶栏 nav-search 拉起弹框,
/// fixture 搜索源走默认 provider(搜索已从独立页面改为全局弹框,对齐 web)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/search/application/search_provider.dart';

void main() {
  /// pump WindowsApp 并返回 router,便于导航到 /search。
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WindowsApp()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final element = tester.element(find.byType(Scaffold));
    return ProviderScope.containerOf(element).read(routerProvider);
  }

  /// 拉起搜索弹框并推进两帧(搜索的现行入口是顶栏 nav-search,不再是路由)。
  Future<GoRouter> openSearch(WidgetTester tester) async {
    final router = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('nav-search')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('search-dialog')), findsOneWidget);
    return router;
  }

  /// 输入关键词并按 300ms 防抖节奏推进时钟,直到结果落地渲染。
  Future<void> typeAndSettle(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('search-input')), text);
    // onChanged → searching=true 渲染进度条。
    await tester.pump();
    // 防抖到期 + resolve 落地。
    await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
    // 渲染结果帧。
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('输入「英雄」:防抖后出现搜索结果行锚点', (tester) async {
    await openSearch(tester);

    await typeAndSettle(tester, '英雄');

    // fixture 命中「英雄联盟」相关房间,结果行锚点 >0。
    expect(
      find.byKey(const Key('search-result-0')),
      findsOneWidget,
      reason: '至少应有一条命中结果行',
    );
    expect(find.byKey(const Key('search-result-1')), findsNothing);
  });

  testWidgets('输入纯数字「63136」:出现房间号直达项', (tester) async {
    await openSearch(tester);

    await typeAndSettle(tester, '63136');

    // 纯数字 → 房间号直达(直达 tile 文案「进入房间 63136」)。
    expect(find.text('进入房间 63136'), findsOneWidget);
  });

  testWidgets('「63136」直达项与结果行互不冲突:直达优先展示', (tester) async {
    await openSearch(tester);

    await typeAndSettle(tester, '63136');

    // 该关键词在 fixture 中无 title/anchor/category 命中,只有直达项。
    expect(find.byKey(const Key('search-result-0')), findsNothing);
    expect(find.text('进入房间 63136'), findsOneWidget);
  });
}
