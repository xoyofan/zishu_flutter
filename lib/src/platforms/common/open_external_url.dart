/// 外部链接打开的平台收敛层:用系统默认浏览器打开房间 web 页等外部 URL。
///
/// 共享 UI(如播放页侧栏)不得直接 import `dart:io`(会进 Web 依赖图,
/// 同 `pip_surface.dart` 头注释的约束),故按条件导出分流:
/// - IO 平台(Windows 桌面优先)→ [openExternalUrl] 调系统默认浏览器;
/// - Web 平台 → 桩实现返回 false(UI 提示不可用;Web 端外链打开本轮不做)。
library;

export 'open_external_url_stub.dart'
    if (dart.library.io) 'open_external_url_io.dart';
