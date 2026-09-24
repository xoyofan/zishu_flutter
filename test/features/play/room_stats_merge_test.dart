/// 播放页统计合并 `mergeDisplayStats` 的 RoomRecord 语义单测(统一契约 Task 5a-2)。
///
/// 钉住的口径:
/// - 逐字段合并:parsed 有值覆盖、缺值回退 local、两侧都没有保持 null(展示「—」);
/// - `roomState` 真源:parsed 非空时状态取 parsed,local 仅在 parsed 整体缺失时兜底;
/// - `audience` 只认 `tryParseOnlineCount` 可解析的可信数值:拒绝「直播中」类
///   在播占位文案,合法 `'0'` 不当作缺失;
/// - 两侧都为 null 时返回 null,不伪造任何零。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show RoomRecord, RoomState;
import 'package:zishu_flutter/src/features/play/application/room_stats_provider.dart';

RoomRecord _record({
  String site = 'douyu',
  String roomId = '1',
  RoomState roomState = RoomState.live,
  String? title,
  String? anchorName,
  String? cid,
  String? category,
  String? audience,
  String? followers,
  String? vip,
  String? svip,
  String? cover,
  String? avatar,
  String? promoTag,
  DateTime? startedAt,
}) => RoomRecord(
  site: site,
  roomId: roomId,
  roomState: roomState,
  title: title,
  anchorName: anchorName,
  cid: cid,
  category: category,
  audience: audience,
  followers: followers,
  vip: vip,
  svip: svip,
  cover: cover,
  avatar: avatar,
  promoTag: promoTag,
  startedAt: startedAt,
);

void main() {
  group('mergeDisplayStats(RoomRecord)', () {
    test('两侧都缺失 → null(展示层整体「—」)', () {
      expect(mergeDisplayStats(), isNull);
      expect(mergeDisplayStats(parsed: null, local: null), isNull);
    });

    test('parsed 整体缺失时整体回退 local', () {
      final local = _record(audience: '1.2万', followers: '9', vip: '8');
      final merged = mergeDisplayStats(local: local);
      expect(merged, isNotNull);
      expect(merged!.audience, '1.2万');
      expect(merged.followers, '9');
      expect(merged.vip, '8');
    });

    test('逐字段合并:parsed 有值覆盖、缺值回退 local、两侧都没有保持 null', () {
      final parsed = _record(title: '新标题', audience: '8.9万', vip: '321');
      final local = _record(
        title: '旧标题',
        anchorName: '旧主播',
        cid: 'cid-9',
        category: '网游',
        audience: '1.2万',
        followers: '12345',
        svip: '66',
      );
      final merged = mergeDisplayStats(parsed: parsed, local: local);
      expect(merged, isNotNull);
      expect(merged!.title, '新标题', reason: '新鲜解析值优先');
      expect(merged.anchorName, '旧主播', reason: 'parsed 缺字段回退 local');
      expect(merged.cid, 'cid-9');
      expect(merged.category, '网游');
      expect(merged.audience, '8.9万');
      expect(merged.followers, '12345');
      expect(merged.vip, '321');
      expect(merged.svip, '66', reason: '两侧都没有 → null,不伪造 0');
      expect(merged.roomState, RoomState.live);
    });

    test('roomState 真源:parsed 非空取 parsed,local 仅兜底', () {
      final parsed = _record(roomState: RoomState.offline);
      final local = _record(roomState: RoomState.live);
      expect(
        mergeDisplayStats(parsed: parsed, local: local)!.roomState,
        RoomState.offline,
        reason: '真实离线必须覆盖旧在播状态',
      );
      expect(
        mergeDisplayStats(local: local)!.roomState,
        RoomState.live,
      );
    });

    test('audience 只认可信数值:拒绝「直播中」占位,取另一侧可信值', () {
      final placeholder = _record(audience: '直播中', vip: '321');
      final trusted = _record(audience: '1.2万');
      final merged = mergeDisplayStats(parsed: placeholder, local: trusted);
      expect(merged!.audience, '1.2万', reason: '占位文案不是人数');
      expect(merged.vip, '321', reason: '其余字段照常逐字段合并');
    });

    test('audience 两侧都不可信 → null;合法 0 不当作缺失', () {
      final merged = mergeDisplayStats(
        parsed: _record(audience: '直播中'),
        local: _record(audience: '—'),
      );
      expect(merged!.audience, isNull, reason: '占位/未知文案不冒充人数');

      final zero = mergeDisplayStats(
        parsed: _record(audience: '0'),
        local: _record(audience: '1.2万'),
      );
      expect(zero!.audience, '0', reason: '有效 0 是可信数值,优先于旧值');
    });
  });
}
