/// 播放事件文件日志:让「真机验证」可被外部观测。
///
/// 为什么必须是文件:release 的 Windows GUI 进程没有控制台,`print` 输出
/// 直接被丢弃;schtasks 拉起时连 stdout 管道都没有。要让外部(人或诊断工具)
/// 看到播放层发生了什么(开流 / 重连 / 恢复重解析 / 终局错误),唯一的可靠
/// 通道就是把事件落到磁盘。
///
/// 设计约束:
/// - 只记录**低频生命周期事件**,mpv 的原始 error 日志行须由调用方去重后再来;
/// - 同步追加写、不刷盘(低频事件无需 flush 的持久性保证);
/// - 任何 IO 异常静默降级为「不再写」——日志器绝不能反过来弄崩播放;
/// - 超过 2MB 轮转为 `playback.old.log`,防止无限增长。
library;

import 'dart:io';

class PlaybackLog {
  PlaybackLog._();

  static const int _maxBytes = 2 * 1024 * 1024;

  static File? _file;
  static bool _broken = false;

  /// 测试注入点;生产路径 lazily 解析 `%APPDATA%\zishu_flutter\logs\playback.log`。
  static void initForTest(String path) {
    _file = File(path);
    _broken = false;
  }

  static void resetForTest() {
    _file = null;
    _broken = false;
  }

  static File? get _target {
    if (_broken) return null;
    final injected = _file;
    if (injected != null) return injected;
    try {
      final base = Platform.environment['APPDATA'];
      if (base == null || base.isEmpty) {
        _broken = true;
        return null;
      }
      final dir = Directory('$base\\zishu_flutter\\logs');
      dir.createSync(recursive: true);
      final file = File('${dir.path}\\playback.log');
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        final old = File('${dir.path}\\playback.old.log');
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
      _file = file;
      return file;
    } catch (_) {
      _broken = true;
      return null;
    }
  }

  /// 记录一条低频资源样本。RSS 只作为趋势观测,不做阈值判断或告警。
  static void writeResourceSample(
    String phase, [
    Map<String, Object?> fields = const {},
  ]) {
    final rssMb = ProcessInfo.currentRss / 1024 / 1024;
    write('resource_sample', {
      ...fields,
      'phase': phase,
      'rss_mb': rssMb.toStringAsFixed(1),
    });
  }

  /// 记录一条事件。[fields] 值会被 `toString`,键值对以空格连接。
  static void write(String event, [Map<String, Object?> fields = const {}]) {
    final file = _target;
    if (file == null) return;
    try {
      final now = DateTime.now();
      final ts = now.toIso8601String().substring(11, 23);
      final body =
          fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
      file.writeAsStringSync(
        '$ts $event${body.isEmpty ? '' : ' $body'}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 写失败(磁盘满 / 权限 / 目录被删):静默放弃,绝不影响播放。
      _broken = true;
    }
  }
}
