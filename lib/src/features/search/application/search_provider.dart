/// 搜索应用层:平台(site)+ 关键词 → 命中列表与直达项。
/// G0 阶段以 kFixtureRooms 为模拟搜索源,后续替换为解析 package 的搜索用例,
/// Widget 只依赖 [SearchState] 与 live_parser 契约模型。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/fixture_sources.dart';

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

/// 搜索页状态:当前平台 + 关键词 + 命中结果 + 直达项。
class SearchState {
  const SearchState({
    this.site = 'douyu',
    this.query = '',
    this.searching = false,
    this.hits = const [],
    this.direct,
  });

  /// 当前平台 id(`all` = 全平台聚合)。
  final String site;

  /// 输入框当前关键词(未 trim,随输入实时更新)。
  final String query;

  /// 防抖等待/查询进行中(结果尚未刷新)。
  final bool searching;

  /// 命中的主播/房间列表。
  final List<SearchHit> hits;

  /// 快捷直达项(房间号 / 链接),无则为 null。
  final DirectTarget? direct;

  /// 关键词是否非空(去除首尾空白)。
  bool get hasQuery => query.trim().isNotEmpty;

  SearchState copyWith({
    String? site,
    String? query,
    bool? searching,
    List<SearchHit>? hits,
    DirectTarget? direct,
    bool clearDirect = false,
  }) {
    return SearchState(
      site: site ?? this.site,
      query: query ?? this.query,
      searching: searching ?? this.searching,
      hits: hits ?? this.hits,
      direct: clearDirect ? null : (direct ?? this.direct),
    );
  }
}

/// 搜索控制器:持有 query 与结果;输入防抖 300ms,
/// 以 generation fence 保证只有最新一次查询能写入状态。
class SearchController extends Notifier<SearchState> {
  int _generation = 0;

  @override
  SearchState build() => const SearchState();

  /// 切换平台,并按当前关键词重新查询(仍走防抖)。
  void setSite(String site) {
    if (site == state.site) return;
    state = state.copyWith(site: site);
    _scheduleSearch();
  }

  /// 关键词实时变更入口(由输入框 onChanged 触发)。
  void setQuery(String query) {
    state = state.copyWith(query: query);
    _scheduleSearch();
  }

  /// 防抖调度:每次变更使上一代查询失效。
  void _scheduleSearch() {
    final generation = ++_generation;
    final keyword = state.query.trim();
    if (keyword.isEmpty) {
      // 清空输入:立即回到空态,同时令未完成的查询全部过期。
      state = state.copyWith(searching: false, hits: const [], clearDirect: true);
      return;
    }
    state = state.copyWith(searching: true);
    Future<void>.delayed(kSearchDebounce, () {
      // generation fence:期间有新输入/切平台,则丢弃本次过期查询。
      if (!ref.mounted || generation != _generation) return;
      state = _resolve(state.site, keyword);
    });
  }

  SearchState _resolve(String site, String keyword) {
    return state.copyWith(
      searching: false,
      hits: _filterRooms(site, keyword.toLowerCase()),
      direct: _resolveDirect(keyword),
    );
  }

  /// fixture 过滤:site 匹配且 title/anchorName/category 包含关键词(大小写不敏感)。
  List<SearchHit> _filterRooms(String site, String lowerKeyword) {
    return [
      for (final room in kFixtureRooms)
        if ((site == 'all' || room.site == site) &&
            (room.title.toLowerCase().contains(lowerKeyword) ||
                room.anchorName.toLowerCase().contains(lowerKeyword) ||
                room.category.toLowerCase().contains(lowerKeyword)))
          SearchHit(
            id: room.roomId,
            anchor: room.anchorName,
            title: room.title,
            // fixture 无独立头像字段,UI 端以昵称首字占位。
            avatar: '',
            cover: room.cover,
            // 约定:online 非空视为直播中,否则未开播。
            state: room.online.isEmpty ? SearchHitState.offline : SearchHitState.live,
            category: room.category,
            online: room.online,
          ),
    ];
  }

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

  /// 命中项所属平台(SearchHit 契约无 site 字段,all 混排时按 fixture 反查)。
  String siteOf(SearchHit hit) {
    for (final room in kFixtureRooms) {
      if (room.roomId == hit.id) return room.site;
    }
    return state.site;
  }
}

/// 搜索页全局 provider(keep-alive:返回搜索页保留上次输入与结果)。
final searchProvider = NotifierProvider<SearchController, SearchState>(SearchController.new);
