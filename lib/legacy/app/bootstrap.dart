/// 应用级启动装配。
///
/// 这里只负责创建并注册 engine 服务，不依赖任何具体 UI。Windows 新 UI、旧 Web
/// 验证 UI 以及未来其他前端入口都通过本文件复用同一套核心解析初始化。
library;

import 'package:get/get.dart';

import '../core/core.dart';
import 'stream_api_config_loader.dart';

class EngineBootstrap {
  EngineBootstrap._();

  static StreamApiClient? _streamApi;

  static StreamApiClient get streamApi {
    final client = _streamApi;
    if (client == null) {
      throw StateError('Engine 尚未初始化：请先调用 EngineBootstrap.initialize()');
    }
    return client;
  }

  static Future<StreamApiClient> initialize() async {
    final existing = _streamApi;
    if (existing != null) return existing;

    final config = await StreamApiConfigLoader.resolve();
    final client = StreamApiClient(config: config);
    _streamApi = client;

    Get.put<StreamApiClient>(client, permanent: true);
    SiteRegistry.init(client);
    return client;
  }

  /// 仅供测试或需要完整重建应用容器的宿主调用。
  static void reset() {
    SiteRegistry.reset();
    if (Get.isRegistered<StreamApiClient>()) {
      Get.delete<StreamApiClient>(force: true);
    }
    _streamApi = null;
  }
}
