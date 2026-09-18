/// 播放档位/线路选择:纯函数,便于确定性单测;播放编排只做调用。
///
/// 与 pure_live `features/play/application/play_selection.dart` 同源 —— 本仓
/// 一度把这两个函数内联成「精确同名 + 首档」与 `quality.preferredLine`,于是
/// 设置里的「线路格式(auto/HLS/FLV)」**在播放侧完全不生效**,且真实平台的
/// 带后缀档名(如「原画1080P60」)匹配不到偏好档。这里按参考实现恢复。
library;

import 'package:live_parser/live_parser.dart';

/// 按默认画质挑档:精确同名 > 双向包含 > 首档。
///
/// 契约 [RoomPayload.qualityByName] 已含精确 + 包含两级回退。真实平台档名
/// 常带后缀(如「原画1080P60」),只做精确匹配会错过目标档并回退首档,
/// 而懒取流下首档通常没有线路 —— 表现是「状态显示错档、播放器不开流」。
/// 只从 `streams`(点得动的集合)挑,保证选中档必然可渲染为 chip。
StreamQuality? pickPlayQuality(RoomPayload payload, String? preferredName) {
  if (payload.streams.isEmpty) return null;
  return payload.qualityByName(preferredName);
}

/// 按线路格式偏好挑线路。
///
/// `auto`/空维持契约首选(HLS 优先);`hls`/`flv` 命中即以该格式为首选,
/// 未命中回退契约首选 —— 偏好是排序而非硬过滤,避免格式不匹配时播不了。
StreamLine? pickStreamLine(StreamQuality? quality, String? preferredFormat) {
  if (quality == null) return null;
  final format = preferredFormat?.trim().toLowerCase() ?? '';
  if (format.isEmpty || format == 'auto') return quality.preferredLine;
  for (final line in quality.lines) {
    if (line.format.toLowerCase() == format) return line;
  }
  return quality.preferredLine;
}
