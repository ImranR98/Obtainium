import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/installers/installer.dart';
import 'package:obtainium/providers/source_provider.dart';

App _app(String url, Map<String, dynamic> settings, {String? overrideSource}) =>
    App(
      id: 'com.example.app',
      url: url,
      author: 'Example',
      name: 'Example',
      latestVersion: '1.0',
      preferredApkIndex: 0,
      additionalSettings: settings,
      overrideSource: overrideSource,
    );

void main() {
  const samsung = 'https://galaxystore.samsung.com/detail/com.example.app';
  const github = 'https://github.com/example/app';
  const galaxyFlag = 'shizukuPretendToBeGalaxyStore';
  const playFlag = 'shizukuPretendToBeGooglePlay';

  test('Samsung opt-in overrides Google Play only for Samsung sources', () {
    for (final global in [false, true]) {
      expect(
        installerPackageNameForApp(
          _app(samsung, {galaxyFlag: true, playFlag: true}),
          googlePlayDefault: global,
        ),
        'com.sec.android.app.samsungapps',
      );
      expect(
        installerPackageNameForApp(
          _app(github, {galaxyFlag: true}),
          googlePlayDefault: global,
        ),
        global ? 'com.android.vending' : '',
      );
    }
    expect(
      installerPackageNameForApp(
        _app(samsung, {galaxyFlag: true}, overrideSource: 'HTML'),
        googlePlayDefault: false,
      ),
      '',
    );
    expect(
      installerPackageNameForApp(
        _app(github, {galaxyFlag: true}, overrideSource: 'SamsungGalaxyStore'),
        googlePlayDefault: false,
      ),
      'com.sec.android.app.samsungapps',
    );
  });

  test(
    'existing global and per-app Google Play settings retain their meaning',
    () {
      for (final url in [samsung, github]) {
        for (final global in [false, true]) {
          for (final local in [false, true]) {
            expect(
              installerPackageNameForApp(
                _app(url, {playFlag: local}),
                googlePlayDefault: global,
              ),
              global || local ? 'com.android.vending' : '',
            );
          }
        }
      }
    },
  );

  test('unresolvable URLs and overrides fall back to the Google Play rule', () {
    for (final global in [false, true]) {
      final expected = global ? 'com.android.vending' : '';
      expect(
        installerPackageNameForApp(
          _app('not a url', {galaxyFlag: true}),
          googlePlayDefault: global,
        ),
        expected,
      );
      expect(
        installerPackageNameForApp(
          _app(github, {galaxyFlag: true}, overrideSource: 'MissingSource'),
          googlePlayDefault: global,
        ),
        expected,
      );
    }
  });
}
