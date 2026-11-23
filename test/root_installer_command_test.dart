import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/installers/root_installer.dart';

void main() {
  group('buildRootInstallCommand', () {
    test('builds the standard install command', () {
      expect(
        buildRootInstallCommand(
          installerPackageName: '',
          userId: 0,
          stagedApks: ["'\$d/obt0.apk'"],
          bypassLowTargetSdkBlock: false,
        ),
        "pm install -r --user 0 '\$d/obt0.apk'",
      );
    });

    test('sets the installer package', () {
      expect(
        buildRootInstallCommand(
          installerPackageName: 'com.example.store',
          userId: 10,
          stagedApks: ["'\$d/obt0.apk'"],
          bypassLowTargetSdkBlock: false,
        ),
        "pm install -r -i 'com.example.store' --user 10 '\$d/obt0.apk'",
      );
    });

    test('adds the low-target-SDK bypass flag', () {
      expect(
        buildRootInstallCommand(
          installerPackageName: '',
          userId: 0,
          stagedApks: ["'\$d/obt0.apk'", "'\$d/obt1.apk'"],
          bypassLowTargetSdkBlock: true,
        ),
        "pm install -r --user 0 --bypass-low-target-sdk-block '\$d/obt0.apk' '\$d/obt1.apk'",
      );
    });
  });
}
