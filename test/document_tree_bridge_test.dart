import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/document_tree_bridge.dart';

void main() {
  const channel = MethodChannel('dev.imranr.obtainium/document_tree');

  testWidgets('parses the picked tree URI', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'pickDocumentTree');
      return 'content://com.android.externalstorage.documents/tree/primary%3ADownload';
    });
    final uri = await DocumentTreeBridge.instance.pickDocumentTree();
    expect(
      uri,
      Uri.parse(
        'content://com.android.externalstorage.documents/tree/primary%3ADownload',
      ),
    );
  });

  testWidgets('returns null when the picker is cancelled', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => null,
    );
    expect(await DocumentTreeBridge.instance.pickDocumentTree(), isNull);
  });

  testWidgets('propagates platform errors to the caller', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'NO_PICKER'),
    );
    expect(
      DocumentTreeBridge.instance.pickDocumentTree(),
      throwsA(isA<PlatformException>()),
    );
  });
}
