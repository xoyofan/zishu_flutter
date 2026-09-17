/// 全局「返回」快捷键:对齐桌面浏览器习惯 —— 鼠标侧键(后退键)与 Alt+←。
///
/// 放在应用根部包住路由内容,所有页面共享同一份实现,避免每页各写一遍。
/// 判定直接走 GoRouter 自身的 `canPop()`:栈内有上一页才 pop,栈底静默不动作
/// (与浏览器停在历史起点时一致),既不误退也不会抛
/// `GoError: There is nothing to pop`(旧实现里「返回」点了没反应的真凶)。
///
/// 分工:
/// - 本组件只做「历史后退」,与播放页内的 Space/M/F/W、Esc 无关;
/// - Esc 仍由播放页自身分派(退全屏/网页全屏/画中画),不在此处抢。
/// - Alt+→(前进)未接:go_router 无 forward 概念,需要宿主自维护前进栈,
///   不属于本轮范围。
library;

import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class AppBackShortcuts extends StatelessWidget {
  const AppBackShortcuts({super.key, required this.router, required this.child});

  /// 应用路由。显式传入而非 `GoRouter.of(context)`:调用点通常是
  /// `MaterialApp.router` 的 `builder`,其 context 位于 Router **之上**,
  /// 在那里查不到 GoRouter。
  final GoRouter router;

  final Widget child;

  /// 后退:栈内有上一页才 pop。
  void _back() {
    if (router.canPop()) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Alt+← = 浏览器后退。Windows 下文本编辑默认绑定用 ctrl+← 移词,
        // 不占用 alt+←,因此输入框聚焦时也不会被抢(真被抢时不后退,无副作用)。
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
      },
      child: Listener(
        // 鼠标侧键:Windows 嵌入层把 XBUTTON1 映射为 kBackMouseButton(0x08),
        // 由 PointerDownEvent.buttons 携带。deferToChild 保证只在内容命中时
        // 参与,不额外吞掉其它指针事件的命中测试。
        onPointerDown: (event) {
          if (event.buttons & kBackMouseButton != 0) _back();
        },
        child: child,
      ),
    );
  }
}
