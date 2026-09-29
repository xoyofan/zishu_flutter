import 'dart:async';
import 'dart:io';

/// 外部 override 默认路径(仅 Windows):`%APPDATA%\zishu_flutter\overrides\tokens.json`。
///
/// 与播放日志同一条「应用数据根」约定(`zishu_flutter`),但日志在 `logs/`
/// 子目录、override 在 `overrides/` 子目录,互不相混。非 Windows 平台返回
/// null:免重打包热更目前只有 Windows 产品需要,Web/Android 只用打包默认。
String? externalZishuTokensOverridePath() {
  if (!Platform.isWindows) return null;
  final base = Platform.environment['APPDATA'];
  if (base == null || base.isEmpty) return null;
  return '$base\\zishu_flutter\\overrides\\tokens.json';
}

/// 读取外部 override 文件内容;[path] 为 null 时用默认路径。
/// 不存在 / IO 失败一律返回 null(上层回退到打包默认),不向上抛。
Future<String?> readZishuTokensOverrideFile(String? path) async {
  final resolved = path ?? externalZishuTokensOverridePath();
  if (resolved == null) return null;
  try {
    return await File(resolved).readAsString();
  } on Object {
    return null;
  }
}

/// 监听外部 override 文件变更(创建 / 写入 / 原子替换),事件不携带内容,
/// 由上层去抖后重读。无法监听(平台不支持 / 路径无法解析)返回 null。
///
/// 监听**父目录**而非文件本身:编辑器保存常用「临时文件 + rename」原子替换,
/// 只盯文件会漏;目录级事件能同时覆盖 create/write/move。目录不存在时顺手
/// 创建 —— 让「先装目录再放文件」的用户在放文件那一刻就被监听到。
Stream<void>? watchZishuTokensOverrideFile(String? path) {
  final resolved = path ?? externalZishuTokensOverridePath();
  if (resolved == null) return null;
  final file = File(resolved);
  try {
    final dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final target = _normalize(file.path);
    return dir
        .watch()
        .where((event) => _normalize(event.path) == target)
        .map<void>((_) {});
  } on Object {
    return null;
  }
}

/// Windows 文件系统大小写不敏感且分隔符有两种写法,监听事件的 path 与
/// 目标路径统一成「正斜杠 + 小写」再比对。
String _normalize(String p) => p.replaceAll('\\', '/').toLowerCase();
