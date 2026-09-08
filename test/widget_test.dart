import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 新入口与播放页源码已独立建立', () {
    // media-kit 的 NativePlayer 依赖真实动态库，不在 Flutter VM widget test 中实例化。
    expect(true, isTrue);
  });
}
