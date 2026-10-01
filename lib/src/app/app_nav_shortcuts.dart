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
///
/// ## 历史栈(2026-09-27 重写:浏览器式双栈,不再依赖 Navigator 栈)
///
/// 旧实现的病根:后退用 `canPop()+pop()`(Navigator 栈),前进用 `go()`;
/// 而本仓路由全是**顶层平铺路由**,`go()` 会把 Navigator 栈重建成单页 ——
/// 于是「后退→前进」两步之后栈被 go 清空,`canPop()` 永远 false,后退彻底
/// 失效(实测操作两步就无法了)。
///
/// 现在由 [AppNavHistory] 完全自管理(浏览器同款双栈):
/// - `back`/`forward` 双栈存 location,**两个方向都用 `go()`** 导航,
///   与 Navigator 栈彻底解耦 —— 多层后退/前进、前进后再后退都成立;
/// - 自家动作(back/forward/home)以外的一切路由变化(点导航 / push 进房 /
///   pop 返回 / 搜索跳转)都视为「走到新分支」:当前页入 back 栈、清空
///   forward 栈,浏览器同语义;
/// - 双栈皆空时静默不动作,永不调 `pop()`,不存在
///   `GoError: There is nothing to pop`。
///
/// **Alt+鼠标点击的独占**:[_NavGate] 在 Alt 按下时阻断子树命中,该
/// pointer 只到达本层 [Listener] —— 否则 Alt+点房间卡会同时触发「后退」与
/// 「进房」两个动作(Listener 无法取消子组件已收到的 pointer)。
///
/// 分工不变:Esc 仍由播放页自行分派(退全屏 / 画中画),Space/M/F/W 同理,
/// 此处不抢。
///
/// **Windows runner 兜底通道**:鼠标手势软件模拟的 Alt+←/→/Home 到不了
/// framework 快捷键层(引擎会剥离合成注入的 Alt 修饰,PostMessage 直投顶层
/// 甚至不派发;定性实验见 nav_syskey_channel.dart)。runner 在消息层识别
/// `KF_ALTDOWN`+方向键后经 `zishu/windows/nav_syskey` 直发本类同款动作,
/// 并消费原始消息 —— Windows 上 Alt 导航实际走该单路径,下方 SingleActivator
/// 保留作兼容兜底(测试宿主/其它平台)。
library;

import 'package:flutter/gestures.dart'
    show kBackMouseButton, kForwardMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../platforms/windows/nav_syskey_channel.dart' as nav_syskey;
import '../shared/application/global_actions.dart';

/// 应用级浏览器式导航历史(后退/前进双栈)。
///
/// 单例([instance])由两方共享:
/// - [AppNavShortcuts](builder 层)负责挂接路由监听并驱动 Alt 快捷键/鼠标侧键;
/// - 播放页等 Router 内组件可读 `canBack` 并调用 [back]/[forward],在
///   Navigator 栈没有上一层(go 重建的单页栈)时也能正确回退。
///
/// location 一律存 `state.uri.toString()`(含 query),回跳时 `go()` 原样
/// 还原;`matchedLocation` 会丢 query,深链参数会静默丢失,不能用。
class AppNavHistory {
  AppNavHistory._();

  static final AppNavHistory instance = AppNavHistory._();

  GoRouter? _router;

  /// 后退栈:走过的 location,栈顶是「来路」。
  final List<String> _back = [];

  /// 前进栈:被后退放弃的 location,栈顶是最近的那个。
  final List<String> _forward = [];

  /// 最近一次路由变化后的 location(监听器在变化**之后**触发,只能靠
  /// 自己记住上一站,才能在用户导航时把「来路」压进后退栈)。
  String? _current;

  /// 本次路由变化由 [back]/[forward]/[home] 发起的标记:路由监听器据此
  /// 区分「自家动作」与「用户导航」,只有后者才改写双栈。
  ///
  /// go_router 的 go 会同步通知 routerDelegate,标志在同一次调用里被
  /// 消费,不存在悬挂窗口(行为由 back_shortcuts_test 钉住)。
  bool _selfNavigation = false;

  /// 后退栈非空(Alt+← 可用)。
  bool get canBack => _back.isNotEmpty;

  /// 前进栈非空(Alt+→ 可用)。
  bool get canForward => _forward.isNotEmpty;

  /// 挂接路由并开始监听。应用内只有一处调用(AppNavShortcuts);
  /// 重复 attach 同一 router 幂等,换 router 则先解绑旧的。
  ///
  /// 换 router(应用重建/测试换宿主)时必须**重置历史**:栈里存的是旧
  /// router 的 location,跨 router 沿用会让新会话凭空多出「来路」,第一次
  /// 后退就跳回旧会话的页面(测试套件里已实测)。
  void attach(GoRouter router) {
    if (identical(_router, router)) return;
    detach();
    _router = router;
    _back.clear();
    _forward.clear();
    _current = null;
    _selfNavigation = false;
    router.routerDelegate.addListener(_onRouteChanged);
  }

  /// 解除监听(随 AppNavShortcuts dispose;历史栈内容保留,热重建不丢)。
  void detach() {
    final router = _router;
    if (router == null) return;
    router.routerDelegate.removeListener(_onRouteChanged);
    _router = null;
  }

  /// 安全读取当前 location。
  ///
  /// go_router 16 的 `GoRouter.state` 实现是 `currentConfiguration.last...`
  /// —— 路由重建/过渡的短暂窗口里 match 列表为空,直接读会抛
  /// `Bad state: No element`(实测:错误兜底页点「回到首页」必现)。此时
  /// 返回 null,调用方把这次通知当 no-op 处理即可。
  String? get _location {
    final router = _router;
    if (router == null) return null;
    try {
      return router.state.uri.toString();
    } catch (_) {
      return null;
    }
  }

  void _onRouteChanged() {
    final location = _location;
    if (location == null) return;
    final previous = _current;
    _current = location;
    if (_selfNavigation) {
      _selfNavigation = false;
      return;
    }
    // 首次记录(启动)与原地重复通知不构成历史边。
    if (previous == null || previous == location) return;
    // 用户自行导航(点导航 / push 进房 / 返回按钮 pop / 搜索跳转):
    // 当前站成为「来路」入后退栈,前进语义失效 —— 浏览器同款开新分支。
    _forward.clear();
    if (_back.isEmpty || _back.last != previous) {
      _back.add(previous);
    }
  }

  /// 后退:回「来路」。双栈皆由本类维护,与 Navigator 栈无关 ——
  /// go 重建过的单页栈也能多层后退。
  void back() {
    if (_back.isEmpty) return;
    final current = _location;
    if (current == null) return;
    final target = _back.removeLast();
    if (current != target) _forward.add(current);
    _selfNavigation = true;
    _router!.go(target);
  }

  /// 前进:回到最近一次被后退放弃的页面;栈空静默。
  void forward() {
    if (_forward.isEmpty) return;
    final current = _location;
    if (current == null) return;
    final target = _forward.removeLast();
    if (current != target) _back.add(current);
    _selfNavigation = true;
    _router!.go(target);
  }

  /// 首页:`go('/all')`。与浏览器 Alt+Home 同语义 —— **不清前进栈**
  /// (Alt+Home 后仍可 Alt+→ 回到刚才的房间),同时把当前站压入后退栈,
  /// 回首页后仍能 Alt+← 原路返回。
  void home() {
    final current = _location;
    if (current == null || current == '/all') return;
    if (_back.isEmpty || _back.last != current) _back.add(current);
    _selfNavigation = true;
    _router!.go('/all');
  }
}

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
  /// runner 层 Alt+导航键兜底通道的清理函数(见 nav_syskey_channel.dart)。
  VoidCallback? _navSyskeyCleanup;

  @override
  void initState() {
    super.initState();
    AppNavHistory.instance.attach(widget.router);
    _navSyskeyCleanup = nav_syskey.installNavSyskeyChannel(
      onBack: _back,
      onForward: _forward,
      onHome: _home,
    );
  }

  @override
  void dispose() {
    _navSyskeyCleanup?.call();
    AppNavHistory.instance.detach();
    super.dispose();
  }

  void _back() => AppNavHistory.instance.back();

  void _forward() => AppNavHistory.instance.forward();

  void _home() => AppNavHistory.instance.home();

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
