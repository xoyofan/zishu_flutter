/// RoomSummary 契约序列化:roomState 三态 roundtrip 与旧 JSON 兼容。
///
/// 钉住两点(2026-09-19 replay 契约):
/// 1. `roomState` 随 toJson/fromJson 同步保留(轮播语义不因落盘/传输丢失);
/// 2. 旧 JSON(无 `roomState` 键)与未知值自然回落 offline,持久化兼容。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  group('RoomSummary roomState JSON', () {
    test('roundtrip:replay 写入并在读回后保留', () {
      const summary = RoomSummary(
        site: 'bilibili',
        roomId: '9527',
        title: '标题',
        anchorName: '主播',
        cid: '325',
        category: '英雄联盟',
        online: '',
        cover: '',
        avatar: 'https://a.test/anchor.jpg',
        roomState: RoomState.replay,
      );

      final restored = RoomSummary.fromJson(summary.toJson());

      expect(restored.roomState, RoomState.replay);
      expect(restored.toJson()['roomState'], 'replay');
      expect(
        restored.avatar,
        'https://a.test/anchor.jpg',
        reason: '主播头像随 json 回环保留(关注 hover 浮层的数据源)',
      );
    });

    test('默认 offline:构造与 toJson 显式写出', () {
      const summary = RoomSummary(
        site: 'douyu',
        roomId: '1',
        title: '',
        anchorName: '',
        cid: '',
        category: '',
        online: '',
        cover: '',
      );

      expect(summary.roomState, RoomState.offline);
      expect(summary.toJson()['roomState'], 'offline');
    });

    test('旧 JSON 兼容:无 roomState 键回落 offline,未知值亦然', () {
      final legacy = RoomSummary.fromJson({
        'site': 'huya',
        'roomId': '9527',
        'nickname': '虎牙主播',
        'online': '',
        'cover': '',
      });
      expect(legacy.roomState, RoomState.offline);

      final unknown = RoomSummary.fromJson({
        'site': 'huya',
        'roomId': '9527',
        'online': '',
        'roomState': 'some-legacy-value',
      });
      expect(unknown.roomState, RoomState.offline);
    });
  });

  group('RoomSummary diamondFans JSON(第 3 列 svip 档)', () {
    test('roundtrip:非空写入并在读回后保留', () {
      const summary = RoomSummary(
        site: 'huya',
        roomId: '9527',
        title: '标题',
        anchorName: '主播',
        cid: '1',
        category: '英雄联盟',
        online: '12.3万',
        cover: '',
        vip: '75',
        diamondFans: '1300',
      );

      final json = summary.toJson();
      expect(json['diamondFans'], '1300');

      final restored = RoomSummary.fromJson(json);
      expect(restored.diamondFans, '1300');
      expect(restored.vip, '75');
    });

    test('空串不写键(旧 JSON 与空值形态兼容)', () {
      const summary = RoomSummary(
        site: 'huya',
        roomId: '9527',
        title: '',
        anchorName: '',
        cid: '',
        category: '',
        online: '',
        cover: '',
      );

      expect(summary.diamondFans, '');
      expect(summary.toJson().containsKey('diamondFans'), isFalse);
      expect(
        RoomSummary.fromJson(const {'site': 'huya', 'roomId': '9527'}).diamondFans,
        '',
        reason: '无该键的旧 JSON 回落空串(展示为「—」)',
      );
    });
  });
}
