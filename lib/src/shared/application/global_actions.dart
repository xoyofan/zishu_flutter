/// 全局动作注册表:让**焦点祖先链上**的全局快捷键(必须位于
/// MaterialApp.builder 才能收到按键)调用到 **Router 内**的页面实现。
///
/// 为什么必须这样桥接(实测结论,2026-09-23):
/// - 快捷键靠焦点祖先生效:用户未点任何控件时 primaryFocus 是路由 Scope,
///   祖先只有 Navigator→Router→builder 树 —— 绑在页面内(AppShell/PlayView)
///   收不到按键(打点实测:绑定零触发);
/// - builder 层 context 又查不到 Navigator/GoRouterState(`MaterialApp.router`
///   强制 `navigatorKey = null`),打不开对话框、拿不到页面状态。
/// 所以:Router 内的组件注册动作,builder 层触发。
///
/// 并存语义(路由过渡期旧页未销毁、新页已建):同名注册**后者覆盖**;
/// 注销只在 owner 仍是自己时移除,不误删新实例。多页面各自占一个动作名
/// (首页 refreshHome / 播放页 refreshPlay),互不覆盖。
class GlobalActions {
  GlobalActions._();

  static final Map<String, ({Object owner, void Function() action})> _actions =
      {};

  /// 注册动作(owner 通常为页面/壳层 State 实例)。同名覆盖。
  static void register(
    String name, {
    required Object owner,
    required void Function() action,
  }) {
    _actions[name] = (owner: owner, action: action);
  }

  /// 注销动作;仅当该名字仍归 [owner] 所有时移除。
  static void unregister(String name, {required Object owner}) {
    final entry = _actions[name];
    if (entry != null && identical(entry.owner, owner)) {
      _actions.remove(name);
    }
  }

  /// 该动作当前是否已注册(供分发方做优先级判断)。
  static bool isActive(String name) => _actions.containsKey(name);

  /// 触发动作;未注册时静默(浏览器式:不可用的快捷键不报错)。
  static void call(String name) => _actions[name]?.action();
}

/// 动作名常量(避免各处拼写漂移)。
abstract final class GlobalActionNames {
  /// 全局搜索(Ctrl+F / Ctrl+K):AppShell 注册。
  static const String search = 'search';

  /// 刷新平台首页列表(F5):HomeView 注册。
  static const String refreshHome = 'refreshHome';

  /// 刷新/重开当前播放(F5):PlayView 注册。
  static const String refreshPlay = 'refreshPlay';
}
