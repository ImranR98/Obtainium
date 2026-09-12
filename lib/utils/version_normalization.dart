/// Version-string normalization used to recognize when two strings describe
/// the same release despite cosmetic formatting differences.
///
/// Android reports the version name baked into the APK, which frequently
/// carries packaging qualifiers that the upstream release tag does not:
/// `0.9.108 strip`, `1.6.15-debug`, `1.0.5-release+26090410`, a leading `v`,
/// and so on. Treating those as genuine version differences made Obtainium
/// permanently consider an app outdated, disable its version detection and
/// then silently re-install the same APK on every background pass.
///
/// Only non-ordering information is removed here. Pre-release qualifiers
/// (`alpha`, `beta`, `rc`, …) change ordering and are never stripped.
library;

/// Build/packaging words that do not participate in version ordering.
const Set<String> _ignorableVersionTokens = {
  'strip',
  'debug',
  'release',
  'stable',
  'final',
  'standard',
  'build',
  'signed',
  'unsigned',
  'universal',
  'nogms',
};

/// Pre-release qualifiers that do change ordering.
const Set<String> _preReleaseQualifiers = {
  'alpha',
  'beta',
  'rc',
  'pre',
  'dev',
  'snapshot',
  'nightly',
  'ose',
};

final RegExp _leadingV = RegExp(r'^v(?=\d)');
final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]+');
final RegExp _firstNumber = RegExp(r'\d+');
final RegExp _majorOnlyPreRelease = RegExp(
  r'^(\d+)(?:[._\-\s]?(' + _preReleaseQualifiers.join('|') + r')\w*)$',
);

/// Produces a comparison key for [version] that keeps the numeric core and
/// ordering-significant qualifiers while discarding cosmetic differences.
///
/// ```dart
/// normalizeVersionForComparison('v1.2.3')            // '1.2.3'
/// normalizeVersionForComparison('0.9.108 strip')     // '0.9.108'
/// normalizeVersionForComparison('1.6.15-debug')      // '1.6.15'
/// normalizeVersionForComparison('1.2.3-beta')        // '1.2.3.beta'
/// ```
String normalizeVersionForComparison(String version) {
  var value = version.trim().toLowerCase().replaceAll('_', '-');
  value = value.replaceFirst(_leadingV, '');
  final tokens = value
      .split(_nonAlphanumeric)
      .where((token) => token.isNotEmpty)
      .where((token) => !_ignorableVersionTokens.contains(token));
  return tokens.join('.');
}

/// Whether [a] and [b] describe the same release once cosmetic differences
/// are ignored. Blank inputs never match.
bool versionsAreCosmeticallyEqual(String a, String b) {
  final normalizedA = normalizeVersionForComparison(a);
  final normalizedB = normalizeVersionForComparison(b);
  if (normalizedA.isEmpty || normalizedB.isEmpty) return false;
  return normalizedA == normalizedB;
}

/// Whether [tag] is a major-only pre-release tag (e.g. `v151_beta`) for the
/// same major version as [installed] (e.g. `151.0.7922.47`).
///
/// Rolling pre-release tags do not encode the full installed version, so an
/// exact comparison is impossible; matching on the major component lets such
/// apps stay on version detection instead of being flipped to pseudo
/// versioning and re-installed forever.
bool isPreReleaseMajorMatch(String tag, String installed) {
  final normalizedTag = tag
      .trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .replaceFirst(_leadingV, '');
  final match = _majorOnlyPreRelease.firstMatch(normalizedTag);
  if (match == null) return false;
  final installedMajor = _firstNumber.firstMatch(
    normalizeVersionForComparison(installed),
  );
  return installedMajor != null && installedMajor.group(0) == match.group(1);
}
