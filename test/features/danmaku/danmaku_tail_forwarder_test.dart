/// DanmakuTailForwarder 单测:环形缓冲快照 → 新增弹幕序列。
///
/// 回归背景(2026-09-11 真机实测):旧实现按 `messages.length > _sentCount`
/// 判定新消息,而会话状态是定长环形缓冲(200 条),灌满后 length 恒为上限
/// → 叠加层在连上后十几秒就再也收不到新弹幕,表现为「聊天在滚、视频上
/// 没有弹幕」。本组用例锁死该场景。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_tail_forwarder.dart';

DanmakuMessage _msg(String text) {
  return DanmakuMessage(
    type: DanmakuMessageType.chat,
    userName: '水友',
    userId: 'u1',
    text: text,
    color: 0,
  );
}

void main() {
  group('DanmakuTailForwarder', () {
    test('初始快照全量转发', () {
      final f = DanmakuTailForwarder();
      final out = f.forward([_msg('a'), _msg('b')]);
      expect(out.map((m) => m.text), ['a', 'b']);
      expect(f.lastForwarded?.text, 'b');
    });

    test('追加新消息:只转发增量', () {
      final f = DanmakuTailForwarder();
      final first = [_msg('a'), _msg('b')];
      f.forward(first);
      // 模拟 provider 的环形追加:同一批实例 + 新实例。
      final second = [...first, _msg('c'), _msg('d')];
      final out = f.forward(second);
      expect(out.map((m) => m.text), ['c', 'd']);
    });

    test('快照无变化:不转发(去抖)', () {
      final f = DanmakuTailForwarder();
      final batch = [_msg('a')];
      f.forward(batch);
      expect(f.forward(batch), isEmpty);
      expect(f.forward(List.of(batch)), isEmpty);
    });

    test('回归:缓冲灌满后 length 恒定,新消息仍持续转发', () {
      final f = DanmakuTailForwarder();
      const cap = 200;
      var snapshot = <DanmakuMessage>[];
      // 灌满缓冲。
      for (var i = 0; i < cap; i++) {
        snapshot = [...snapshot, _msg('m$i')];
      }
      f.forward(snapshot);
      // 灌满后 length 恒为 cap(旧实现在此场景下永远不转发)。
      for (var round = 0; round < 5; round++) {
        snapshot = [...snapshot.sublist(1), _msg('n$round')];
        final out = f.forward(snapshot);
        expect(out.map((m) => m.text), [
          'n$round',
        ], reason: '环形缓冲灌满后(length 恒为上限)仍必须转发新消息');
      }
    });

    test('环形整圈刷新(上次基准被淘汰):全量转发不丢消息', () {
      final f = DanmakuTailForwarder();
      final first = [_msg('a')];
      f.forward(first);
      // 两次通知之间来了超过整圈的新消息,旧的基准实例已被淘汰。
      final refreshed = [_msg('x1'), _msg('x2'), _msg('x3')];
      final out = f.forward(refreshed);
      expect(out.map((m) => m.text), [
        'x1',
        'x2',
        'x3',
      ], reason: '基准被环形淘汰时应全量转发,宁可重复不可漏');
    });

    test('空快照重置基准;再来消息时重新全量转发', () {
      final f = DanmakuTailForwarder();
      f.forward([_msg('a')]);
      expect(f.forward(const []), isEmpty);
      expect(f.lastForwarded, isNull, reason: '断开/清空后应重置基准');
      final out = f.forward([_msg('b')]);
      expect(out.map((m) => m.text), ['b']);
    });

    test('实例身份判定:同文案不同实例的新消息不被误判为旧消息', () {
      final f = DanmakuTailForwarder();
      f.forward([_msg('hello')]);
      // 新快照里「最后一条」是另一个实例但同文案 → 不影响;中间夹新消息。
      final snapshot = [_msg('hello'), _msg('world')];
      final out = f.forward(snapshot);
      // 基准 'hello' 实例已不在快照中(被淘汰)→ 全量转发。
      expect(out.map((m) => m.text), ['hello', 'world']);
    });
  });
}
