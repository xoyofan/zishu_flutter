/// 弹幕通道抽象：SSE 与 douyu WS 直连共用。
library;

import '../core/models/danmaku_message.dart';

/// 通道连接状态机。
enum DanmakuChannelState {
  /// 初始/未连接。
  idle,

  /// 正在建立连接。
  connecting,

  /// 已就绪（SSE 收到 `ready` 事件 / WS 完成握手并 join 房间）。
  ready,

  /// 连接中断，正在按指数退避重连。
  reconnecting,

  /// 已关闭（手动 disconnect 或重连次数耗尽）。
  closed,
}

/// 单条弹幕通道。实现方保证：
/// - `connect` 前自动断开旧连接（generation fence 防串房）；
/// - 断开后不再向 [messages] / [states] 发事件。
abstract interface class DanmakuChannel {
  String get site;

  /// 弹幕消息流（broadcast）。
  Stream<DanmakuMessage> get messages;

  /// 状态流（broadcast）。
  Stream<DanmakuChannelState> get states;

  Future<void> connect({required String roomId});

  Future<void> disconnect();
}
