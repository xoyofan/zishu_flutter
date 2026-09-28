/// 直播 URL 寿命解析:斗鱼等平台在流 URL query 里携带 `expire=<秒>`
/// (实测 2026-09-28 斗鱼 web getH5PlayV1 为 300s),token 过期后 CDN 会掐
/// TLS 连接(`connection reset by peer`)。播放编排据此在寿命的 ~80% 处
/// 主动重签,不再等 reset 触发被动恢复。
library;

/// 默认寿命:与斗鱼官方一致;其余无 expire 参数的平台按此保守取值。
const int kDefaultUrlTtlSeconds = 300;

/// 提取 URL query 中的 `expire` 参数作为寿命秒数。
///
/// 非法/缺失回退 [defaultSeconds];结果夹到 [minSeconds, 86400] 防呆
/// (防异常值把刷新周期排到几小时后或立刻触发)。
int urlTtlSeconds(
  String? url, {
  int defaultSeconds = kDefaultUrlTtlSeconds,
  int minSeconds = 30,
}) {
  final fallback = defaultSeconds.clamp(minSeconds, 86400);
  if (url == null || url.isEmpty) return fallback;
  final query = Uri.tryParse(url)?.queryParameters;
  final raw = query?['expire'];
  if (raw == null) return fallback;
  final parsed = int.tryParse(raw);
  if (parsed == null) return fallback;
  return parsed.clamp(minSeconds, 86400);
}
