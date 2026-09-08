import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/apps/windows/windows_app.dart';

/// 默认产品入口：全新的 Windows UI。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const WindowsApp());
}
