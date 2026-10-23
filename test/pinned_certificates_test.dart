import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/pinned_certificates.dart';

String fingerprint(Uint8List der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

void main() {
  test('registry covers every bundled certificate exactly once', () {
    final files = Directory('assets/ca-certs')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.crt'))
        .map((file) => file.path)
        .toSet();
    final registered = <String>{};
    for (final host in builtInPinnedHosts) {
      final hostAssets = host.certificates
          .map((cert) => cert.assetPath!)
          .toList();
      expect(
        hostAssets.toSet(),
        hasLength(hostAssets.length),
        reason: '${host.host} lists a certificate more than once',
      );
      registered.addAll(hostAssets);
    }

    expect(registered, files);
    expect(builtInPinnedHosts.map((host) => host.host).toSet(), {
      'github.com',
      'codeberg.org',
      'gitlab.com',
      'rustore.ru',
    });
  });

  test('registry fingerprints match the bundled assets', () {
    final colonSeparated = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');
    for (final host in builtInPinnedHosts) {
      for (final certificate in host.certificates) {
        final pem = File(certificate.assetPath!).readAsStringSync();
        final base64Body = pem
            .replaceAll(RegExp(r'-----[^-]+-----'), '')
            .replaceAll(RegExp(r'\s'), '');
        final der = Uint8List.fromList(base64Decode(base64Body));

        expect(certificate.sha256, matches(colonSeparated));
        expect(
          fingerprint(der),
          certificate.sha256,
          reason: certificate.assetPath,
        );
        expect(certificate.exportFileName, endsWith('.pem'));
      }
    }
  });

  test('PEM helpers round-trip and split certificate bundles', () {
    final pem = File('assets/ca-certs/isrg-root-x1.crt').readAsStringSync();
    final ders = pemBlocksToDers(pem);
    expect(ders, hasLength(1));
    expect(certificateFingerprint(ders.single), fingerprintFromPem(pem));
    expect(fingerprintFromPem(derToPem(ders.single)), fingerprintFromPem(pem));
    expect(pemBlocksToDers('$pem\n$pem'), hasLength(2));
  });
}
