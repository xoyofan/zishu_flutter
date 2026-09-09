import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/browse_provider.dart';
import '../widgets/room_grid.dart';

/// 分类页:左侧大类分组 tabs + 右侧子分类网格与房间列表。
/// 分组数据来自 [browseCategoriesProvider],选中子分类后由
/// [browseRoomsProvider] 按 (site, cid) 拉取房间。
class CategoryView extends ConsumerStatefulWidget {
  const CategoryView({
    super.key,
    required this.site,
    this.cid,
    this.categoryKey,
  });

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

  /// 用户手动选中的组/子分类;null 表示按路由参数或默认规则推导。
  String? _selectedGroupId;
  String? _selectedCid;

  @override
  void didUpdateWidget(covariant CategoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换站点或路由参数变化时重置选择状态。
    if (oldWidget.site != widget.site ||
        oldWidget.cid != widget.cid ||
        oldWidget.categoryKey != widget.categoryKey) {
      setState(() {
        _selectedGroupId = null;
        _selectedCid = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(browseCategoriesProvider(widget.site));
    return switch (categoriesAsync) {
      // value 非 null 即有数据。
      AsyncValue(:final value?) => value.groups.isEmpty
          ? _HintPlaceholder(
              icon: Icons.category_rounded,
              message: '暂无分类数据,下拉或稍后再试',
            )
          : _content(context, value),
      AsyncValue(:final error?) => _ErrorRetry(
          message: '分类加载失败：$error',
          onRetry: () =>
              ref.read(browseCategoriesProvider(widget.site).notifier).refresh(),
        ),
      _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    };
  }

  /// 分组 tabs + 右侧(子分类网格 + 房间网格)的主内容。
  Widget _content(BuildContext context, CategoryResult result) {
    final tokens = context.tokens;
    final group = _pickGroup(result.groups);
    final item = _pickItem(group);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupTabs(
          groups: result.groups,
          selectedGroupId: group.id,
          isAll: widget.site == 'all',
          width: _tabsWidth,
          onGroupTap: (target) => setState(() {
            _selectedGroupId = target.id;
            _selectedCid = null;
          }),
        ),
        Container(width: 1, color: tokens.border),
        Expanded(
          child: _CategoryPanel(
            site: widget.site,
            group: group,
            selectedItem: item,
            brandColor: _brandColor(context),
            onItemTap: (target) => setState(() => _selectedCid = target.cid),
          ),
        ),
      ],
    );
  }

  Color _brandColor(BuildContext context) =>
      PlatformBrandCatalog.byId(widget.site)?.color ?? context.tokens.brand;

  /// 解析当前选中的分组:手动选择 > cid 归属 > categoryKey 匹配 > 第一组。
  CategoryGroup _pickGroup(List<CategoryGroup> groups) {
    final selectedId = _selectedGroupId;
    if (selectedId != null) {
      for (final group in groups) {
        if (group.id == selectedId) return group;
      }
    }
    final cid = _selectedCid ?? widget.cid;
    if (cid != null && cid.isNotEmpty) {
      for (final group in groups) {
        if (group.items.any((item) => item.cid == cid)) return group;
      }
    }
    final key = widget.categoryKey;
    if (key != null && key.isNotEmpty) {
      for (final group in groups) {
        if (group.name == key ||
            group.items.any((item) => item.name == key)) {
          return group;
        }
      }
    }
    return groups.first;
  }

  /// 解析当前选中的子分类:cid 精确匹配,其次 categoryKey 匹配子分类名。
  CategoryItem? _pickItem(CategoryGroup group) {
    final cid = _selectedCid ?? widget.cid;
    if (cid != null && cid.isNotEmpty) {
      for (final item in group.items) {
        if (item.cid == cid) return item;
      }
    }
    final key = widget.categoryKey;
    if (key != null && key.isNotEmpty) {
      for (final item in group.items) {
        if (item.name == key) return item;
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
    required this.onGroupTap,
  });

  final List<CategoryGroup> groups;
  final String selectedGroupId;
  final bool isAll;
  final double width;
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
    final platforms = PlatformBrandCatalog.navPlatforms;
    return platforms[name.hashCode.abs() % platforms.length].color;
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({
    required this.group,
    required this.selected,
    required this.dotColor,
    required this.onTap,
  });

  final CategoryGroup group;
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
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
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

/// 右侧面板:子分类网格(顶部)+ 选中子分类的房间网格(独立滚动)。
class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({
    required this.site,
    required this.group,
    required this.selectedItem,
    required this.brandColor,
    required this.onItemTap,
  });

  final String site;
  final CategoryGroup group;
  final CategoryItem? selectedItem;
  final Color brandColor;
  final ValueChanged<CategoryItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    final item = selectedItem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: [
                for (final entry in group.items)
                  _CategoryTile(
                    item: entry,
                    selected: item?.cid == entry.cid,
                    brandColor: brandColor,
                    onTap: () => onItemTap(entry),
                  ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: context.tokens.border),
        Expanded(
          child: item == null
              ? const _HintPlaceholder(
                  icon: Icons.touch_app_rounded,
                  message: '选择一个子分类查看直播间',
                )
              : _RoomSection(site: site, cid: item.cid, isAll: site == 'all'),
        ),
      ],
    );
  }
}

/// 子分类方块:图片缺失时用名称首字占位。
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.item,
    required this.selected,
    required this.brandColor,
    required this.onTap,
  });

  final CategoryItem item;
  final bool selected;
  final Color brandColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: 88,
      child: InkWell(
        // 测试锚点:定位/点击子分类 tile。
        key: Key('category-item-${item.cid}'),
        borderRadius: AppRadius.allMd,
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: AppRadius.allMd,
                color: tokens.surfaceRaised,
                border: Border.all(
                  color: selected ? brandColor : tokens.border,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: item.pic.isEmpty
                  ? Text(
                      item.name.isEmpty
                          ? '?'
                          : String.fromCharCode(item.name.runes.first),
                      style: AppTypography.body.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.pic,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          ColoredBox(color: tokens.surfaceRaised),
                      errorWidget: (_, _, _) =>
                          ColoredBox(color: tokens.surfaceRaised),
                    ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySecondary.copyWith(
                color: selected ? tokens.textPrimary : tokens.textSecondary,
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
  const _RoomSection({required this.site, required this.cid, required this.isAll});

  final String site;
  final String cid;
  final bool isAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final query = BrowseRoomQuery(site: site, cid: cid);
    final roomsAsync = ref.watch(browseRoomsProvider(query));
    final controller = ref.read(browseRoomsProvider(query).notifier);
    return switch (roomsAsync) {
      AsyncValue(:final value?) =>
        value.rooms.isEmpty
            ? const _HintPlaceholder(
                icon: Icons.snooze_rounded,
                message: '该分类暂无直播中的房间',
              )
            : RefreshIndicator(
                onRefresh: controller.refresh,
                color: tokens.brand,
                child: RoomGrid(
                  rooms: value.rooms,
                  hasMore: value.hasMore,
                  onLoadMore: controller.loadMore,
                  showPlatformBadge: isAll,
                  onRoomTap: (room) =>
                      context.push('/${room.site}/play/${room.roomId}'),
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
          Text(message, style: AppTypography.bodySecondary),
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
          Text(message, style: AppTypography.bodySecondary),
          const SizedBox(height: AppSpacing.lg),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
            style: TextButton.styleFrom(foregroundColor: tokens.brand),
          ),
        ],
      ),
    );
  }
}
