import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'defaults to the Android certificate store and an unseen warning',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider();
      provider.prefs = await SharedPreferences.getInstance();

      expect(provider.useAndroidCertStore, isTrue);
      expect(provider.dclWarningShown, isFalse);
    },
  );

  test('persists the certificate-store preference and warning state', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SettingsProvider();
    provider.prefs = await SharedPreferences.getInstance();

    provider.useAndroidCertStore = false;
    provider.dclWarningShown = true;

    final reloaded = SettingsProvider();
    reloaded.prefs = await SharedPreferences.getInstance();

    expect(reloaded.useAndroidCertStore, isFalse);
    expect(reloaded.dclWarningShown, isTrue);
  });
}
