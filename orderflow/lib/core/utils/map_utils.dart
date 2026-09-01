/// Universal JS-safe and Dart2JS-safe Map extractor.
/// Bypasses Dart2JS minified JSObject / _JsonMap type cast exceptions.
class MapUtils {
  static Map<String, dynamic>? extractMap(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final Map<String, dynamic> result = {};
      value.forEach((k, v) => result[k.toString()] = v);
      return result;
    }
    try {
      final dynamic dyn = value;
      if (dyn is Iterable) return null;
      final Map<String, dynamic> result = {};
      dyn.forEach((dynamic k, dynamic v) {
        result[k.toString()] = v;
      });
      return result;
    } catch (_) {}
    return null;
  }

  static int countEntries(dynamic value) {
    if (value == null) return 0;
    if (value is Map) return value.length;
    final m = extractMap(value);
    return m?.length ?? 0;
  }
}
