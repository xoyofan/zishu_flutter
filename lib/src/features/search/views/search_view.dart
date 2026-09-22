// SearchController 归 search_provider(搜索页控制器);material 同名类(搜索
// 匹配面板)本页不用,hide 掉以免 doc 注释引用产生 ambiguous_import。
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/widgets.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/search_provider.dart';
import '../widgets/search_direct_tile.dart';
import '../widgets/search_platform_chips.dart';
import '../widgets/search_result_tile.dart';

/// 首屏骨架行数(清单 §3.6):与一屏可见结果行数量级一致即可。
const int _skeletonRowCount = 5;

/// 搜索档位:主播 / 房间。对齐 web `SearchDialog.vue` 的 `activeTab`。
///
/// 档位持久在 `SearchState.type`(provider 层):切档经 [SearchController.setType]
/// 以现有关键词按新档位重新查询,查询携带 `SearchRequest.type` 走解析侧
/// `anchors|rooms` 分流 —— 与 web `type=anchors|rooms` 取数同构。主播档因此
/// 不再混入房间结果行,房间档不再混入主播行;房间号/链接直达卡仍属房间档
/// (主播档输入房间号无意义,既有口径)。
enum _SearchTab { anchor, room }

/// 搜索主体:输入框(autofocus)+ 平台 chips + 快捷直达 + 命中列表。
/// 键盘:Enter 执行(直达优先,否则进入首个结果),Esc 关闭。
///
/// 宿主形态有两种,本组件不自作主张:
/// - **对话框**(现行,对齐 web `SearchDialog.vue`):宿主传 [onNavigate]/[onClose],
///   本组件只上报目标 location 与关闭意图 —— 先关框再导航,避免弹框压在目标页之上;
/// - **页面态**(旧 `/search` 路由,现仅作深链兼容兜底):两者为 null 时自行
///   `context.push`,行为与旧实现一致。
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key, this.onNavigate, this.onClose});

  /// 命中/直达目标的路由位置由宿主接管;为 null 时自行 push(页面态)。
  final ValueChanged<String>? onNavigate;

  /// 关闭动作(Esc);为 null 时退化为 `context.pop()`(页面态)。
  final VoidCallback? onClose;

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// 当前生效档位:由 `SearchState.type`(用户显式选择)推导;该档在本平台
  /// 不可用时回退默认档(房间优先,同 web `syncDefaultTab`)。现有平台能力
  /// 矩阵中不存在「仅主播」站,回退只是显示层兜底,不改变查询档位。
  _SearchTab _resolveTab(
    SearchType type, {
    required bool anchorOk,
    required bool roomOk,
  }) {
    if (type == SearchType.rooms && roomOk) return _SearchTab.room;
    if (type == SearchType.anchors && anchorOk) return _SearchTab.anchor;
    if (roomOk) return _SearchTab.room;
    return _SearchTab.anchor;
  }

  @override
  void initState() {
    super.initState();
    // provider 为 keep-alive:再次进入搜索页回填上一次输入。
    _input.text = ref.read(searchProvider).query;
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Enter:直达项优先,其次进入首个命中结果。
  void _submit() {
    final search = ref.read(searchProvider);
    if (search.direct != null) {
      _openDirect(search.direct!);
      return;
    }
    if (search.hits.isNotEmpty) {
      _openRoom(search.hits.first);
    }
  }

  /// 进入直播间:仅直播中可进,未开播给出提示。
  void _openRoom(SearchHitItem item) {
    if (item.hit.state != SearchHitState.live) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('「${item.hit.anchor}」当前未开播')));
      return;
    }
    _inputFocus.unfocus();
    _go('/${item.site}/play/${item.hit.id}');
  }

  /// 头像/昵称进入主播主页。
  void _openAnchor(SearchHitItem item) {
    _inputFocus.unfocus();
    _go('/${item.site}/anchor/${item.hit.id}');
  }

  /// 打开直达项:链接直达固定 douyu;房间号直达跟随当前所选平台。
  void _openDirect(DirectTarget target) {
    final site = target.kind == DirectKind.link
        ? 'douyu'
        : ref.read(searchProvider).site;
    _inputFocus.unfocus();
    _go('/$site/play/${target.roomId}');
  }

  /// 跳转:对话框宿主接管则只上报 location(由宿主先关框再导航)。
  void _go(String location) {
    final navigate = widget.onNavigate;
    if (navigate != null) {
      navigate(location);
      return;
    }
    context.push(location);
  }

  /// Esc:对话框宿主接管则关框,否则退化为返回上一页(页面态)。
  void _close() {
    final close = widget.onClose;
    if (close != null) {
      close();
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final search = ref.watch(searchProvider);

    final anchorOk = PlatformBrandCatalog.supportsAnchorSearch(search.site);
    final roomOk = PlatformBrandCatalog.supportsRoomSearch(search.site);
    final supported = anchorOk || roomOk;
    final tab = _resolveTab(search.type, anchorOk: anchorOk, roomOk: roomOk);

    return CallbackShortcuts(
      bindings: {
        // Esc 关闭搜索(对话框宿主接管时只关框,页面态退化为返回上一页)。
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (supported)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: _SearchTabBar(
                tab: tab,
                anchorEnabled: anchorOk,
                roomEnabled: roomOk,
                // 切档写回 provider,并以现有关键词按新档位重新查询。
                onChanged: (next) => ref
                    .read(searchProvider.notifier)
                    .setType(
                      next == _SearchTab.room
                          ? SearchType.rooms
                          : SearchType.anchors,
                    ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                '该平台暂不支持主播/房间搜索',
                style: context.textSecondary.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: _buildSearchField(tokens, search, tab),
          ),
          const SearchPlatformChips(),
          Expanded(child: _buildResults(tokens, search, tab)),
        ],
      ),
    );
  }

  Widget _buildSearchField(
    ZishuTokens tokens,
    SearchState search,
    _SearchTab tab,
  ) {
    final field = TextField(
      // 测试锚点:定位/输入搜索关键词。
      key: const Key('search-input'),
      controller: _input,
      focusNode: _inputFocus,
      autofocus: true,
      onChanged: ref.read(searchProvider.notifier).setQuery,
      onSubmitted: (_) => _submit(),
      cursorColor: tokens.accent,
      style: context.textBody.copyWith(color: tokens.textPrimary),
      decoration: InputDecoration(
        // 占位文案随档位切换,对齐 web `inputPlaceholder`(SearchDialog.vue:255)。
        hintText: tab == _SearchTab.room ? '搜索房间名 / 房间号 / 直播间链接' : '搜索主播名',
        hintStyle: context.textBody.copyWith(color: tokens.textSecondary),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: tokens.textSecondary,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _EscHint(isDialog: true),
            if (search.query.isNotEmpty)
              IconButton(
                tooltip: '清空',
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: tokens.textSecondary,
                ),
                onPressed: () {
                  _input.clear();
                  ref.read(searchProvider.notifier).setQuery('');
                  _inputFocus.requestFocus();
                },
              ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        isDense: true,
        filled: true,
        fillColor: tokens.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.allMd,
          borderSide: BorderSide(color: tokens.accent),
        ),
      ),
    );

    // 「进入直播间」主操作只在房间档出现,对齐 web `SearchDialog.vue:46-48`。
    if (tab != _SearchTab.room) return field;
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          // 测试锚点:房间档的进入直播间主操作,同时充当档位判据。
          key: const Key('search-submit-room'),
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: tokens.accent,
            // 主题背景色做反差字色(与 parse_benchmark_view 的 brand 按钮同法);
            // 不引用 AppColors.* —— 静态守则要求主题色一律走 context.tokens。
            foregroundColor: tokens.background,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
          ),
          child: const Text('进入直播间'),
        ),
      ],
    );
  }

  Widget _buildResults(ZishuTokens tokens, SearchState search, _SearchTab tab) {
    // 未输入:引导空态。
    if (!search.hasQuery) {
      return _EmptyHint(
        icon: Icons.manage_search_rounded,
        title: '搜索主播 / 房间号 / 直播间链接',
        subtitle: '支持纯数字房间号直达,或粘贴 douyu.com 直播间链接',
      );
    }
    // 房间号/链接直达只属于房间档:主播档下输入房间号没有意义。
    final direct = tab == _SearchTab.room ? search.direct : null;
    final noun = tab == _SearchTab.room ? '房间' : '主播';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (search.searching)
          LinearProgressIndicator(
            minHeight: 2,
            color: tokens.accent,
            backgroundColor: tokens.surfaceRaised,
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (direct != null) ...[
                SearchDirectTile(
                  target: direct,
                  onTap: () => _openDirect(direct),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              // 首屏加载(清单 §3.6):原先的「搜索中…」文本占位换成结果行形状的
              // 骨架(时机 = 原占位出现的时机,判定分支不动);骨架行与
              // SearchResultTile 等高,结果落地时列表不跳动。
              // 顶部 LinearProgressIndicator 保留:增量搜索仍需要连续在转的
              // 「进行中」反馈,骨架行表达不了。
              if (search.searching && search.hits.isEmpty)
                Semantics(
                  label: '搜索中…',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _skeletonRowCount; i++)
                        SkeletonRow(key: Key('search-skeleton-$i')),
                    ],
                  ),
                ),
              for (final (index, item) in search.hits.indexed)
                SearchResultTile(
                  // 测试锚点:定位第 index 条搜索结果行。
                  key: Key('search-result-$index'),
                  hit: item.hit,
                  onRowTap: () => _openRoom(item),
                  onAnchorTap: () => _openAnchor(item),
                ),
              if (!search.searching && direct == null && search.hits.isEmpty)
                _EmptyHint(
                  icon: Icons.search_off_rounded,
                  // 空态名词随档位切换,对齐 web `searchNoun`。
                  title: '未找到与「${search.query.trim()}」相关的$noun',
                  subtitle: '换个关键词,或试试房间号 / 直播间链接',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 搜索档位切换条(主播 / 房间),对齐 web `SearchDialog.vue:14-18` 的 el-tabs。
///
/// 刻意不引 Material `TabBar`:那需要 `TabController` 并会把下划线铺满整行,
/// 而 web 的 el-tabs 是「左对齐、短下划线、按能力位增减档」——本组件直接复刻。
class _SearchTabBar extends StatelessWidget {
  const _SearchTabBar({
    required this.tab,
    required this.anchorEnabled,
    required this.roomEnabled,
    required this.onChanged,
  });

  final _SearchTab tab;
  final bool anchorEnabled;
  final bool roomEnabled;
  final ValueChanged<_SearchTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (anchorEnabled)
          _tab(
            context,
            _SearchTab.anchor,
            '主播',
            const Key('search-tab-anchor'),
          ),
        if (roomEnabled)
          _tab(context, _SearchTab.room, '房间', const Key('search-tab-room')),
      ],
    );
  }

  Widget _tab(BuildContext context, _SearchTab value, String label, Key key) {
    final tokens = context.tokens;
    final active = value == tab;
    return InkWell(
      key: key,
      onTap: () => onChanged(value),
      // 档位 tab:底为透明(靠选中下划线表达),hover 抬亮;
      // 键盘焦点/按压用 accent 低 alpha。
      hoverColor: tokens.surfaceRaised,
      splashColor: AppStateLayer.splashOf(tokens.accent),
      highlightColor: AppStateLayer.pressedOf(tokens.accent),
      focusColor: AppStateLayer.focusOf(tokens.accent),
      child: Padding(
        padding: const EdgeInsets.only(
          right: AppSpacing.lg,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.textBody.copyWith(
                color: active ? tokens.accent : tokens.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              height: 2,
              width: AppSpacing.xl,
              color: active ? tokens.accent : const Color(0x00000000),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索框尾部「Esc 关闭 / 返回」说明徽标。
class _EscHint extends StatelessWidget {
  const _EscHint({this.isDialog = false});

  /// 对话框形态:Esc 是「关闭」;页面形态(深链兑底)是「返回」。
  final bool isDialog;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.allSm,
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        isDialog ? 'Esc 关闭' : 'Esc 返回',
        style: context.textCaption.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// 空态提示(未输入引导 / 无结果)。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: tokens.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: context.textBody.copyWith(color: tokens.textSecondary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: context.textCaption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
