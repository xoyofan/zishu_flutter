/// 搜索数据源 / 控制器单测:覆盖 fake 注入、全平台聚合隔离、fixture 旧行为一致、
/// 平台归属正确(不再依赖 fixture 反查)。
library;

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';

import 'package:zishu_flutter/src/features/search/application/search_provider.dart';
import 'package:zishu_flutter/src/features/search/application/search_source_provider.dart';
import 'package:zishu_flutter/src/shared/application/search_source.dart';

/// 构造最小 SearchHit。
SearchHit makeHit(String id) => SearchHit(
  id: id,
  anchor: 'a$id',
  title: 't$id',
  avatar: '',
  cover: '',
  state: SearchHitState.live,
  category: 'c$id',
  online: '1',
);

/// 简易 fake 数据源:要么整批返回 [hits],要么按 site 映射返回([bySite])。
class FakeSearchSource implements SearchSource {
  FakeSearchSource(List<SearchHit> hits) : _all = hits, _bySite = null;

  FakeSearchSource.bySite(Map<String, List<SearchHit>> bySite)
    : _all = const [],
      _bySite = bySite;

  final List<SearchHit> _all;
  final Map<String, List<SearchHit>>? _bySite;

  @override
  Future<List<SearchHit>> search({
    required String site,
    required String keyword,
    int limit = 20,
  }) async {
    if (_bySite != null) return _bySite[site] ?? const [];
    return _all;
  }
}

/// 占位 resolver:搜索路径不依赖它,仅满足 SiteRegistration 必填项。
class _DummyResolver implements RoomResolver {
  const _DummyResolver();

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async =>
      throw UnsupportedError('unused in search');
}

/// 可在 search 时抛错的 fake repo,用于验证单站失败隔离。
class _FakeRepo implements SearchRepository {
  _FakeRepo(this.hits, {this.throws = false});

  final List<SearchHit> hits;
  final bool throws;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    if (throws) throw StateError('boom ${request.site}');
    return SearchResult(site: request.site, hits: hits);
  }
}

SiteRegistration _reg(String id, SearchRepository repo) => SiteRegistration(
  id: id,
  name: id,
  capabilities: const SiteCapabilities(),
  resolver: const _DummyResolver(),
  search: repo,
);

/// 用 [source] 覆盖 searchSourceProvider,返回控制器与 container。
Future<(SearchController, ProviderContainer)> pumpController(
  WidgetTester tester,
  SearchSource source,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [searchSourceProvider.overrideWithValue(source)],
      child: const SizedBox.shrink(),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SizedBox)),
  );
  return (container.read(searchProvider.notifier), container);
}

/// 推进防抖 + resolve 落地两帧。
Future<void> settle(WidgetTester tester) async {
  await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  test('SearchSource 端口:ParserSearchSource 单站命中', () async {
    final registry = SiteRegistry()
      ..register(_reg('douyu', _FakeRepo([makeHit('d1')])));
    final source = ParserSearchSource(registry: registry);

    final hits = await source.search(site: 'douyu', keyword: 'x');
    expect(hits.map((h) => h.id), ['d1']);
  });

  test('ParserSearchSource:未注册/不支持搜索的站点抛 StateError', () async {
    final registry = SiteRegistry()
      ..register(_reg('douyu', _FakeRepo([makeHit('d1')])));
    final source = ParserSearchSource(registry: registry);

    expect(
      () => source.search(site: 'huya', keyword: 'x'),
      throwsA(isA<StateError>()),
    );
  });

  test('ParserSearchSource:site=all 并发聚合三站,单站失败被隔离', () async {
    final registry = SiteRegistry()
      ..register(_reg('douyu', _FakeRepo([makeHit('d1')])))
      ..register(_reg('huya', _FakeRepo([makeHit('h1')], throws: true)))
      ..register(_reg('bilibili', _FakeRepo([makeHit('b1')])));
    final source = ParserSearchSource(registry: registry);

    final hits = await source.search(site: 'all', keyword: 'x');
    expect(hits.map((h) => h.id).toList(), unorderedEquals(['d1', 'b1']));
  });

  test('FixtureSearchSource:keyword 命中 title/anchor/category', () async {
    const source = FixtureSearchSource();

    expect(
      (await source.search(site: 'douyu', keyword: '英雄')).map((h) => h.id),
      ['63136'],
      reason: '英雄联盟 房间应被 title 命中',
    );
    expect(
      (await source.search(site: 'douyu', keyword: '神超')).map((h) => h.id),
      ['63136'],
      reason: '神超 应被 anchorName 命中',
    );
    expect((await source.search(site: 'all', keyword: '云顶')).map((h) => h.id), [
      '288016',
    ], reason: '云顶之弈 应被 title/category 命中');
  });

  testWidgets('① fake 注入:命中列表正确且 searching 复位', (tester) async {
    final (ctrl, container) = await pumpController(
      tester,
      FakeSearchSource([makeHit('A'), makeHit('B')]),
    );

    ctrl.setQuery('anything');
    await settle(tester);

    final state = container.read(searchProvider);
    expect(state.hits.map((i) => i.hit.id).toList(), ['A', 'B']);
    expect(state.searching, isFalse);
    expect(state.direct, isNull);
  });

  testWidgets('③ 开关关闭走 fixture:fixture 路径结果与旧行为一致', (tester) async {
    final (ctrl, container) = await pumpController(
      tester,
      const FixtureSearchSource(),
    );

    ctrl.setQuery('英雄');
    await settle(tester);

    final state = container.read(searchProvider);
    expect(state.hits.map((i) => i.hit.id).toList(), ['63136']);
    expect(state.hits.first.site, 'douyu');
  });

  testWidgets('④ 平台归属正确:all 聚合下命中携带各自 site,无 fixture 反查', (tester) async {
    final (ctrl, container) = await pumpController(
      tester,
      FakeSearchSource.bySite({
        'douyu': [makeHit('D')],
        'huya': [makeHit('H')],
        'bilibili': [makeHit('B')],
      }),
    );

    ctrl.setSite('all');
    ctrl.setQuery('x');
    await settle(tester);

    final state = container.read(searchProvider);
    final byId = {for (final i in state.hits) i.hit.id: i.site};
    expect(byId, {'D': 'douyu', 'H': 'huya', 'B': 'bilibili'});
  });

  testWidgets('搜索失败不抛 widget:保留上次结果并以 error 标记', (tester) async {
    final source = _ToggleSource();
    final (ctrl, container) = await pumpController(tester, source);

    // 第一次查询成功,落地一条结果。
    ctrl.setQuery('ok');
    await settle(tester);
    expect(container.read(searchProvider).hits.map((i) => i.hit.id), ['OK']);

    // 第二次查询失败:不应抛到 widget,也不清空上次结果。
    source.fail = true;
    ctrl.setQuery('boom');
    await settle(tester);
    final after = container.read(searchProvider);
    expect(after.error, isNotNull);
    expect(after.searching, isFalse);
    expect(after.hits.map((i) => i.hit.id), ['OK']);
  });
}

/// 可切换成功/失败的 fake 数据源,用于验证失败容错。
class _ToggleSource implements SearchSource {
  bool fail = false;

  @override
  Future<List<SearchHit>> search({
    required String site,
    required String keyword,
    int limit = 20,
  }) async {
    if (fail) throw StateError('network down');
    return [makeHit('OK')];
  }
}
