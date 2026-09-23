import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show UpstreamProxy;
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/app_router.dart';
import 'src/app/app_version.dart';
import 'src/apps/windows/windows_app.dart';
import 'src/platforms/common/playback/playback_log.dart';
import 'src/platforms/common/playback/window_presentation.dart';
import 'src/platforms/common/proxy_setup.dart';

/// 默认产品入口：全新的 Windows UI。
/// 命令行参数(Flutter 桌面经 main args 注入,如 `--route /soop/category`)
/// 供真机自动化验证直达目标页面。
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  StartupRoute.configure(args);
  // 上游代理探测(env→Windows 系统代理)先于任何解析请求:海外站
  // twitch/youtube 直连不可达,探测结果决定 HTTP/弹幕层是否走代理。
  await configureUpstreamProxy();
  // 会话分隔标记:日志会跨多次启动追加,没有它无法区分「这次运行」。
  // 同时记录代理状态 —— 海外站解析/翻译/模型下载失败时第一个要看的字段。
  PlaybackLog.write('app_start', {
    'proxy': UpstreamProxy.hostPort ?? 'direct',
    'route': StartupRoute.value,
  });
  // window_manager 必须先初始化:播放页的全屏(setFullScreen)与画中画都走它。
  // 未初始化时插件不监听窗口事件,isFullScreen() 的边界与状态同步都没有保障。
  // 非桌面平台(Web / Android)没有对应原生实现,静默跳过——那些平台的窗口呈现
  // 不由 window_manager 承担。
  try {
    await windowManager.ensureInitialized();
  } catch (_) {
    // 非桌面平台或插件缺失:无需窗口管理器。
  }
  await loadAppVersion();
  // 窗口几何恢复必须在 runApp(首帧)之前完成:runner 是「首帧就绪回调才
  // Show 窗口」,此刻窗口仍隐藏;隐藏期的 setSize/setPosition 不存在
  // 「先显示旧尺寸首帧、再 resize 触发 surface 重建」的白屏窗口期(冷启动
  // 慢时该竞态必然复现,表现为打开白屏数秒直到下一帧数据到达)。此前恢复
  // 挂在 WindowsApp.initState(runApp 之后),正是白屏根因。
  await WindowPresentation.instance.restoreMainWindowGeometry();
  runApp(const ProviderScope(child: WindowsApp()));
}
