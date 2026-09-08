/// 弹幕通道矩阵：按服务端 `/api/config/playback` 的 `danmaku_connector` 配置
/// 决定各平台走 SSE 还是浏览器 WS 直连。
///
/// 配置形态（对齐 SFVideoLive live-config.json playback.danmaku_connector）：
/// `{ "douyu": "browser_ws", "douyin_native": "server_sse", ... }`。
/// Flutter Web 只消费明键与 `*_browser` 键（`*_native` 属原生端，忽略）。
/// 默认回退：douyu → WS，其余 → SSE。
library;

import 'douyu_ws_danmaku_channel.dart';
import 'sse_danmaku_channel.dart';
import 'danmaku_channel.dart';

enum DanmakuConnectorMode { browserWs, serverSse }

class DanmakuChannelResolver {
  const DanmakuChannelResolver();

  /// 返回 [site] 对应的通道实例。
  ///
  /// [playbackConfig] 为 `/api/config/playback` 响应体（可空，空则用默认矩阵）；
  /// [streamApiBaseUrl] 供 SSE 通道拼 URL。
  DanmakuChannel resolve(
    String site, {
    Map<String, dynamic>? playbackConfig,
    String? streamApiBaseUrl,
  }) {
    final mode = modeFor(site, playbackConfig);
    switch (mode) {
      case DanmakuConnectorMode.browserWs:
        return DouyuWsDanmakuChannel();
      case DanmakuConnectorMode.serverSse:
        return SseDanmakuChannel(site: site, baseUrl: streamApiBaseUrl ?? '');
    }
  }

  /// 通道决策（纯逻辑，可测）。
  static DanmakuConnectorMode modeFor(
    String site,
    Map<String, dynamic>? playbackConfig,
  ) {
    final raw = playbackConfig?['danmaku_connector'];
    final map = raw is Map ? raw : null;
    String? rawMode;
    if (map != null) {
      // Web 端优先 `*_browser` 键，其次明键；`*_native` 键不消费。
      for (final key in ['${site}_browser', site]) {
        final value = map[key]?.toString();
        if (value != null && value.isNotEmpty) {
          rawMode = value;
          break;
        }
      }
    }
    final mode = switch (rawMode) {
      'browser_ws' => DanmakuConnectorMode.browserWs,
      'server_sse' => DanmakuConnectorMode.serverSse,
      // Web 无 rust 客户端，rust_ws 回退服务端 SSE。
      'rust_ws' => DanmakuConnectorMode.serverSse,
      _ => null,
    };
    if (mode != null) {
      // browser_ws 目前仅 douyu 有 WS 协议实现（huya 配置也是 browser_ws，
      // 但未移植其协议），无实现时回退 SSE。
      if (mode == DanmakuConnectorMode.browserWs && site != 'douyu') {
        return DanmakuConnectorMode.serverSse;
      }
      return mode;
    }
    return site == 'douyu'
        ? DanmakuConnectorMode.browserWs
        : DanmakuConnectorMode.serverSse;
  }
}
