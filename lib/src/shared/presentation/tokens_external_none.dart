/// 无 `dart:io` 平台(Web)的空实现:没有外部 override 层,
/// 只剩打包内 JSON 与代码常量两层。
String? externalZishuTokensOverridePath() => null;

Future<String?> readZishuTokensOverrideFile(String? path) async => null;

Stream<void>? watchZishuTokensOverrideFile(String? path) => null;
