/// 默认后端/承载面工厂 —— 条件导出：
/// Flutter Web 用 js_media_loader.dart 的真实实现；
/// VM（flutter test / 非 Web 编译）用 stub，调用即抛 UnsupportedError。
///
/// 适配器（web_video_player_adapter.dart）只依赖本文件 + web_player_backend.dart，
/// 因此纯逻辑测试可在 VM 上直接跑（注入 fake 工厂）。
library;

export 'backend_factory_stub.dart'
    if (dart.library.js_interop) 'js_media_loader.dart';
