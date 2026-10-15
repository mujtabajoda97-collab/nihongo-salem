/// Strict readers for the bundled content files. A malformed file fails loudly
/// with the exact key that is wrong, instead of showing a broken lesson later.
String reqString(Map<String, dynamic> json, String key, {String ctx = ''}) {
  final v = json[key];
  if (v is String) return v;
  throw FormatException('${ctx}expected a string at "$key"', v);
}

int reqInt(Map<String, dynamic> json, String key, {String ctx = ''}) {
  final v = json[key];
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  throw FormatException('${ctx}expected an integer at "$key"', v);
}

bool reqBool(Map<String, dynamic> json, String key, {String ctx = ''}) {
  final v = json[key];
  if (v is bool) return v;
  throw FormatException('${ctx}expected a boolean at "$key"', v);
}

List<dynamic> reqList(Map<String, dynamic> json, String key, {String ctx = ''}) {
  final v = json[key];
  if (v is List<dynamic>) return v;
  throw FormatException('${ctx}expected a list at "$key"', v);
}

Map<String, dynamic> reqMap(Map<String, dynamic> json, String key,
    {String ctx = ''}) {
  final v = json[key];
  if (v is Map<String, dynamic>) return v;
  throw FormatException('${ctx}expected an object at "$key"', v);
}

List<String> reqStringList(Map<String, dynamic> json, String key,
    {String ctx = ''}) {
  final list = reqList(json, key, ctx: ctx);
  return [
    for (var i = 0; i < list.length; i++)
      if (list[i] is String)
        list[i] as String
      else
        throw FormatException('${ctx}expected a string at "$key[$i]"', list[i]),
  ];
}

/// Items of a list of objects, each parsed with [parse].
List<T> reqObjects<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic> item, String ctx) parse, {
  String ctx = '',
}) {
  final list = reqList(json, key, ctx: ctx);
  return [
    for (var i = 0; i < list.length; i++)
      if (list[i] is Map<String, dynamic>)
        parse(list[i] as Map<String, dynamic>, '$ctx$key[$i]: ')
      else
        throw FormatException('${ctx}expected an object at "$key[$i]"', list[i]),
  ];
}

String? optString(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is String ? v : null;
}

/// Lenient boolean for AI/server answers (`true`, `"true"`); anything else is false.
bool readBool(Object? v) {
  if (v is bool) return v;
  if (v is String) return v.trim().toLowerCase() == 'true';
  return false;
}
