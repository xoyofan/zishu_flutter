/// 弹幕统一消息模型。
///
/// 服务端 SSE `chat` 事件 payload（对齐 SFVideoLive web/src/platforms/connectors/sse.ts）
/// 与 douyu 浏览器 WS 直连 `chatmsg` 包均归一化到本模型；`rich` 字段预留
/// （superChat / 礼物等富内容），当前通道不填充。
library;

class DanmakuMessage {
  /// 用户昵称。
  final String user;

  /// 弹幕文本。
  final String text;

  /// 文本颜色 0xRRGGBB；null = 使用渲染默认色（白）。
  final int? color;

  /// 粉丝牌文本（如「粉丝团 21」）；无则为 null。
  final String? badge;

  /// 平台侧消息时间；SSE 通道通常为 null，渲染层用到达时间。
  final DateTime? ts;

  /// 去重用消息 id（douyu cid / SSE id）；可为空。
  final String? id;

  /// 富内容预留。
  final Map<String, dynamic>? rich;

  const DanmakuMessage({
    required this.user,
    required this.text,
    this.color,
    this.badge,
    this.ts,
    this.id,
    this.rich,
  });

  /// 从 SSE `chat` 事件 JSON 归一化。
  ///
  /// 字段对齐 sse.ts 的 chat payload：
  /// `{id?, user, text, color?, badge?, rich?, userLevel?, payGrade?}`。
  /// color 接受 int（0xRRGGBB）或 `#RRGGBB` 字符串。
  static DanmakuMessage? fromSseJson(
    Map<String, dynamic> json, {
    int seq = 0,
    String? room,
  }) {
    final text = json['text']?.toString() ?? '';
    final user = json['user']?.toString() ?? '';
    if (text.isEmpty && user.isEmpty) return null;
    final rawId = json['id']?.toString() ?? '';
    final rich = json['rich'];
    return DanmakuMessage(
      user: user,
      text: text,
      color: parseColor(json['color']),
      badge: json['badge']?.toString(),
      id: rawId.isNotEmpty ? rawId : (room != null ? '$room-$seq' : null),
      rich: rich is Map ? Map<String, dynamic>.from(rich) : null,
    );
  }

  /// 解析颜色字段：int / num 直接取 0xFFFFFF 掩码；字符串支持 `#RRGGBB`/`RRGGBB`。
  static int? parseColor(dynamic value) {
    if (value is num) return value.toInt() & 0xFFFFFF;
    if (value is String) {
      final hex = value.trim().replaceAll('#', '');
      if (hex.isEmpty) return null;
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? null : parsed & 0xFFFFFF;
    }
    return null;
  }
}
