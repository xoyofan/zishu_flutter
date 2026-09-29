import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_nav_shortcuts.dart';
import '../../app/app_router.dart';
import '../../app/app_theme.dart';
import '../../features/browse/application/browse_provider.dart';
import '../../features/browse/application/category_warmup.dart';
import '../../features/follow/application/settings_provider.dart';
import '../../platforms/common/playback/window_presentation.dart';
import '../../shared/presentation/tokens_override.dart';

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
  /// 分类预热延迟触发器:dispose 时取消,避免测试环境留下 pending timer。
  Timer? _warmupTimer;

  /// 外置主题色 token 热更订阅:override 文件变更 → 重载 → 换
  /// ZishuTheme.tokens 并重建 MaterialApp(免重打包调样式;解析失败时
  /// 监听器不发事件,界面保持现值,见 tokens_override.dart)。
  StreamSubscription<ZishuTokenSet>? _tokensSub;

  @override
  void initState() {
    super.initState();
    // 非 Windows / Web 没有 override 文件,start 内部静默跳过。
    ZishuTokensReloader.instance.start();
    _tokensSub = ZishuTokensReloader.instance.changes.listen((set) {
      if (!mounted) return;
      ZishuTheme.tokens = set;
      setState(() {});
    });
    // 非桌面 / 未初始化 window_manager(VM 单测)时,下列调用在
    // WindowPresentation 内部静默降级,不抛异常。
    windowManager.addListener(this);
    // 主窗口几何恢复已上移到 main() 的 runApp 之前(见 main.dart 注释):
    // 恢复必须发生在「首帧就绪回调 Show 窗口」之前,否则隐藏期后的 resize
    // 会造成打开白屏;此处只保留几何采集(落盘)的窗口事件转发。
    // 分类预热(用户口径 2026-09-19:各平台分类与映射初始打开时异步预热
    // 进内存,hover 平台分类浮层时立即显示):延迟 2s —— 让首页首屏数据
    // 先行,再串行逐站拉分类索引进缓存;失败静默(hover 时自然重试)。
    _warmupTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      unawaited(
        warmupBrowseCategories(
          (site) => ref.read(browseCategoriesProvider(site).future),
          browseWarmupSites(),
        ),
      );
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _warmupTimer?.cancel();
    _tokensSub?.cancel();
    ZishuTokensReloader.instance.stop();
    super.dispose();
  }

  /// 窗口尺寸/位置/最大化落定 → 采集几何(主窗口 debounce 500ms 落盘)。
  @override
  void onWindowResized() =>
      WindowPresentation.instance.scheduleGeometryCapture();

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
  void onWindowClose() =>
      unawaited(WindowPresentation.instance.flushGeometry());

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
      // 全局返回(鼠标侧键 / Alt+← / Ctrl+F 搜索):包在路由内容外侧,
      // 焦点无论落在路由 Scope 还是具体控件,本层恒在焦点祖先链上。
      builder: (context, child) => AppNavShortcuts(
        router: router,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
