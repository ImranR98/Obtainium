import 'dart:typed_data';

import 'package:android_package_manager/android_package_manager.dart';
import 'package:crypto/crypto.dart';

final AndroidPackageManager _packageManager = AndroidPackageManager();
final PackageInfoFlags _signingInfoFlags = PackageInfoFlags({
  PMFlag.getSigningCertificates,
  PMFlag.getSignatures,
});

/// Formats a signing certificate (DER bytes) as an uppercase, colon-separated
/// SHA-256 digest, the format shown in the app UI and accepted in settings.
String formatCertHash(Uint8List cert) {
  final digest = sha256.convert(cert);
  return digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}

/// Signer certificate hashes from [signingInfo]. Multi-signer apps expose the
/// current signers through [SigningInfo.apkContentSigners]; single-signer apps
/// expose the certificate history, which includes any rotation lineage.
Set<String> certHashesFromSigningInfo(SigningInfo? signingInfo) {
  if (signingInfo == null) return {};
  final certs = signingInfo.hasMultipleSigners
      ? signingInfo.apkContentSigners
      : signingInfo.signingCertificateHistory;
  return certs?.map(formatCertHash).toSet() ?? {};
}

/// Signer certificate hashes of the APK at [apkPath], or an empty set when the
/// signing info is unavailable (pre-API 28 or unreadable archive).
Future<Set<String>> apkSigningCertHashes(String apkPath) async =>
    (await apkSigningCertInfo(apkPath)).hashes;

/// Union of the signer certificate hashes across [apkPaths] (base APK plus
/// splits); every split of a valid bundle is signed with the same certificate.
Future<Set<String>> apkFilesSigningCertHashes(
  Iterable<String> apkPaths,
) async => (await apkFilesSigningCertInfo(apkPaths)).hashes;

class ApkSigningCertInfo {
  final Set<String> hashes;
  final bool hasPastSigningCertificates;

  const ApkSigningCertInfo({
    required this.hashes,
    required this.hasPastSigningCertificates,
  });
}

Future<ApkSigningCertInfo> apkSigningCertInfo(String apkPath) async {
  final info = await _packageManager.getPackageArchiveInfo(
    archiveFilePath: apkPath,
    flags: _signingInfoFlags,
  );
  final signingInfo = info?.signingInfo;
  return ApkSigningCertInfo(
    hashes: certHashesFromSigningInfo(signingInfo),
    hasPastSigningCertificates:
        signingInfo?.hasPastSigningCertificates ?? false,
  );
}

Future<ApkSigningCertInfo> apkFilesSigningCertInfo(
  Iterable<String> apkPaths,
) async {
  final hashes = <String>{};
  var hasPastSigningCertificates = false;
  for (final path in apkPaths) {
    final info = await apkSigningCertInfo(path);
    hashes.addAll(info.hashes);
    hasPastSigningCertificates =
        hasPastSigningCertificates || info.hasPastSigningCertificates;
  }
  return ApkSigningCertInfo(
    hashes: hashes,
    hasPastSigningCertificates: hasPastSigningCertificates,
  );
}

bool signingCertsMatch({
  required Set<String> installedHashes,
  required Set<String> apkHashes,
  required bool apkHasPastSigningCertificates,
}) {
  if (apkHashes.isEmpty || installedHashes.isEmpty) return false;
  if (apkHashes.every(installedHashes.contains)) return true;
  return apkHasPastSigningCertificates &&
      installedHashes.every(apkHashes.contains);
}

final RegExp _certHashHex = RegExp(r'^[0-9a-fA-F]{64}$');

/// Normalizes a certificate hash to the uppercase colon-separated form.
/// Accepts hashes with or without separators; unrecognizable input is returned
/// uppercased so it simply won't match anything.
String normalizeCertHash(String raw) {
  final hex = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (!_certHashHex.hasMatch(hex)) return raw.trim().toUpperCase();
  return [
    for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
  ].join(':').toUpperCase();
}

/// Parses the `allowedSigningCertHashes` setting (hashes separated by newlines,
/// whitespace, commas or semicolons) into a set of normalized hashes.
Set<String> parseAllowedSigningCertHashes(String? raw) => (raw ?? '')
    .split(RegExp(r'[\s,;]+'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .map(normalizeCertHash)
    .toSet();

/// Whether [value] consists only of valid SHA-256 hashes (one or more per
/// line, separated by whitespace/comma/semicolon) or is empty.
bool isValidCertHashList(String? value) {
  if (value == null || value.trim().isEmpty) return true;
  return value
      .split(RegExp(r'[\s,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .every((e) {
        return _certHashHex.hasMatch(e.replaceAll(RegExp(r'[^0-9a-fA-F]'), ''));
      });
}
