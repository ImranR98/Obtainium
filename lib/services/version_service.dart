// Version extraction, standard-format classification, comparison, and the
// install-status reconciliation that drives update badges.
//
// The pipeline, in the order the app uses it:
//  1. [extractVersion] pulls a version out of a raw string using the app's
//     `versionExtractionRegEx` / `matchGroupToUse` settings.
//  2. [findStandardFormatsForVersion] classifies a version string into the
//     standard shapes Obtainium can order. Strict means the whole string
//     matches a shape; loose means a substring does.
//  3. [reconcileVersionDifferences] compares two versions sharing a shape.
//  4. [versionDetectionPossible] decides whether "Reconcile version string
//     with version detected from OS" can work for an app, and
//     [reconcileTrackedVersion] applies the cosmetic and device corrections
//     when it can.
//  5. [isAppUpdateable] decides whether the UI shows an update.
//
// Everything here is pure (no I/O, no state); the unit tests in
// `test/version_reconciliation_test.dart` cover the whole pipeline.

import 'package:easy_localization/easy_localization.dart';

import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/utils/version_normalization.dart';

const String _defaultMatchGroup = '0';

// ========================================================================
// Extraction
// ========================================================================

/// Returns an error string when [value] is not a valid regular expression.
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

/// Applies [versionExtractionRegEx] to [stringToCheck] and returns the captured
/// match group (the whole match when [matchGroupString] is empty or null).
/// Returns null when no extraction regex is configured and throws
/// [NoVersionError] when the regex does not match or yields nothing.
String? extractVersion(
  String? versionExtractionRegEx,
  String? matchGroupString,
  String stringToCheck,
) {
  if (versionExtractionRegEx?.isNotEmpty != true) return null;
  final matches = RegExp(versionExtractionRegEx!).allMatches(stringToCheck);
  if (matches.isEmpty) {
    throw NoVersionError();
  }
  final trimmedGroup = matchGroupString?.trim();
  final version = _replaceMatchGroupsInString(
    matches.last,
    trimmedGroup == null || trimmedGroup.isEmpty
        ? _defaultMatchGroup
        : trimmedGroup,
  );
  if (version?.isNotEmpty != true) {
    throw NoVersionError();
  }
  return version;
}

/// Replaces `$N` references in a string with the corresponding regex match
/// groups. A `\` before a reference keeps it literal.
String? _replaceMatchGroupsInString(
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

// ========================================================================
// Standard version formats
// ========================================================================

/// Regex patterns for the "standard" version shapes: a numeric basic
/// (`1`, `1.2`, `1.2.3`, `1.2.3.4`) optionally followed by a pre-release
/// qualifier and/or a trailing numeric build (`1.2.3`, `1.2.3-beta`,
/// `1.2.3-beta2`, `1.2.3+4`, ...).
final List<String> _standardVersionPatterns =
    _generateStandardVersionPatterns();

final List<MapEntry<String, RegExp>> _strictStandardVersionRegExes =
    _standardVersionPatterns.map((p) => MapEntry(p, RegExp('^$p\$'))).toList();

final List<MapEntry<String, RegExp>> _looseStandardVersionRegExes =
    _standardVersionPatterns.map((p) => MapEntry(p, RegExp(p))).toList();

List<String> _generateStandardVersionPatterns() {
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
  final results = <String>{};
  for (var basic in basics) {
    results.add(basic);
    for (var preSuffix in preSuffixes) {
      for (var suffix in suffixes) {
        results.add('$basic$suffix');
        results.add('$basic$preSuffix$suffix');
        for (var finalSuffix in finals) {
          results.add('$basic$suffix$finalSuffix');
          results.add('$basic$preSuffix$suffix$finalSuffix');
        }
      }
    }
  }
  return results.toList();
}

final Map<String, Set<String>> _strictFormatCache = {};
final Map<String, Set<String>> _looseFormatCache = {};
const int _maxFormatCacheSize = 4096;

/// The set of standard format patterns that [version] matches. Strict patterns
/// must match the whole string; loose patterns may match any substring.
Set<String> findStandardFormatsForVersion(
  String version, {
  required bool strict,
}) {
  final cache = strict ? _strictFormatCache : _looseFormatCache;
  final cached = cache[version];
  if (cached != null) return cached;
  final patterns = strict
      ? _strictStandardVersionRegExes
      : _looseStandardVersionRegExes;
  final results = {
    for (final entry in patterns)
      if (entry.value.hasMatch(version)) entry.key,
  };
  if (cache.length >= _maxFormatCacheSize) cache.clear();
  cache[version] = results;
  return results;
}

/// Whether the first match of [pattern] is identical in both strings.
bool doStringsMatchUnderRegEx(String pattern, String value1, String value2) {
  final regExp = RegExp(pattern);
  final match1 = regExp.firstMatch(value1);
  final match2 = regExp.firstMatch(value2);
  return match1 != null && match2 != null
      ? value1.substring(match1.start, match1.end) ==
            value2.substring(match2.start, match2.end)
      : false;
}

/// Compares two versions numerically when they share a common non-strict
/// standard format. Returns a negative value if [version1] is older than
/// [version2], a positive value if it is newer, 0 if they are numerically
/// equal, and null if they cannot be compared in a valid way.
int? compareVersionsNumerically(String version1, String version2) {
  final commonFormats = findStandardFormatsForVersion(
    version1,
    strict: false,
  ).intersection(findStandardFormatsForVersion(version2, strict: false));
  if (commonFormats.isEmpty) {
    return null;
  }
  final digitRunRegex = RegExp('[0-9]+');
  var mostSpecific = commonFormats.first;
  var mostSpecificRuns = digitRunRegex.allMatches(mostSpecific).length;
  for (final format in commonFormats) {
    final runs = digitRunRegex.allMatches(format).length;
    if (runs > mostSpecificRuns ||
        (runs == mostSpecificRuns && format.length > mostSpecific.length)) {
      mostSpecific = format;
      mostSpecificRuns = runs;
    }
  }
  final mostSpecificRegExp = RegExp(mostSpecific);
  List<int> extractNumericRuns(String version) {
    final match = mostSpecificRegExp.firstMatch(version)!;
    return digitRunRegex
        .allMatches(match.group(0)!)
        .map((m) => int.parse(m.group(0)!))
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

// ========================================================================
// Reconciliation
// ========================================================================

/// Result of comparing two version strings under a common standard format.
///
/// [version] is the string that should be kept: the comparison version when
/// the two match under a shared format, otherwise the template version.
typedef VersionComparison = ({bool areEqual, String version});

/// Reconciles two version strings that share a standard version format.
///
/// Returns null when no common format exists.
VersionComparison? reconcileVersionDifferences(
  String templateVersion,
  String comparisonVersion,
) {
  final templateFormats = findStandardFormatsForVersion(
    templateVersion,
    strict: true,
  );
  var comparisonFormats = findStandardFormatsForVersion(
    comparisonVersion,
    strict: true,
  );
  if (comparisonFormats.isEmpty) {
    comparisonFormats = findStandardFormatsForVersion(
      comparisonVersion,
      strict: false,
    );
  }
  final commonFormats = templateFormats.intersection(comparisonFormats);
  if (commonFormats.isEmpty) {
    return null;
  }
  for (final pattern in commonFormats) {
    if (doStringsMatchUnderRegEx(pattern, comparisonVersion, templateVersion)) {
      return (areEqual: true, version: comparisonVersion);
    }
  }
  return (areEqual: false, version: templateVersion);
}

/// Whether standard version detection can work for an app whose on-device
/// version is [realInstalledVersion] and whose tracked version is
/// [trackedVersion]. [isHtmlWithNoVersionDetection] and
/// [versionDetectionDisallowed] describe the source; a naive source treats any
/// pair of non-null versions as comparable.
///
/// A rolling major-only pre-release tag (e.g. `v151_beta`) cannot be reconciled
/// with a full installed version (`151.0.7922.47`): matching only the major
/// component would hide real updates, so detection is disabled for it (except
/// on naive sources, which keep their override) and the update stays visible.
bool versionDetectionPossible({
  required bool trackOnly,
  required bool releaseDateAsVersion,
  required bool isHtmlWithNoVersionDetection,
  required bool versionDetectionDisallowed,
  required String? realInstalledVersion,
  required String? trackedVersion,
  required String latestVersion,
  required bool naiveStandardVersionDetection,
}) {
  if (trackOnly ||
      releaseDateAsVersion ||
      isHtmlWithNoVersionDetection ||
      versionDetectionDisallowed) {
    return false;
  }
  if (realInstalledVersion == null || trackedVersion == null) return false;
  final bool rollingTag =
      isPreReleaseMajorMatch(latestVersion, realInstalledVersion) ||
      isPreReleaseMajorMatch(latestVersion, trackedVersion);
  if (rollingTag && !naiveStandardVersionDetection) return false;
  // A cosmetic difference (leading "v", packaging qualifiers such as
  // "strip"/"debug") still means the versions can be compared.
  return reconcileVersionDifferences(realInstalledVersion, trackedVersion) !=
          null ||
      versionsAreCosmeticallyEqual(realInstalledVersion, trackedVersion) ||
      versionsAreCosmeticallyEqual(realInstalledVersion, latestVersion) ||
      naiveStandardVersionDetection;
}

/// Applies the install-status reconciliation steps that depend only on version
/// strings:
///  1. collapse cosmetic differences between the tracked version and
///     [latestVersion] (leading "v", packaging qualifiers, build metadata);
///  2. adopt [latestVersion] when the device's real version is the same
///     release (the tracked value was stale);
///  3. reconcile [realInstalledVersion] against the tracked version;
///  4. collapse again in case step 3 produced a version that now matches.
///
/// A rolling major-only pre-release tag is never collapsed: it does not encode
/// the full installed version, so the update must stay visible (the caller
/// disables version detection for it instead).
/// Returns the corrected tracked version, or null when nothing changes.
String? reconcileTrackedVersion({
  required String? trackedVersion,
  required String? realInstalledVersion,
  required String latestVersion,
  required bool versionDetectionIsStandard,
  required bool naiveStandardVersionDetection,
}) {
  if (trackedVersion == null) return null;
  var current = trackedVersion;
  var changed = false;

  bool sameRelease(String version) =>
      installedMatchesRemote(installed: version, remote: latestVersion);

  void collapseIfSameRelease(String version) {
    if (current == latestVersion) return;
    if (sameRelease(version)) {
      current = latestVersion;
      changed = true;
    }
  }

  // Collapse a cosmetic difference between the tracked version and the latest
  // release, and let the device's real version override a stale tracked value.
  collapseIfSameRelease(current);
  if (realInstalledVersion != null) {
    collapseIfSameRelease(realInstalledVersion);
  }
  if (realInstalledVersion != null &&
      current != realInstalledVersion &&
      versionDetectionIsStandard) {
    // App's reported version and real version don't match (and it uses
    // standard version detection). If they share a standard format (and are
    // still different under it), update the reported version accordingly.
    final corrected = reconcileVersionDifferences(
      realInstalledVersion,
      current,
    );
    if (corrected != null && !corrected.areEqual) {
      current = corrected.version;
      changed = true;
    } else if (naiveStandardVersionDetection &&
        !versionsAreCosmeticallyEqual(realInstalledVersion, current)) {
      current = realInstalledVersion;
      changed = true;
    }
  }
  // The reconciliation above may have produced a version that now matches the
  // latest release.
  collapseIfSameRelease(current);
  return changed ? current : null;
}

/// Whether [app] should be presented as having an update available: its
/// installed version differs from its latest version and is not numerically
/// newer than it. Numeric comparison only applies when both versions share a
/// common non-strict standard format (see [compareVersionsNumerically]) and the
/// "hide downgrades" setting is enabled — otherwise a downgrade is still
/// presented as an update.
bool isAppUpdateable(App app, SettingsProvider settingsProvider) {
  final installed = app.installedVersion;
  final latest = app.latestVersion;
  if (installed == null || installed == latest) {
    return false;
  }
  if (!settingsProvider.hideDowngrades) {
    return true;
  }
  final comparison = compareVersionsNumerically(installed, latest);
  return comparison == null || comparison <= 0;
}
