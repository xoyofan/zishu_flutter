/// 死节点(host)负缓存:把"恢复时被逃离的 CDN 节点"记一段时间,让后续
/// 自动选线(进房/重解析)避开它,直到节点自愈。
///
/// 为什么需要它(实测 2026-09-28 斗鱼 9999):`hwa.douyucdn2.cn` 故障时,
/// 单线路源重开永远回到同一死 URL;恢复升级 re-resolve 虽能逃到 `huosa`,
/// 但这个记忆只活在**恢复路径**里 —— 用户重启应用、再进同房间,冷启动首选
/// 又钉回 `hwa`,先卡 3~5 分钟等 CDN reset 再升级换线。当天日志里用户重启
/// 5 次,每次都重复首撞。把死 host 按绝对时间戳落到磁盘,TTL 内进房直接
/// 开在健康节点上。
///
/// 边界口径:
/// - 只影响**自动**选线(进房 build);用户手动切线路/切档不避让,尊重
///   2026-09-26「不偷换用户选的线路」口径;
/// - 避让是**排序而非硬过滤**:同 format 未避让 > 任意未避让 > 原首选,
///   全部被避让时按原选播,保证永远有线路可播(万一记录过期前节点恢复或
///   误判,也只是回到旧行为,不会无流可开);
/// - 恢复逃离即记录(乐观):不等新线路 playing_ok —— 若新线也坏,升级
///   轮换会继续把它记入,TTL 到期自然回退,无需回滚机制。
library;

import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart' show StreamLine;

/// 负缓存 TTL:实测死节点故障持续数十分钟,而"升级逃离"只在同节点连续
/// 2 轮卡顿后发生(正常节点偶发抖动到不了这里),15 分钟足够跨过一次重启
/// 再进房,又不至于把节点判死太久。
const Duration kHostAvoidTtl = Duration(minutes: 15);

/// [url] 的 host 是否仍在负缓存期内。
///
/// url 为 null/非法、表为空、条目已过期均返回 false(避让失败即回正常选线)。
bool isHostAvoided(
  Map<String, int> failedAtMs,
  String? url, {
  int nowMs = 0,
  Duration ttl = kHostAvoidTtl,
}) {
  if (url == null || url.isEmpty) return false;
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return false;
  final failedAt = failedAtMs[host];
  if (failedAt == null) return false;
  return nowMs - failedAt < ttl.inMilliseconds;
}

/// 剔除已过期条目(返回裁剪副本),避免文件无限增长。
Map<String, int> pruneHostAvoidlist(
  Map<String, int> failedAtMs, {
  int nowMs = 0,
  Duration ttl = kHostAvoidTtl,
}) {
  final ttlMs = ttl.inMilliseconds;
  return {
    for (final entry in failedAtMs.entries)
      if (nowMs - entry.value < ttlMs) entry.key: entry.value,
  };
}

/// 自动选线避让:[preferred] 的 host 在负缓存内时,在 [lines] 里挑一条
/// 未避让的替代 —— 先保持同 format(不破坏 FLV 起播优选/用户格式偏好),
/// 同 format 全避让再放宽到任意未避让,全部避让返回原首选。
StreamLine? avoidFlaggedLine(
  StreamLine? preferred,
  List<StreamLine> lines,
  Map<String, int> failedAtMs, {
  int nowMs = 0,
  Duration ttl = kHostAvoidTtl,
}) {
  if (preferred == null) return null;
  if (!isHostAvoided(failedAtMs, preferred.url, nowMs: nowMs, ttl: ttl)) {
    return preferred;
  }
  final format = preferred.format.toLowerCase();
  for (final line in lines) {
    if (line.format.toLowerCase() != format) continue;
    if (!isHostAvoided(failedAtMs, line.url, nowMs: nowMs, ttl: ttl)) {
      return line;
    }
  }
  for (final line in lines) {
    if (!isHostAvoided(failedAtMs, line.url, nowMs: nowMs, ttl: ttl)) {
      return line;
    }
  }
  return preferred;
}

/// 负缓存文件:`%APPDATA%\zishu_flutter\config\host_avoidlist.json`
/// (与 mpv_tuning.json 同一 config 目录)。
String hostAvoidlistFilePath() {
  final base = Platform.environment['APPDATA'];
  final root =
      (base == null || base.isEmpty) ? Directory.systemTemp.path : base;
  return [root, 'zishu_flutter', 'config', 'host_avoidlist.json']
      .join(Platform.pathSeparator);
}

/// 编码为磁盘格式(host → 失败时刻的 epoch 毫秒,绝对时间跨重启有效)。
String encodeHostAvoidlist(Map<String, int> failedAtMs) =>
    jsonEncode(failedAtMs);

/// 解码磁盘内容;null/空白/非法结构/非整数值一律回退空表,不让坏文件
/// 弄坏选线。
Map<String, int> decodeHostAvoidlist(String? content) {
  final text = content?.trim();
  if (text == null || text.isEmpty) return {};
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return {};
  }
  if (decoded is! Map<String, dynamic>) return {};
  final result = <String, int>{};
  for (final entry in decoded.entries) {
    final value = entry.value;
    if (entry.key.isEmpty || value is! int) continue;
    result[entry.key] = value;
  }
  return result;
}
