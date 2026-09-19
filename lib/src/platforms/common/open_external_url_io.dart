/// IO 平台实现:调系统默认浏览器打开外部链接(Windows 优先)。
library;

import 'dart:io';

/// 用系统默认浏览器打开 [url];成功发起返回 true,失败(无可执行文件等)
/// 返回 false 而不抛出,交由调用方提示。
///
/// Windows 走 `rundll32 url.dll,FileProtocolHandler`:不经 cmd 二次解析,
/// URL 含 `&` 等特殊字符也安全;macOS/Linux 回落 `open` / `xdg-open`。
Future<bool> openExternalUrl(String url) async {
  try {
    final List<String> command;
    if (Platform.isWindows) {
      command = ['rundll32', 'url.dll,FileProtocolHandler', url];
    } else if (Platform.isMacOS) {
      command = ['open', url];
    } else {
      command = ['xdg-open', url];
    }
    final process = await Process.start(
      command.first,
      command.sublist(1),
      mode: ProcessStartMode.detached,
    );
    return process.pid > 0;
  } catch (_) {
    return false;
  }
}
