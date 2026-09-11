import 'package:live_parser/live_parser.dart' show DanmakuMessage;

/// 弹幕尾部转发器:把会话 provider 的环形缓冲快照换算成「新增弹幕」序列。
///
/// ## 为什么不能按长度比较(实测 bug)
/// 会话状态是**定长环形缓冲**(单房间最多 200 条,FIFO 淘汰最旧)。缓冲灌满后
/// `messages.length` 恒等于上限,「length 变大才有新消息」的比较永远为 false
/// —— 叠加层在连上后十几秒(灌满缓冲所需时间)就再也收不到任何新弹幕,
/// 表现为「聊天 tab 在滚、视频上没有弹幕」(2026-09-11 真机实测)。
///
/// 因此改用**对象身份**追踪:记录上次已转发的最后一条,在新快照里找它的
/// 最后出现位置,其后即全部新消息。环形淘汰导致找不到时(两次通知之间涌入
/// 超过整圈的新消息,极端情况)退化为全量转发——宁可重复,不可漏弹幕。
class DanmakuTailForwarder {
  DanmakuMessage? _lastForwarded;

  /// 输入最新快照,返回需要新转发的消息(可能为空)。
  List<DanmakuMessage> forward(List<DanmakuMessage> messages) {
    if (messages.isEmpty) {
      _lastForwarded = null;
      return const [];
    }
    final last = _lastForwarded;
    if (identical(messages.last, last)) return const [];
    var start = 0;
    if (last != null) {
      final idx = messages.lastIndexWhere((m) => identical(m, last));
      if (idx >= 0) {
        start = idx + 1;
      } else {
        // 上次那条已被环形淘汰:整圈刷新,全量转发并把基准重置到当前尾部。
      }
    }
    _lastForwarded = messages.last;
    return messages.sublist(start);
  }

  /// 已转发到快照的最后一条(测试与诊断用)。
  DanmakuMessage? get lastForwarded => _lastForwarded;
}
