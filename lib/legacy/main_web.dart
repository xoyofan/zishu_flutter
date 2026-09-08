import 'package:flutter/material.dart';

import 'web_app/legacy_web_ui.dart';
import 'app/bootstrap.dart';

/// 旧 Web UI 独立入口，仅保留给既有 Web 播放与 E2E 回归。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EngineBootstrap.initialize();
  runApp(const ZishuApp());
}
