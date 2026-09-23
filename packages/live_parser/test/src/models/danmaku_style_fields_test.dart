import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  test('弹幕身份字段可表达 Web guard/等级/图片语义', () {
    final message = DanmakuMessage(
      type: DanmakuMessageType.chat,
      userName: '主播',
      userId: '1',
      text: '舰长你好',
      guard: const DanmakuBadge(
        name: '舰长',
        level: 3,
        color: 0xfff39c12,
        kind: 'guard',
      ),
      userLevelIconUrl: 'https://cdn.example/wealth.png',
      userLevelBadgeStyle: 2,
      userLevelIsPolished: 1,
      userLevelColor: 0xffffff,
    );

    expect(message.guard?.kind, 'guard');
    expect(message.guard?.name, '舰长');
    expect(message.userLevelIconUrl, contains('wealth'));
    expect(message.userLevelBadgeStyle, 2);
    expect(message.userLevelIsPolished, 1);
    expect(message.userLevelColor, 0xffffff);
  });

  test('DanmakuBadge 可表达协议图与虎牙超粉字段', () {
    const badge = DanmakuBadge(
      name: '铁粉团',
      level: 13,
      iconUrl: 'https://cdn.example/badge.png',
      vFlag: 1,
      vLogo: 'https://cdn.example/v.png',
    );

    expect(badge.iconUrl, contains('badge'));
    expect(badge.vFlag, 1);
    expect(badge.vLogo, contains('/v.png'));
  });

  test('旧 DanmakuSegment 构造与空字段保持兼容', () {
    const segment = DanmakuSegment.emoji(
      text: '[smile]',
      url: 'https://x/e.png',
    );

    expect(segment.name, isEmpty);
    expect(segment.url, 'https://x/e.png');
  });
}
