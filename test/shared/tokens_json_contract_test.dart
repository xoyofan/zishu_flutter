// 契约:assets/config/tokens.json 与代码常量(ZishuTokens.dark/light)逐字节一致。
//
// 代码常量是唯一真源(AGENTS.md 视觉真源链),打包 JSON 是它的序列化产物;
// 本测试漂移即失败,并给出再生成命令。改 token 值的正常流程仍是:
// DESIGN.md → token 文件 → 本契约 → `ZISHU_REGEN_TOKENS=1` 重生成 JSON。
//
// 重新生成(漂移时按提示执行):
//   ZISHU_REGEN_TOKENS=1 flutter test test/shared/tokens_json_contract_test.dart
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/shared/presentation/tokens_override.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('打包内 tokens.json 与代码常量逐字节一致', () async {
    final encoded = encodeZishuTokensJson(ZishuTokenSet.codeDefaults);
    final file = File('assets/config/tokens.json');

    if (Platform.environment['ZISHU_REGEN_TOKENS'] == '1') {
      await file.writeAsString(encoded);
      // ignore: avoid_print
      print('已重写 ${file.path}(${encoded.length} 字节)');
      return;
    }

    final bundled = await rootBundle.loadString('assets/config/tokens.json');
    expect(
      bundled,
      encoded,
      reason: '''
assets/config/tokens.json 与代码常量漂移。
重新生成:
  ZISHU_REGEN_TOKENS=1 flutter test test/shared/tokens_json_contract_test.dart
''',
    );
  });
}
