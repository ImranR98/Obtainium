import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/source_provider.dart';

void main() {
  test('extractVersion extracts semver', () {
    final version = VersionService().extractVersion(
      r'v(\d+\.\d+\.\d+)',
      '1',
      'v1.2.3',
    );
    expect(version, '1.2.3');
  });

  test('findStandardFormatsForVersion detects common patterns', () {
    final version = VersionService();
    expect(version.findStandardFormatsForVersion('2.0.0', false), isNotEmpty);
  });
}
