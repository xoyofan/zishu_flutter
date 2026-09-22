part of '../app_shell.dart';

/// 「我的分类」hover 浮层:对齐 SFVideoLive `NavMyCategoryMenu.vue`。
///
/// 结构:右上角「管理分类」入口 + 收藏 chip 折行区(max-height 11rem≈176px),
/// 空集合显示「暂无收藏分类」。chip 点击跳对应子分类并收起浮层。
class _MyCategoryFlyout extends ConsumerWidget {
  const _MyCategoryFlyout({
    required this.site,
    required this.onEnter,
    required this.onExit,
    required this.onClose,
  });

  /// 当前站点,用于「管理分类」弹窗的分类目录。
  final String site;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  /// 立即收起浮层(跳转/开弹窗前调用)。
  final VoidCallback onClose;

  /// chip 区最大高度:11rem @16px ≈ 176px(同 `.nav-my-cat-menu__tags`)。
  static const double _kTagsMaxHeight = 176;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = [
      for (final entry in ref.watch(myCategoriesProvider))
        if (entry.isValid) entry,
    ];
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: _FlyoutPanel(
        key: const Key('my-category-flyout-panel'),
        padding: const EdgeInsets.fromLTRB(6.4, 5.6, 6.4, 6.4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 22,
                child: TextButton(
                  onPressed: () {
                    onClose();
                    showDialog<void>(
                      context: context,
                      builder: (_) => _MyCategoryManageDialog(site: site),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: context.tokens.accent,
                    textStyle: const TextStyle(
                      fontSize: AppFontSize.bodySecondary,
                    ),
                  ),
                  child: const Text('管理分类'),
                ),
              ),
            ),
            if (entries.isEmpty)
              const _FlyoutHint('暂无收藏分类')
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _kTagsMaxHeight),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 5.12,
                    runSpacing: 4.48,
                    children: [
                      for (final entry in entries)
                        _MyCategoryChip(
                          entry: entry,
                          onTap: () {
                            onClose();
                            context.go(
                              _categoryRoute(entry.site, cid: entry.cid),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 收藏 chip:对齐 `.nav-my-cat-menu__tag`(描边 pill,hover 转金色)。
class _MyCategoryChip extends StatefulWidget {
  const _MyCategoryChip({required this.entry, required this.onTap});

  final MyCategoryEntry entry;
  final VoidCallback onTap;

  @override
  State<_MyCategoryChip> createState() => _MyCategoryChipState();
}

class _MyCategoryChipState extends State<_MyCategoryChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final gold = _hovering;
    // 底色/描边铺进 ink 层(`Ink`),InkWell 的 hover/按下叠色才能画在它之上;
    // `_hovering` 只负责描边与星形/文字转品牌色(web `.nav-my-cat-menu__tag:hover`
    // 的“金描边 + 金字”,hover 底色由 InkWell 的 hoverColor 承担)。
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Ink(
        decoration: BoxDecoration(
          color: context.tokens.surfaceSoft,
          border: Border.all(
            color: gold
                ? context.tokens.brand.withValues(alpha: 0.55)
                : context.tokens.border,
          ),
          borderRadius: AppRadius.allPill,
        ),
        child: InkWell(
          borderRadius: AppRadius.allPill,
          onTap: widget.onTap,
          hoverColor: context.tokens.brand.withValues(alpha: 0.1),
          focusColor: context.tokens.surfaceRaised,
          splashColor: context.tokens.brand.withValues(alpha: 0.12),
          highlightColor: context.tokens.brand.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9.6, vertical: 4.8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 12,
                  color: gold
                      ? context.tokens.brand
                      : context.tokens.textSecondary,
                ),
                SizedBox(width: 4),
                Text(
                  // 旧快照可能存的是英文/韩文原名:渲染时按 (site,cid) 再映射
                  // 一次中文名,不重写存储(与 web 展示层归一同口径)。
                  displayCategoryName(
                    widget.entry.site,
                    widget.entry.name,
                    widget.entry.cid,
                  ),
                  style: TextStyle(
                    fontSize: AppFontSize.subtitle,
                    fontWeight: FontWeight.w500,
                    color: gold
                        ? context.tokens.brand
                        : context.tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 我的分类管理弹窗:勾选当前平台的分类作为收藏(上限
/// [MyCategoryController.maxCount]),顶部列出已收藏项可移除。
class _MyCategoryManageDialog extends ConsumerWidget {
  const _MyCategoryManageDialog({required this.site});

  final String site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(myCategoriesProvider);
    final async = ref.watch(browseCategoriesProvider(site));
    return AlertDialog(
      backgroundColor: context.tokens.surface,
      title: Text(
        '我的分类(${favorites.length}/${MyCategoryController.maxCount})',
        style: TextStyle(
          fontSize: AppFontSize.subtitle,
          color: context.tokens.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (favorites.isNotEmpty) ...[
              Text(
                '已收藏(点击 × 移除)',
                style: TextStyle(
                  fontSize: AppFontSize.bodySecondary,
                  color: context.tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in favorites)
                    _RemovableChip(
                      entry: entry,
                      onRemove: () =>
                          ref.read(myCategoriesProvider.notifier).remove(entry),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '分类目录(点击收藏/取消)',
              style: TextStyle(
                fontSize: AppFontSize.bodySecondary,
                color: context.tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _catalog(context, ref, async, favorites)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _catalog(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<CategoryResult> async,
    List<MyCategoryEntry> favorites,
  ) {
    return switch (async) {
      AsyncData(:final value) =>
        value.groups.isEmpty
            ? const _FlyoutHint('暂无分类数据')
            : ListView(
                children: [
                  for (final group in value.groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayCategoryGroupName(site, group.name),
                            style: TextStyle(
                              fontSize: AppFontSize.bodySecondary,
                              fontWeight: FontWeight.w700,
                              color: context.tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final item in group.items)
                                _PickableChip(
                                  label: displayCategoryName(
                                    site,
                                    item.name,
                                    item.cid,
                                  ),
                                  selected: favorites.any(
                                    (entry) =>
                                        entry.site == site &&
                                        entry.cid == item.cid,
                                  ),
                                  onTap: () async {
                                    final ok = await ref
                                        .read(myCategoriesProvider.notifier)
                                        .toggle(
                                          MyCategoryEntry(
                                            site: site,
                                            cid: item.cid,
                                            name: displayCategoryName(
                                              site,
                                              item.name,
                                              item.cid,
                                            ),
                                          ),
                                        );
                                    if (!ok && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '最多收藏 ${MyCategoryController.maxCount} 个分类',
                                            ),
                                          ),
                                        );
                                    }
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      AsyncError(:final error) => _FlyoutHint('分类加载失败:$error', danger: true),
      _ => _FlyoutHint('加载分类…'),
    };
  }
}

/// 已收藏 chip:带移除叉号。
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.entry, required this.onRemove});

  final MyCategoryEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: 9.6, right: 2),
      decoration: BoxDecoration(
        color: context.tokens.brand.withValues(alpha: 0.1),
        border: Border.all(color: context.tokens.brand.withValues(alpha: 0.55)),
        borderRadius: AppRadius.allPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // 同 _MyCategoryChip:旧快照英文名渲染时再映射一次中文。
            displayCategoryName(entry.site, entry.name, entry.cid),
            style: TextStyle(
              fontSize: AppFontSize.body,
              color: context.tokens.brand,
            ),
          ),
          InkWell(
            borderRadius: AppRadius.allPill,
            onTap: onRemove,
            hoverColor: context.tokens.surfaceRaised,
            focusColor: context.tokens.surfaceRaised,
            splashColor: _pressTint(context),
            highlightColor: _pressTint(context),
            child: Padding(
              padding: EdgeInsets.all(3),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: context.tokens.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 目录中的可选 chip:选中为金色描边 + 实心星,未选中为描边 pill。
class _PickableChip extends StatelessWidget {
  const _PickableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Ink(
      decoration: BoxDecoration(
        color: selected
            ? context.tokens.brand.withValues(alpha: 0.12)
            : context.tokens.surfaceSoft,
        border: Border.all(
          color: selected
              ? context.tokens.brand.withValues(alpha: 0.55)
              : context.tokens.border,
        ),
        borderRadius: AppRadius.allPill,
      ),
      child: InkWell(
        borderRadius: AppRadius.allPill,
        onTap: onTap,
        // 选中态底色已是品牌金 12%:hover / 按下 / 焦点全部取品牌金淡染
        // (选中再叠金只是更深,不会把“已选”状态盖掉);
        // 焦点色直接取 AppFocus 环的光晕档(品牌金 24%),不另造数值。
        hoverColor: context.tokens.brand.withValues(alpha: 0.1),
        focusColor: AppFocus.ring(context.tokens.brand).first.color,
        splashColor: context.tokens.brand.withValues(alpha: 0.12),
        highlightColor: context.tokens.brand.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9.6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.star_rounded : Icons.star_border_rounded,
                size: 13,
                color: selected
                    ? context.tokens.brand
                    : context.tokens.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.body,
                  color: selected
                      ? context.tokens.brand
                      : context.tokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
