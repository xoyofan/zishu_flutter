part of '../app_shell.dart';

/// 平台分类底部面板:标题「{平台} · 分类」+ 关闭;分组标题 + 子分类 chips,
/// 点选后跳该平台子分类页(与顶栏/侧栏分类入口同一套路由)。
class _PlatformCategorySheet extends ConsumerWidget {
  const _PlatformCategorySheet({required this.site});

  final String site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final brand = PlatformBrandCatalog.byId(site);
    final async = ref.watch(browseCategoriesProvider(site));
    return Container(
      key: const Key('platform-cat-sheet'),
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${brand?.name ?? site} · 分类',
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('platform-cat-sheet-close'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  hoverColor: tokens.surfaceRaised,
                  focusColor: AppStateLayer.focusOf(tokens.accent),
                  splashColor: AppStateLayer.splashOf(context.tokens.accent),
                  highlightColor: AppStateLayer.pressedOf(
                    context.tokens.accent,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: tokens.border),
          Expanded(
            child: async.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, _) => Center(
                child: Text(
                  '分类加载失败',
                  style: TextStyle(
                    fontSize: AppFontSize.bodySecondary,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
              data: (result) {
                final groups = result.groups;
                if (groups.isEmpty) {
                  return Center(
                    child: Text(
                      '暂无分类数据',
                      style: TextStyle(
                        fontSize: AppFontSize.bodySecondary,
                        color: tokens.textSecondary,
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final group in groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          displayCategoryGroupName(site, group.name),
                          style: TextStyle(
                            fontSize: AppFontSize.bodySecondary,
                            fontWeight: FontWeight.w700,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in group.items)
                            // chip 底色不透明:InkWell 的叠色必须画在填色**之上**,
                            // 故用 `Ink` 把底色铺进 Material 的 ink 层
                            // (同 follow_avatars.dart 的 _FollowAvatarTile)。
                            Ink(
                              decoration: BoxDecoration(
                                color: tokens.surfaceRaised,
                                borderRadius: AppRadius.allMd,
                                border: Border.all(color: tokens.border),
                              ),
                              child: InkWell(
                                key: Key('platform-cat-item-${item.cid}'),
                                borderRadius: AppRadius.allMd,
                                // 底色已是抬升顶档 surfaceRaised,没有更亮的灰阶可抬:
                                // hover 改走强调色 12% 淡染(同浮层内分类 chip 口径)。
                                hoverColor: tokens.accent.withValues(
                                  alpha: AppDirectoryDrawer.activeChipAlpha,
                                ),
                                // 焦点:底色与 surfaceRaised 同值会看不见,
                                // 故取 AppFocus 环的光晕色(accent 24%,直接取自 token)。
                                focusColor: AppFocus.ring(tokens.accent)
                                    .first
                                    .color,
                                splashColor: AppStateLayer.splashOf(
                                  context.tokens.accent,
                                ),
                                highlightColor: AppStateLayer.pressedOf(
                                  context.tokens.accent,
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  context.go(
                                    _categoryRoute(site, cid: item.cid),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    displayCategoryName(
                                      site,
                                      item.name,
                                      item.cid,
                                    ),
                                    style: TextStyle(
                                      fontSize: AppFontSize.bodySecondary,
                                      color: tokens.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// hover 浮层面板容器:对齐 SFVideoLive `.nav-platform-menu` / `.nav-follow-flyout`
/// 的容器规格(面板底色 + 1px 边框 + 圆角 + shadow-16),内容超高由
/// [maxHeight] 约束后自行滚动。
class _FlyoutPanel extends StatelessWidget {
  const _FlyoutPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(9.6, 8.8, 9.6, 9.6),

    /// 26rem @16px ≈ 416px(同 `.nav-platform-menu` 的 max-height);
    /// 关注浮层另传 5 行网格高度。
    this.maxHeight = 416,
  });

  final Widget child;
  final EdgeInsets padding;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border.all(color: context.tokens.border),
        borderRadius: AppRadius.allMd,
        boxShadow: AppElevation.popover,
      ),
      child: Material(
        // 浮层挂在 Stack 顶层,不在 Scaffold 的 Material 子树内,
        // 需自带 Material 才能承载内部 InkWell。
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 浮层内的提示行(加载中/错误/空态),对齐 `.nav-platform-menu__hint`。
class _FlyoutHint extends StatelessWidget {
  const _FlyoutHint(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.2, vertical: 5.6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: AppFontSize.body,
          color: danger ? context.tokens.error : context.tokens.textSecondary,
        ),
      ),
    );
  }
}

/// 平台 tab hover 出的分类浮层:对齐 SFVideoLive `NavPlatformCategoryMenu.vue`。
/// 数据来自 [browseCategoriesProvider](fixture/真实解析双轨同一入口),
/// 不新造硬编码分类表。
class _PlatformCategoryFlyout extends ConsumerWidget {
  const _PlatformCategoryFlyout({
    required this.site,
    required this.onEnter,
    required this.onExit,
  });

  final String site;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(browseCategoriesProvider(site));
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: _FlyoutPanel(
        key: const Key('platform-flyout-panel'),
        child: switch (async) {
          AsyncData(:final value) =>
            value.groups.isEmpty
                ? const _FlyoutHint('暂无分类')
                : _CategoryBoard(site: site, groups: value.groups),
          AsyncError(:final error) => _FlyoutHint(
            error.toString(),
            danger: true,
          ),
          _ => const _FlyoutHint('加载分类…'),
        },
      ),
    );
  }
}

/// 分类看板:单组平台平铺网格,多组平台横向分栏(列间 1px 竖线)。
class _CategoryBoard extends StatefulWidget {
  const _CategoryBoard({required this.site, required this.groups});

  /// 列宽 4.2rem ≈ 67px(同 `.nav-platform-menu__column`)。
  static const double _kColumnWidth = 67.2;

  /// 列内容最大高度:_FlyoutPanel maxHeight(416) 减面板上下 padding
  /// (8.8+9.6);条目超出后列内纵向滚动(对齐 web `scrolly` 语义)。
  static const double _kBoardContentMax = 396;

  final String site;
  final List<CategoryGroup> groups;

  @override
  _CategoryBoardState createState() => _CategoryBoardState();
}

class _CategoryBoardState extends State<_CategoryBoard> {
  /// 每个纵向滚动视图独立 controller:Scrollbar(thumbVisibility) 在
  /// PrimaryScrollController 上多 ScrollPosition 会直接报错(实测)。
  final _scrollControllers = <int, ScrollController>{};

  ScrollController _controllerFor(int index) =>
      _scrollControllers.putIfAbsent(index, () => ScrollController());

  @override
  void dispose() {
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final groups = widget.groups;
    if (groups.length == 1) {
      // 单一大组:平铺网格(对齐 `.nav-platform-menu__hot-track`)。
      // soop 等单组可达 300+ 条:限高内纵向滚动 + 常驻滚动条
      // (对齐 web `nav-platform-menu__hot-scroll scrolly`)。
      return _FlyoutScrollbar(
        controller: _controllerFor(0),
        child: SingleChildScrollView(
          controller: _controllerFor(0),
          child: Wrap(
            children: [
              for (final item in groups.first.items)
                SizedBox(
                  width: _CategoryBoard._kColumnWidth,
                  child: _CategoryChip(
                    key: ValueKey('flyout-category-${item.cid}'),
                    label: displayCategoryName(site, item.name, item.cid),
                    onTap: () => _goCategory(context, item.cid),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups)
            Container(
              width: _CategoryBoard._kColumnWidth,
              padding: const EdgeInsets.only(left: 2.4),
              constraints: const BoxConstraints(
                maxHeight: _CategoryBoard._kBoardContentMax,
              ),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: context.tokens.border)),
              ),
              // 列内容超高时列内纵向滚动:此前是无界 Column,内容一多
              // 直接撑破 _FlyoutPanel 的 maxHeight 报 bottom overflow。
              child: _FlyoutScrollbar(
                controller: _controllerFor(groups.indexOf(group)),
                child: SingleChildScrollView(
                  controller: _controllerFor(groups.indexOf(group)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(bottom: 3.8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.tokens.border),
                          ),
                        ),
                        child: Text(
                          displayCategoryGroupName(site, group.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.bodySecondary,
                            fontWeight: FontWeight.w700,
                            color: context.tokens.textSecondary,
                          ),
                        ),
                      ),
                      for (final item in group.items)
                        _CategoryChip(
                          key: ValueKey('flyout-category-${item.cid}'),
                          label: displayCategoryName(site, item.name, item.cid),
                          onTap: () => _goCategory(context, item.cid),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 跳平台分类页:带 cid 进 `/:site/category/:cid`,CategoryView 据此高亮
  /// 所属分组与子分类(落地页形态见 [_categoryRoute])。
  void _goCategory(BuildContext context, String cid) =>
      context.go(_categoryRoute(widget.site, cid: cid));
}

/// 浮层内纵向滚动条:常驻 4px 细条(对齐 web `scrolly` 的
/// `scrollbar-width: thin` + 4px `--scrollbar-size`)。
class _FlyoutScrollbar extends StatelessWidget {
  const _FlyoutScrollbar({required this.child, required this.controller});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      thickness: 4,
      radius: const Radius.circular(AppRadius.pill),
      child: child,
    );
  }
}

/// 分类条目:hover → 金(平台主色)+ chip 底(同 `.nav-platform-menu__item:hover`)。
class _CategoryChip extends StatefulWidget {
  const _CategoryChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    // hover 底色改由 InkWell 的 hoverColor 承担:原先 Container 在 hover 时
    // 自填 accent 12%,会把 InkWell 的叠色盖在下面(且叠加 M3 默认 8%,两层不可控);
    // `_hovering` 现在只负责文字转强调色(web `.nav-platform-menu__item:hover`
    // 的“金底 + 金字”:金底走 hoverColor,金字走这里)。
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: context.tokens.accent.withValues(
          alpha: AppDirectoryDrawer.activeChipAlpha,
        ),
        focusColor: AppStateLayer.focusOf(context.tokens.accent),
        splashColor: AppStateLayer.splashOf(context.tokens.accent),
        highlightColor: AppStateLayer.pressedOf(context.tokens.accent),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0.64, vertical: 1.28),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.bodySecondary,
              color: _hovering
                  ? context.tokens.accent
                  : context.tokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
