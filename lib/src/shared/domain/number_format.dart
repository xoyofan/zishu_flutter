/// 统计数字的展示格式化(纯 Dart,无 Flutter 依赖)。
///
/// 收敛 `play_side_panel._statText` / `_formatFollowersText` 与
/// `play_meta_bar` 同类逻辑:上游文本缺失时显示占位、纯数字按「万」
/// 收敛,已带单位的文本一律原样,不伪造数据。
library;

/// 统计文本:空串(未关注/上游未提供)显示「—」占位,不伪造。
String statOrDash(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '—' : text;
}

/// 关注/观众数显示格式(用户口径 2026-09-20):纯数字 ≥1万 显示「X.X万」
/// (≥100万 收敛为整数万);已带单位或非数字文本原样返回,不伪造。
String formatCountWan(String raw) {
  final text = raw.trim().replaceAll(',', '');
  if (text.isEmpty) return '—';
  final value = int.tryParse(text);
  if (value == null) return text;
  if (value >= 10000) {
    final wan = value / 10000;
    return wan >= 100
        ? '${wan.toStringAsFixed(0)}万'
        : '${wan.toStringAsFixed(1)}万';
  }
  return text;
}
