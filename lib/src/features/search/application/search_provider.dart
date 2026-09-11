/// 搜索应用层:平台(site)+ 关键词 → 命中列表与直达项。
/// Widget 只依赖 [SearchState] 与 live_parser 契约模型;命中数据源经
/// [searchSourceProvider] 注入(fixture / 真实解析由编译开关切换)。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/search_source.dart';
import '../application/search_source_provider.dart';

/// 输入防抖间隔:停顿 300ms 后才真正执行一次查询。
const Duration kSearchDebounce = Duration(milliseconds: 300);

/// 纯数字输入 → 房间号直达。
final RegExp _roomIdPattern = RegExp(r'^\d+$');

/// 含 douyu.com 的输入 → 链接直达,从链接中提取房间号。
final RegExp _douyuLinkPattern = RegExp(r'douyu\.com/(\d+)');

/// 直达项类型。
enum DirectKind { roomId, link }

/// 直达目标:纯数字房间号,或 douyu.com 链接解析出的房间。
class DirectTarget {
  const DirectTarget({required this.kind, required this.roomId, this.url});

  final DirectKind kind;

  /// 直达房间号。
  final String roomId;

  /// [DirectKind.link] 时的原始输入,用于副行展示。
  final String? url;
}

/// 命中项 UI 侧包装:携带平台归属,彻底去掉对 fixture 的反查。
///
/// [SearchHit] 契约无 site 字段,real 数据下无法靠 id 反查平台。改为在状态中
/// 显式保存 (site, hit) 对,UI 用 [site] 拼路由、用 [hit] 渲染。
class SearchHitItem {
  const SearchHitItem({required this.site, required this.hit});

  /// 命中所属平台 id。
  final String site;

  /// 真实命中数据(live_parser 契约模型)。
  final SearchHit hit;
}

/// 搜索页状态:当前平台 + 关键词 + 命中结果 + 直达项 + 错误标记。
class SearchState {
  const SearchState({
    this.site = 'douyu',
    this.query = '',
    this.searching = false,
    this.hits = const [],
    this.direct,
    this.error,
  });

  /// 当前平台 id(`all` = 全平台聚合)。
  final String site;

  /// 输入框当前关键词(未 trim,随输入实时更新)。
  final String query;

  /// 防抖等待/查询进行中(结果尚未刷新)。
  final bool searching;

  /// 命中的主播/房间列表(已携带平台归属)。
  final List<SearchHitItem> hits;

  /// 快捷直达项(房间号 / 链接),无则为 null。
  final DirectTarget? direct;

  /// 最近一次查询的错误信息(非空表示查询失败;结果保留上次,不抛到 widget)。
  final String? error;

  /// 关键词是否非空(去除首尾空白)。
  bool get hasQuery => query.trim().isNotEmpty;

  SearchState copyWith({
    String? site,
    String? query,
    bool? searching,
    List<SearchHitItem>? hits,
    DirectTarget? direct,
    bool clearDirect = false,
    String? error,
    bool clearError = false,
  }) {
    return SearchState(
      site: site ?? this.site,
      query: query ?? this.query,
      searching: searching ?? this.searching,
      hits: hits ?? this.hits,
      direct: clearDirect ? null : (direct ?? this.direct),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 搜索控制器:持有 query 与结果;输入防抖 300ms,
/// 以 generation fence 保证只有最新一次查询能写入状态。
class SearchController extends Notifier<SearchState> {
  int _generation = 0;
  late final SearchSource _source;

  @override
  SearchState build() {
    _source = ref.watch(searchSourceProvider);
    return const SearchState();
  }

  /// 切换平台,并按当前关键词重新查询(仍走防抖)。
  void setSite(String site) {
    if (site == state.site) return;
    state = state.copyWith(site: site, clearError: true);
    _scheduleSearch();
  }

  /// 关键词实时变更入口(由输入框 onChanged 触发)。
  void setQuery(String query) {
    state = state.copyWith(query: query, clearError: true);
    _scheduleSearch();
  }

  /// 防抖调度:每次变更使上一代查询失效。
  void _scheduleSearch() {
    final generation = ++_generation;
    final keyword = state.query.trim();
    if (keyword.isEmpty) {
      // 清空输入:立即回到空态,同时令未完成的查询全部过期。
      state = state.copyWith(
        searching: false,
        hits: const [],
        clearDirect: true,
        clearError: true,
      );
      return;
    }
    state = state.copyWith(searching: true, clearError: true);
    Future<void>.delayed(kSearchDebounce, () {
      // generation fence:期间有新输入/切平台,则丢弃本次过期查询。
      if (!ref.mounted || generation != _generation) return;
      _resolve(state.site, keyword, generation);
    });
  }

  /// 异步查询并写入状态;保留防抖与 generation fence。
  Future<void> _resolve(String site, String keyword, int generation) async {
    try {
      final hits = await _searchAttributed(site, keyword);
      // generation fence:期间有新输入/切平台,则丢弃本次结果。
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        searching: false,
        hits: hits,
        direct: _resolveDirect(keyword),
        clearError: true,
      );
    } on Object catch (e) {
      // 查询失败:保留上次结果与输入,仅标记 error;不抛到 widget、不整页空白。
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(searching: false, error: _errorMessage(e));
    }
  }

  /// 调用数据源并携带平台归属:[site] 为单站时整批归属该站;
  /// `all` 时并发聚合 [ParserSearchSource.aggregateSites],各站命中归属各自平台。
  ///
  /// 单站失败直接向上抛出(由 [_resolve] 统一以 [SearchState.error] 表达,
  /// 不整页空白、不抛到 widget);仅 `all` 聚合模式下才逐站隔离失败。
  Future<List<SearchHitItem>> _searchAttributed(String site, String keyword) async {
    if (site == 'all') {
      final results = await Future.wait([
        for (final s in ParserSearchSource.aggregateSites)
          _searchSiteIsolated(s, keyword),
      ]);
      return results.expand((items) => items).toList(growable: false);
    }
    final hits = await _source.search(site: site, keyword: keyword);
    return [for (final hit in hits) SearchHitItem(site: site, hit: hit)];
  }

  /// 单站隔离查询(仅用于 `all` 聚合):失败返回空,该站本轮空缺,
  /// 不影响其余平台结果,整页不空白。
  Future<List<SearchHitItem>> _searchSiteIsolated(String site, String keyword) async {
    try {
      final hits = await _source.search(site: site, keyword: keyword);
      return [for (final hit in hits) SearchHitItem(site: site, hit: hit)];
    } on Object {
      return const [];
    }
  }

  String _errorMessage(Object e) => e is StateError ? e.message : e.toString();

  /// 直达识别:纯数字 → 房间号;含 douyu.com → 链接直达。
  DirectTarget? _resolveDirect(String keyword) {
    if (_roomIdPattern.hasMatch(keyword)) {
      return DirectTarget(kind: DirectKind.roomId, roomId: keyword);
    }
    final match = _douyuLinkPattern.firstMatch(keyword);
    if (match != null) {
      return DirectTarget(kind: DirectKind.link, roomId: match.group(1)!, url: keyword);
    }
    return null;
  }
}

/// 搜索页全局 provider(keep-alive:返回搜索页保留上次输入与结果)。
final searchProvider = NotifierProvider<SearchController, SearchState>(SearchController.new);
