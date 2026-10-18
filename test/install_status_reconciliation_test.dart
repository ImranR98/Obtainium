import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider_lifecycle.dart';

void main() {
  bool shouldDisable({
    bool installed = true,
    bool versionDetectionIsStandard = true,
    bool useVersionCodeAsOSVersion = false,
    bool versionDetectionPossible = false,
  }) => shouldDisableVersionDetection(
    installed: installed,
    versionDetectionIsStandard: versionDetectionIsStandard,
    useVersionCodeAsOSVersion: useVersionCodeAsOSVersion,
    versionDetectionPossible: versionDetectionPossible,
  );

  test('keeps version detection in versionCode mode', () {
    expect(shouldDisable(useVersionCodeAsOSVersion: true), isFalse);
  });

  test('disables version detection for unreconcilable normal versions', () {
    expect(shouldDisable(), isTrue);
  });

  test('does not disable version detection when it is already off', () {
    expect(shouldDisable(versionDetectionIsStandard: false), isFalse);
  });

  test('does not disable version detection for uninstalled apps', () {
    expect(shouldDisable(installed: false), isFalse);
  });

  test(
    'does not disable version detection when reconciliation is possible',
    () {
      expect(shouldDisable(versionDetectionPossible: true), isFalse);
    },
  );
}
