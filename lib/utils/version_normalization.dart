// Pure version-string analysis used to recognize when two strings describe the
// same release despite cosmetic formatting differences.
//
// Android reports the version name baked into the APK, which frequently
// carries packaging qualifiers that the upstream release tag does not:
// `0.9.108 strip`, `1.6.15-debug`, `1.0.5-release+26090410`, a leading `v`,
// and so on. Treating those as genuine version differences made Obtainium
// permanently consider an app outdated, disable its version detection and
// then silently re-install the same APK on every background pass.
//
// The comparison is deliberately conservative so that it never hides a real
// update:
//  * Only *packaging* words are ignored (see [_ignorableVersionTokens]);
//    pre-release qualifiers such as `alpha`/`beta`/`rc` keep their ordering
//    meaning and are never stripped.
//  * Conflicting packaging words are not treated as the same build:
//    `1.6.15-debug` installed and `1.6.15-release` published is an update.
//  * [installedMatchesRemote] only allows the *installed* side to carry extra
//    packaging words or build metadata; a release that carries a qualifier the
//    installed build does not is a different build.
//  * Build metadata (`+...`) is significant when the remote carries it, and
//    packaging noise when only the installed APK carries it.
//  * Non-ASCII words (e.g. localized suffixes) are kept as tokens and compared
//    literally instead of being discarded.
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

/// Separator: any run of characters that is neither a Unicode letter nor a
/// Unicode digit. Keeping non-ASCII letters as tokens means localized suffixes
/// are compared literally.
final RegExp _tokenSeparator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Splits a token into letter and digit runs so that `beta1` and `beta.1`
/// compare equal, while `2.3` and `2.30` still differ.
final RegExp _segments = RegExp(r'\p{L}+|\p{N}+', unicode: true);

final RegExp _firstNumber = RegExp(r'\d+');
final RegExp _majorOnlyPreRelease = RegExp(
  r'^(\d+)(?:[._\-\s]?(' + _preReleaseQualifiers.join('|') + r')\w*)$',
);

class _VersionParts {
  /// Ordering-significant tokens (numbers, pre-release qualifiers, and any
  /// other words), with letter/digit runs split apart.
  final List<String> core;

  /// Packaging words present in the version string, kept whole.
  final Set<String> packaging;

  /// Ordering-significant tokens that appear after the first `+`.
  final List<String> metadata;

  const _VersionParts(this.core, this.packaging, this.metadata);
}

bool _sameTokens(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _segment(String token) =>
    _segments.allMatches(token).map((m) => m.group(0)!).toList();

List<String> _tokens(String value) =>
    value.split(_tokenSeparator).where((t) => t.isNotEmpty).toList();

_VersionParts _analyze(String version) {
  var value = version.trim().toLowerCase().replaceAll('_', '-');
  value = value.replaceFirst(_leadingV, '');
  // Build metadata (everything after the first '+') is treated separately:
  // when only the installed APK carries it, it is packaging noise; when the
  // remote carries it, it is a distinct build and must be compared.
  final plus = value.indexOf('+');
  final versionPart = plus >= 0 ? value.substring(0, plus) : value;
  final metadataPart = plus >= 0 ? value.substring(plus + 1) : '';
  final core = <String>[];
  final packaging = <String>{};
  for (final token in _tokens(versionPart)) {
    if (_ignorableVersionTokens.contains(token)) {
      packaging.add(token);
    } else {
      core.addAll(_segment(token));
    }
  }
  final metadata = <String>[];
  for (final token in _tokens(metadataPart)) {
    if (_ignorableVersionTokens.contains(token)) continue;
    metadata.addAll(_segment(token));
  }
  return _VersionParts(core, packaging, metadata);
}

/// Produces a canonical key for [version] that keeps the numeric core and
/// ordering-significant words while discarding cosmetic packaging words.
/// Build metadata is not part of the key; use [versionsAreCosmeticallyEqual]
/// for full comparison. Blank/qualifier-only inputs produce an empty string.
///
/// ```dart
/// normalizeVersionForComparison('v1.2.3')           // '1.2.3'
/// normalizeVersionForComparison('0.9.108 strip')    // '0.9.108'
/// normalizeVersionForComparison('1.6.15-debug')     // '1.6.15'
/// normalizeVersionForComparison('1.2.3-beta.1')     // '1.2.3.beta.1'
/// normalizeVersionForComparison('1.2.3稳定版')       // '1.2.3.稳定版'
/// ```
String normalizeVersionForComparison(String version) =>
    _analyze(version).core.join('.');

/// Whether [a] and [b] describe the same underlying release once cosmetic
/// packaging words are ignored.
///
/// This is symmetric and intentionally tolerant of conflicting packaging words
/// (`-debug` vs `-release`): it exists to keep version detection enabled, not
/// to decide whether an update is available. Use [installedMatchesRemote] for
/// that decision. Build metadata must match when both sides carry it.
bool versionsAreCosmeticallyEqual(String a, String b) {
  final partsA = _analyze(a);
  final partsB = _analyze(b);
  if (partsA.core.isEmpty || partsB.core.isEmpty) return false;
  if (!_sameTokens(partsA.core, partsB.core)) return false;
  if (partsA.metadata.isNotEmpty &&
      partsB.metadata.isNotEmpty &&
      !_sameTokens(partsA.metadata, partsB.metadata)) {
    return false;
  }
  return true;
}

/// Whether the installed build ([installed]) is the same release as the
/// published one ([remote]), allowing the installed side to carry extra
/// packaging words or build metadata that the release does not.
///
/// A packaging word or build metadata on the remote side that the installed
/// build lacks means a different build, so this returns false. That keeps
/// `1.6.15-debug` installed / `1.6.15` published collapsing, while
/// `1.6.15` installed / `1.6.15-debug` published (and conflicting variants
/// such as `debug` vs `release`) still surface as an update.
bool installedMatchesRemote({
  required String installed,
  required String remote,
}) {
  final partsInstalled = _analyze(installed);
  final partsRemote = _analyze(remote);
  if (partsInstalled.core.isEmpty || partsRemote.core.isEmpty) return false;
  if (!_sameTokens(partsInstalled.core, partsRemote.core)) return false;
  if (!partsInstalled.packaging.containsAll(partsRemote.packaging)) {
    return false;
  }
  // Metadata present only on the installed side is packaging noise; metadata
  // present on the remote side is a distinct build and must match.
  if (partsRemote.metadata.isNotEmpty &&
      !_sameTokens(partsInstalled.metadata, partsRemote.metadata)) {
    return false;
  }
  return true;
}

/// Whether [tag] is a major-only pre-release tag (e.g. `v151_beta`) for the
/// same major version as [installed] (e.g. `151.0.7922.47`).
///
/// Rolling pre-release tags do not encode the full installed version, so they
/// cannot be reconciled with it: matching only the major component would hide
/// real updates. Callers must keep the update visible and disable OS version
/// reconciliation for such tags instead of treating them as the same release.
bool isPreReleaseMajorMatch(String tag, String installed) {
  var normalizedTag = tag.trim().toLowerCase().replaceAll('_', '-');
  normalizedTag = normalizedTag.replaceFirst(_leadingV, '');
  final match = _majorOnlyPreRelease.firstMatch(normalizedTag);
  if (match == null) return false;
  final installedCore = _analyze(installed).core;
  if (installedCore.isEmpty) return false;
  final installedMajor = _firstNumber.firstMatch(installedCore.join('.'));
  return installedMajor != null && installedMajor.group(0) == match.group(1);
}
