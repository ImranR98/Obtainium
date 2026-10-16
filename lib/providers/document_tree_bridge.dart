import 'package:flutter/services.dart';

/// Picks a folder through `ACTION_OPEN_DOCUMENT_TREE` with read and write
/// persistable access. Needed because shared_storage's `openDocumentTree` can
/// only request one of the two flags, so persisted export directories lose
/// read access once the temporary grant expires (#3227).
class DocumentTreeBridge {
  DocumentTreeBridge._();

  static final DocumentTreeBridge instance = DocumentTreeBridge._();

  static const MethodChannel _channel = MethodChannel(
    'dev.imranr.obtainium/document_tree',
  );

  /// Returns the picked tree URI, or null when the user cancelled.
  Future<Uri?> pickDocumentTree() async {
    final result = await _channel.invokeMethod<String>('pickDocumentTree');
    return result == null ? null : Uri.parse(result);
  }
}
