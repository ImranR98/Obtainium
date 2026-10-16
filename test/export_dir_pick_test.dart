import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const documentFileChannel = MethodChannel(
    'io.alexrintt.plugins/sharedstorage/documentfile',
  );
  const documentTreeChannel = MethodChannel(
    'dev.imranr.obtainium/document_tree',
  );

  Map<String, dynamic> permission(String uri) => {
    'isReadPermission': true,
    'isWritePermission': true,
    'persistedTime': 0,
    'uri': uri,
    'isTreeDocumentFile': true,
  };

  void mockSaf(
    WidgetTester tester, {
    required List<String> persistedUris,
    required List<String> released,
  }) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      documentFileChannel,
      (call) async {
        switch (call.method) {
          case 'persistedUriPermissions':
            return persistedUris.map(permission).toList();
          case 'canRead':
          case 'canWrite':
            return true;
          case 'releasePersistableUriPermission':
            released.add(call.arguments['uri'] as String);
            return null;
        }
        return null;
      },
    );
  }

  testWidgets('cancelling the picker keeps the stored directory', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'exportDir': 'content://tree/keep',
    });
    final prefs = await SharedPreferences.getInstance();
    final released = <String>[];
    mockSaf(tester, persistedUris: ['content://tree/keep'], released: released);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      documentTreeChannel,
      (call) async => null,
    );

    final settingsProvider = SettingsProvider()..prefs = prefs;
    await settingsProvider.pickExportDir();

    expect(prefs.getString('exportDir'), 'content://tree/keep');
    expect(released, isEmpty);
  });

  testWidgets('picking a directory stores it and releases stale grants', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'exportDir': 'content://tree/old'});
    final prefs = await SharedPreferences.getInstance();
    final released = <String>[];
    mockSaf(tester, persistedUris: ['content://tree/old'], released: released);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      documentTreeChannel,
      (call) async => 'content://tree/new',
    );

    final settingsProvider = SettingsProvider()..prefs = prefs;
    await settingsProvider.pickExportDir();

    expect(prefs.getString('exportDir'), 'content://tree/new');
    expect(released, ['content://tree/old']);
  });
}
