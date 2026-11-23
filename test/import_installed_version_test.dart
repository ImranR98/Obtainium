import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/apps_provider_import_export.dart';

App _app({
  String? installedVersion,
  Map<String, dynamic> additionalSettings = const {},
}) => App(
  id: 'com.example.app',
  url: 'https://example.com/app',
  author: 'Author',
  name: 'App',
  installedVersion: installedVersion,
  latestVersion: '2.0.0',
  preferredApkIndex: 0,
  additionalSettings: additionalSettings,
);

void main() {
  group('resolveImportedInstalledVersion', () {
    test('uses the version installed on this device', () {
      final app = _app(
        installedVersion: '1.0.0',
        additionalSettings: const {'trackOnly': true, 'versionDetection': true},
      );
      expect(resolveImportedInstalledVersion(app, '1.0.0'), '1.0.0');
      expect(resolveImportedInstalledVersion(app, '0.9.0'), '0.9.0');
    });

    test('keeps the exported version for track-only apps', () {
      final app = _app(
        installedVersion: '1.2.3',
        additionalSettings: const {'trackOnly': true, 'versionDetection': true},
      );
      expect(resolveImportedInstalledVersion(app, null), '1.2.3');
    });

    test('keeps the exported version when version detection is disabled', () {
      final app = _app(
        installedVersion: '2.3.4',
        additionalSettings: const {'versionDetection': false},
      );
      expect(resolveImportedInstalledVersion(app, null), '2.3.4');
    });

    test(
      'drops the exported version for regular apps that are not installed',
      () {
        final app = _app(
          installedVersion: '3.4.5',
          additionalSettings: const {'versionDetection': true},
        );
        expect(resolveImportedInstalledVersion(app, null), isNull);
      },
    );

    test(
      'returns null when a pseudo-versioned app has no exported version',
      () {
        final app = _app(
          additionalSettings: const {
            'trackOnly': true,
            'versionDetection': true,
          },
        );
        expect(resolveImportedInstalledVersion(app, null), isNull);
      },
    );
  });
}
