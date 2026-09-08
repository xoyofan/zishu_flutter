import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'engine/engine.dart';
import 'ui/ui.dart';

/// 全局 engine 服务（M1 起在依赖注入中注册到 Get）。
late final StreamApiClient streamApi;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await StreamApiConfig.resolve();
  streamApi = StreamApiClient(config: config);
  Get.put<StreamApiClient>(streamApi, permanent: true);
  SiteRegistry.init(streamApi);

  runApp(const ZishuApp());
}
