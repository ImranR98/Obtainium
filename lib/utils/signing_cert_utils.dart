import 'dart:typed_data';

import 'package:android_package_manager/android_package_manager.dart';
import 'package:crypto/crypto.dart';

final AndroidPackageManager _packageManager = AndroidPackageManager();
final PackageInfoFlags _signingInfoFlags = PackageInfoFlags({
  PMFlag.getSigningCertificates,
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
Future<Set<String>> apkSigningCertHashes(String apkPath) async {
  final info = await _packageManager.getPackageArchiveInfo(
    archiveFilePath: apkPath,
    flags: _signingInfoFlags,
  );
  return certHashesFromSigningInfo(info?.signingInfo);
}

/// Union of the signer certificate hashes across [apkPaths] (base APK plus
/// splits); every split of a valid bundle is signed with the same certificate.
Future<Set<String>> apkFilesSigningCertHashes(Iterable<String> apkPaths) async {
  final result = <String>{};
  for (final path in apkPaths) {
    result.addAll(await apkSigningCertHashes(path));
  }
  return result;
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
