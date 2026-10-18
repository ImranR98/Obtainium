import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/installers/shizuku_installer.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shizuku_apk_installer/shizuku_apk_installer_platform_interface.dart';

class _FakeShizukuPlatform extends ShizukuApkInstallerPlatform {
  String? mode;
  String? permissionResult = 'granted_adb';
  int checkCalls = 0;
  int servicesNotFoundFailures = 0;

  @override
  Future<void> setInstallerMode(String mode) async {
    this.mode = mode;
  }

  @override
  Future<String?> checkPermission() async {
    checkCalls++;
    if (servicesNotFoundFailures > 0) {
      servicesNotFoundFailures--;
      return 'services_not_found';
    }
    return permissionResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeShizukuPlatform fake;
  late SettingsProvider settings;

  setUp(() async {
    fake = _FakeShizukuPlatform();
    ShizukuApkInstallerPlatform.instance = fake;
    SharedPreferences.setMockInitialValues({});
    settings = SettingsProvider();
    settings.prefs = await SharedPreferences.getInstance();
  });

  test('default backend is auto and is passed to the plugin', () async {
    expect(settings.shizukuInstallerMode, 'auto');
    expect(await ShizukuInstaller(settings).checkPermission(), isTrue);
    expect(fake.mode, 'auto');
  });

  test('explicit backends are passed to the plugin', () async {
    settings.shizukuInstallerMode = 'dhizuku';
    await ShizukuInstaller(settings).checkPermission();
    expect(fake.mode, 'dhizuku');

    settings.shizukuInstallerMode = 'shizuku';
    await ShizukuInstaller(settings).checkPermission();
    expect(fake.mode, 'shizuku');
  });

  test('ensurePermission retries a transient missing binder', () async {
    fake.servicesNotFoundFailures = 2;

    await ShizukuInstaller(settings).ensurePermission();

    expect(fake.checkCalls, 3);
  });

  test('ensurePermission surfaces persistent backend errors', () async {
    fake.permissionResult = 'services_not_found';
    await expectLater(
      ShizukuInstaller(settings).ensurePermission(),
      throwsA(isA<ObtainiumError>()),
    );
    expect(fake.checkCalls, 4);
  });
}
