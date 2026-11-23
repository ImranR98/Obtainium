import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/utils/app_id_utils.dart';

void main() {
  group('isValidAppId', () {
    test('accepts package names and temporary IDs', () {
      expect(isValidAppId('com.example.app'), isTrue);
      expect(isValidAppId('org.barebrowser'), isTrue);
      expect(isValidAppId('a1b2c3d4e5f6'), isTrue);
      expect(isValidAppId('1234567890'), isTrue);
      expect(isValidAppId('com.example.app_debug'), isTrue);
    });

    test('rejects path separators and null bytes', () {
      expect(isValidAppId('../escape'), isFalse);
      expect(isValidAppId('..\\escape'), isFalse);
      expect(isValidAppId('sub/dir'), isFalse);
      expect(isValidAppId('sub\\dir'), isFalse);
      expect(isValidAppId('com.example\x00app'), isFalse);
    });

    test('rejects parent directory components', () {
      expect(isValidAppId('.'), isFalse);
      expect(isValidAppId('..'), isFalse);
    });

    test('rejects empty and overlong IDs', () {
      expect(isValidAppId(''), isFalse);
      expect(isValidAppId('a' * 256), isFalse);
      expect(isValidAppId('a' * 255), isTrue);
    });
  });
}
