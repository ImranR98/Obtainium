import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/apps_provider_install.dart';

App _app(Map<String, dynamic> additionalSettings) => App(
  id: 'com.example.app',
  url: 'https://example.com/app',
  author: 'Author',
  name: 'App',
  latestVersion: '1.0',
  preferredApkIndex: 0,
  additionalSettings: additionalSettings,
);

void main() {
  test('an app with its own install method uses it', () {
    expect(
      installerModeFor(_app({'installerMode': 'shizuku'}), 'system'),
      'shizuku',
    );
    expect(
      installerModeFor(_app({'installerMode': 'system'}), 'root'),
      'system',
    );
  });

  test('otherwise the global install method is used', () {
    expect(installerModeFor(null, 'root'), 'root');
    expect(installerModeFor(_app({}), 'shizuku'), 'shizuku');
    expect(
      installerModeFor(_app({'installerMode': ''}), 'external'),
      'external',
    );
    expect(
      installerModeFor(_app({'installerMode': 'bogus'}), 'system'),
      'system',
    );
  });
}
