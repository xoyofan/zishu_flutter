import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/app/app_version.dart';

void main() {
  test('窗口标题自动附加当前构建版本', () {
    expect(
      formatWindowTitle(
        pageTitle: '直播间',
        appName: '紫薯直播',
        version: '1.0.3-beta',
      ),
      '直播间 · 紫薯直播 1.0.3-beta',
    );
  });

  test('版本不可用时保持原应用名', () {
    expect(
      formatWindowTitle(pageTitle: '分类', appName: '紫薯直播', version: ''),
      '分类 · 紫薯直播',
    );
  });
}
