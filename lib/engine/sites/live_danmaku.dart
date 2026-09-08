/// LiveDanmaku 弹幕源契约 —— 与 pure_live lib/core/interface/live_danmaku.dart:5 对齐：
/// `onMessage` / `onClose` / `onReady` 回调 + `start` / `stop` / `heartbeat`。
/// 差异：消息类型用 engine 统一的 [DanmakuMessage]（而非 pure_live 的 LiveMessage），
/// `start` 参数由 `dynamic args` 收紧为 `{required String room}`。
///
/// 由 remote/remote_danmaku_source.dart（远程 SSE/WS 通道桥接）实现；
/// 后续站点级弹幕适配器同样 implements 本契约。
library;

import '../danmaku/danmaku_message.dart';

abstract class LiveDanmaku {
  void Function(DanmakuMessage message)? onMessage;
  void Function(String message)? onClose;
  void Function()? onReady;

  int heartbeatTime = 0;

  bool get isConnected;

  void heartbeat() {}

  Future<void> start({required String room});

  Future<void> stop();
}
