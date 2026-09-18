/// chat 域弹幕去重:容量上限 + FIFO 淘汰,对齐 web `utils/danmaku/danmakuDedup.ts`
/// 的 `createDanmakuDedup`(Set 登记 + 队列 shift 淘汰最老 key)。
///
/// web 各平台提供 key 规则与容量:huya 800(`sMessageId`,`\d+-\d+` 为占位)、
/// bilibili 1200(`id_str`,纯数字为占位);id 缺失/无效时回退「用户+正文」兜底。
///
/// flutter 的 [DanmakuMessage] 契约暂无 id 字段,两平台先用兜底 key
/// `userName\u0000text`(与 web 的 fallback 语义一致);协议 id 解析补齐后由
/// 调用方改传完整 key,容量口径不变。
///
/// **已知残留**:兜底 key 会把「同一用户短时间内连发相同内容」的正常弹幕
/// 一并滤掉 —— web 靠 id 维度避免此误杀,待契约补 id 后消除。
library;

/// [allow] 返回放行与否;容量满时淘汰最早登记的 key(与 web FIFO 一致,
/// 命中不刷新位置 —— web 的 Set/队列即此语义)。
final class ChatDedup {
  ChatDedup({required this.cap});

  /// 去重容量(登记 key 数上限,超出淘汰最早登记者)。
  final int cap;
  final Set<String> _keys = <String>{};

  /// 空 key 滤除(对齐 web `if (!key) continue`)。
  bool allow(String key) {
    if (key.isEmpty) return false;
    if (_keys.length >= cap) _keys.remove(_keys.first);
    return _keys.add(key);
  }

  /// 清空(重连/换房场景由调用方决定;与 web `reset()` 同义)。
  void reset() => _keys.clear();
}
