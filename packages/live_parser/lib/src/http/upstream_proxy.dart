/// 上游代理全局配置(进程级):**按主机分流**。
///
/// 背景(2026-09-21 实测):
/// - Twitch / YouTube 在本网络**必须**经代理(直连不可达);
/// - SOOP / 斗鱼 / 虎牙 / B站 / 抖音 / 快手 / YY 等**直连可达**,走代理反而变慢:
///   同一台机器实测 SOOP 单档 assign+aid 直连 554ms、经代理 31853ms,
///   冷解析中位数直连 1090ms vs 代理 3497ms。
///
/// 因此不能「全局挂代理」——那等于给所有国内可达站点额外加一跳。本类按
/// **主机后缀策略**决定每个请求走 PROXY 还是 DIRECT,HTTP 层(ParserHttp)、
/// 弹幕传输(IoDanmakuTransport)与播放器(mpv http-proxy)共用同一份规则,
/// 避免三处各写一遍。
///
/// 探测逻辑归宿主(app 启动时读环境变量/Windows 系统代理),解析包只消费配置。
library;

import 'dart:io';

class UpstreamProxy {
  const UpstreamProxy._();

  /// 形如 `127.0.0.1:7897`;null/空 = 直连。
  static String? _hostPort;

  /// 需要走代理的主机后缀(小写)。
  ///
  /// 只收「本网络直连不可达」的域:
  /// - Twitch:GQL / usher / 播放 CDN / IRC 弹幕;
  /// - YouTube:站点、googlevideo 媒体、图片、InnerTube;
  /// - Google 翻译端点(内容中文化走它);
  /// - HuggingFace(字幕模型下载);
  /// - 志愿者翻译实例(lingva / simplytranslate)。
  static const List<String> proxyHostSuffixes = <String>[
    'twitch.tv',
    'ttvnw.net',
    'jtvnw.net',
    'youtube.com',
    'youtu.be',
    'googlevideo.com',
    'ytimg.com',
    'ggpht.com',
    'googleusercontent.com',
    'googleapis.com',
    'huggingface.co',
    'hf.co',
    'hf-mirror.com',
    'lingva.garudalinux.org',
    'lingva.lunar.icu',
    'simplytranslate.org',
    'translate.jae.fi',
  ];

  /// 配置全局上游代理;空值恢复直连。幂等,建议宿主启动时调用一次。
  static void configure(String? hostPort) {
    final trimmed = hostPort?.trim();
    _hostPort = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? get hostPort => _hostPort;

  static bool get enabled => _hostPort != null;

  /// 该主机是否需要走代理。未收录 = 直连(国内站点的默认路径)。
  ///
  /// [LIVE_PROXY_ALL]=1 时全站走代理(含国内站):供「直连路径劣化」的
  /// 网络救急 —— 本机 2026-09-29 实测:Clash TUN 直连路到斗鱼/虎牙/抖音
  /// 全部停滞(TCP 通、首字节永不到),而同一 Clash 的 HTTP 代理口
  /// (127.0.0.1:7897)全部正常。此类网络下国内站也必须走代理。
  static bool needsProxy(String host) {
    if (_hostPort == null) return false;
    if (_proxyAllHosts) return true;
    final normalized = host.toLowerCase();
    for (final suffix in proxyHostSuffixes) {
      if (normalized == suffix || normalized.endsWith('.$suffix')) return true;
    }
    return false;
  }

  /// 进程级「全站走代理」开关(env `LIVE_PROXY_ALL=1`)。
  static final bool _proxyAllHosts =
      Platform.environment['LIVE_PROXY_ALL'] == '1';

  /// `HttpClient.findProxy` 的返回值:`PROXY host:port` 或 `DIRECT`。
  static String findProxyFor(Uri uri) =>
      needsProxy(uri.host) ? 'PROXY $_hostPort' : 'DIRECT';

  /// 未配置代理时为空串;仅在 [needsProxy] 为真时给出代理串。
  static String proxyFor(Uri uri) =>
      needsProxy(uri.host) ? 'PROXY $_hostPort' : '';

  /// 无条件代理串(仅供需要「一定走代理」的调用方保留:如已确认目标的
  /// 探测脚本);业务路径请用 [findProxyFor]。
  static String get findProxyValue => 'PROXY $_hostPort';
}
