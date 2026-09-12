// Regex-based version extraction, validation, and comparison.

import 'package:easy_localization/easy_localization.dart';

import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';

// ========================================================================
// VersionService — regex-based version extraction, validation, and matching.
// ========================================================================

class VersionService {
  static const defaultMatchGroup = '0';

  static final List<String> standardVersionRegExStrings =
      _generateStandardVersionRegExStrings();

  static final List<MapEntry<String, RegExp>> strictStandardVersionRegExes =
      standardVersionRegExStrings
          .map((p) => MapEntry(p, RegExp('^$p\$')))
          .toList();

  static final List<MapEntry<String, RegExp>> looseStandardVersionRegExes =
      standardVersionRegExStrings.map((p) => MapEntry(p, RegExp(p))).toList();

  static List<String> _generateStandardVersionRegExStrings() {
    final basics = [
      '[0-9]+',
      '[0-9]+\\.[0-9]+',
      '[0-9]+\\.[0-9]+\\.[0-9]+',
      '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+',
    ];
    final preSuffixes = ['-', '\\+'];
    final suffixes = [
      'alpha',
      'beta',
      'rc',
      'pre',
      'dev',
      'snapshot',
      'nightly',
      'ose',
      '[0-9]+',
    ];
    final finals = ['\\+[0-9]+', '[0-9]+'];
    final List<String> results = [];
    for (var b in basics) {
      results.add(b);
      for (var p in preSuffixes) {
        for (var s in suffixes) {
          results.add('$b$s');
          results.add('$b$p$s');
          for (var f in finals) {
            results.add('$b$s$f');
            results.add('$b$p$s$f');
          }
        }
      }
    }
    return results.toSet().toList();
  }

  String? regExValidator(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      RegExp(value);
    } catch (e) {
      return tr('invalidRegEx');
    }
    return null;
  }

  /// Replaces `$N` references in a string with the corresponding regex match groups.
  String? replaceMatchGroupsInString(
    RegExpMatch match,
    String matchGroupString,
  ) {
    if (RegExp('^\\d+\$').hasMatch(matchGroupString)) {
      matchGroupString = '\$$matchGroupString';
    }
    final numberRegex = RegExp(r'\$\d+');
    final numbers = numberRegex.allMatches(matchGroupString);
    if (numbers.isEmpty) {
      return null;
    }
    var outputString = matchGroupString;
    for (final numberMatch in numbers) {
      final number = numberMatch.group(0)!;
      final matchGroup = match.group(int.parse(number.substring(1))) ?? '';
      final isEscaped = outputString.contains('\\$number');
      if (!isEscaped) {
        outputString = outputString.replaceAll(number, matchGroup);
      } else {
        outputString = outputString.replaceAll('\\$number', number);
      }
    }
    return outputString;
  }

  /// Applies a version extraction regex to a string and returns the captured match group.
  String? extractVersion(
    String? versionExtractionRegEx,
    String? matchGroupString,
    String stringToCheck,
  ) {
    if (versionExtractionRegEx?.isNotEmpty == true) {
      String? version = stringToCheck;
      final match = RegExp(versionExtractionRegEx!).allMatches(version);
      if (match.isEmpty) {
        throw NoVersionError();
      }
      matchGroupString = matchGroupString?.trim() ?? '';
      if (matchGroupString.isEmpty) {
        matchGroupString = defaultMatchGroup;
      }
      version = replaceMatchGroupsInString(match.last, matchGroupString);
      if (version?.isNotEmpty != true) {
        throw NoVersionError();
      }
      return version!;
    } else {
      return null;
    }
  }

  static final Map<String, Set<String>> _strictFormatCache = {};
  static final Map<String, Set<String>> _looseFormatCache = {};
  static const int _maxFormatCacheSize = 4096;

  Set<String> findStandardFormatsForVersion(String version, bool strict) {
    final cache = strict ? _strictFormatCache : _looseFormatCache;
    final cached = cache[version];
    if (cached != null) return cached;

    final Set<String> results = {};
    final patterns = strict
        ? strictStandardVersionRegExes
        : looseStandardVersionRegExes;
    for (var entry in patterns) {
      if (entry.value.hasMatch(version)) {
        results.add(entry.key);
      }
    }
    if (cache.length >= _maxFormatCacheSize) cache.clear();
    cache[version] = results;
    return results;
  }

  bool doStringsMatchUnderRegEx(String pattern, String value1, String value2) {
    final r = RegExp(pattern);
    final m1 = r.firstMatch(value1);
    final m2 = r.firstMatch(value2);
    return m1 != null && m2 != null
        ? value1.substring(m1.start, m1.end) ==
              value2.substring(m2.start, m2.end)
        : false;
  }

  /// Compares two versions numerically when they share a common non-strict
  /// standard format. Returns a negative value if [version1] is older than
  /// [version2], a positive value if it is newer, 0 if they are numerically
  /// equal, and null if they cannot be compared in a valid way.
  int? compareVersionsNumerically(String version1, String version2) {
    final commonFormats = findStandardFormatsForVersion(
      version1,
      false,
    ).intersection(findStandardFormatsForVersion(version2, false));
    if (commonFormats.isEmpty) {
      return null;
    }
    final digitRunRegex = RegExp('[0-9]+');
    String mostSpecific = commonFormats.first;
    var mostSpecificRuns = digitRunRegex.allMatches(mostSpecific).length;
    for (final format in commonFormats) {
      final runs = digitRunRegex.allMatches(format).length;
      if (runs > mostSpecificRuns ||
          (runs == mostSpecificRuns && format.length > mostSpecific.length)) {
        mostSpecific = format;
        mostSpecificRuns = runs;
      }
    }
    List<int> extractNumericRuns(String version) {
      final match = RegExp(mostSpecific).firstMatch(version);
      return digitRunRegex
          .allMatches(match!.group(0)!)
          .map((e) => int.parse(e.group(0)!))
          .toList();
    }

    final runs1 = extractNumericRuns(version1);
    final runs2 = extractNumericRuns(version2);
    for (var i = 0; i < runs1.length; i++) {
      if (runs1[i] != runs2[i]) {
        return runs1[i] > runs2[i] ? 1 : -1;
      }
    }
    return 0;
  }
}

/// Whether [app] should be presented as having an update available: its
/// installed version differs from its latest version and is not numerically
/// newer than it. Numeric comparison only applies when both versions share a
/// common non-strict standard format (see
/// [VersionService.compareVersionsNumerically]) and the "hide downgrades"
/// setting is enabled — otherwise a downgrade is still presented as an update.
bool isAppUpdateable(App app, SettingsProvider settingsProvider) {
  final installed = app.installedVersion;
  final latest = app.latestVersion;
  if (installed == null || installed == latest) {
    return false;
  }
  if (!settingsProvider.hideDowngrades) {
    return true;
  }
  final comparison = VersionService().compareVersionsNumerically(
    installed,
    latest,
  );
  return comparison == null || comparison <= 0;
}

/// Delegates to [VersionService.regExValidator].
String? regExValidator(String? value) => VersionService().regExValidator(value);

/// Delegates to [VersionService.replaceMatchGroupsInString].
String? replaceMatchGroupsInString(
  RegExpMatch match,
  String matchGroupString,
) => VersionService().replaceMatchGroupsInString(match, matchGroupString);

/// Delegates to [VersionService.extractVersion].
String? extractVersion(
  String? versionExtractionRegEx,
  String? matchGroupString,
  String stringToCheck,
) => VersionService().extractVersion(
  versionExtractionRegEx,
  matchGroupString,
  stringToCheck,
);
