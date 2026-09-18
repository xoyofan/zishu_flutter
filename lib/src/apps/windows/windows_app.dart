import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_back_shortcuts.dart';
import '../../app/app_router.dart';
import '../../app/app_theme.dart';
import '../../features/follow/application/settings_provider.dart';
import '../../platforms/common/playback/window_presentation.dart';

/// Windows 产品入口 app:ZishuTheme + go_router 路由 + 全局返回快捷键。
///
/// 同时是窗口几何记忆(app 壳侧接线):启动时恢复主窗口几何,窗口尺寸/位置/
/// 最大化落定时驱动 [WindowPresentation] 采集落盘,退出前 flush。窗口级状态
/// 全部收拢在 [WindowPresentation],本壳只做原生事件转发,不另存窗口状态。
class WindowsApp extends ConsumerStatefulWidget {
  const WindowsApp({super.key});

  @override
  ConsumerState<WindowsApp> createState() => _WindowsAppState();
}

class _WindowsAppState extends ConsumerState<WindowsApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    // 非桌面 / 未初始化 window_manager(VM 单测)时,下列调用在
    // WindowPresentation 内部静默降级,不抛异常。
    windowManager.addListener(this);
    unawaited(WindowPresentation.instance.restoreMainWindowGeometry());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 窗口尺寸/位置/最大化落定 → 采集几何(主窗口 debounce 500ms 落盘)。
  @override
  void onWindowResized() => WindowPresentation.instance.scheduleGeometryCapture();

  @override
  void onWindowMoved() => WindowPresentation.instance.scheduleGeometryCapture();

  @override
  void onWindowMaximize() =>
      WindowPresentation.instance.scheduleGeometryCapture();

  @override
  void onWindowUnmaximize() =>
      WindowPresentation.instance.scheduleGeometryCapture();

  @override
  void onWindowRestore() =>
      WindowPresentation.instance.scheduleGeometryCapture();

  /// 退出路径:把 debounce 未触发的最后一次几何立即落盘,避免关窗丢失。
  @override
  void onWindowClose() => unawaited(WindowPresentation.instance.flushGeometry());

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // 主题模式来自设置(浅色/深色/跟随系统),切换即重建 MaterialApp 并生效。
    final themeMode = ZishuTheme.modeOf(ref.watch(settingsProvider).themeMode);
    return MaterialApp.router(
      title: '紫薯直播',
      debugShowCheckedModeBanner: false,
      theme: ZishuTheme.light(),
      darkTheme: ZishuTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      // 全局返回(鼠标侧键 / Alt+←):包在路由内容外侧,全页面生效。
      builder: (context, child) =>
          AppBackShortcuts(router: router, child: child ?? const SizedBox.shrink()),
    );
  }
}
