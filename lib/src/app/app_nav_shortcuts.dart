/// 全局导航快捷键:对齐桌面浏览器习惯 —— 后退 / 前进 / 首页 / 搜索。
///
/// 快捷键(浏览器同款三件套 + 通用搜索):
/// - 后退:`Alt+←`、鼠标侧键 X1(kBackMouseButton);
/// - 前进:`Alt+→`、鼠标侧键 X2(kForwardMouseButton);
/// - 首页:`Alt+Home`;
/// - 搜索:`Ctrl+F` / `Ctrl+K`(桌面浏览器/播放器通用入口);
/// - 刷新:`F5`(浏览器式 —— 播放页重开当前线路,否则刷新平台首页列表)。
///
/// **为什么在 builder 层**:快捷键靠焦点祖先生效 —— 用户未点任何控件时
/// primaryFocus 是路由 Scope,其祖先只有 Navigator→Router→builder 树;
/// 放在 AppShell(路由内容内)会被焦点隔离,初始态收不到按键(实测
/// primaryFocus=_ModalScopeState 时 AppShell 层绑定零触发)。
///
/// **为什么又要 Router 内 context**:builder 层查不到 Navigator/GoRouterState
/// (MaterialApp.router 强制 navigatorKey=null,GoRouter 也不公开 key),故
/// 通过 [GlobalActions] 注册表由 Router 内的组件(AppShell / HomeView /
/// PlayView)各自注册落地,注销随其 dispose。
///
/// 放在应用根部包住路由内容,所有页面共享同一份实现,避免每页各写一遍。
/// 后退判定直接走 GoRouter 自身的 `canPop()`:栈内有上一页才 pop,栈底静默
/// 不动作(与浏览器停在历史起点时一致),既不误退也不会抛
/// `GoError: There is nothing to pop`。
///
/// **前进栈**(go_router 无 forward 概念,由本组件自维护 [_forwardStack]):
/// - 后退时把当前 location 入栈,前进时取出 `go()` 回去,浏览器同语义;
/// - 除 back/forward 外的路由变化(点导航 / 进房)视为新会话,清空前进栈;
/// - 栈空时前进静默不动作。
///
/// **Alt+鼠标点击的独占**:[_NavGate] 在 Alt 按下时阻断子树命中测试,该
/// pointer 只到达本层 [Listener] —— 否则 Alt+点房间卡会同时触发「后退」与
/// 「进房」两个动作(Listener 无法取消子组件已收到的 pointer)。
///
/// 分工不变:Esc 仍由播放页自行分派(退全屏 / 画中画),Space/M/F/W 同理,
/// 此处不抢。
library;

import 'package:flutter/gestures.dart'
    show kBackMouseButton, kForwardMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../shared/application/global_actions.dart';

class AppNavShortcuts extends StatefulWidget {
  const AppNavShortcuts({super.key, required this.router, required this.child});

  /// 应用路由。显式传入而非 `GoRouter.of(context)`:调用点通常是
  /// `MaterialApp.router` 的 `builder`,其 context 位于 Router **之上**,
  /// 在那里查不到 GoRouter。
  final GoRouter router;

  final Widget child;

  @override
  State<AppNavShortcuts> createState() => _AppNavShortcutsState();
}

class _AppNavShortcutsState extends State<AppNavShortcuts> {
  /// 前进栈:后退入栈、前进出栈,浏览器同语义(go_router 本身无 forward)。
  final List<String> _forwardStack = [];

  /// 本次路由变化由本组件发起(back/forward/首页)的标记:路由监听器据此
  /// 区分「自家动作」与「用户点了导航」,只有后者才清空前进栈。
  ///
  /// go_router 的 pop/go 会同步通知 routerDelegate,故标志在同一次调用里
  /// 被消费,不存在悬挂窗口(行为由 back_shortcuts_test 钉住)。
  bool _selfNavigation = false;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    if (_selfNavigation) {
      _selfNavigation = false;
      return;
    }
    // 用户自行导航(点菜单 / 进房 / 切平台):前进语义失效,浏览器同款清空。
    _forwardStack.clear();
  }

  /// 后退:栈内有上一页才 pop;当前页同时入前进栈。
  void _back() {
    if (!widget.router.canPop()) return;
    _forwardStack.add(widget.router.state.matchedLocation);
    _selfNavigation = true;
    widget.router.pop();
  }

  /// 前进:前进栈非空则 go 回上一个后退点;栈空静默。
  void _forward() {
    if (_forwardStack.isEmpty) return;
    final target = _forwardStack.removeLast();
    _selfNavigation = true;
    widget.router.go(target);
  }

  /// 首页:go 到 `/all`。标记为自家动作 —— 前进栈保留,Alt+Home 后仍可
  /// `Alt+→` 回到刚才的房间(浏览器 Alt+Home 同样不清历史)。
  void _home() {
    if (widget.router.state.matchedLocation == '/all') return;
    _selfNavigation = true;
    widget.router.go('/all');
  }

  /// Ctrl+F / Ctrl+K = 全局搜索。实现由 Router 内的壳层经 [GlobalActions]
  /// 注册(builder 层 context 无 Navigator/GoRouterState 可用),防重入随
  /// 动作在 AppShell 侧管理。
  void _openSearch() {
    GlobalActions.call(GlobalActionNames.search);
  }

  /// 浏览器式 F5:播放页在栈顶时重开当前线路,否则刷新平台首页列表。
  ///
  /// 分发依据是「谁注册了」:播放页注册 refreshPlay、首页注册 refreshHome,
  /// 注销随 dispose 天然反映当前可见页面 —— 播放页 push 后首页仍在栈下,但
  /// refreshPlay 优先;播放页离开即注销,回落 refreshHome。
  void _refresh() {
    if (GlobalActions.isActive(GlobalActionNames.refreshPlay)) {
      GlobalActions.call(GlobalActionNames.refreshPlay);
      return;
    }
    GlobalActions.call(GlobalActionNames.refreshHome);
  }

  void _handlePointer(PointerDownEvent event) {
    final buttons = event.buttons;
    if (buttons & kBackMouseButton != 0) {
      _back();
    } else if (buttons & kForwardMouseButton != 0) {
      _forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Alt+← / Alt+→ = 浏览器后退 / 前进。Windows 下文本编辑默认绑定
        // 是 ctrl+←/→ 移词,不占用 alt+方向键,输入框聚焦时也不会被抢。
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _forward,
        const SingleActivator(LogicalKeyboardKey.home, alt: true): _home,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openSearch,
        // F5 = 浏览器式刷新(裸 F5,无修饰;文本输入不产生该键,无冲突)。
        const SingleActivator(LogicalKeyboardKey.f5): _refresh,
      },
      child: Listener(
        // opaque:空白区也参与命中 —— 鼠标侧键(X1/X2)是落点无关的全局手势。
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointer,
        // 不根据全局键盘状态阻断子树命中。Windows 切窗/Alt-Tab 偶尔会丢失
        // keyup，使 HardwareKeyboard.isAltPressed 残留为 true；若据此持续
        // 关闭 hitTestChildren，整个首页会永久失去点击能力。
        child: widget.child,
      ),
    );
  }
}
