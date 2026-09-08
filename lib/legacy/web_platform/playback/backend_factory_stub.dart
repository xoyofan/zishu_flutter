/// VM/非 Web 编译下的工厂 stub：仅在真实 Web 环境才能创建播放后端。
///
/// 单测请通过 WebVideoPlayerAdapter 的 backendFactory/surfaceFactory 注入 fake。
library;

import 'web_player_backend.dart';

WebPlayerBackend defaultWebPlayerBackendFactory(String format) =>
    throw UnsupportedError('Web 播放后端仅可在 Flutter Web 环境使用（format: $format）');

WebVideoSurface defaultWebVideoSurface() =>
    throw UnsupportedError('Web 渲染承载面仅可在 Flutter Web 环境使用');
