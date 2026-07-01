import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/source_provider.dart';

void main() {
  test('isApkOrContainerFile detects APK files', () {
    expect(ApkFilterService.isApkOrContainerFile('app.apk'), true);
    expect(ApkFilterService.isApkOrContainerFile('app.xapk'), true);
    expect(ApkFilterService.isApkOrContainerFile('app.txt'), false);
  });
}
