import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'src/apps/windows/windows_app.dart';

/// 默认产品入口：全新的 Windows UI。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // window_manager 必须先初始化:播放页的全屏(setFullScreen)与画中画都走它。
  // 未初始化时插件不监听窗口事件,isFullScreen() 的边界与状态同步都没有保障。
  // 非桌面平台(Web / Android)没有对应原生实现,静默跳过——那些平台的窗口呈现
  // 不由 window_manager 承担。
  try {
    await windowManager.ensureInitialized();
  } catch (_) {
    // 非桌面平台或插件缺失:无需窗口管理器。
  }
  runApp(const ProviderScope(child: WindowsApp()));
}
