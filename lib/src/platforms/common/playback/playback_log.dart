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

  /// 事件分类表:按**调试场景**聚合,`cat=` 作为首个字段附加在事件名后。
  /// 快速调试口径(2026-09-28 用户要求):一 grep 拉出一类事件,例如
  /// - `grep 'cat=recovery' playback.log` —— 卡了多久、怎么恢复的;
  /// - `grep 'cat=line' playback.log` —— 选了哪条线/避让/URL 重签;
  /// - `grep 'cat=stream' playback.log` —— 缓冲与首帧健康度。
  /// 未映射事件落 `cat=other`,新增埋点忘记归类时也不会丢。
  static final Map<String, String> _eventCategories = _buildCategories();

  static Map<String, String> _buildCategories() => {
        // 恢复链路:卡顿检测/重开/升级 re-resolve/放弃。
        for (final e in [
          'stall_begin', 'stall_end', 'stall_watchdog', 'reopen_requested',
          'external_pause_watchdog', 'external_pause_recover',
          'recover_request', 'recover_ok', 'recover_fail', 'recover_skip',
          'recover_early', 'recovery_cancelled',
          'escalate_recover_request', 'escalate_recover_ok',
          'escalate_recover_fail', 'escalate_recover_throttled',
          'single_line_escalate', 'decode_flap', 'decode_storm_reopen',
          'playing_ok', 'playing_ok_revoked', 'give_up', 'give_up_latched',
          'dead_open_recover', 'dead_open_reopen', 'dead_open_resolved',
          'ad_stall_hold',
        ])
          e: 'recovery',
        // 解析:进房/重解析/画质预取。
        for (final e in [
          'resolve_ms', 'resolve_ok', 'resolve_fail', 'resolve_skip',
          'prefetch_start', 'prefetch_ok', 'prefetch_fail', 'prefetch_skip',
          'prefetch_empty',
        ])
          e: 'resolve',
        // 线路:开流选线/死节点避让/URL 寿命重签。
        for (final e in [
          'open', 'open_queue_wait', 'open_superseded', 'ad_filter_wrap',
          'mpv_proxy', 'cdn_failover_order', 'url_refresh',
          'url_refresh_skip', 'url_refresh_scheduled',
          'host_avoid_recorded', 'host_avoid_applied',
          'host_avoid_persist_error',
        ])
          e: 'line',
        // 流健康:首帧/解码/缓冲观测。
        for (final e in [
          'video_first_frame_rendered', 'video_first_frame_timeout',
          'open_to_first_frame', 'video_state', 'video_params',
          'video_stability', 'video_stability_error', 'video_hwdec',
          'video_hwdec_error', 'video_kick', 'time_pos_regression',
          'transport_flap', 'health_reset',
        ])
          e: 'stream',
        // mpv 原始/诊断日志。
        for (final e in [
          'mpv_log', 'mpv_log_suppressed', 'mpv_tuning', 'mpv_diag',
        ])
          e: 'mpv',
        // 生命周期:app/窗口/房间/播放器实例。
        for (final e in [
          'app_start', 'app_lifecycle', 'window_event', 'player_created',
          'player_native_disposed', 'player_idle_scheduled',
          'player_idle_cancelled', 'play_cmd', 'play_state',
          'play_view_params', 'stop', 'caption_load_ok',
        ])
          e: 'lifecycle',
        'resource_sample': 'resource',
        'source_open_failure': 'player',
      };

  /// 记录一条事件。[fields] 值会被 `toString`,键值对以空格连接;
  /// 行内首个字段为 `cat=<分类>`(见 [_eventCategories])。
  static void write(String event, [Map<String, Object?> fields = const {}]) {
    final file = _target;
    if (file == null) return;
    try {
      final now = DateTime.now();
      final ts = now.toIso8601String().substring(11, 23);
      final cat = _eventCategories[event] ?? 'other';
      final body =
          fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
      file.writeAsStringSync(
        '$ts $event cat=$cat${body.isEmpty ? '' : ' $body'}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 写失败(磁盘满 / 权限 / 目录被删):静默放弃,绝不影响播放。
      _broken = true;
    }
  }
}
