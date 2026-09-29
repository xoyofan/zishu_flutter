/// 外部 override 文件的平台接入层。
///
/// IO 平台(Windows)读 `%APPDATA%` 下的 override 文件并提供目录监听;
/// Web 等无 `dart:io` 平台走空实现(没有外部层,只剩打包 JSON 与代码常量)。
/// 本文件按目标平台二选一导出,签名刻意不出现任何 `dart:io` 类型,
/// 保证 tokens_override.dart 本体可被三端共享编译。
library;

export 'tokens_external_none.dart'
    if (dart.library.io) 'tokens_external_io.dart';
