/// 站点 JSON 容错读取工具:上游字段类型不稳定,统一在此收敛。
library;

Map<String, dynamic> jsonMapOf(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Object?> jsonListOf(Object? value) => value is List ? value : const [];

String jsonText(Object? value) => value?.toString() ?? '';

int jsonInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool jsonBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1';
}
