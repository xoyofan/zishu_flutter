import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../features/browse/application/browse_provider.dart';
import '../features/browse/application/my_category_provider.dart';
import '../features/follow/application/follow_provider.dart';
import '../shared/application/auth_provider.dart';
import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/platform_brands.dart';
import '../shared/presentation/widgets/platform_icon.dart';

/// 应用壳层:桌面/平板(>=768)为 44px 顶部导航;
/// 手机(<768)为平台条 + 56px 底部主导航。结构对齐 SFVideoLive
/// `NavSidebar.vue` 的品牌区、中心平台区与右侧工具区。
/// 播放页不套壳。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.site, required this.child});

  /// 当前选中的平台 id(`all` = 全平台聚合)。
  final String site;
  final Widget child;

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
    final isPhone = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;
    // hover 浮层只走桌面/平板(触屏无 hover 语义)。
    final showPlatformFlyout = !isPhone && _hoveredPlatform != null;
    final showFollowFlyout = !isPhone && _followHover;
    final showMyCatFlyout = !isPhone && _myCatHover;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
          bottomNavigationBar: isPhone ? _BottomNav(currentSite: widget.site) : null,
        ),
        if (showPlatformFlyout)
          _HoverOverlay(
            centerX: _hoveredPlatformX,
            width: _kPlatformFlyoutWidth,
            child: _PlatformCategoryFlyout(
              site: _hoveredPlatform!,
              onEnter: _cancelClose,
              onExit: _scheduleClose,
            ),
          ),
        if (showFollowFlyout)
          _HoverOverlay(
            centerX: _followX,
            width: _kFollowFlyoutWidth,
            child: _FollowFlyout(onEnter: _cancelClose, onExit: _scheduleClose),
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

/// 平台分类浮层宽度:对齐 SFVideoLive `.nav-platform-menu`
/// (min-width 12rem / max-width 56rem),这里取中间值 + 由 _HoverOverlay 夹到视口内。
const double _kPlatformFlyoutWidth = 560;

/// 关注浮层宽度:对齐 `.nav-follow-flyout` 的 21rem(16px 基准 ≈ 336px)。
const double _kFollowFlyoutWidth = 336;

/// 我的分类浮层宽度:chips 折行,取略窄于关注浮层的 20rem(16px 基准 ≈ 320px)。
const double _kMyCategoryFlyoutWidth = 320;

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

/// 移动端平台条:竖屏(X < 768)两行网格,对齐 SFVideoLive
/// `responsive-chrome.css:265-369`(`nav-platform-strip__item` flex 1 1 15% →
/// 12 项平分两行、隐藏平台文字、图标 1.75rem、箭头列 1.8rem、不滚动)。
///
/// 每格 = 品牌图标入口(锚点 `platform-tab-{site}`)+ 独立分类箭头(锚点
/// `platform-category-{site}`),各自语义动作分离;平台清单来自
/// `PlatformBrandCatalog.navPlatforms`(每行 6 项,共 2 行)。
class _PlatformStrip extends StatelessWidget {
  const _PlatformStrip({required this.currentSite});

  final String currentSite;

  /// 图标尺寸(对齐 CSS 1.75rem,16px 基准 ≈ 28px)。
  static const double _kIconSize = 28;

  /// 分类箭头列宽(对齐 CSS 1.8rem ≈ 28.8px)。
  static const double _kArrowWidth = 28.8;

  /// 单行高度:图标 + 上下内边距。
  static const double _kRowHeight = 44;

  /// 两行内容高度(单行高 × 2 + 行距)。
  static const double _kContentHeight = _kRowHeight * 2 + 8;

  /// 每行平台数:12 项 → 6 × 2。
  static const int _kColumns = 6;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final platforms = PlatformBrandCatalog.navPlatforms;
    final rows = <Widget>[
      for (int r = 0;
          r < ((platforms.length / _kColumns).ceil());
          r++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                for (int c = 0; c < _kColumns; c++)
                  if (r * _kColumns + c < platforms.length)
                    _StripGridCell(
                      brand: platforms[r * _kColumns + c],
                      selected: platforms[r * _kColumns + c].id == currentSite,
                    ),
              ],
            ),
          ),
        ),
    ];
    return Container(
      padding: EdgeInsets.only(top: safeTop),
      decoration: const BoxDecoration(
        color: AppColors.surfaceSoft,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        height: _kContentHeight,
        child: Column(children: rows),
      ),
    );
  }
}

/// 平台条单格:图标入口(点击跳平台首页)+ 分类箭头(点击跳平台分类页)。
class _StripGridCell extends StatelessWidget {
  const _StripGridCell({required this.brand, required this.selected});

  final PlatformBrand brand;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: brand.name,
              child: InkWell(
                key: Key('platform-tab-${brand.id}'),
                onTap: () => context.go(_platformRoute(brand.id)),
                hoverColor: AppColors.surfaceRaised,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: selected
                        ? brand.color.withValues(alpha: 0.16)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected ? brand.color : Colors.transparent,
                    ),
                    borderRadius: AppRadius.allSm,
                  ),
                  child: Center(
                    child: PlatformIcon(id: brand.id, size: _PlatformStrip._kIconSize),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: '${brand.name}分类',
            child: InkWell(
              key: Key('platform-category-${brand.id}'),
              onTap: () => context.go(_categoryRoute(brand.id)),
              hoverColor: AppColors.surfaceRaised,
              child: SizedBox(
                width: _PlatformStrip._kArrowWidth,
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
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
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
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
          route: '/search',
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-theme'),
          icon: Icons.dark_mode_outlined,
          label: '深色',
          tooltip: '切换主题',
          showLabel: showLabels,
        ),
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
          const CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.brand,
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
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
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
        color: AppColors.surface,
        onSelected: (action) {
          if (action == 'logout') {
            ref.read(authProvider.notifier).logout();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'logout',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 15, color: AppColors.error),
                SizedBox(width: 8),
                Text(
                  '退出登录',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
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
          hoverColor: AppColors.surfaceSoft,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const _LoginDialog(),
          ),
          child: row,
        ),
      ),
    );
  }
}

/// data-server 登录对话框:用户名/密码 + 记住密码(默认勾选)。
/// 用户名预填默认账号;成功后关闭,关注云同步由 FollowController 监听登录态触发。
class _LoginDialog extends ConsumerStatefulWidget {
  const _LoginDialog();

  @override
  ConsumerState<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends ConsumerState<_LoginDialog> {
  final TextEditingController _userController =
      TextEditingController(text: kDefaultAuthUsername);
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
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        '登录账号',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
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
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                labelText: '用户名',
                labelStyle:
                    const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passController,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                labelText: '密码',
                labelStyle:
                    const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Checkbox(
                      value: _remember,
                      visualDensity: VisualDensity.compact,
                      activeColor: AppColors.brand,
                      onChanged: (v) => setState(() => _remember = v ?? true),
                    ),
                  ),
                  const Text(
                    '记住密码(下次打开自动登录)',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  lastError,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
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
        hoverColor: AppColors.surfaceSoft,
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
                    color: AppColors.brand,
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
                const Text(
                  '紫薯直播',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
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
    this.onTap,
    this.onHoverStart,
    this.onHoverEnd,
  });

  final IconData icon;
  final String label;
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
    final color = active ? AppColors.brand : AppColors.textSecondary;
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
                hoverColor: AppColors.surfaceSoft,
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
                      Icon(icon, size: 18, color: color),
                      if (showLabel) ...[
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w500,
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
          for (final brand in PlatformBrandCatalog.navPlatforms)
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
                    hoverColor: AppColors.surfaceSoft,
                    onTap: () => context.go(_platformRoute(brand.id)),
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: currentSite == brand.id
                            ? AppColors.surfaceRaised
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
                                  color: brand.color.withValues(alpha: 0.22),
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
      height: AppSpacing.bottomNavHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSoft,
        border: Border(top: BorderSide(color: AppColors.border)),
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
                  decoration: const BoxDecoration(
                    color: AppColors.brand,
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
            leading: _bottomIcon(Icons.home_rounded, currentSite == 'all'),
            label: '首页',
            route: '/all',
            active: currentSite == 'all',
          ),
          _BottomItem(
            key: const Key('nav-category'),
            leading: _bottomIcon(Icons.grid_view_rounded, false),
            label: '分类',
            route: _categoryRoute(currentSite),
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-follow'),
            leading: _bottomIcon(Icons.star_border_rounded, currentSite == 'follow'),
            label: '关注',
            route: '/follow',
            active: currentSite == 'follow',
          ),
          _BottomItem(
            key: const Key('nav-search'),
            leading: _bottomIcon(Icons.search_rounded, false),
            label: '搜索',
            route: '/search',
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-theme'),
            leading: _bottomIcon(Icons.dark_mode_outlined, false),
            label: '主题',
            onTap: () {},
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-settings'),
            leading: _bottomIcon(
              Icons.person_outline_rounded,
              currentSite == 'settings',
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
Widget _bottomIcon(IconData icon, bool active) =>
    Icon(icon, size: 20, color: active ? AppColors.brand : AppColors.textSecondary);

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
    final color = active ? AppColors.brand : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        hoverColor: AppColors.surface,
        onTap: onTap ?? (route == null ? null : () => context.go(route!)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ],
        ),
      ),
    );
  }
}

/// hover 浮层面板容器:对齐 SFVideoLive `.nav-platform-menu` / `.nav-follow-flyout`
/// 的容器规格(面板底色 + 1px 边框 + 圆角 + shadow-16),内容超高由
/// [maxHeight] 约束后自行滚动。
class _FlyoutPanel extends StatelessWidget {
  const _FlyoutPanel({
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
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
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
          color: danger ? AppColors.error : AppColors.textSecondary,
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
        child: switch (async) {
          AsyncData(:final value) => value.groups.isEmpty
              ? const _FlyoutHint('暂无分类')
              : _CategoryBoard(site: site, groups: value.groups),
          AsyncError(:final error) =>
            _FlyoutHint(error.toString(), danger: true),
          _ => const _FlyoutHint('加载分类…'),
        },
      ),
    );
  }
}

/// 分类看板:单组平台平铺网格,多组平台横向分栏(列间 1px 竖线)。
class _CategoryBoard extends StatelessWidget {
  const _CategoryBoard({required this.site, required this.groups});

  /// 列宽 4.2rem ≈ 67px(同 `.nav-platform-menu__column`)。
  static const double _kColumnWidth = 67.2;

  final String site;
  final List<CategoryGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.length == 1) {
      // 单一大组:平铺网格(对齐 `.nav-platform-menu__hot-track`)。
      return SingleChildScrollView(
        child: Wrap(
          children: [
            for (final item in groups.first.items)
              SizedBox(
                width: _kColumnWidth,
                child: _CategoryChip(
                  key: ValueKey('flyout-category-${item.cid}'),
                  label: item.name,
                  onTap: () => _goCategory(context, item.cid),
                ),
              ),
          ],
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
              width: _kColumnWidth,
              padding: const EdgeInsets.only(left: 2.4),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 3.8),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  for (final item in group.items)
                    _CategoryChip(
                      key: ValueKey('flyout-category-${item.cid}'),
                      label: item.name,
                      onTap: () => _goCategory(context, item.cid),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 跳平台分类页:带 cid 进 `/:site/category/:cid`,CategoryView 据此高亮
  /// 所属分组与子分类(落地页形态见 [_categoryRoute])。
  void _goCategory(BuildContext context, String cid) =>
      context.go(_categoryRoute(site, cid: cid));
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
          color: _hovering ? AppColors.brand.withValues(alpha: 0.12) : null,
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.84,
              color: _hovering ? AppColors.brand : AppColors.textPrimary,
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
  const _FollowFlyout({required this.onEnter, required this.onExit});

  /// 头像 1.85rem ≈ 29.6px。
  static const double _kAvatarSize = 29.6;

  /// 名字 .56rem ≈ 9px。
  static const double _kNameSize = 8.96;

  /// 行间距 .22rem ≈ 3.52px;列间距 .06rem ≈ 0.96px。
  static const double _kRowGap = 3.52;
  static const double _kColumnGap = 0.96;
  static const int _kColumns = 7;

  /// 5 行可见高度 + padding(同 `.follow-hover-avatar-grid` 的 max-height)。
  static const double _kMaxHeight = 280;

  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(followProvider);
    final live = [for (final entry in entries) if (entry.isLive) entry];
    final list = live.isNotEmpty ? live : entries;
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: _FlyoutPanel(
        padding: const EdgeInsets.fromLTRB(3.52, 4.16, 3.52, 3.52),
        maxHeight: _kMaxHeight,
        child: list.isEmpty
            ? const _FlyoutHint('暂无关注')
            : GridView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _kColumns,
                  mainAxisExtent: 50,
                  mainAxisSpacing: _kRowGap,
                  crossAxisSpacing: _kColumnGap,
                ),
                itemBuilder: (context, index) =>
                    _FollowAvatarTile(entry: list[index]),
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
  const _FollowAvatarTile({required this.entry});

  final FollowEntry entry;

  @override
  Widget build(BuildContext context) {
    final room = entry.room;
    final brand = PlatformBrandCatalog.byId(room.site);
    final color = brand?.color ?? AppColors.textPrimary;
    return Tooltip(
      message: '${room.anchorName} · ${room.title}',
      child: Ink(
        color: color.withValues(alpha: 0.16),
        child: InkWell(
          hoverColor: color.withValues(alpha: 0.3),
          onTap: () => context.go('/${room.site}/play/${room.roomId}'),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 0.96, vertical: 2.56),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(room),
                const SizedBox(height: 1.92),
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

  Widget _avatar(RoomSummary room) {
    final fallback = CircleAvatar(
      radius: _FollowFlyout._kAvatarSize / 2,
      backgroundColor: AppColors.surfaceRaised,
      child: Text(
        room.anchorName.isEmpty ? '?' : room.anchorName.substring(0, 1),
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                    foregroundColor: AppColors.brand,
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
                ? AppColors.brand.withValues(alpha: 0.1)
                : AppColors.surfaceSoft,
            border: Border.all(
              color: gold
                  ? AppColors.brand.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
            borderRadius: AppRadius.allPill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star_rounded,
                size: 12,
                color: gold ? AppColors.brand : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.entry.name,
                style: TextStyle(
                  fontSize: 14.4,
                  fontWeight: FontWeight.w500,
                  color: gold ? AppColors.brand : AppColors.textPrimary,
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
      backgroundColor: AppColors.surface,
      title: Text(
        '我的分类(${favorites.length}/${MyCategoryController.maxCount})',
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (favorites.isNotEmpty) ...[
              const Text(
                '已收藏(点击 × 移除)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
            const Text(
              '分类目录(点击收藏/取消)',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
      AsyncData(:final value) => value.groups.isEmpty
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
                          group.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final item in group.items)
                              _PickableChip(
                                label: item.name,
                                selected: favorites.any((entry) =>
                                    entry.site == site &&
                                    entry.cid == item.cid),
                                onTap: () async {
                                  final ok = await ref
                                      .read(myCategoriesProvider.notifier)
                                      .toggle(
                                    MyCategoryEntry(
                                      site: site,
                                      cid: item.cid,
                                      name: item.name,
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
      AsyncError(:final error) =>
        _FlyoutHint('分类加载失败:$error', danger: true),
      _ => const _FlyoutHint('加载分类…'),
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
      padding: const EdgeInsets.only(left: 9.6, right: 2),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.55)),
        borderRadius: AppRadius.allPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.name,
            style: const TextStyle(fontSize: 13, color: AppColors.brand),
          ),
          InkWell(
            borderRadius: AppRadius.allPill,
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(3),
              child:
                  Icon(Icons.close_rounded, size: 13, color: AppColors.brand),
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
              ? AppColors.brand.withValues(alpha: 0.12)
              : AppColors.surfaceSoft,
          border: Border.all(
            color: selected
                ? AppColors.brand.withValues(alpha: 0.55)
                : AppColors.border,
          ),
          borderRadius: AppRadius.allPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.star_rounded : Icons.star_border_rounded,
              size: 13,
              color: selected ? AppColors.brand : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? AppColors.brand : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
