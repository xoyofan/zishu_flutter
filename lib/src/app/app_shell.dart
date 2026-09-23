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
import 'app_nav_shortcuts.dart';

part 'shell/hover_overlay.dart';
part 'shell/top_nav.dart';
part 'shell/theme_actions.dart';
part 'shell/user_area.dart';
part 'shell/platform_strip.dart';
part 'shell/bottom_nav.dart';
part 'shell/follow_avatars.dart';
part 'shell/category_flyout.dart';
part 'shell/my_category_flyout.dart';

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

  /// 本壳层落地给全局快捷键的搜索动作(身份用 this,见 dispose 的按己清理)。
  Future<void> _openSearchAction() => openSearchDialog(context);

  @override
  void dispose() {
    _closeTimer?.cancel();
    // 只清自己的注册:若路由过渡期新壳层已先注册,不动它的。
    if (identical(GlobalActions.owner, this)) {
      GlobalActions.openSearch = null;
      GlobalActions.owner = null;
    }
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
    // 注册全局搜索动作(Ctrl+F/Ctrl+K):快捷键监听在 Router 之上(builder 层),
    // 落地需要 Router 内 context —— 本壳层恒在 Router 内且跨页面常驻。
    GlobalActions.openSearch = _openSearchAction;
    GlobalActions.owner = this;
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
              visibleFollowEntries(
                ref.watch(followProvider),
                liveOnly: true,
              ).length,
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
({int columns, double width}) _platformFlyoutLayoutFor(CategoryResult? result) {
  final groups = result?.groups ?? const <CategoryGroup>[];
  final maxColumns =
      ((_kFlyoutMaxWidth - _kPlatformFlyoutChrome) /
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
