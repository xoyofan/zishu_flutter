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

/// 计数展示(**保留真 0**):`0` → `'0'`,只有不可解析/负数才留空。
///
/// 给「上游确实报告了一个 0」的字段用(如 B 站大航海人数):调用方拿 `null`
/// 表示取数失败,两者不再混成同一个「—」。web 侧 `statDisplay` 对空值也直接
/// 显示 `"0"`,本函数与之对齐。
String formatExactCountOrZero(Object? count) {
  final value = count is num ? count : num.tryParse('${count ?? ''}'.trim());
  if (value == null || value < 0) return '';
  if (value == 0) return '0';
  return value.truncate().toString();
}

/// [formatOnlineCount] 的逆运算:把「1.2万 / 3.4千 / 1234」还原为整数,用于跨站热度排序。
/// 无法解析或为空一律返回 0,保证排序稳定。
///
/// 需要区分「合法的 0」与「缺失/不可解析」时用 [tryParseOnlineCount];
/// 本函数是其 `?? 0` 的兼容包装,两老共用同一个私有 parser,不会漂移。
int parseOnlineCount(Object? count) => tryParseOnlineCount(count) ?? 0;

/// [parseOnlineCount] 的可空变体:合法数值(**含 0**)→ int;
/// 空串 / null / 不可解析 → null。
///
/// 排序等调用方需要把「缺失沉底」与「合法零参与数值序」分开时用本函数
/// (关注列表档内观看数排序,审阅口径 2026-09-24)。解析规则与
/// [parseOnlineCount] 同一份实现([_parseOnlineCountOrNull])。
int? tryParseOnlineCount(Object? count) => _parseOnlineCountOrNull(count);

/// 唯一解析实现:返回 null 表示空/不可解析,合法数值(含 0)返回 int。
int? _parseOnlineCountOrNull(Object? count) {
  final text = '${count ?? ''}'.trim().replaceAll(',', '');
  if (text.isEmpty) return null;
  final match = RegExp(r'^([\d.]+)\s*([万千wk]?)$').firstMatch(text.toLowerCase());
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
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
