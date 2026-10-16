import 'package:obtainium/providers/settings_provider.dart';

String capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

bool isObtainiumVariant(String id) =>
    id == obtainiumId ||
    id == '$obtainiumId.fdroid' ||
    id == '$obtainiumId.debug';

/// Builds a regex alternation pattern from a list of hostname strings,
/// escaping dots.
String getSourceRegex(List<String> hosts) {
  return '(${hosts.join('|').replaceAll('.', '\\.')})';
}

bool passesRegExFilter(RegExp regEx, String value, {bool invert = false}) {
  final matches = regEx.hasMatch(value);
  return invert ? !matches : matches;
}
