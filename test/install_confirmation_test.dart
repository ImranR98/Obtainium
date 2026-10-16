import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider_install.dart';

void main() {
  group('shouldPollForInstallConfirmation', () {
    test('races stock, Shizuku and root installs with package polling', () {
      expect(
        shouldPollForInstallConfirmation('stock', needsBGWorkaround: false),
        isTrue,
      );
      expect(
        shouldPollForInstallConfirmation('shizuku', needsBGWorkaround: false),
        isTrue,
        reason: 'a lost Shizuku result callback must not stall the chain',
      );
      expect(
        shouldPollForInstallConfirmation('root', needsBGWorkaround: false),
        isTrue,
      );
    });

    test(
      'does not poll for the background workaround or external installer',
      () {
        expect(
          shouldPollForInstallConfirmation('stock', needsBGWorkaround: true),
          isFalse,
          reason: 'the background stock result never arrives by design (#896)',
        );
        expect(
          shouldPollForInstallConfirmation(
            'external',
            needsBGWorkaround: false,
          ),
          isFalse,
          reason: 'the external installer reports completion natively',
        );
      },
    );
  });
}
