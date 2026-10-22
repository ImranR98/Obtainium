import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// One certificate bundled for a pinned host.
class PinnedCertificate {
  final String assetPath;
  final String displayName;
  final String subject;
  final String issuer;
  final DateTime notBefore;
  final DateTime notAfter;

  /// SHA-256 fingerprint of the DER certificate, in the same uppercase,
  /// colon-separated form used for APK signing certificate hashes.
  final String expectedSha256;

  const PinnedCertificate({
    required this.assetPath,
    required this.displayName,
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
    required this.expectedSha256,
  });

  String get exportFileName {
    final name = assetPath.split('/').last;
    final dot = name.lastIndexOf('.');
    return '${dot > 0 ? name.substring(0, dot) : name}.pem';
  }
}

/// The certificates trusted for a pinned host (and its subdomains).
class PinnedHost {
  final String host;
  final List<PinnedCertificate> certificates;

  const PinnedHost(this.host, this.certificates);
}

class PinnedCertificateContents {
  final String pem;
  final String sha256;

  const PinnedCertificateContents({required this.pem, required this.sha256});
}

const String russianMintsifryAssetPath =
    'assets/ca-certs/russian-mintsifry-root.crt';

final PinnedCertificate _sectigoR46 = PinnedCertificate(
  assetPath: 'assets/ca-certs/sectigo-pub-serv-auth-r46.crt',
  displayName: 'Sectigo Public Server Authentication Root R46',
  subject:
      'C=GB, O=Sectigo Limited, CN=Sectigo Public Server Authentication Root R46',
  issuer:
      'C=GB, O=Sectigo Limited, CN=Sectigo Public Server Authentication Root R46',
  notBefore: DateTime.utc(2021, 3, 22),
  notAfter: DateTime.utc(2046, 3, 21, 23, 59, 59),
  expectedSha256:
      '7B:B6:47:A6:2A:EE:AC:88:BF:25:7A:A5:22:D0:1F:FE:A3:95:E0:AB:45:C7:3F:93:F6:56:54:EC:38:F2:5A:06',
);

final PinnedCertificate _sectigoE46 = PinnedCertificate(
  assetPath: 'assets/ca-certs/sectigo-pub-serv-auth-e46.crt',
  displayName: 'Sectigo Public Server Authentication Root E46',
  subject:
      'C=GB, O=Sectigo Limited, CN=Sectigo Public Server Authentication Root E46',
  issuer:
      'C=GB, O=Sectigo Limited, CN=Sectigo Public Server Authentication Root E46',
  notBefore: DateTime.utc(2021, 3, 22),
  notAfter: DateTime.utc(2046, 3, 21, 23, 59, 59),
  expectedSha256:
      'C9:0F:26:F0:FB:1B:40:18:B2:22:27:51:9B:5C:A2:B5:3E:2C:A5:B3:BE:5C:F1:8E:FE:1B:EF:47:38:0C:53:83',
);

final PinnedCertificate _isrgX1 = PinnedCertificate(
  assetPath: 'assets/ca-certs/isrg-root-x1.crt',
  displayName: 'ISRG Root X1',
  subject: 'C=US, O=Internet Security Research Group, CN=ISRG Root X1',
  issuer: 'C=US, O=Internet Security Research Group, CN=ISRG Root X1',
  notBefore: DateTime.utc(2015, 6, 4, 11, 4, 38),
  notAfter: DateTime.utc(2035, 6, 4, 11, 4, 38),
  expectedSha256:
      '96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6',
);

final PinnedCertificate _isrgX2 = PinnedCertificate(
  assetPath: 'assets/ca-certs/isrg-root-x2.crt',
  displayName: 'ISRG Root X2',
  subject: 'C=US, O=Internet Security Research Group, CN=ISRG Root X2',
  issuer: 'C=US, O=Internet Security Research Group, CN=ISRG Root X2',
  notBefore: DateTime.utc(2020, 9, 4),
  notAfter: DateTime.utc(2040, 9, 17, 16),
  expectedSha256:
      '69:72:9B:8E:15:A8:6E:FC:17:7A:57:AF:B7:17:1D:FC:64:AD:D2:8C:2F:CA:8C:F1:50:7E:34:45:3C:CB:14:70',
);

final PinnedCertificate _isrgYe = PinnedCertificate(
  assetPath: 'assets/ca-certs/isrg-root-ye.crt',
  displayName: 'ISRG Root YE',
  subject: 'C=US, O=ISRG, CN=Root YE',
  issuer: 'C=US, O=ISRG, CN=Root YE',
  notBefore: DateTime.utc(2025, 9, 3),
  notAfter: DateTime.utc(2045, 9, 2, 23, 59, 59),
  expectedSha256:
      'E1:4F:FC:AD:5B:00:25:73:10:06:CA:A4:3A:12:1A:22:D8:E9:70:0F:4F:B9:CF:85:2F:02:A7:08:AA:5D:56:66',
);

final PinnedCertificate _isrgYr = PinnedCertificate(
  assetPath: 'assets/ca-certs/isrg-root-yr.crt',
  displayName: 'ISRG Root YR',
  subject: 'C=US, O=ISRG, CN=Root YR',
  issuer: 'C=US, O=ISRG, CN=Root YR',
  notBefore: DateTime.utc(2025, 9, 3),
  notAfter: DateTime.utc(2045, 9, 2, 23, 59, 59),
  expectedSha256:
      'E5:7B:7E:6F:15:0C:41:91:02:E8:D5:C0:55:72:9F:F9:67:B9:D1:A8:29:BF:00:CE:C8:9C:A6:04:EB:F4:A8:6F',
);

final PinnedCertificate _haricaRsa = PinnedCertificate(
  assetPath: 'assets/ca-certs/harica-tls-root-2021-rsa.crt',
  displayName: 'HARICA TLS RSA Root CA 2021',
  subject:
      'C=GR, O=Hellenic Academic and Research Institutions CA, CN=HARICA TLS RSA Root CA 2021',
  issuer:
      'C=GR, O=Hellenic Academic and Research Institutions CA, CN=HARICA TLS RSA Root CA 2021',
  notBefore: DateTime.utc(2021, 2, 19, 10, 55, 38),
  notAfter: DateTime.utc(2045, 2, 13, 10, 55, 37),
  expectedSha256:
      'D9:5D:0E:8E:DA:79:52:5B:F9:BE:B1:1B:14:D2:10:0D:32:94:98:5F:0C:62:D9:FA:BD:9C:D9:99:EC:CB:7B:1D',
);

final PinnedCertificate _haricaEcc = PinnedCertificate(
  assetPath: 'assets/ca-certs/harica-tls-root-2021-ecc.crt',
  displayName: 'HARICA TLS ECC Root CA 2021',
  subject:
      'C=GR, O=Hellenic Academic and Research Institutions CA, CN=HARICA TLS ECC Root CA 2021',
  issuer:
      'C=GR, O=Hellenic Academic and Research Institutions CA, CN=HARICA TLS ECC Root CA 2021',
  notBefore: DateTime.utc(2021, 2, 19, 11, 1, 10),
  notAfter: DateTime.utc(2045, 2, 13, 11, 1, 9),
  expectedSha256:
      '3F:99:CC:47:4A:CF:CE:4D:FE:D5:87:94:66:5E:47:8D:15:47:73:9F:2E:78:0F:1B:B4:CA:9B:13:30:97:D4:01',
);

final PinnedCertificate _mintsifry = PinnedCertificate(
  assetPath: russianMintsifryAssetPath,
  displayName: 'Russian Trusted Root CA (Mintsifry)',
  subject:
      'C=RU, O=The Ministry of Digital Development and Communications, CN=Russian Trusted Root CA',
  issuer:
      'C=RU, O=The Ministry of Digital Development and Communications, CN=Russian Trusted Root CA',
  notBefore: DateTime.utc(2022, 3, 1, 21, 4, 15),
  notAfter: DateTime.utc(2032, 2, 27, 21, 4, 15),
  expectedSha256:
      'D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31',
);

/// Hosts whose requests use the bundled roots instead of the OS trust store
/// when certificate pinning is enabled.
final List<PinnedHost> pinnedHosts = [
  PinnedHost('github.com', [
    _sectigoR46,
    _sectigoE46,
    _isrgX1,
    _isrgX2,
    _isrgYe,
    _isrgYr,
  ]),
  PinnedHost('codeberg.org', [_isrgX1, _isrgX2, _isrgYe, _isrgYr]),
  PinnedHost('gitlab.com', [_sectigoR46, _sectigoE46]),
  PinnedHost('rustore.ru', [_haricaRsa, _haricaEcc, _mintsifry]),
];

String _fingerprint(Uint8List der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

Future<PinnedCertificateContents> loadPinnedCertificateContents(
  PinnedCertificate certificate,
) async {
  final data = await rootBundle.load(certificate.assetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final pem = utf8.decode(bytes);
  final base64Body = pem
      .replaceAll(RegExp(r'-----[^-]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  final der = Uint8List.fromList(base64Decode(base64Body));
  return PinnedCertificateContents(pem: pem, sha256: _fingerprint(der));
}
