import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../features/search/widgets/search_dialog.dart';
import '../features/browse/application/browse_provider.dart';
import '../features/browse/application/my_category_provider.dart';
import '../features/follow/application/follow_provider.dart';
import '../features/follow/application/follow_sort.dart';
import '../features/follow/application/follow_status_poller.dart';
import '../features/follow/application/settings_provider.dart';
import '../shared/application/auth_provider.dart';
import '../shared/domain/category_display.dart';
import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/platform_brands.dart';
import '../shared/presentation/zishu_tokens.dart';
import '../shared/presentation/widgets/platform_icon.dart';

/// 应用壳层:桌面/平板(>=768)为 44px 顶部导航;
/// 手机(<768)为平台条 + 56px 底部主导航。结构对齐 SFVideoLive
/// `NavSidebar.vue` 的品牌区、中心平台区与右侧工具区。
///
/// 播放页同样套本壳(对齐参考实现:`AppLayout` 包裹 `PlayView`,顶栏在播放页
/// 常驻);仅沉浸态(网页全屏/全屏/画中画)把 chrome 收起,口径与
/// `html.play-webscreen .nav-sidebar { display:none }` 一致。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.site,
    required this.child,
    this.chromeHidden = false,
  });

  /// 当前选中的平台 id(`all` = 全平台聚合)。
  final String site;
  final Widget child;

  /// 沉浸态:收起顶部/底部导航与 hover 浮层,让内容(视频)占满窗口。
  final bool chromeHidden;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// hover 浮层关闭延迟:对齐 SFVideoLive `composables/useHoverUi.ts` 的
  /// HOVER_MENU_CLOSE_MS(800)——离开触发区后留时间把鼠标移进浮层。
  static const Duration _kHoverCloseDelay = Duration(milliseconds: 800);

  Timer? _closeTimer;
  String? _hoveredPlatform;
  double _hoveredPlatformX = 0;
  bool _followHover = false;
  double _followX = 0;
  bool _myCatHover = false;
  double _myCatX = 0;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _cancelClose() => _closeTimer?.cancel();

  /// 立即收起所有浮层(点击收藏分类跳转 / 打开管理弹窗前调用)。
  void _closeAll() {
    _closeTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _hoveredPlatform = null;
      _followHover = false;
      _myCatHover = false;
    });
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(_kHoverCloseDelay, () {
      if (!mounted) return;
      setState(() {
        _hoveredPlatform = null;
        _followHover = false;
        _myCatHover = false;
      });
    });
  }

  /// 关注浮层点主播格:先收浮层,再 push 播放页。
  ///
  /// 必须是 push 而非 go:go 会把壳层页也一并从栈里换掉,播放页左上角
  /// 「返回」就无栈可回(go_router 抛 `GoError: There is nothing to pop`,
  /// 表现为点返回没反应)。
  void _openRoom(FollowEntry entry) {
    _closeAll();
    final room = entry.room;
    unawaited(context.push('/${room.site}/play/${room.roomId}'));
  }

  void _openPlatform(String id, double centerX) {
    _cancelClose();
    setState(() {
      _hoveredPlatform = id;
      _hoveredPlatformX = centerX;
      _followHover = false;
      _myCatHover = false;
    });
  }

  void _openFollow(double centerX) {
    _cancelClose();
    // 浮层一开就补跑一轮状态刷新:用户看到的应是**此刻**在播的主播,
    // 而不是等到下一个轮询周期。无 refresher(fixture/测试)时 provider 为
    // null,这里自然退化为无操作。
    unawaited(ref.read(followStatusPollerProvider)?.wake());
    setState(() {
      _followHover = true;
      _followX = centerX;
      _hoveredPlatform = null;
      _myCatHover = false;
    });
  }

  /// 「我的分类」hover 打开。
  void _openMyCategory(double centerX) {
    _cancelClose();
    if (_myCatHover) return;
    setState(() {
      _myCatHover = true;
      _myCatX = centerX;
      _hoveredPlatform = null;
      _followHover = false;
    });
  }

  /// 「我的分类」点击 toggle(对齐 SFVideoLive `onMyCatTriggerClick`)。
  void _toggleMyCategory(double centerX) {
    if (_myCatHover) {
      _closeAll();
      return;
    }
    _cancelClose();
    setState(() {
      _myCatHover = true;
      _myCatX = centerX;
      _hoveredPlatform = null;
      _followHover = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 关注在播状态定时轮询常驻(播放页也常驻——顶栏在),无 refresher 时为 null。
    ref.watch(followStatusPollerProvider);
    final isPhone = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;
    // hover 中的平台:浮层宽度需要它的分类数据(见 _platformFlyoutLayoutFor)。
    final hoveredPlatform = _hoveredPlatform ?? '';
    // 沉浸态(播放页网页全屏/全屏/画中画)不渲染 chrome:浮层也一并停用,
    // 避免鼠标划过不可见顶栏时飘出浮层盖住视频。
    final showChrome = !widget.chromeHidden;
    // hover 浮层只走桌面/平板(触屏无 hover 语义)。
    final showPlatformFlyout =
        showChrome && !isPhone && _hoveredPlatform != null;
    final showFollowFlyout = showChrome && !isPhone && _followHover;
    final showMyCatFlyout = showChrome && !isPhone && _myCatHover;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: context.tokens.background,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showChrome)
                if (isPhone)
                  _PlatformStrip(currentSite: widget.site)
                else
                  _TopNav(
                    currentSite: widget.site,
                    onPlatformHover: _openPlatform,
                    onPlatformHoverEnd: _scheduleClose,
                    onFollowHover: _openFollow,
                    onFollowHoverEnd: _scheduleClose,
                    onMyCategoryHover: _openMyCategory,
                    onMyCategoryTap: _toggleMyCategory,
                    onMyCategoryHoverEnd: _scheduleClose,
                  ),
              Expanded(child: widget.child),
            ],
          ),
          bottomNavigationBar: showChrome && isPhone
              ? _BottomNav(currentSite: widget.site)
              : null,
        ),
        if (showPlatformFlyout)
          _HoverOverlay(
            centerX: _hoveredPlatformX,
            // 宽度随实际列数收缩(不是固定 560),夹取交给 _HoverOverlay。
            width: _platformFlyoutLayoutFor(
              ref.watch(browseCategoriesProvider(hoveredPlatform)).value,
            ).width,
            child: _PlatformCategoryFlyout(
              site: hoveredPlatform,
              onEnter: _cancelClose,
              onExit: _scheduleClose,
            ),
          ),
        if (showFollowFlyout)
          _HoverOverlay(
            centerX: _followX,
            width: _followFlyoutLayoutFor(
              visibleFollowEntries(ref.watch(followProvider), liveOnly: true)
                  .length,
            ).width,
            child: _FollowFlyout(
              // 列数同样按实际在播数收敛(与宽度同源,避免「列少反而更宽」)。
              columns: _followFlyoutLayoutFor(
                visibleFollowEntries(
                  ref.watch(followProvider),
                  liveOnly: true,
                ).length,
              ).columns,
              onEnter: _cancelClose,
              onExit: _scheduleClose,
              onOpenRoom: _openRoom,
            ),
          ),
        if (showMyCatFlyout)
          _HoverOverlay(
            centerX: _myCatX,
            width: _kMyCategoryFlyoutWidth,
            child: _MyCategoryFlyout(
              site: widget.site,
              onEnter: _cancelClose,
              onExit: _scheduleClose,
              onClose: _closeAll,
            ),
          ),
      ],
    );
  }
}

/// 浮层尺寸规格:对齐 SFVideoLive `.nav-platform-menu`
/// `{ min-width: 12rem; max-width: min(92vw, 56rem) }` —— 宽度**由内容决定**,
/// 不写死一个中间值(那样条目少时右侧会留一整片空列)。视口夹取仍由
/// [_HoverOverlay] 负责。
const double _kFlyoutMinWidth = 192; // 12rem
const double _kFlyoutMaxWidth = 896; // 56rem

/// `_FlyoutPanel` 默认左右内边距(9.6×2)+ 左右各 1px 边框。
const double _kPlatformFlyoutChrome = 9.6 * 2 + 2;

/// 平台分类列宽 4.2rem ≈ 67.2px(同 `.nav-platform-menu__column`)。
const double _kPlatformFlyoutColumnWidth = 67.2;

/// 关注浮层:头像格宽 45.9px(由原「固定 7 列 / 336px」反推),列间距 0.96px,
/// 左右内边距 3.52×2 + 边框 2px。
const double _kFollowFlyoutSlotWidth = 45.9;
const double _kFollowFlyoutColumnGap = 0.96;
const double _kFollowFlyoutChrome = 3.52 * 2 + 2;

/// 关注浮层列数上限:对齐原实现的固定 7 列(web `.follow-hover-avatar-grid`)。
const int _kFollowFlyoutMaxColumns = 7;

/// 平台分类浮层布局:**列数 = 实际列数**(多分组时一组一列;单组时按条目数折行,
/// 但**封顶 5 列** —— 用户口径 2026-09-18:「twitch 的 hover 不要这么多列」,
/// 对齐 web 面板定高 22rem + auto-fill 的紧凑观感,溢出条目竖向滚动),
/// 宽度 = 列宽×列数 + 内边距,再夹到 `[12rem, 56rem]`。
///
/// 之前固定 560px 宽 + 看板内部再按内容排,条目少时右侧就留出整片空列 ——
/// 这里让「列数 → 宽度」同源推导,列少则面板窄。
({int columns, double width}) _platformFlyoutLayoutFor(
  CategoryResult? result,
) {
  final groups = result?.groups ?? const <CategoryGroup>[];
  final maxColumns = ((_kFlyoutMaxWidth - _kPlatformFlyoutChrome) /
          _kPlatformFlyoutColumnWidth)
      .floor()
      .clamp(1, 64);
  final rawColumns = groups.length > 1
      // 多分组:横向分栏,一组一列(超出 maxColumns 时由看板横向滚动)。
      ? groups.length
      // 单组:平铺网格,列数 = 条目数封顶 5(twitch 40 条不再摊成 13 列)。
      : (groups.isEmpty ? 1 : groups.first.items.length.clamp(1, 5));
  final columns = rawColumns.clamp(1, maxColumns);
  final width = (_kPlatformFlyoutChrome + columns * _kPlatformFlyoutColumnWidth)
      .clamp(_kFlyoutMinWidth, _kFlyoutMaxWidth);
  return (columns: columns, width: width);
}

/// 关注浮层布局:**列数 = 实际在播数**(≤7),宽度随列数收缩并夹到
/// `[12rem, 56rem]` —— 3 个在播就只占 3 列,不再留 4 列空白。
({int columns, double width}) _followFlyoutLayoutFor(int liveCount) {
  final columns = liveCount.clamp(1, _kFollowFlyoutMaxColumns);
  final width =
      (_kFollowFlyoutChrome +
              columns * _kFollowFlyoutSlotWidth +
              (columns - 1) * _kFollowFlyoutColumnGap)
          .clamp(_kFlyoutMinWidth, _kFlyoutMaxWidth);
  return (columns: columns, width: width);
}

/// 我的分类浮层宽度:对齐 web `.nav-my-cat-flyout { width: min(92vw, 18.5rem) }`
/// —— 桌面为 18.5rem ≈ 296px,窄视口由 [_HoverOverlay] 夹取到视口内。
/// chips 走 [Wrap] 折行,不存在「固定列数留空列」的问题。
const double _kMyCategoryFlyoutWidth = 18.5 * 16;

/// hover 浮层定位:水平以触发点为中心,并夹到视口内;
/// 顶部留 [_kBridgeHeight] 透明桥接区(SFVideoLive `.nav-*-flyout::before`),
/// 鼠标从触发区移入浮层时不经过"非 hover 空白"。
class _HoverOverlay extends StatelessWidget {
  const _HoverOverlay({
    required this.centerX,
    required this.width,
    required this.child,
  });

  static const double _kBridgeHeight = 10;

  final double centerX;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final w = width.clamp(120.0, screenWidth - 16).toDouble();
    final left = (centerX - w / 2).clamp(8.0, screenWidth - w - 8).toDouble();
    return Positioned(
      top: AppSpacing.topNavHeight - _kBridgeHeight,
      left: left,
      width: w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: _kBridgeHeight),
          child,
        ],
      ),
    );
  }
}

/// 移动端平台条:对齐 SFVideoLive `NavPlatformStrip.vue` + `responsive-chrome.css`
/// 的两条方向分支(源码真源,不按截图目测):
///
/// - **竖屏**:`nav-platform-strip__item` 为 `flex: 1 1 15%` 折行宫格 ——
///   12 项平分两行、隐藏平台文字、图标 1.75rem、箭头列 1.8rem、不滚动;
/// - **横屏**:高度稀缺,`flex-wrap: nowrap` 改**单行横向滚动**,图标 1.5rem、
///   箭头列 1.7rem,条高 `--nav-platform-strip-height`(= safe-top + 3.25rem)。
///
/// 每格 = 品牌图标入口(锚点 `platform-tab-{site}`)+ 独立分类箭头,各自语义
/// 动作分离;平台清单来自 `PlatformBrandCatalog.navigationPlatforms`。
///
/// 箭头锚点有两套:`platform-strip-cat-{site}` 是新契约(打开分类面板),
/// 外层 `KeyedSubtree` 保留旧锚点 `platform-category-{site}` 供既有响应式
/// 用例继续断言存在性 —— 一个控件两个名字是刻意的过渡期兼容,勿删。
class _PlatformStrip extends StatelessWidget {
  const _PlatformStrip({required this.currentSite});

  final String currentSite;

  /// 竖屏宫格图标:1.75rem ≈ 28px(web `[data-platform=phone][portrait]`)。
  static const double _kIconSize = 28;

  /// 横屏单行图标:1.5rem ≈ 24px。
  static const double _kIconSizeLandscape = 24;

  /// 分类箭头列宽:竖屏 1.8rem ≈ 28.8px,横屏 1.7rem ≈ 27.2px。
  static const double _kArrowWidth = 28.8;
  static const double _kArrowWidthLandscape = 27.2;

  /// 宫格单行高度(图标 + 上下内边距)。
  static const double _kRowHeight = 44;

  /// 竖屏宫格内容高度(单行高 × 2 + 行距)。
  static const double _kGridHeight = _kRowHeight * 2 + 8;

  /// 横屏单行条高:web `--nav-platform-strip-height: safe-top + 3.25rem`。
  static const double _kStripHeight = 52;

  /// 竖屏每行平台数:12 项 → 6 × 2(web `flex: 1 1 15%` 在 375px 下的实际落位)。
  static const int _kColumns = 6;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    // 形态按方向切换,与 web 的 `[data-platform=phone][data-orientation]` 分支同源:
    // 竖屏折行宫格(标签隐藏、宽度平分),横屏 `flex-wrap: nowrap` 单行横向滚动
    // —— 横屏高度稀缺,单行才能把平台压进 52px。
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final platforms = PlatformBrandCatalog.navigationPlatforms;
    return Container(
      padding: EdgeInsets.only(top: safeTop),
      decoration: BoxDecoration(
        color: context.tokens.surfaceSoft,
        border: Border(bottom: BorderSide(color: context.tokens.border)),
      ),
      child: isLandscape
          ? SizedBox(
              height: _kStripHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4.8),
                child: Row(
                  children: [
                    for (final brand in platforms)
                      _StripItem(
                        brand: brand,
                        selected: brand.id == currentSite,
                        landscape: true,
                      ),
                  ],
                ),
              ),
            )
          : SizedBox(
              height: _kGridHeight,
              child: Column(
                children: [
                  for (int r = 0;
                      r < (platforms.length / _kColumns).ceil();
                      r++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            for (int c = 0; c < _kColumns; c++)
                              if (r * _kColumns + c < platforms.length)
                                Expanded(
                                  child: _StripItem(
                                    brand: platforms[r * _kColumns + c],
                                    selected:
                                        platforms[r * _kColumns + c].id ==
                                            currentSite,
                                  ),
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

/// 平台条单格(web `.nav-platform-strip__item`):左侧平台 tab + 右侧独立 ▼ 按钮。
///
/// ▼ 不是「跳分类页」的快捷方式,而是打开该平台的**分类底部面板**
/// (web `.nav-cat-sheet` + `NavPlatformCategoryMenu`):手机没有 hover,
/// 分类只能在面板里选。
class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.brand,
    required this.selected,
    this.landscape = false,
  });

  final PlatformBrand brand;
  final bool selected;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final iconSize = landscape
        ? _PlatformStrip._kIconSizeLandscape
        : _PlatformStrip._kIconSize;
    final arrowWidth = landscape
        ? _PlatformStrip._kArrowWidthLandscape
        : _PlatformStrip._kArrowWidth;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.6),
      child: DecoratedBox(
        // web:item 有 1px 边框 + 圆角,选中项边框转品牌色。
        decoration: BoxDecoration(
          border: Border.all(color: selected ? brand.color : tokens.border),
          borderRadius: AppRadius.allSm,
          color: selected
              ? brand.color.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Tooltip(
                message: brand.name,
                child: InkWell(
                  // 测试锚点:平台入口(既有契约,勿改)。
                  key: Key('platform-tab-${brand.id}'),
                  onTap: () => context.go(_platformRoute(brand.id)),
                  hoverColor: tokens.surfaceRaised,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.8,
                      vertical: 6,
                    ),
                    child: PlatformIcon(id: brand.id, size: iconSize),
                  ),
                ),
              ),
            ),
            Container(width: 1, height: iconSize, color: tokens.border),
            // 旧锚点 `platform-category-{id}`:既有响应式用例仍按它断言入口
            // 可达,故用 KeyedSubtree 继续提供(点击落到下面的 InkWell)。
            KeyedSubtree(
              key: Key('platform-category-${brand.id}'),
              child: Tooltip(
                message: '${brand.name}分类',
                child: InkWell(
                  // 测试锚点:▼ 打开该平台分类面板。
                  key: Key('platform-strip-cat-${brand.id}'),
                  onTap: () => _openCategorySheet(context, brand.id),
                  hoverColor: tokens.surfaceRaised,
                  child: SizedBox(
                    width: arrowWidth,
                    height: iconSize + 12,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: landscape ? 17 : 20,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 打开平台分类底部面板(web `nav-cat-sheet`:Teleport 到 body 的底部抽屉)。
Future<void> _openCategorySheet(BuildContext context, String site) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PlatformCategorySheet(site: site),
  );
}

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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('platform-cat-sheet-close'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
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
              loading: () =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, _) => Center(
                child: Text(
                  '分类加载失败',
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
              ),
              data: (result) {
                final groups = result.groups;
                if (groups.isEmpty) {
                  return Center(
                    child: Text(
                      '暂无分类数据',
                      style: TextStyle(fontSize: 12, color: tokens.textSecondary),
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
                            fontSize: 12,
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
                            InkWell(
                              key: Key('platform-cat-item-${item.cid}'),
                              borderRadius: AppRadius.allMd,
                              onTap: () {
                                Navigator.of(context).pop();
                                context.go(_categoryRoute(site, cid: item.cid));
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.surfaceRaised,
                                  borderRadius: AppRadius.allMd,
                                  border: Border.all(color: tokens.border),
                                ),
                                child: Text(
                                  displayCategoryName(site, item.name, item.cid),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tokens.textPrimary,
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

/// 桌面顶栏:品牌/主导航在左,平台图标居中,工具区在右。
///
/// SFVideoLive 的桌面 `NavSidebar.vue` 使用 44px 高度、30px 品牌图标、
/// 34px 平台 tab 与 36px 级工具点击目标;平台 tab 默认只显示真实品牌图标,
/// 平台名通过 Tooltip 提供,避免 12 个平台文字把中心区域挤变形。
class _TopNav extends StatelessWidget implements PreferredSizeWidget {
  const _TopNav({
    required this.currentSite,
    required this.onPlatformHover,
    required this.onPlatformHoverEnd,
    required this.onFollowHover,
    required this.onFollowHoverEnd,
    required this.onMyCategoryHover,
    required this.onMyCategoryTap,
    required this.onMyCategoryHoverEnd,
  });

  final String currentSite;

  /// 平台 tab hover → `(平台 id, 触发点中心 x)`;移出触发 800ms 后关闭浮层。
  final void Function(String id, double centerX) onPlatformHover;
  final VoidCallback onPlatformHoverEnd;

  /// 「我的关注」入口 hover → 触发点中心 x。
  final void Function(double centerX) onFollowHover;
  final VoidCallback onFollowHoverEnd;

  /// 「我的分类」入口:hover 打开浮层,点击 toggle(均回传触发点中心 x)。
  final void Function(double centerX) onMyCategoryHover;
  final void Function(double centerX) onMyCategoryTap;
  final VoidCallback onMyCategoryHoverEnd;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.topNavHeight);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showLabels = width >= AppBreakpoints.desktop;
    return Container(
      height: AppSpacing.topNavHeight,
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(bottom: BorderSide(color: context.tokens.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          _TopNavLeading(
            currentSite: currentSite,
            showLabels: showLabels,
            onMyCategoryHover: onMyCategoryHover,
            onMyCategoryTap: onMyCategoryTap,
            onMyCategoryHoverEnd: onMyCategoryHoverEnd,
          ),
          Expanded(
            child: Center(
              child: _PlatformTabs(
                currentSite: currentSite,
                onHover: onPlatformHover,
                onHoverEnd: onPlatformHoverEnd,
              ),
            ),
          ),
          _TopNavTools(
            showLabels: showLabels,
            onFollowHover: onFollowHover,
            onFollowHoverEnd: onFollowHoverEnd,
          ),
        ],
      ),
    );
  }
}

class _TopNavLeading extends StatelessWidget {
  const _TopNavLeading({
    required this.currentSite,
    required this.showLabels,
    required this.onMyCategoryHover,
    required this.onMyCategoryTap,
    required this.onMyCategoryHoverEnd,
  });

  final String currentSite;
  final bool showLabels;

  /// 「我的分类」:hover 打开浮层,点击 toggle。
  final void Function(double centerX) onMyCategoryHover;
  final void Function(double centerX) onMyCategoryTap;
  final VoidCallback onMyCategoryHoverEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Logo(showLabel: showLabels),
        const SizedBox(width: AppSpacing.xs),
        _NavAction(
          key: const Key('nav-home'),
          icon: Icons.home_rounded,
          label: '首页',
          tooltip: '首页',
          route: '/all',
          active: currentSite == 'all',
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-category'),
          icon: Icons.grid_view_rounded,
          label: '分类',
          tooltip: '分类',
          route: _categoryRoute(currentSite),
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-my-category'),
          icon: Icons.star_border_rounded,
          label: '我的分类',
          tooltip: '我的分类(收藏常用分类)',
          showLabel: showLabels,
          onTap: onMyCategoryTap,
          onHoverStart: onMyCategoryHover,
          onHoverEnd: onMyCategoryHoverEnd,
        ),
      ],
    );
  }
}

class _TopNavTools extends StatelessWidget {
  const _TopNavTools({
    required this.showLabels,
    required this.onFollowHover,
    required this.onFollowHoverEnd,
  });

  final bool showLabels;
  final void Function(double centerX) onFollowHover;
  final VoidCallback onFollowHoverEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavAction(
          key: const Key('nav-follow'),
          icon: Icons.star_border_rounded,
          // 有在播时显示最多 3 个头像堆叠(web `nav-follow-avatars`),
          // 无在播回落星形图标。
          leading: const _NavFollowAvatars(),
          label: '我的关注',
          tooltip: '我的关注',
          route: '/follow',
          showLabel: showLabels,
          onHoverStart: onFollowHover,
          onHoverEnd: onFollowHoverEnd,
        ),
        _NavAction(
          key: const Key('nav-search'),
          icon: Icons.search_rounded,
          label: '搜索',
          tooltip: '搜索进房',
          // 对齐 web:搜索是全局弹框(`SearchDialog.vue`),不再切页面。
          onTap: (_) => openSearchDialog(context),
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-time'),
          icon: Icons.timeline_rounded,
          label: '动态',
          tooltip: '动态时间线',
          route: '/timeline',
          showLabel: showLabels,
        ),
        _NavThemeAction(showLabel: showLabels),
        _NavAction(
          key: const Key('nav-settings'),
          icon: Icons.settings_outlined,
          label: '设置',
          tooltip: '设置',
          route: '/settings',
          showLabel: showLabels,
        ),
        _UserAvatar(showLabels: showLabels),
      ],
    );
  }
}

/// 顶栏主题切换:在深色 ⇄ 浅色之间切换(写 `settingsProvider.setThemeMode`)。
///
/// 按钮文案与图标表示「点击后要切到的目标」:当前生效为深色 → 显示「浅色」+
/// [Icons.light_mode_outlined](与 web `NavSidebar.vue` 的 `themeMode === 'dark'
/// ? '浅色' : '深色'` 一致)。判定/切换本身由 [_isDarkTheme] / [_toggleTheme]
/// 单一实现提供,移动底栏的「主题」项复用同一份。
class _NavThemeAction extends ConsumerWidget {
  const _NavThemeAction({required this.showLabel});

  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = _isDarkTheme(context, ref);
    return _NavAction(
      key: const Key('nav-theme'),
      icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      label: isDark ? '浅色' : '深色',
      tooltip: '切换主题',
      showLabel: showLabel,
      onTap: (_) => _toggleTheme(context, ref),
    );
  }
}

/// 当前**生效**主题是否为深色。
///
/// 显式 dark/light 直接取设置值;system 按平台亮度解析 —— 与 MaterialApp 的
/// `themeMode` 解析口径一致,保证按钮文案与真实观感不拧。
bool _isDarkTheme(BuildContext context, WidgetRef ref) {
  return switch (ref.watch(settingsProvider).themeMode) {
    ThemeModeChoice.dark => true,
    ThemeModeChoice.light => false,
    ThemeModeChoice.system =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark,
  };
}

/// 深色 ⇄ 浅色 切换(顶栏与移动底栏共用,避免两处各写一份漂移)。
void _toggleTheme(BuildContext context, WidgetRef ref) {
  ref
      .read(settingsProvider.notifier)
      .setThemeMode(
        _isDarkTheme(context, ref) ? ThemeModeChoice.light : ThemeModeChoice.dark,
      );
}

/// 顶栏右侧账号区:对齐 SFVideoLive `NavSidebar.vue` 登录态的头像 + 用户名。
///
/// 登录态由 [authProvider] 驱动(data-server 账号 + JWT):
/// - restoring:头像占位 + 「…」,交互禁用;
/// - authenticated:头像 + 用户名,点击弹账号菜单(退出登录);
/// - anonymous:头像 + 「登录」,点击弹登录框。
/// 手动登录成功后的关注云同步由 FollowController 的登录监听自动触发。
/// 保留 `nav-user` 锚点;`showLabels` 时附带头像旁文案。
class _UserAvatar extends ConsumerWidget {
  const _UserAvatar({required this.showLabels});

  final bool showLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    // 登录态跃迁(手动登录/启动链完成)→ 拉取云端关注。
    // pullRemote 幂等且防重入;登录早于本页构建时由 FollowController
    // _restore 尾部直接拉取,此处只补「登录在后」的时序。
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.phase == AuthPhase.authenticated &&
          prev?.phase != AuthPhase.authenticated) {
        ref.read(followProvider.notifier).pullRemote();
      }
    });
    final authenticated = auth.phase == AuthPhase.authenticated;
    final restoring = auth.phase == AuthPhase.restoring;
    final label = restoring
        ? '…'
        : authenticated
        ? (auth.session?.username ?? '已登录')
        : '登录';

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: context.tokens.brand,
            child: Icon(
              Icons.person_outline_rounded,
              size: 16,
              color: Colors.black87,
            ),
          ),
          if (showLabels) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: authenticated
                    ? context.tokens.textPrimary
                    : context.tokens.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );

    if (restoring) {
      return Tooltip(message: '账号状态恢复中', child: row);
    }
    if (authenticated) {
      return PopupMenuButton<String>(
        key: const Key('nav-user'),
        tooltip: '账号',
        offset: const Offset(0, 30),
        color: context.tokens.surface,
        onSelected: (action) {
          if (action == 'logout') {
            ref.read(authProvider.notifier).logout();
            return;
          }
          if (action == 'credentials') {
            // 用户/平台凭证页:保存 YouTube / 小红书 等平台的登录态。
            // 用 push(不重置历史栈):凭证页返回后仍能回到原页面。
            context.push('/user');
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'credentials',
            height: 34,
            child: Row(
              children: [
                Icon(
                  Icons.key_outlined,
                  size: 15,
                  color: context.tokens.textSecondary,
                ),
                SizedBox(width: 8),
                Text(
                  '平台凭证',
                  style: TextStyle(fontSize: 12, color: context.tokens.textPrimary),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'logout',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 15, color: context.tokens.error),
                SizedBox(width: 8),
                Text(
                  '退出登录',
                  style: TextStyle(fontSize: 12, color: context.tokens.textPrimary),
                ),
              ],
            ),
          ),
        ],
        child: row,
      );
    }
    return Tooltip(
      message: '登录',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('nav-user'),
          borderRadius: AppRadius.allPill,
          hoverColor: context.tokens.surfaceSoft,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const LoginDialog(),
          ),
          child: row,
        ),
      ),
    );
  }
}

/// data-server 登录对话框:用户名/密码 + 记住密码(默认勾选)。
/// 用户名预填默认账号;成功后关闭,关注云同步由 FollowController 监听登录态触发。
class LoginDialog extends ConsumerStatefulWidget {
  const LoginDialog({super.key});

  @override
  ConsumerState<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends ConsumerState<LoginDialog> {
  final TextEditingController _userController = TextEditingController(
    text: kDefaultAuthUsername,
  );
  final TextEditingController _passController = TextEditingController();
  bool _remember = true;
  bool _busy = false;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _userController.text.trim();
    final pass = _passController.text;
    if (user.isEmpty || pass.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(authProvider.notifier)
        .login(user, pass, remember: _remember);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastError = ref.watch(authProvider).lastError;
    return AlertDialog(
      backgroundColor: context.tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        '登录账号',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.tokens.textPrimary,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _userController,
              style: TextStyle(
                fontSize: 13,
                color: context.tokens.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: '用户名',
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: context.tokens.textSecondary,
                ),
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passController,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: 13,
                color: context.tokens.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: '密码',
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: context.tokens.textSecondary,
                ),
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Checkbox(
                      value: _remember,
                      visualDensity: VisualDensity.compact,
                      activeColor: context.tokens.brand,
                      onChanged: (v) => setState(() => _remember = v ?? true),
                    ),
                  ),
                  Text(
                    '记住密码(下次打开自动登录)',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (lastError != null)
              Padding(
                padding: EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  lastError,
                  style: TextStyle(fontSize: 12, color: context.tokens.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(fontSize: 12, color: context.tokens.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.tokens.brand,
            foregroundColor: Colors.black87,
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.showLabel = true});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '紫薯直播',
      child: InkWell(
        key: const Key('nav-brand'),
        borderRadius: AppRadius.allMd,
        hoverColor: context.tokens.surfaceSoft,
        onTap: () => context.go('/all'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/ui/logo/logo-128.png',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.tokens.brand,
                    borderRadius: AppRadius.allMd,
                  ),
                  child: const Text(
                    '薯',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '紫薯直播',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.tokens.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面主导航动作:36px 级点击目标,hover/active 由 InkWell 负责,
/// 小窗口自动切换为 icon-only,平台名和动作名由 Tooltip 承载。
class _NavAction extends StatelessWidget {
  const _NavAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.route,
    this.active = false,
    this.showLabel = false,
    this.leading,
    this.onTap,
    this.onHoverStart,
    this.onHoverEnd,
  });

  final IconData icon;
  final String label;

  /// 自定义左侧图形(如「我的关注」的在播头像堆叠);为空时渲染 [icon]。
  final Widget? leading;
  final String tooltip;
  final String? route;
  final bool active;
  final bool showLabel;

  /// 自定义点击(回传触发点中心 x,供浮层定位);为空时按 [route] 跳转。
  final void Function(double centerX)? onTap;

  /// hover 浮层挂钩:进入时回传触发点中心 x(全局坐标),移出时通知关闭。
  final void Function(double centerX)? onHoverStart;
  final VoidCallback? onHoverEnd;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.tokens.brand : context.tokens.textSecondary;
    return Builder(
      builder: (hoverContext) {
        // 触发点中心 x:MouseRegion 与 InkWell 共用同一个 RenderBox 快照。
        RenderBox? box;
        double centerX() {
          final target = box ??= hoverContext.findRenderObject() as RenderBox?;
          if (target == null) return 0;
          final dx = target.localToGlobal(Offset.zero).dx;
          return dx + target.size.width / 2;
        }

        return MouseRegion(
          onEnter: (onHoverStart == null && onTap == null)
              ? null
              : (_) => onHoverStart?.call(centerX()),
          onExit: onHoverEnd == null ? null : (_) => onHoverEnd!(),
          child: Tooltip(
            message: tooltip,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadius.allMd,
                hoverColor: context.tokens.surfaceSoft,
                onTap: onTap != null
                    ? () => onTap!(centerX())
                    : (route == null ? null : () => context.go(route!)),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: showLabel ? AppSpacing.sm : AppSpacing.xs,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      leading ?? Icon(icon, size: 18, color: color),
                      if (showLabel) ...[
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlatformTabs extends StatelessWidget {
  const _PlatformTabs({
    required this.currentSite,
    required this.onHover,
    required this.onHoverEnd,
  });

  final String currentSite;

  /// hover 平台 tab → `(平台 id, 触发点中心 x)`;移出触发 800ms 后关闭。
  final void Function(String id, double centerX) onHover;
  final VoidCallback onHoverEnd;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final brand in PlatformBrandCatalog.navigationPlatforms)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Builder(
                builder: (hoverContext) => MouseRegion(
                  onEnter: (_) {
                    final box = hoverContext.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final dx = box.localToGlobal(Offset.zero).dx;
                    onHover(brand.id, dx + box.size.width / 2);
                  },
                  onExit: (_) => onHoverEnd(),
                  child: Tooltip(
                    message: brand.name,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: Key('platform-tab-${brand.id}'),
                        borderRadius: AppRadius.allSm,
                        hoverColor: context.tokens.surfaceSoft,
                        onTap: () => context.go(_platformRoute(brand.id)),
                        child: AnimatedContainer(
                          duration: AppMotion.fast,
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: currentSite == brand.id
                                ? context.tokens.surfaceRaised
                                : Colors.transparent,
                            border: Border.all(
                              color: currentSite == brand.id
                                  ? brand.color
                                  : Colors.transparent,
                            ),
                            borderRadius: AppRadius.allSm,
                            boxShadow: currentSite == brand.id
                                ? [
                                    BoxShadow(
                                      color: brand.color.withValues(
                                        alpha: 0.22,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: PlatformIcon(id: brand.id, size: 28),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _platformRoute(String id) => id == 'all' ? '/all' : '/$id';

/// 分类路由:[cid] 为空时进分类落地页(`/:site/category`,由 CategoryView
/// 默认选中第一组),否则进子分类(`/:site/category/:cid`)。
///
/// 注意路由表里 `/:site/category/:cid` 是**三/两段路径**,早期版本拼出的
/// `/all/category`(缺 cid)匹配不到任何路由 → go_router 抛 no-routes 异常。
String _categoryRoute(String site, {String? cid}) {
  final target = site.isEmpty ? 'all' : site;
  if (cid == null || cid.isEmpty) return '/$target/category';
  return '/$target/category/${Uri.encodeComponent(cid)}';
}

/// 手机(<768)底部主导航:56px 高,保留既有 nav-* 锚点契约。
///
/// 7 项对齐 SFVideoLive 移动端底部栏:紫薯 logo / 首页 / 分类 / 关注 / 搜索 /
/// 主题 / 我的。其中 `nav-home`/`nav-follow`/`nav-search`/`nav-settings` 锚点
/// 必须保留(`nav-settings` 挂在「我的」项上,该路由到 `/settings`)。
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentSite});

  final String currentSite;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 测试锚点:移动底栏容器(桌面顶栏形态下不存在)。
      key: const Key('bottom-nav'),
      height: AppSpacing.bottomNavHeight,
      decoration: BoxDecoration(
        color: context.tokens.surfaceSoft,
        border: Border(top: BorderSide(color: context.tokens.border)),
      ),
      child: Row(
        children: [
          _BottomItem(
            key: const Key('nav-brand'),
            leading: SizedBox(
              width: 26,
              height: 26,
              child: Image.asset(
                'assets/ui/logo/logo-128.png',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.tokens.brand,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '薯',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            label: '',
            route: '/all',
            active: currentSite == 'all',
          ),
          _BottomItem(
            key: const Key('nav-home'),
            leading: _bottomIcon(Icons.home_rounded, currentSite == 'all', context.tokens),
            label: '首页',
            route: '/all',
            active: currentSite == 'all',
          ),
          _BottomItem(
            key: const Key('nav-category'),
            leading: _bottomIcon(Icons.grid_view_rounded, false, context.tokens),
            label: '分类',
            route: _categoryRoute(currentSite),
            active: false,
          ),
          _BottomMyCategoryItem(currentSite: currentSite),
          _BottomItem(
            key: const Key('nav-follow'),
            leading: const _NavFollowAvatars(size: _NavFollowAvatars.bottomSize),
            label: '关注',
            route: '/follow',
            active: currentSite == 'follow',
          ),
          _BottomItem(
            key: const Key('nav-search'),
            leading: _bottomIcon(Icons.search_rounded, false, context.tokens),
            label: '搜索',
            // 与顶栏同源:搜索是全局弹框,不切页面。
            onTap: () => openSearchDialog(context),
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-time'),
            leading: _bottomIcon(
              Icons.timeline_rounded,
              currentSite == 'timeline',
              context.tokens,
            ),
            label: '动态',
            route: '/timeline',
            active: currentSite == 'timeline',
          ),
          const _BottomThemeItem(),
          _BottomItem(
            key: const Key('nav-settings'),
            leading: _bottomIcon(
              Icons.person_outline_rounded,
              currentSite == 'settings',
              context.tokens,
            ),
            label: '我的',
            route: '/settings',
            active: currentSite == 'settings',
          ),
        ],
      ),
    );
  }
}

/// 底部导航图标(按选中态着色)。
Widget _bottomIcon(IconData icon, bool active, ZishuTokens tokens) => Icon(
  icon,
  size: 20,
  color: active ? tokens.brand : tokens.textSecondary,
);

/// 移动底栏「主题」项:与顶栏 `nav-theme` 同一份判定与切换逻辑。
///
/// 文案同样表示「点击后要切到的目标」,与顶栏保持一致(旧实现是 `onTap: () {}`
/// 的空按钮 —— 移动端主题切换一直没接上)。
class _BottomThemeItem extends ConsumerWidget {
  const _BottomThemeItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = _isDarkTheme(context, ref);
    return _BottomItem(
      key: const Key('nav-theme'),
      leading: _bottomIcon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        false,
        context.tokens,
      ),
      label: isDark ? '浅色' : '深色',
      onTap: () => _toggleTheme(context, ref),
      active: false,
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    super.key,
    required this.leading,
    required this.label,
    this.route,
    required this.active,
    this.onTap,
  });

  final Widget leading;
  final String label;
  final String? route;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.tokens.brand : context.tokens.textSecondary;
    return Expanded(
      child: InkWell(
        hoverColor: context.tokens.surface,
        onTap: onTap ?? (route == null ? null : () => context.go(route!)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              // 9 项挤在 360px 宽下时,靠 scaleDown 收敛而不是溢出
              // (「我的分类」4 字在 40px 槽位里必须缩)。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: TextStyle(fontSize: 11, color: color)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 导航项里的在播关注头像堆叠(web `NavSidebar.vue` 的 `.nav-follow-avatars`)。
///
/// 规格取自 web CSS:`--nav-follow-avatar-size: 1.48rem`(≈23.68px)、
/// `--nav-follow-avatar-overlap: 0.32`(相邻头像左移 32% 宽度实现堆叠),
/// 上限 `NAV_FOLLOW_AVATAR_LIMIT = 3`;没有在播时**回落星形图标**
/// (web `v-else` 分支的 `StarFilled`)。
///
/// 在播列表走 [visibleFollowEntries] 的 `liveOnly`(与 hover 浮层同一份口径),数据由关注状态
/// 定时刷新链路(FollowStatusPoller,60s)驱动 —— 这里不另起定时器。
class _NavFollowAvatars extends ConsumerWidget {
  const _NavFollowAvatars({this.size = topSize});

  /// 顶栏尺寸:1.48rem。
  static const double topSize = 23.68;

  /// 底栏尺寸:56px 高的底栏里再留出文案行,取 20px。
  static const double bottomSize = 20;

  /// 重叠比例(web `--nav-follow-avatar-overlap`):相邻头像左移 size×0.32。
  static const double overlapRatio = 0.32;

  /// 上限(web `NAV_FOLLOW_AVATAR_LIMIT`)。
  static const int limit = 3;

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = visibleFollowEntries(ref.watch(followProvider), liveOnly: true);
    if (live.isEmpty) {
      return Icon(
        Icons.star_border_rounded,
        size: size * 0.76,
        color: context.tokens.textSecondary,
      );
    }
    final shown = live.take(limit).toList();
    final step = size * (1 - overlapRatio);
    final width = size + (shown.length - 1) * step;
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              // 左起第一个在最上层(web 用 `zIndex: length - index` 配 margin-left 负值)。
              left: i * step,
              child: _NavFollowAvatar(entry: shown[i], size: size),
            ),
        ],
      ),
    );
  }
}

/// 单个圆形头像:封面图 + 首字兜底(与浮层单格同一套兜底口径)。
class _NavFollowAvatar extends StatelessWidget {
  const _NavFollowAvatar({required this.entry, required this.size});

  final FollowEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final room = entry.room;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.tokens.surfaceRaised,
        shape: BoxShape.circle,
      ),
      child: Text(
        room.anchorName.isEmpty ? '?' : room.anchorName.substring(0, 1),
        style: TextStyle(
          fontSize: size * 0.5,
          color: context.tokens.textSecondary,
        ),
      ),
    );
    return Container(
      key: Key('nav-follow-avatar-${room.site}-${room.roomId}'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.tokens.surfaceSoft),
      ),
      child: room.cover.isEmpty
          ? fallback
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: room.cover,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

/// 底栏「我的分类」项:桌面走 hover 浮层,触屏没有 hover —— 直接开管理弹窗
/// (与顶栏 hover 浮层里的「管理分类」是同一个弹窗,不是另一套实现)。
class _BottomMyCategoryItem extends StatelessWidget {
  const _BottomMyCategoryItem({required this.currentSite});

  final String currentSite;

  @override
  Widget build(BuildContext context) {
    return _BottomItem(
      key: const Key('nav-my-category'),
      leading: _bottomIcon(Icons.category_outlined, false, context.tokens),
      label: '我的分类',
      active: false,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _MyCategoryManageDialog(site: currentSite),
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
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
          fontSize: 12.5,
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

  ScrollController _controllerFor(int index) => _scrollControllers
      .putIfAbsent(index, () => ScrollController());

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
              constraints: const BoxConstraints(maxHeight: _CategoryBoard._kBoardContentMax),
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
                            fontSize: 11.5,
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
      radius: const Radius.circular(999),
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 0.64, vertical: 1.28),
          color: _hovering ? context.tokens.brand.withValues(alpha: 0.12) : null,
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.84,
              color: _hovering ? context.tokens.brand : context.tokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 「我的关注」hover 出的主播网格:对齐 SFVideoLive
/// `FollowHoverAvatarGrid.vue`(7 列、头像 1.85rem、名字 .56rem、最多 5 行滚动)。
/// 开播中优先;无开播时退化为全部关注,避免空面板。
class _FollowFlyout extends ConsumerWidget {
  const _FollowFlyout({
    required this.columns,
    required this.onEnter,
    required this.onExit,
    required this.onOpenRoom,
  });

  /// 实际列数(由壳层按在播数算好传入,与面板宽度同源)。
  final int columns;

  /// 头像 1.85rem ≈ 29.6px。
  static const double _kAvatarSize = 29.6;

  /// 名字 .56rem ≈ 9px。
  static const double _kNameSize = 8.96;

  /// 行间距 .22rem ≈ 3.52px;列间距 .06rem ≈ 0.96px。
  static const double _kRowGap = 3.52;
  static const double _kColumnGap = 0.96;

  /// 5 行可见高度 + padding(同 `.follow-hover-avatar-grid` 的 max-height)。
  static const double _kMaxHeight = 280;

  final VoidCallback onEnter;
  final VoidCallback onExit;

  /// 点主播格进播放页:由壳层提供(负责先收起浮层再入栈)。
  final void Function(FollowEntry entry) onOpenRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只列**在播**:浮层是「现在能点进去看」的快捷入口。离线条目(包括离线
    // 超关)只在「我的关注」页/播放页侧栏保留 —— 两个入口的可见性口径不同,
    // 见 follow_sort.dart 的 isPlayFollowVisible 与 visibleFollowEntries。
    // 对齐参考实现 `NavSidebar.vue`:`liveFollows` + 空态「暂无开播」
    // (旧实现在没有在播时兜底展示全部条目,与参考实现相反)。
    //
    // 与导航项的头像堆叠共用 [visibleFollowEntries] 同一份口径(同一排序、同一
    // 在播判据),避免「浮层里有 A、导航头像里是 B」的两套世界。
    final live = visibleFollowEntries(ref.watch(followProvider), liveOnly: true);
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: _FlyoutPanel(
        key: const Key('follow-flyout-panel'),
        padding: const EdgeInsets.fromLTRB(3.52, 4.16, 3.52, 3.52),
        maxHeight: _kMaxHeight,
        child: live.isEmpty
            ? const _FlyoutHint('暂无开播')
            : GridView.builder(
                shrinkWrap: true,
                itemCount: live.length,
                // 列数按实际在播数收敛:条目少时不留空列(传进来的 columns
                // 与面板宽度同源,格宽因此保持稳定)。
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 50,
                  mainAxisSpacing: _kRowGap,
                  crossAxisSpacing: _kColumnGap,
                ),
                itemBuilder: (context, index) => _FollowAvatarTile(
                  entry: live[index],
                  onTap: () => onOpenRoom(live[index]),
                ),
              ),
      ),
    );
  }
}

/// 关注浮层单格:圆形头像 + 单行名字(超长省略),点击进入播放页。
///
/// 每格底色与名字都取**平台品牌色**:底为低透明度品牌色,hover 时加深,
/// 让「哪个平台的主播」在网格里一眼可辨(未收录平台回退主文字色)。
class _FollowAvatarTile extends StatelessWidget {
  const _FollowAvatarTile({required this.entry, required this.onTap});

  final FollowEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = entry.room;
    final brand = PlatformBrandCatalog.byId(room.site);
    final color = brand?.color ?? context.tokens.textPrimary;
    return Tooltip(
      message: '${room.anchorName} · ${room.title}',
      child: Ink(
        color: color.withValues(alpha: 0.16),
        child: InkWell(
          hoverColor: color.withValues(alpha: 0.3),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 0.96,
              vertical: 2.56,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(context, room),
                SizedBox(height: 1.92),
                Text(
                  room.anchorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _FollowFlyout._kNameSize,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, RoomSummary room) {
    final fallback = CircleAvatar(
      radius: _FollowFlyout._kAvatarSize / 2,
      backgroundColor: context.tokens.surfaceRaised,
      child: Text(
        room.anchorName.isEmpty ? '?' : room.anchorName.substring(0, 1),
        style: TextStyle(fontSize: 12, color: context.tokens.textSecondary),
      ),
    );
    if (room.cover.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: room.cover,
        width: _FollowFlyout._kAvatarSize,
        height: _FollowFlyout._kAvatarSize,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

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
                    foregroundColor: context.tokens.brand,
                    textStyle: const TextStyle(fontSize: 12),
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        borderRadius: AppRadius.allPill,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9.6, vertical: 4.8),
          decoration: BoxDecoration(
            color: gold
                ? context.tokens.brand.withValues(alpha: 0.1)
                : context.tokens.surfaceSoft,
            border: Border.all(
              color: gold
                  ? context.tokens.brand.withValues(alpha: 0.55)
                  : context.tokens.border,
            ),
            borderRadius: AppRadius.allPill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star_rounded,
                size: 12,
                color: gold ? context.tokens.brand : context.tokens.textSecondary,
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
                  fontSize: 14.4,
                  fontWeight: FontWeight.w500,
                  color: gold ? context.tokens.brand : context.tokens.textPrimary,
                ),
              ),
            ],
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
        style: TextStyle(fontSize: 15, color: context.tokens.textPrimary),
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
                style: TextStyle(fontSize: 12, color: context.tokens.textSecondary),
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
              style: TextStyle(fontSize: 12, color: context.tokens.textSecondary),
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
                              fontSize: 12,
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
                                  label: displayCategoryName(site, item.name, item.cid),
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
            style: TextStyle(fontSize: 13, color: context.tokens.brand),
          ),
          InkWell(
            borderRadius: AppRadius.allPill,
            onTap: onRemove,
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
    return InkWell(
      borderRadius: AppRadius.allPill,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9.6, vertical: 5),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.star_rounded : Icons.star_border_rounded,
              size: 13,
              color: selected ? context.tokens.brand : context.tokens.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? context.tokens.brand : context.tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
