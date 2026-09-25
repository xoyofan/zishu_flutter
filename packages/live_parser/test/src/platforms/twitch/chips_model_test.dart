/// chip 基类模型契约:SiteChip / RoomSummary / RoomRecord 的 chips 字段
/// JSON roundtrip、mergeRefresh 保留/覆盖语义与构造深冻结。
///
/// 钉住 Stage 1 语义(2026-10 feat/twitch-tags):
/// 1. chips 默认空列表,其它平台零影响;空不写键,旧 JSON 回落空;
/// 2. mergeRefresh:fresh 非空覆盖、空保留(与 streams 同语义);
/// 3. RoomRecord 构造边界深冻结,外部改写不得渗入已构造记录;
/// 4. fromSummary/toSummary 转换链路保留 chips;fromPayload/toPayload
///    不携带 chips(播放详情模型不含分类 chip)。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  group('chips 模型契约', () {
    const tagChip = SiteChip(
      id: '77777777-7777-4777-8777-777777777777',
      name: '策略',
      kind: SiteChipKind.tag,
      filterCid: '77777777-7777-4777-8777-777777777777',
    );
    const langChip = SiteChip(
      id: 'EN',
      name: '英语',
      kind: SiteChipKind.language,
    );

    test('SiteChip navigable 判据是 filterCid 非空', () {
      expect(tagChip.navigable, isTrue);
      expect(langChip.navigable, isFalse);
      expect(
        const SiteChip(
          id: 'x',
          name: 'x',
          kind: SiteChipKind.category,
          filterCid: 'y',
        ).navigable,
        isTrue,
      );
    });

    test('RoomSummary chips JSON roundtrip', () {
      const summary = RoomSummary(
        site: 'twitch',
        roomId: 'r1',
        title: 't',
        anchorName: 'a',
        cid: 'c',
        category: 'cat',
        online: '100',
        cover: '',
        chips: [tagChip, langChip],
      );

      final json = summary.toJson();
      expect(json['chips'], isA<List<dynamic>>());
      final restored = RoomSummary.fromJson(json);
      expect(restored.chips, [tagChip, langChip]);

      expect(
        const RoomSummary(
          site: 'twitch',
          roomId: 'r2',
          title: '',
          anchorName: '',
          cid: '',
          category: '',
          online: '',
          cover: '',
        ).toJson().containsKey('chips'),
        isFalse,
        reason: '空 chips 不写键(旧 JSON 形态兼容)',
      );
      expect(
        RoomSummary.fromJson(const {'site': 'twitch', 'roomId': 'r3'}).chips,
        isEmpty,
        reason: '无 chips 键的旧 JSON 回落空列表',
      );
    });

    test('RoomRecord chips JSON roundtrip 与构造深冻结', () {
      final source = <SiteChip>[tagChip];
      final record = RoomRecord(
        site: 'twitch',
        roomId: 'r1',
        roomState: RoomState.live,
        chips: source,
      );

      final restored = RoomRecord.fromJson(record.toJson());
      expect(restored.chips, [tagChip]);

      source.clear();
      expect(
        record.chips,
        [tagChip],
        reason: '外部列表事后改写不得影响已构造记录(构造边界深冻结)',
      );
      expect(
        () => record.chips.add(langChip),
        throwsUnsupportedError,
        reason: '记录暴露的 chips 列表本身也不可改写',
      );
      expect(
        RoomRecord.fromJson(const {'site': 'twitch', 'roomId': 'r9'}).chips,
        isEmpty,
        reason: '无 chips 键的旧 JSON 回落空列表',
      );
      expect(
        RoomRecord(
          site: 'other',
          roomId: 'x',
          roomState: RoomState.offline,
        ).chips,
        isEmpty,
        reason: '默认空列表保证其它平台零影响',
      );
    });

    test('fromSummary/toSummary 转换链路保留 chips', () {
      const summary = RoomSummary(
        site: 'twitch',
        roomId: 'r1',
        title: 't',
        anchorName: 'a',
        cid: '',
        category: '',
        online: '1',
        cover: '',
        chips: [tagChip],
      );
      final record = RoomRecord.fromSummary(summary);
      expect(record.chips, [tagChip]);
      expect(record.toSummary().chips, [tagChip]);
    });

    test('mergeRefresh:fresh 非空覆盖,空保留旧 chips', () {
      final old = RoomRecord(
        site: 'twitch',
        roomId: 'r1',
        roomState: RoomState.live,
        chips: const [tagChip],
      );

      final mergedKeep = old.mergeRefresh(
        RoomRecord(
          site: 'twitch',
          roomId: 'r1',
          roomState: RoomState.offline,
          // fresh 未提供 chips → 保留旧值。
        ),
      );
      expect(mergedKeep.chips, [tagChip]);

      final fresh = RoomRecord(
        site: 'twitch',
        roomId: 'r1',
        roomState: RoomState.live,
        chips: const [langChip],
      );
      expect(
        old.mergeRefresh(fresh).chips,
        [langChip],
        reason: 'fresh 提供了 chips → 覆盖旧值',
      );
    });

    test('fromPayload/toPayload 不携带 chips(播放详情模型不含分类 chip)', () {
      final record = RoomRecord(
        site: 'twitch',
        roomId: 'r1',
        roomState: RoomState.live,
        chips: const [tagChip],
      );
      expect(record.toPayload().toJson().containsKey('chips'), isFalse);
      expect(RoomRecord.fromPayload(record.toPayload()).chips, isEmpty);
    });
  });
}
