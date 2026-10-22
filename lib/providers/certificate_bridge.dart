import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';

class CertificateInfo {
  final Uint8List der;
  final String subject;
  final String issuer;
  final DateTime notBefore;
  final DateTime notAfter;
  final bool isCA;

  const CertificateInfo({
    required this.der,
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
    required this.isCA,
  });

  String get displayName {
    final commonName = RegExp(
      r'(?:^|,)\s*CN=([^,]+)',
    ).firstMatch(subject)?.group(1)?.trim();
    if (commonName != null && commonName.isNotEmpty) return commonName;
    final organization = RegExp(
      r'(?:^|,)\s*O=([^,]+)',
    ).firstMatch(subject)?.group(1)?.trim();
    if (organization != null && organization.isNotEmpty) return organization;
    return subject.isNotEmpty ? subject : tr('certificateFallbackName');
  }
}

class CertificateBridge {
  CertificateBridge._();

  static final CertificateBridge instance = CertificateBridge._();

  static const MethodChannel _channel = MethodChannel(
    'dev.imranr.obtainium/certificate',
  );

  Future<List<CertificateInfo>> parse(List<Uint8List> ders) async {
    if (ders.isEmpty) return [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'parseCertificates',
        {'ders': ders},
      );
      return [
        for (final item in raw ?? const [])
          _fromMap(Map<String, dynamic>.from(item as Map)),
      ];
    } on MissingPluginException {
      throw ObtainiumError(tr('certificateParseUnavailable'));
    } on PlatformException catch (e) {
      AppLogger.warn('Certificate parse failed: ${e.code} ${e.message}');
      throw ObtainiumError(tr('certificateParseFailed'));
    }
  }

  CertificateInfo _fromMap(Map<String, dynamic> map) => CertificateInfo(
    der: map['der'] as Uint8List,
    subject: map['subject'] as String? ?? '',
    issuer: map['issuer'] as String? ?? '',
    notBefore: DateTime.fromMillisecondsSinceEpoch(
      map['notBefore'] as int,
      isUtc: true,
    ),
    notAfter: DateTime.fromMillisecondsSinceEpoch(
      map['notAfter'] as int,
      isUtc: true,
    ),
    isCA: map['isCA'] == true,
  );
}
