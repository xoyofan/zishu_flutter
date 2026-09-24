import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_display.dart';

void main() {
  test('平台列值按契约映射,缺失值为占位符', () {
    // 统一房间记录(RoomRecord 版):统计缺失为 null,不伪造 0。
    final record = RoomRecord(
      site: 'huya',
      roomId: '1',
      roomState: RoomState.live,
      audience: '12万',
      followers: '12345',
      vip: '88',
    );

    expect(roomStatValue(record, RoomStatField.audience), '12万');
    expect(roomStatValue(record, RoomStatField.vip), '88');
    expect(displayStatValue(roomStatValue(record, RoomStatField.svip)), '—');
    expect(formatFollowersValue(record.followers), '1.2万');
    expect(formatFollowersValue(null), '—');
  });

  test('平台声明决定列名而不是 UI site 分支', () {
    expect(
      displaySpecFor('douyin').roomStats.map((column) => column.label),
      ['观众', '粉丝团', '会员'],
    );
    expect(
      displaySpecFor('soop').roomStats.map((column) => column.label),
      ['观看', '订阅'],
    );
  });

  test('开播时间与弹幕能力使用统一策略', () {
    final at = DateTime(2026, 9, 24, 20, 30);
    expect(formatStartedAt(at, isLive: true), '09-24 20:30');
    expect(formatStartedAt(null, isLive: true), '开播中');
    expect(formatStartedAt(null, isLive: false), '—');
    expect(siteSupportsDanmaku('huya'), isTrue);
    expect(siteSupportsDanmaku('yy'), isTrue, reason: 'YY trident 弹幕已接入');
  });
}
