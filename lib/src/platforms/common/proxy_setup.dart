/// 启动早期的上游代理探测:海外平台(twitch/youtube)直连不可达的网络下,
/// 解析与弹幕必须走代理。
///
/// 探测顺序(与 web streaming-server platform-http.ts 的 env 口径对齐):
/// 1. 环境变量 HTTPS_PROXY / https_proxy / HTTP_PROXY / http_proxy / LIVE_PROXY;
/// 2. Windows 系统代理(注册表 `ProxyEnable` + `ProxyServer`)——桌面用户
///    开 Clash/v2RayN 后大多只改系统代理,环境变量往往为空。
/// 探测结果注入解析包 [UpstreamProxy],HTTP 与弹幕 WebSocket 共用。
library;

import 'dart:io';

import 'package:live_parser/live_parser.dart';

/// 探测并配置上游代理;幂等,失败静默(保持直连)。
Future<void> configureUpstreamProxy() async {
  try {
    final env = Platform.environment;
    var hostPort = _normalize(
      env['HTTPS_PROXY'] ??
          env['https_proxy'] ??
          env['HTTP_PROXY'] ??
          env['http_proxy'] ??
          env['LIVE_PROXY'],
    );
    hostPort ??= await _windowsSystemProxy();
    UpstreamProxy.configure(hostPort);
  } catch (_) {
    // 探测失败保持直连,不阻塞启动。
  }
}

/// 归一为 `host:port`:剥掉 scheme 与尾部斜杠;无法解析返回 null。
String? _normalize(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  value = value.split('/').first;
  if (!value.contains(':')) return null; // 无端口,视为不可用配置
  return value;
}

/// 读 Windows 系统代理(注册表 Internet Settings)。
Future<String?> _windowsSystemProxy() async {
  if (!Platform.isWindows) return null;
  const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  try {
    final enable = await Process.run('reg', [
      'query',
      key,
      '/v',
      'ProxyEnable',
    ]).timeout(const Duration(seconds: 3));
    // 输出行形如 `    ProxyEnable    REG_DWORD    0x1`
    if (!RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1').hasMatch(enable.stdout)) {
      return null;
    }
    final server = await Process.run('reg', [
      'query',
      key,
      '/v',
      'ProxyServer',
    ]).timeout(const Duration(seconds: 3));
    // 值形如 `127.0.0.1:7897`;分协议形式 `http=...;https=...;ftp=...`
    // 取 https 段(https=127.0.0.1:7897 或仅 `=host:port` 的尾段)。
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(
      server.stdout,
    );
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains(';')) {
      for (final part in raw.split(';')) {
        final segment = part.trim();
        if (segment.startsWith('https=')) {
          return _normalize(segment.substring('https='.length));
        }
      }
      return null;
    }
    return _normalize(raw);
  } catch (_) {
    return null;
  }
}
