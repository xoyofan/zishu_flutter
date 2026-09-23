import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  test('每个注册平台的展示列与标签固定', () {
    final registry = buildSiteRegistry();

    expect(
      registry['douyu']!.display.roomStats.map((column) => column.label),
      ['观众', '贵宾', '钻粉'],
    );
    expect(
      registry['huya']!.display.roomStats.map((column) => column.label),
      ['观众', '贵宾', '超粉'],
    );
    expect(
      registry['bilibili']!.display.roomStats.map((column) => column.label),
      ['观众', '粉丝勋章', '大航海'],
    );
    expect(
      registry['douyin']!.display.roomStats.map((column) => column.label),
      ['观众', '粉丝团', '会员'],
    );
    expect(
      registry['soop']!.display.roomStats.map((column) => column.label),
      ['观看', '订阅'],
    );
    expect(registry['twitch']!.display.roomStats.single.label, '观众');
    expect(registry['iptv']!.display.roomStats, isEmpty);
  });

  test('平台声明的公共开关与统计列一致', () {
    final registry = buildSiteRegistry();

    expect(registry['douyu']!.display.showFollowers, isTrue);
    expect(registry['douyu']!.display.showStartedAt, isTrue);
    expect(registry['huya']!.display.showFollowers, isTrue);
    expect(registry['huya']!.display.showStartedAt, isFalse);
    expect(registry['bilibili']!.display.showFollowers, isTrue);
    expect(registry['douyin']!.display.showFollowers, isTrue);
    expect(registry['soop']!.display.showStartedAt, isTrue);
    expect(registry['twitch']!.display.showStartedAt, isTrue);
    expect(registry['iptv']!.display.showFollowers, isFalse);
  });

  test('SiteRegistration 未传 display 时使用空展示能力', () {
    final registration = SiteRegistration(
      id: 'fake',
      name: 'Fake',
      capabilities: const SiteCapabilities(),
      resolver: const UnsupportedRoomResolver('fake'),
    );

    expect(registration.display.roomStats, isEmpty);
    expect(registration.display.showFollowers, isFalse);
    expect(registration.display.showStartedAt, isFalse);
  });
}
