// Type-safe wrapper around a raw settings map.

// ========================================================================
// TypedSettings — type-safe wrapper around App.additionalSettings.
// ========================================================================

/// Type-safe wrapper around [App.additionalSettings] that eliminates
/// manual casts and null checks when reading per-source configuration values.
///
/// Usage:
/// ```dart
/// if (app.settings.getBool('trackOnly')) { ... }
/// String? regex = app.settings.getStringOrNull('apkFilterRegEx');
/// ```
class TypedSettings {
  final Map<String, dynamic> _raw;

  const TypedSettings(Map<String, dynamic> raw) : _raw = raw;

  bool getBool(String key, {bool defaultValue = false}) {
    final val = _raw[key];
    if (val == null) return defaultValue;
    if (val is bool) return val;
    if (val is String) return val == 'true';
    return defaultValue;
  }

  int? getIntOrNull(String key) {
    final val = _raw[key];
    if (val is int) return val;
    if (val is String) return int.tryParse(val);
    return null;
  }

  String? getStringOrNull(String key) {
    final val = _raw[key];
    if (val == null) return null;
    if (val is String) return val.isNotEmpty ? val : null;
    return val.toString();
  }

  String getString(String key, {String defaultValue = ''}) =>
      getStringOrNull(key) ?? defaultValue;

  @override
  String toString() => _raw.toString();
}
