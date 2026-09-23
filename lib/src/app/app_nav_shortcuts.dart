/// 全局导航快捷键:对齐桌面浏览器习惯 —— 后退 / 前进 / 首页 / 搜索。
///
/// 快捷键(浏览器同款三件套 + 通用搜索):
/// - 后退:`Alt+←`、`Alt+鼠标左键`、鼠标侧键 X1(kBackMouseButton);
/// - 前进:`Alt+→`、`Alt+鼠标右键`、鼠标侧键 X2(kForwardMouseButton);
/// - 首页:`Alt+Home`;
/// - 搜索:`Ctrl+F` / `Ctrl+K`(桌面浏览器/播放器通用入口)。
///
/// **为什么在 builder 层**:快捷键靠焦点祖先生效 —— 用户未点任何控件时
/// primaryFocus 是路由 Scope,其祖先只有 Navigator→Router→builder 树;
/// 放在 AppShell(路由内容内)会被焦点隔离,初始态收不到按键(实测
/// primaryFocus=_ModalScopeState 时 AppShell 层绑定零触发)。
///
/// **为什么又要 Router 内 context**:builder 层查不到 Navigator/GoRouterState
/// (MaterialApp.router 强制 navigatorKey=null,GoRouter 也不公开 key),故
/// 通过 [GlobalActions] 注册表由 Router 内的常驻壳层(AppShell)落地实现。
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
    show
        kBackMouseButton,
        kForwardMouseButton,
        kPrimaryMouseButton,
        kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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

  /// 搜索对话框防重入:openSearchDialog 本身不防叠,连按两次 Ctrl+F
  /// 会开两层、得关两次。标志在对话框关闭后复位。
  bool _searchOpening = false;

  /// Ctrl+F / Ctrl+K = 全局搜索。实现由 Router 内的壳层经 [GlobalActions]
  /// 注册(builder 层 context 无 Navigator/GoRouterState 可用)。
  Future<void> _openSearch() async {
    if (_searchOpening) return;
    final action = GlobalActions.openSearch;
    if (action == null) return; // 壳层尚未注册(极早期按键)。
    _searchOpening = true;
    try {
      await action();
    } finally {
      _searchOpening = false;
    }
  }

  void _handlePointer(PointerDownEvent event) {
    final buttons = event.buttons;
    if (HardwareKeyboard.instance.isAltPressed) {
      if (buttons & kPrimaryMouseButton != 0) return _back();
      if (buttons & kSecondaryMouseButton != 0) return _forward();
      // Alt + 侧键不占用:落到下面的原生侧键语义。
    }
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
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _forward,
        const SingleActivator(LogicalKeyboardKey.home, alt: true): _home,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openSearch,
      },
      child: Listener(
        // opaque:空白区也参与命中 —— Alt+点击空白处同样要能后退/前进;
        // 侧键(X1/X2)本就是「落点无关」的全局手势,不能只在内容上生效。
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointer,
        child: _NavGate(child: widget.child),
      ),
    );
  }
}

/// Alt 按下时阻断子树命中测试,让上层 [Listener] 独占该 pointer。
///
/// 为什么必须有它:Listener 与子组件的 GestureDetector 同时收到 pointer down,
/// 只拦 Listener 侧会出现「Alt+点击房间卡 → 既后退又进房」。命中测试发生在
/// pointer down 阶段,此时 Alt 已按下(HardwareKeyboard 可读),直接让子树不参与
/// 本次命中即可 —— 子组件收不到该 pointer,也就不会响应这次点击。
class _NavGate extends SingleChildRenderObjectWidget {
  const _NavGate({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _NavGateRender();
}

class _NavGateRender extends RenderProxyBox {
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (HardwareKeyboard.instance.isAltPressed) return false;
    return super.hitTestChildren(result, position: position);
  }
}

/// Router 内组件注册的全局动作表(builder 层快捷键的落地点)。
///
/// 键盘监听必须位于 MaterialApp.builder(Router **之上**,焦点祖先链恒经过),
/// 而打开对话框需要 Router **内**的 context —— 两者无法同址,故用这张注册表:
/// Router 内的常驻壳层(AppShell)在 build 时注册、dispose 时按身份清理。
///
/// 注:`MaterialApp.router` 强制 `navigatorKey = null`(其初始化列表),
/// go_router 也不公开 navigatorKey —— 无法用 key 桥接,注册表是唯一通路。
class GlobalActions {
  GlobalActions._();

  /// 全局搜索(Ctrl+F / Ctrl+K)。签名与 openSearchDialog 一致。
  static Future<void> Function()? openSearch;

  /// 当前注册者身份(实例方法 tearoff 每次求值不是同一对象,不能靠
  /// identical 比较回调 —— 用壳层实例做身份,dispose 时按己清理)。
  static Object? owner;
}
