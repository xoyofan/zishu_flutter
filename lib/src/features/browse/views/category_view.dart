import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/retry_button.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/browse_provider.dart';
import '../application/my_category_provider.dart';
import '../widgets/browse_sidebar.dart';
import '../widgets/room_grid.dart';

/// 分类页,两种形态对齐 web:
/// - `/:site/category`(裸路由,顶栏「分类」入口):分组 tabs + 子分类网格,
///   **只显示分类不显示房间**(对齐 web `CategoryIndexView.vue`);
/// - `/:site/category/:cid`(带具体分类):纯房间列表,由
///   [browseRoomsProvider] 按 (site, cid) 拉取(对齐 web `CategoryRoomsView.vue`)。
class CategoryView extends ConsumerStatefulWidget {
  const CategoryView({super.key, required this.site, this.cid, this.categoryKey});

  /// `all` 表示全平台聚合(组名前展示平台色点)。
  final String site;

  /// 子分类 id(来自 `/:site/category/:cid` 路由)。
  final String? cid;

  /// 分类名(来自 `/all/category/:key` 路由,可匹配组名或子分类名)。
  final String? categoryKey;

  @override
  ConsumerState<CategoryView> createState() => _CategoryViewState();
}

class _CategoryViewState extends ConsumerState<CategoryView> {
  /// 左侧分组栏宽度。
  static const double _tabsWidth = 132;

  /// 用户手动选中的分组;null 表示按路由参数或默认规则推导。
  String? _selectedGroupId;

  @override
  void didUpdateWidget(covariant CategoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换站点或路由参数变化时重置选择状态。
    if (oldWidget.site != widget.site ||
        oldWidget.cid != widget.cid ||
        oldWidget.categoryKey != widget.categoryKey) {
      setState(() => _selectedGroupId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(browseCategoriesProvider(widget.site));
    return switch (categoriesAsync) {
      // value 非 null 即有数据。
      AsyncValue(:final value?) =>
        value.groups.isEmpty
            ? _HintPlaceholder(icon: Icons.category_rounded, message: '暂无分类数据,下拉或稍后再试')
            : _content(context, value),
      AsyncValue(:final error?) => _ErrorRetry(
        message: '分类加载失败：$error',
        onRetry: () => ref.read(browseCategoriesProvider(widget.site).notifier).refresh(),
      ),
      _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    };
  }

  /// 分组 tabs + 右侧内容区的主内容。
  ///
  /// 用户口径(2026-09-20):**带具体分类上下文进入**(顶栏 hover 分类、
  /// 「我的分类」、侧栏/索引页分类点击 —— 路由带 cid/key 且能命中)时,
  /// 只显示该分类下的房间列表:不要分组 tabs、不要子分类网格,侧栏目录
  /// 也隐藏(对齐 web `CategoryRoomsView.vue`:选定分类 = 纯房间页)。
  /// 裸 `/site/category`(顶栏「分类」入口,分类索引)**只显示分类**:
  /// 分组 tabs + 子分类网格铺满内容区,没有底部房间区;点子分类 tile 走
  /// 路由跳转到带 cid 的房间页(对齐 web `CategoryIndexView.vue` 里
  /// `CategoryGrid` 的 RouterLink 行为)。
  Widget _content(BuildContext context, CategoryResult result) {
    final tokens = context.tokens;
    final group = _pickGroup(result.groups);
    final item = _pickItem(group);
    final isPhone = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;
    // 路由带具体分类且能解析命中 → 纯房间列表形态。
    final hasConcreteCategory =
        (widget.cid != null && widget.cid!.isNotEmpty) ||
        (widget.categoryKey != null && widget.categoryKey!.isNotEmpty && item != null);
    // 路由带了 cid 但**没命中分类索引**(item==null)时,仍按该 cid 渲染纯房间
    // 列表,而不是退到分类索引页。原因:卡片 chip 点进来的 cid 是**过滤 id**
    // 而非分类 id —— Twitch 游戏标签 `tag:<id>`、语言 `lang:<CODE>` 等,
    // 它们本来就不在分类树里,靠分类索引匹配必然落空,落空就等于「点了没反应」。
    if (hasConcreteCategory &&
        item == null &&
        widget.cid != null &&
        widget.cid!.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isPhone) BrowseSidebar(site: widget.site),
          if (!isPhone) Container(width: 1, color: tokens.border),
          Expanded(
            child: _RoomSection(site: widget.site, cid: widget.cid!),
          ),
        ],
      );
    }
    if (hasConcreteCategory && item != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isPhone) BrowseSidebar(site: widget.site),
          if (!isPhone) Container(width: 1, color: tokens.border),
          Expanded(
            child: _RoomSection(site: widget.site, cid: item.cid),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isPhone) BrowseSidebar(site: widget.site),
        if (!isPhone) Container(width: 1, color: tokens.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GroupTabs(
                groups: result.groups,
                selectedGroupId: group.id,
                isAll: widget.site == 'all',
                width: _tabsWidth,
                site: widget.site,
                onGroupTap: (target) => setState(() => _selectedGroupId = target.id),
              ),
              Container(width: 1, color: tokens.border),
              Expanded(
                child: _CategoryGrid(site: widget.site, group: group),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 解析当前选中的分组:手动选择 > cid 归属 > categoryKey 匹配 > 第一组。
  CategoryGroup _pickGroup(List<CategoryGroup> groups) {
    final selectedId = _selectedGroupId;
    if (selectedId != null) {
      for (final group in groups) {
        if (group.id == selectedId) return group;
      }
    }
    final cid = widget.cid;
    if (cid != null && cid.isNotEmpty) {
      for (final group in groups) {
        if (group.items.any((item) => item.cid == cid)) return group;
      }
    }
    // key 既可能是分类名(web 侧 `/all/category/:key`),也可能是 cid
    // (顶栏 hover 与「我的分类」按 cid 跳转),两者都要命中。
    final key = widget.categoryKey;
    if (key != null && key.isNotEmpty) {
      for (final group in groups) {
        if (group.name == key ||
            group.items.any((item) => item.name == key || item.cid == key)) {
          return group;
        }
      }
    }
    return groups.first;
  }

  /// 解析当前选中的子分类:cid 精确匹配,其次 categoryKey 匹配子分类名或 cid。
  CategoryItem? _pickItem(CategoryGroup group) {
    final cid = widget.cid;
    if (cid != null && cid.isNotEmpty) {
      for (final item in group.items) {
        if (item.cid == cid) return item;
      }
    }
    final key = widget.categoryKey;
    if (key != null && key.isNotEmpty) {
      for (final item in group.items) {
        if (item.name == key || item.cid == key) return item;
      }
    }
    return null;
  }
}

/// 左侧大类分组栏。
class _GroupTabs extends StatelessWidget {
  const _GroupTabs({
    required this.groups,
    required this.selectedGroupId,
    required this.isAll,
    required this.width,
    required this.site,
    required this.onGroupTap,
  });

  final List<CategoryGroup> groups;
  final String selectedGroupId;
  final bool isAll;
  final double width;
  final String site;
  final ValueChanged<CategoryGroup> onGroupTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: width,
      color: tokens.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          for (final group in groups)
            _GroupTab(
              group: group,
              site: site,
              selected: group.id == selectedGroupId,
              // 全平台聚合时按组名稳定映射一个平台色点。
              dotColor: isAll ? _platformDotColor(group.name) : null,
              onTap: () => onGroupTap(group),
            ),
        ],
      ),
    );
  }

  /// 按名称 hash 稳定取一个导航平台色,保证同名组色点不闪烁。
  static Color _platformDotColor(String name) {
    final platforms = PlatformBrandCatalog.navigationPlatforms;
    return platforms[name.hashCode.abs() % platforms.length].color;
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({
    required this.group,
    required this.site,
    required this.selected,
    required this.dotColor,
    required this.onTap,
  });

  final CategoryGroup group;
  final String site;
  final bool selected;
  final Color? dotColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      // 测试锚点:定位/点击左侧分组 tab。
      key: Key('category-group-${group.id}'),
      color: selected ? tokens.surfaceRaised : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // 分组 tab:选中底已是 surfaceRaised,此时 hover 只能退一档到 surface;
        // 未选中为透明底, hover 抬到 surfaceRaised。
        hoverColor: selected ? tokens.surface : tokens.surfaceRaised,
        splashColor: AppStateLayer.splashOf(tokens.accent),
        highlightColor: AppStateLayer.pressedOf(tokens.accent),
        focusColor: AppStateLayer.focusOf(tokens.accent),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (dotColor != null) ...[
                Container(
                  width: AppSpacing.sm,
                  height: AppSpacing.sm,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  // 抖音/斗鱼/虎牙/哔哩哔哩 分组名直接用平台原名(已是中文或平台原生)。
                  displayCategoryGroupName(site, group.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textBody.copyWith(
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分类索引的内容网格:子分类 tile 铺满内容区独立滚动,点击路由跳转到
/// 带 cid 的房间页(web `CategoryGrid` 的 RouterLink 语义,不在索引页内
/// 原地展开房间)。
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.site, required this.group});

  final String site;
  final CategoryGroup group;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: [
          for (final entry in group.items)
            _CategoryTile(
              item: entry,
              site: site,
              onTap: entry.cid.isEmpty
                  ? null
                  : () => context.go(
                      site == 'all'
                          ? '/all/category/${Uri.encodeComponent(entry.cid)}'
                          : '/$site/category/${Uri.encodeComponent(entry.cid)}',
                    ),
            ),
        ],
      ),
    );
  }
}

/// 子分类方块:图片缺失时用名称首字占位。
///
/// 右上角带「我的分类」收藏星(对齐参考实现 `CategoryGrid.vue` 的 `favoritable`:
/// 星标常驻、收藏后分类名与描边高亮)。星标自己在最上层命中,不触发 tile 跳转。
class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.item, required this.site, required this.onTap});

  final CategoryItem item;

  /// 收藏归属站点(`all` = 全平台聚合,与「我的分类」管理弹窗同口径)。
  final String site;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final brandColor = PlatformBrandCatalog.byId(site)?.color ?? tokens.brand;
    // 收藏判定按跨平台分类 key(与播放页星标同源,见
    // [isCategoryFavorited]):收藏过任一平台的同名分类即亮。
    final displayName = displayCategoryName(site, item.name, item.cid);
    final favorited =
        item.cid.isNotEmpty &&
        isCategoryFavorited(
          ref.watch(myCategoriesProvider),
          site: site,
          cid: item.cid,
          name: displayName,
        );
    return SizedBox(
      width: 88,
      child: InkWell(
        // 测试锚点:定位/点击子分类 tile。
        key: Key('category-item-${item.cid}'),
        borderRadius: AppRadius.allMd,
        onTap: onTap,
        // 状态反馈(全部走 token):hover 抬亮;焦点/按压用 accent 低 alpha。
        hoverColor: tokens.surfaceRaised,
        splashColor: AppStateLayer.splashOf(tokens.accent),
        highlightColor: AppStateLayer.pressedOf(tokens.accent),
        focusColor: AppStateLayer.focusOf(tokens.accent),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.allMd,
                    color: tokens.surfaceRaised,
                    border: Border.all(color: favorited ? brandColor : tokens.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: item.pic.isEmpty
                      ? Text(
                          item.name.isEmpty
                              ? '?'
                              : String.fromCharCode(item.name.runes.first),
                          style: context.textBody.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: item.pic,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => ColoredBox(color: tokens.surfaceRaised),
                          errorWidget: (_, _, _) =>
                              ColoredBox(color: tokens.surfaceRaised),
                        ),
                ),
                if (item.cid.isNotEmpty)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Tooltip(
                      message: favorited ? '取消收藏' : '收藏到我的分类',
                      child: InkWell(
                        key: Key('category-favorite-${item.cid}'),
                        borderRadius: AppRadius.allPill,
                        onTap: () => ref
                            .read(myCategoriesProvider.notifier)
                            .toggleForCategory(
                              MyCategoryEntry(
                                site: site,
                                cid: item.cid,
                                // 收藏快照存中文展示名,与导航「我的分类」
                                // chip 渲染口径一致(twitch/soop 原名不直存)。
                                name: displayName,
                              ),
                            ),
                        // 收藏星:底为 surface,hover 抬亮;焦点/按压用 accent 低 alpha。
                        hoverColor: tokens.surfaceRaised,
                        splashColor: AppStateLayer.splashOf(tokens.accent),
                        highlightColor: AppStateLayer.pressedOf(tokens.accent),
                        focusColor: AppStateLayer.focusOf(tokens.accent),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: tokens.border),
                          ),
                          child: Icon(
                            favorited ? Icons.star_rounded : Icons.star_border_rounded,
                            size: 12,
                            color: favorited ? tokens.brand : tokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              // 跨平台统一中文分类名:命中映射用 canonical 名,否则回落平台原名。
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textSecondary.copyWith(
                color: favorited ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中子分类后的房间列表:复用 [browseRoomsProvider] 的分页与刷新。
class _RoomSection extends ConsumerWidget {
  const _RoomSection({required this.site, required this.cid});

  final String site;
  final String cid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final query = BrowseRoomQuery(site: site, cid: cid);
    final roomsAsync = ref.watch(browseRoomsProvider(query));
    final controller = ref.read(browseRoomsProvider(query).notifier);
    return switch (roomsAsync) {
      AsyncValue(:final value?) =>
        value.rooms.isEmpty
            ? const _HintPlaceholder(icon: Icons.snooze_rounded, message: '该分类暂无直播中的房间')
            : RefreshIndicator(
                onRefresh: controller.refresh,
                color: tokens.accent,
                child: RoomGrid(
                  rooms: value.rooms,
                  hasMore: value.hasMore,
                  onLoadMore: controller.loadMore,
                  onRoomTap: (room) => context.push('/${room.site}/play/${room.roomId}'),
                ),
              ),
      AsyncValue(:final error?) => _ErrorRetry(
        message: '房间列表加载失败：$error',
        onRetry: controller.refresh,
      ),
      _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    };
  }
}

/// 通用提示占位(空态/引导)。
class _HintPlaceholder extends StatelessWidget {
  const _HintPlaceholder({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: tokens.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: context.textSecondary),
        ],
      ),
    );
  }
}

/// 错误占位:错误说明 + 重试按钮。
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: tokens.error),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: context.textSecondary),
          const SizedBox(height: AppSpacing.lg),
          RetryButton(onRetry: onRetry),
        ],
      ),
    );
  }
}
