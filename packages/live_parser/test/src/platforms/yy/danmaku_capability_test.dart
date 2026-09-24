import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  test('YY 注册项接入现行 trident 弹幕协议', () {
    // 历史结论「游客 WS join 失效」针对旧 pure_live 路径(uri=3104100);
    // 2026-09-04 逆向的现行官方 Web trident 协议(h5-sinchl.yy.com,登录/注册/
    // 模板订阅)已接入为 YyDanmakuConnector,协议级 fixture 测试覆盖帧往返。
    // 真实网络连通性尚待在线 smoke(见 tasks 已验证记录)。
    final registration = buildYyRegistration();

    expect(registration.capabilities.danmaku, isTrue);
    expect(registration.danmaku, isNotNull);
  });
}
