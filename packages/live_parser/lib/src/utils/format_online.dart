/// 人数展示格式化:过万显示「X万 / X.X万」,过千显示「X.X千」,否则原数;0/非法为空。
library;

String formatOnlineCount(Object? count) {
  final double? value = switch (count) {
    final num n => n.toDouble(),
    _ => double.tryParse('${count ?? ''}'.trim()),
  };
  if (value == null) return '';
  if (value >= 10000) return _formatWan(value);
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}千';
  if (value > 0) return value.truncate().toString();
  return '';
}

/// 计数展示(粉丝数等):显示实际数字不做万/千省略;0/非法为空。
String formatExactCount(Object? count) {
  final value = count is num ? count : num.tryParse('${count ?? ''}'.trim());
  if (value == null || value <= 0) return '';
  return value.truncate().toString();
}

/// [formatOnlineCount] 的逆运算:把「1.2万 / 3.4千 / 1234」还原为整数,用于跨站热度排序。
/// 无法解析或为空一律返回 0,保证排序稳定。
int parseOnlineCount(Object? count) {
  final text = '${count ?? ''}'.trim().replaceAll(',', '');
  if (text.isEmpty) return 0;
  final match = RegExp(r'^([\d.]+)\s*([万千wk]?)$').firstMatch(text.toLowerCase());
  if (match == null) return 0;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return 0;
  return switch (match.group(2)) {
    '万' || 'w' => (value * 10000).round(),
    '千' || 'k' => (value * 1000).round(),
    _ => value.round(),
  };
}

String _formatWan(double value) {
  final wan = value / 10000;
  if (wan == wan.truncateToDouble()) return '${wan.truncate()}万';
  return '${wan.toStringAsFixed(1)}万';
}
