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

/// 实测 FLV 起播更快的站点白名单,对齐 SFVideoLive web 真源 `usePlayer.ts`
/// 的 `preferFlvForNative`(commits 45241d2 + a074399,斗鱼首帧 2.3s→1.0s):
/// - douyu / bilibili / douyin:FLV 单流连接即出帧(0.9~1.7s),HLS 需清单+分片
///   (1.8~2.3s,抖音 HLS 甚至多数起不来帧)→ 起播优选 FLV;
/// - huya 明确排除:其实测 FLV 多数不起帧(仅 1/4 出帧),HLS 0.7~1.0s 更稳;
/// - kuaishou / yy:play_url 本就是 FLV,无需切换。
const _flvFastStartSites = {'douyu', 'bilibili', 'douyin'};

/// 按线路格式偏好挑线路。
///
/// `hls`/`flv` 显式偏好命中即以该格式为首选,未命中回退契约首选 —— 偏好是
/// 排序而非硬过滤,避免格式不匹配时播不了(用户显式选 HLS 时尊重,不做 FLV
/// 优选覆盖)。
///
/// `auto`/空维持契约首选([StreamQuality.preferredLine],HLS 优先);但白名单
/// 站点([_flvFastStartSites])在同档存在 FLV 线时优选 FLV 起播 —— 起播快一倍
/// 以上。契约首选已是 FLV 时原样返回,因此与「斗鱼 HLS 仅兜底(hlsH5Preview
/// 不再抢首选)」的解析侧修复天然不冲突;非白名单站点(虎牙等)维持契约首选。
StreamLine? pickStreamLine(
  StreamQuality? quality,
  String? preferredFormat, {
  String? site,
}) {
  if (quality == null) return null;
  final format = preferredFormat?.trim().toLowerCase() ?? '';
  if (format.isNotEmpty && format != 'auto') {
    for (final line in quality.lines) {
      if (line.format.toLowerCase() == format) return line;
    }
    return quality.preferredLine;
  }
  final contract = quality.preferredLine;
  if (contract == null) return null;
  final siteKey = site?.trim().toLowerCase() ?? '';
  if (contract.format.toLowerCase() == 'flv' ||
      !_flvFastStartSites.contains(siteKey)) {
    return contract;
  }
  for (final line in quality.lines) {
    if (line.format.toLowerCase() == 'flv') return line;
  }
  return contract;
}
