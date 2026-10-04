import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/installers/shizuku_installer.dart';
import 'package:obtainium/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  const channel = MethodChannel('shizuku_apk_installer');

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 0;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('single and split installs identify each actual target package', () async {
    final installer = ShizukuInstaller(SettingsProvider());
    final single = await installer.installApk(
      ['/test/base.apk'],
      appId: 'example.internal',
      installOptions: {'shizukuPretendToBeGooglePlay': true},
    );
    final split = await installer.installApk(
      ['/test/other.apk', '/test/config.apk'],
      appId: 'example.external',
    );
    expect(single.isSuccess, isTrue);
    expect(split.isSuccess, isTrue);
    expect(calls.map((call) => call.method), ['installAPKs', 'installAPKs']);
    expect(calls[0].arguments, {
      'apkFilesURIs': ['file:///test/base.apk'],
      'fakeInstallSource': 'com.android.vending',
      'packageName': 'example.internal',
    });
    expect(calls[1].arguments, {
      'apkFilesURIs': ['file:///test/other.apk', 'file:///test/config.apk'],
      'fakeInstallSource': '',
      'packageName': 'example.external',
    });
  });
}
