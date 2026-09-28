/// mpv 调优外部配置:`<APPDATA>/zishu_flutter/config/mpv_tuning.json`。
///
/// 为什么要有这层:调参(cache/preadahead/framedrop 等)是高频试错过程,
/// 硬编码在 [MediaKitLivePlayer.kLiveTuningProperties] 里每次都要重编译。
/// 外部文件让调参变成「改 JSON → 重启应用」,内置表退居**默认值**:
///
/// - 文件不存在/为空 → 全量回退内置默认([liveTuningConfigTemplate] 首次
///   启动会尝试写出模板,写失败不影响播放);
/// - 文件存在 → 逐键覆盖内置表(**含文件新增的属性**,不设白名单,方便
///   试验内置表没有的 mpv 属性);
/// - 文件存在但**整体非法**(不是 JSON 对象/类型错)→ 整表回退默认,
///   绝不带着半解析状态开流;单键非法(空串/对象/数组/null)只剔除该键。
///
/// 解析是纯函数([resolveLiveTuningProperties]),不碰 IO —— 文件读取与
/// 模板落盘在 [_readTuningFile]/[ensureLiveTuningConfigExists],便于单测。
library;

import 'dart:convert';
import 'dart:io';

import 'media_kit_live_player.dart';

/// 配置文件完整路径:`%APPDATA%\zishu_flutter\config\mpv_tuning.json`
/// (与 [PlaybackLog] 同一数据根,便于用户一次找齐日志与配置)。
String liveTuningConfigFilePath() {
  final base = Platform.environment['APPDATA'];
  final root = (base == null || base.isEmpty)
      ? Directory.systemTemp.path
      : base;
  return [
    root,
    'zishu_flutter',
    'config',
    'mpv_tuning.json',
  ].join(Platform.pathSeparator);
}

/// 解析外部配置内容,与内置默认合并为最终属性表。
///
/// [jsonContent] 为 null/空白 → 内置默认。合并规则见库文档。
List<(String, String)> resolveLiveTuningProperties({String? jsonContent}) {
  final defaults = MediaKitLivePlayer.kLiveTuningProperties;
  final content = jsonContent?.trim();
  if (content == null || content.isEmpty) return defaults;

  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return defaults; // 非法 JSON:整体回退,不让调参文件弄坏播放。
  }
  if (decoded is! Map<String, dynamic>) return defaults;

  final merged = <String, String>{
    for (final (name, value) in defaults) name: value,
  };
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key.isEmpty || key.startsWith('_')) continue; // _comment 模板注释位
    final value = _normalizeMpvValue(entry.value);
    if (value == null) continue; // 单键非法:剔除,保留内置值
    merged[key] = value;
  }
  return merged.entries.map((e) => (e.key, e.value)).toList();
}

/// 把 JSON 值归一化为 mpv 属性字符串;无法表达的类型返回 null(剔除)。
///
/// - String → 原样(去空白,空串剔除);
/// - num → toString(cache-secs: 10 这类数字写法);
/// - bool → 'yes'/'no'(仅当语义就是布尔的属性,如 cache;framedrop 这类
///   枚举属性写 true 属于误配,同样给 yes/no —— 由 mpv 拒绝该值并保持
///   无效赋值前状态,风险与手工写错字符串等同);
/// - 其他(map/list/null)→ null。
String? _normalizeMpvValue(Object? value) {
  switch (value) {
    case final String s:
      final trimmed = s.trim();
      return trimmed.isEmpty ? null : trimmed;
    case final num n:
      return n.toString();
    case final bool b:
      return b ? 'yes' : 'no';
    default:
      return null;
  }
}

/// 首次运行写出模板文件(含 `_comment` 说明),失败静默 —— 配置文件是
/// 调参便利,不是播放依赖。
void ensureLiveTuningConfigExists() {
  try {
    final file = File(liveTuningConfigFilePath());
    if (file.existsSync()) return;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(liveTuningConfigTemplate());
  } catch (_) {
    // 目录不可写等:忽略,下次启动再试。
  }
}

/// 读配置文件内容;任何 IO 异常返回 null(等价于无配置)。
String? readLiveTuningFile() {
  try {
    final file = File(liveTuningConfigFilePath());
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  } catch (_) {
    return null;
  }
}

/// 模板内容:内置默认 + `_comment` 使用说明。
String liveTuningConfigTemplate() {
  const comment =
      'mpv 直播调优(改完重启应用生效)。键=mpv 属性名,值=属性值;'
      '去掉本键(_开头)即为合法配置项。整体写坏会回退内置默认,单键写坏只忽略该键。';
  final map = <String, Object?>{'_comment': comment};
  for (final (name, value) in MediaKitLivePlayer.kLiveTuningProperties) {
    map[name] = value;
  }
  return const JsonEncoder.withIndent('  ').convert(map);
}
