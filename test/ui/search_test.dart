/// 搜索弹框(SearchView 宿主于对话框)widget test:输入防抖后的结果行与直达项验证。
/// 无窗口后台验证:VM 中直接 pump WindowsApp,点顶栏 nav-search 拉起弹框,
/// fixture 搜索源走默认 provider(搜索已从独立页面改为全局弹框,对齐 web)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/search/application/search_provider.dart';
import 'package:zishu_flutter/src/features/search/application/search_source_provider.dart';
import 'package:zishu_flutter/src/features/search/widgets/search_result_tile.dart';
import 'package:zishu_flutter/src/shared/application/search_source.dart';

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

  /// 读取结果列表第一行命中 id(结果行锚点 search-result-N)。
  String firstResultId(WidgetTester tester) =>
      tester
          .widget<SearchResultTile>(find.byKey(const Key('search-result-0')))
          .hit
          .id;

  testWidgets('搜索结果显示平台与真实粉丝数,轮播不误显示未开播', (tester) async {
    const hit = SearchHit(
      id: '9527',
      anchor: '主播',
      title: '房间',
      avatar: '',
      cover: '',
      state: SearchHitState.replay,
      category: '网游',
      online: '',
      fans: '12345',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ZishuTheme.dark(),
          home: Scaffold(
            body: SearchResultTile(
              site: 'bilibili',
              hit: hit,
              onRowTap: () {},
              onAnchorTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('哔哩'), findsOneWidget);
    expect(find.text('粉丝 1.2万'), findsOneWidget);
    expect(find.text('轮播'), findsOneWidget);
    expect(find.text('未开播'), findsNothing);
  });

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

  testWidgets('searchTabs:弹框含 主播/房间 双档,默认落在房间档(对齐 web syncDefaultTab)', (
    tester,
  ) async {
    await openSearch(tester);

    expect(find.byKey(const Key('search-tab-anchor')), findsOneWidget);
    expect(find.byKey(const Key('search-tab-room')), findsOneWidget);
    // web `syncDefaultTab()`:roomSearchEnabled 优先,默认选中「房间」。
    // 「进入直播间」按钮只在房间档出现,用它作为当前档位的判据。
    expect(
      find.byKey(const Key('search-submit-room')),
      findsOneWidget,
      reason: '默认应为房间档(该档才渲染进入直播间按钮)',
    );
  });

  testWidgets('searchTabs:切到主播档后直达项与「进入直播间」均不出现', (tester) async {
    await openSearch(tester);

    await tester.tap(find.byKey(const Key('search-tab-anchor')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('search-submit-room')), findsNothing);
    // 占位文案随档位切换(对齐 web `inputPlaceholder`)。
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('search-input')))
          .decoration
          ?.hintText,
      contains('主播'),
    );

    await typeAndSettle(tester, '63136');
    expect(
      find.text('进入房间 63136'),
      findsNothing,
      reason: '主播档不展示房间号直达项',
    );
  });

  testWidgets('searchTabs:房间档保留房间号直达与「进入直播间」', (tester) async {
    await openSearch(tester);

    await typeAndSettle(tester, '63136');

    expect(find.byKey(const Key('search-submit-room')), findsOneWidget);
    expect(find.text('进入房间 63136'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('search-input')))
          .decoration
          ?.hintText,
      contains('房间'),
    );
  });

  testWidgets('searchTabs 双档隔离:切档把 type 传到查询层,两档各只出本档结果行', (
    tester,
  ) async {
    final source = _TypeAwareSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchSourceProvider.overrideWithValue(source)],
        child: const WindowsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('nav-search')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 默认房间档:查询带 type=rooms,结果只有房间行。
    await typeAndSettle(tester, '英雄');
    expect(source.types.last, SearchType.rooms, reason: '默认档(房间)查询携带 rooms');
    expect(firstResultId(tester), 'room-1');

    // 切主播档:以现有关键词按 anchors 重查,房间行被主播行整体替换。
    await tester.tap(find.byKey(const Key('search-tab-anchor')));
    await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(source.types.last, SearchType.anchors, reason: '主播档查询携带 anchors');
    expect(firstResultId(tester), 'anchor-1', reason: '主播档只渲染主播行');
    expect(
      find.byKey(const Key('search-result-1')),
      findsNothing,
      reason: '切档后另一档的旧行不得残留',
    );
    expect(tester.takeException(), isNull);
  });
}

/// 按档位返回不同命中、并记录每次请求 type 的 fake 数据源:
/// 验证 UI 双档(主播/房间)真正分流到查询层,而非共用同一批混合结果。
class _TypeAwareSource implements SearchSource {
  final List<SearchType?> types = [];

  @override
  List<String> get aggregateSites => const ['douyu'];

  SearchHit _hit(String id) => SearchHit(
    id: id,
    anchor: 'a-$id',
    title: 't-$id',
    avatar: '',
    cover: '',
    state: SearchHitState.live,
    category: 'c',
    online: '1',
  );

  @override
  Future<List<SearchHit>> search({
    required String site,
    required String keyword,
    int limit = 20,
    SearchType? type,
  }) async {
    types.add(type);
    return switch (type) {
      SearchType.anchors => [_hit('anchor-1')],
      SearchType.rooms => [_hit('room-1')],
      _ => [_hit('mixed-1')],
    };
  }
}
