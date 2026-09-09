import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/app_theme.dart';

/// Windows 产品入口 app:ZishuTheme + go_router 路由。
class WindowsApp extends ConsumerWidget {
  const WindowsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '紫薯直播',
      debugShowCheckedModeBanner: false,
      theme: ZishuTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
