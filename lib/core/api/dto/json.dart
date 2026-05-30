/// Защитные хелперы парсинга — api-v2 нередко отдаёт null/строки вместо чисел.
int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String asStr(Object? v, [String fallback = '']) =>
    v is String ? v : (v?.toString() ?? fallback);

bool asBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asMapList(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];
