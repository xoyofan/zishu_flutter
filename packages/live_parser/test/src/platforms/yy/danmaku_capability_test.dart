import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  test('YY 弹幕标记不支持:官方游客 WS 协议已失效,不注册 danmaku connector', () {
    // 对齐 web 2b2f66f:YY 游客 WS join 虽被上游接受但 0 弹幕帧(官方客户端
    // 已改用会话加密握手的私有协议),弹幕能力标记为不支持、不发起注定失败
    // 的连接;UI 按 capabilities.danmaku 禁用弹幕开关。
    final registration = buildYyRegistration();

    expect(registration.capabilities.danmaku, isFalse);
    expect(registration.danmaku, isNull);
  });
}
