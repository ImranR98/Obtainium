import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/external_install_bridge.dart';

void main() {
  group('externalInstallResultFromNative', () {
    test('maps a successful native result', () {
      final result = externalInstallResultFromNative({
        'installed': true,
        'errorCode': null,
      });
      expect(result, isNotNull);
      expect(result!.installed, isTrue);
      expect(result.errorCode, isNull);
    });

    test('maps an explicit failure with the installer code', () {
      final result = externalInstallResultFromNative({
        'installed': false,
        'errorCode': -15,
      });
      expect(result, isNotNull);
      expect(result!.installed, isFalse);
      expect(result.errorCode, -15);
    });

    test('treats missing values as not installed without a code', () {
      final result = externalInstallResultFromNative(<String, dynamic>{});
      expect(result, isNotNull);
      expect(result!.installed, isFalse);
      expect(result.errorCode, isNull);
    });

    test('returns null when the native side reported nothing', () {
      expect(externalInstallResultFromNative(null), isNull);
      expect(externalInstallResultFromNative('unexpected'), isNull);
    });
  });
}
