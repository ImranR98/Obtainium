import 'dart:async';

import 'package:android_package_manager/android_package_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApplicationInfo extends ApplicationInfo {
  _FakeApplicationInfo({required super.enabled})
    : super(
        compatibleWidthLimitDp: 0,
        dataDir: '',
        descriptionRes: 0,
        flags: 0,
        largestWidthLimitDp: 0,
        processName: '',
        publicSourceDir: '',
        requiresSmallestWidthDp: 0,
        sourceDir: '',
        theme: 0,
        uiOptions: 0,
        uid: 0,
        targetSdkVersion: 35,
      );
}

class _FakePackageInfo extends PackageInfo {
  const _FakePackageInfo({super.packageName, super.applicationInfo})
    : super(installLocation: AndroidInstallLocation.auto);
}

class _TestAppsProvider extends ChangeNotifier implements AppsProvider {
  _TestAppsProvider(this.settingsProvider);

  @override
  Map<String, AppInMemory> apps = {};

  @override
  final SettingsProvider settingsProvider;

  @override
  Completer<List<App>>? updateCheckCompleter;

  @override
  CancellationToken? updateCheckCancellation;

  @override
  final ValueNotifier<double?> refreshProgress = ValueNotifier<double?>(null);

  @override
  Future<void> waitForAppsToLoad() async {}

  @override
  void notify() => notifyListeners();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

App _app({
  required String id,
  String? installedVersion,
  bool disabled = false,
  bool trackOnly = false,
}) => App(
  id: id,
  url: 'https://example.com/$id',
  author: 'Author',
  name: 'App $id',
  installedVersion: installedVersion,
  latestVersion: '2.0.0',
  preferredApkIndex: 0,
  additionalSettings: {'trackOnly': trackOnly},
  disabled: disabled,
);

AppInMemory _aim(App app, {PackageInfo? installedInfo}) =>
    AppInMemory(app, null, installedInfo, null);

PackageInfo _pkg(String id, {bool? enabled}) => _FakePackageInfo(
  packageName: id,
  applicationInfo: enabled == null
      ? null
      : _FakeApplicationInfo(enabled: enabled),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider.checkSystemDisabledApps', () {
    test('defaults to true and persists changes', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider();
      provider.prefs = await SharedPreferences.getInstance();

      expect(provider.checkSystemDisabledApps, isTrue);

      provider.checkSystemDisabledApps = false;
      expect(provider.checkSystemDisabledApps, isFalse);

      final reloaded = SettingsProvider();
      reloaded.prefs = await SharedPreferences.getInstance();
      expect(reloaded.checkSystemDisabledApps, isFalse);

      reloaded.checkSystemDisabledApps = true;
      expect(reloaded.checkSystemDisabledApps, isTrue);
    });
  });

  group('AppInMemory.isSystemDisabled', () {
    test('reports false when not installed or applicationInfo is missing', () {
      expect(_aim(_app(id: 'a')).isSystemDisabled, isFalse);
      expect(
        _aim(
          _app(id: 'b', installedVersion: '1.0.0'),
          installedInfo: _pkg('b'),
        ).isSystemDisabled,
        isFalse,
      );
    });

    test('reflects applicationInfo.enabled state', () {
      expect(
        _aim(
          _app(id: 'enabled', installedVersion: '1.0.0'),
          installedInfo: _pkg('enabled', enabled: true),
        ).isSystemDisabled,
        isFalse,
      );
      expect(
        _aim(
          _app(id: 'disabled', installedVersion: '1.0.0'),
          installedInfo: _pkg('disabled', enabled: false),
        ).isSystemDisabled,
        isTrue,
      );
    });
  });

  group('getAppsSortedByUpdateCheckTime with system-disabled apps', () {
    late SettingsProvider settings;
    late _TestAppsProvider appsProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
      appsProvider = _TestAppsProvider(settings);
      appsProvider.apps = {
        'enabled': _aim(
          _app(id: 'enabled', installedVersion: '1.0.0'),
          installedInfo: _pkg('enabled', enabled: true),
        ),
        'sys_disabled': _aim(
          _app(id: 'sys_disabled', installedVersion: '1.0.0'),
          installedInfo: _pkg('sys_disabled', enabled: false),
        ),
        'not_installed': _aim(_app(id: 'not_installed')),
        'track_only': _aim(_app(id: 'track_only', trackOnly: true)),
        'obtainium_disabled': _aim(
          _app(
            id: 'obtainium_disabled',
            installedVersion: '1.0.0',
            disabled: true,
          ),
          installedInfo: _pkg('obtainium_disabled', enabled: true),
        ),
      };
    });

    tearDown(() {
      appsProvider.dispose();
    });

    test(
      'includes system-disabled apps when checkSystemDisabledApps is true',
      () {
        final ids = appsProvider.getAppsSortedByUpdateCheckTime(
          checkSystemDisabledApps: true,
          forceAll: true,
        );

        expect(
          ids,
          containsAll([
            'enabled',
            'sys_disabled',
            'not_installed',
            'track_only',
          ]),
        );
        expect(ids, isNot(contains('obtainium_disabled')));
      },
    );

    test(
      'skips system-disabled apps when checkSystemDisabledApps is false',
      () {
        final ids = appsProvider.getAppsSortedByUpdateCheckTime(
          checkSystemDisabledApps: false,
          forceAll: true,
        );

        expect(ids, containsAll(['enabled', 'not_installed', 'track_only']));
        expect(ids, isNot(contains('sys_disabled')));
        expect(ids, isNot(contains('obtainium_disabled')));
      },
    );

    test(
      'combines checkSystemDisabledApps=false with onlyCheckInstalledOrTrackOnlyApps=true',
      () {
        final ids = appsProvider.getAppsSortedByUpdateCheckTime(
          onlyCheckInstalledOrTrackOnlyApps: true,
          checkSystemDisabledApps: false,
          forceAll: true,
        );

        expect(ids, unorderedEquals(['enabled', 'track_only']));
      },
    );

    test(
      'refreshInstalledInfoForChecks updates enabled state before filtering',
      () async {
        await appsProvider.refreshInstalledInfoForChecks(
          fetchInstalledInfo: () async => [
            _pkg('enabled', enabled: false),
            _pkg('sys_disabled', enabled: true),
          ],
        );

        expect(appsProvider.apps['enabled']!.isSystemDisabled, isTrue);
        expect(appsProvider.apps['sys_disabled']!.isSystemDisabled, isFalse);

        final ids = appsProvider.getAppsSortedByUpdateCheckTime(
          checkSystemDisabledApps: false,
          forceAll: true,
        );
        expect(ids, contains('sys_disabled'));
        expect(ids, isNot(contains('enabled')));
      },
    );

    test(
      'checkUpdates with forceAll skips system-disabled apps when setting is off',
      () async {
        settings.checkSystemDisabledApps = false;
        appsProvider.apps = {
          'sys_disabled': _aim(
            _app(id: 'sys_disabled', installedVersion: '1.0.0'),
            installedInfo: _pkg('sys_disabled', enabled: false),
          ),
        };

        final updates = await appsProvider.checkUpdates(forceAll: true);
        expect(updates, isEmpty);
      },
    );

    test(
      'single-app fetchUpdate is unaffected by system-disabled status',
      () async {
        settings.checkSystemDisabledApps = false;
        await expectLater(
          appsProvider.fetchUpdate('sys_disabled'),
          throwsA(isA<Object>()),
        );
        expect(await appsProvider.fetchUpdate('obtainium_disabled'), isNull);
      },
    );
  });
}
