import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/utils/bg_update_guards.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('evaluateBgGuards', () {
    BgGuardDecision evaluate({
      BgGuardMode wifi = BgGuardMode.checksAndUpdates,
      BgGuardMode charging = BgGuardMode.checksAndUpdates,
      bool onWiFi = true,
      bool chargingNow = true,
    }) => evaluateBgGuards(
      wifiMode: wifi,
      chargingMode: charging,
      onUnmeteredNetwork: onWiFi,
      charging: chargingNow,
    );

    test('allows checks and installs when both conditions are met', () {
      final decision = evaluate(
        wifi: BgGuardMode.nothing,
        charging: BgGuardMode.nothing,
      );
      expect(decision.skipChecks, isFalse);
      expect(decision.allowInstalls, isTrue);
    });

    test('checksOnly off Wi-Fi allows checks but blocks installs', () {
      final decision = evaluate(wifi: BgGuardMode.checksOnly, onWiFi: false);
      expect(decision.skipChecks, isFalse);
      expect(decision.allowInstalls, isFalse);
    });

    test('checksOnly while not charging blocks installs only', () {
      final decision = evaluate(
        charging: BgGuardMode.checksOnly,
        chargingNow: false,
      );
      expect(decision.skipChecks, isFalse);
      expect(decision.allowInstalls, isFalse);
    });

    test('nothing off Wi-Fi skips checks', () {
      final decision = evaluate(wifi: BgGuardMode.nothing, onWiFi: false);
      expect(decision.skipChecks, isTrue);
      expect(decision.allowInstalls, isFalse);
    });

    test('nothing while not charging skips checks', () {
      final decision = evaluate(
        charging: BgGuardMode.nothing,
        chargingNow: false,
      );
      expect(decision.skipChecks, isTrue);
      expect(decision.allowInstalls, isFalse);
    });

    test('checksAndUpdates allows installs even when conditions are unmet', () {
      expect(
        evaluate(
          wifi: BgGuardMode.checksAndUpdates,
          onWiFi: false,
        ).allowInstalls,
        isTrue,
      );
      expect(
        evaluate(
          charging: BgGuardMode.checksAndUpdates,
          chargingNow: false,
        ).allowInstalls,
        isTrue,
      );
    });
  });

  group('canInstallInBackground', () {
    const allowed = BgGuardDecision(skipChecks: false, allowInstalls: true);
    const blocked = BgGuardDecision(skipChecks: false, allowInstalls: false);
    const skipped = BgGuardDecision(skipChecks: true, allowInstalls: false);

    test('guards decide installs for background tasks', () {
      expect(
        canInstallInBackground(forceAll: false, decision: allowed),
        isTrue,
      );
      expect(
        canInstallInBackground(forceAll: false, decision: blocked),
        isFalse,
      );
      expect(
        canInstallInBackground(forceAll: false, decision: skipped),
        isFalse,
      );
    });

    test('manual runs never install', () {
      expect(
        canInstallInBackground(forceAll: true, decision: allowed),
        isFalse,
      );
      expect(
        canInstallInBackground(forceAll: true, decision: blocked),
        isFalse,
      );
      expect(
        canInstallInBackground(forceAll: true, decision: skipped),
        isFalse,
      );
    });
  });

  group('SettingsProvider background guard modes', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
    });

    test('default to checksAndUpdates', () {
      expect(settings.bgGuardOnWiFi, BgGuardMode.checksAndUpdates);
      expect(settings.bgGuardWhileCharging, BgGuardMode.checksAndUpdates);
    });

    test('legacy true migrates to checksOnly', () async {
      SharedPreferences.setMockInitialValues({
        'bgUpdatesOnWiFiOnly': true,
        'bgUpdatesWhileChargingOnly': true,
      });
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
      expect(settings.bgGuardOnWiFi, BgGuardMode.checksOnly);
      expect(settings.bgGuardWhileCharging, BgGuardMode.checksOnly);
    });

    test('legacy false migrates to checksAndUpdates', () async {
      SharedPreferences.setMockInitialValues({
        'bgUpdatesOnWiFiOnly': false,
        'bgUpdatesWhileChargingOnly': false,
      });
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
      expect(settings.bgGuardOnWiFi, BgGuardMode.checksAndUpdates);
      expect(settings.bgGuardWhileCharging, BgGuardMode.checksAndUpdates);
    });

    test('new key takes precedence over the legacy boolean', () async {
      SharedPreferences.setMockInitialValues({
        'bgUpdatesOnWiFiOnly': true,
        'bgGuardOnWiFi': BgGuardMode.nothing.name,
      });
      settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
      expect(settings.bgGuardOnWiFi, BgGuardMode.nothing);
      expect(settings.bgGuardWhileCharging, BgGuardMode.checksAndUpdates);
    });

    test('round-trips all modes', () {
      for (final mode in BgGuardMode.values) {
        settings.bgGuardOnWiFi = mode;
        settings.bgGuardWhileCharging = mode;
        expect(settings.bgGuardOnWiFi, mode);
        expect(settings.bgGuardWhileCharging, mode);
      }
    });
  });
}
