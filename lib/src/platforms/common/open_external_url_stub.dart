/// 非 IO 平台(Web)桩实现:不做任何事,返回 false 交由 UI 提示不可用。
///
/// 本轮平台优先级为 Windows > Web > Android;Web 端如需在新标签页打开
/// 外链,后续应在 `src/platforms/web/` 里以 `dart:js_interop` 实现。
library;

/// 用系统默认浏览器打开 [url];Web 桩恒返回 false(未打开)。
Future<bool> openExternalUrl(String url) async => false;
