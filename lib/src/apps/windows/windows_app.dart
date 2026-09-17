import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_back_shortcuts.dart';
import '../../app/app_router.dart';
import '../../app/app_theme.dart';

/// Windows 产品入口 app:ZishuTheme + go_router 路由 + 全局返回快捷键。
class WindowsApp extends ConsumerWidget {
  const WindowsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '紫薯直播',
      debugShowCheckedModeBanner: false,
      theme: ZishuTheme.dark(),
      routerConfig: router,
      // 全局返回(鼠标侧键 / Alt+←):包在路由内容外侧,全页面生效。
      builder: (context, child) =>
          AppBackShortcuts(router: router, child: child ?? const SizedBox.shrink()),
    );
  }
}
