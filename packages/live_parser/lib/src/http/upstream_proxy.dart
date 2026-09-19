/// 上游代理全局配置(进程级):海外平台(twitch/youtube)在直连不可达的
/// 网络环境下必须经代理访问 —— 与 web streaming-server `fetchPlatform`
/// 的代理网关(platform-http.ts 读 HTTPS_PROXY 等)同构。
///
/// 探测逻辑归宿主(app 启动时读环境变量/Windows 系统代理),解析包只消费
/// 配置:HTTP 层(ParserHttp)与弹幕 WebSocket 层(IoDanmakuTransport)共用。
library;

class UpstreamProxy {
  const UpstreamProxy._();

  /// 形如 `127.0.0.1:7897`;null/空 = 直连。
  static String? _hostPort;

  /// 配置全局上游代理;空值恢复直连。幂等,建议宿主启动时调用一次。
  static void configure(String? hostPort) {
    final trimmed = hostPort?.trim();
    _hostPort = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? get hostPort => _hostPort;

  static bool get enabled => _hostPort != null;

  /// HttpClient.findProxy 的返回值(CONNECT 隧道,https 同样生效)。
  static String get findProxyValue => 'PROXY $_hostPort';
}
