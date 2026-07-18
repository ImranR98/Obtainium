import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/bulk_import_service.dart';

void main() {
  group('APKMirror availability metadata', () {
    test('extracts icon URL from the existing availability response', () {
      final item = <String, dynamic>{
        'pname': 'eu.darken.sdmse',
        'exists': true,
        'app': <String, dynamic>{
          'link': '/apk/darken/sd-maid-2-se-system-cleaner/',
          'icon_url': ' https://cdn.example.com/sd-maid-se.png ',
        },
      };

      expect(
        apkMirrorIconUrlFromAvailabilityItem(item),
        'https://cdn.example.com/sd-maid-se.png',
      );
    });

    test('ignores missing or empty icon URLs', () {
      expect(
        apkMirrorIconUrlFromAvailabilityItem(<String, dynamic>{
          'app': <String, dynamic>{'icon_url': '   '},
        }),
        isNull,
      );
      expect(apkMirrorIconUrlFromAvailabilityItem(null), isNull);
    });
  });
}
