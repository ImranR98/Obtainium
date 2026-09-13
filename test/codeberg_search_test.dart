import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/codeberg.dart';
import 'package:obtainium/custom_errors.dart';

void main() {
  group('Codeberg.searchUriFor', () {
    test('defaults to codeberg.org', () {
      expect(Codeberg.searchUriFor(null).origin, 'https://codeberg.org');
      expect(Codeberg.searchUriFor('').origin, 'https://codeberg.org');
      expect(Codeberg.searchUriFor('   ').origin, 'https://codeberg.org');
    });

    test('accepts scheme-less hosts', () {
      expect(
        Codeberg.searchUriFor('git.example.com').origin,
        'https://git.example.com',
      );
    });

    test('keeps schemes and ports and strips paths', () {
      expect(
        Codeberg.searchUriFor('https://git.example.com/user/repo').origin,
        'https://git.example.com',
      );
      expect(
        Codeberg.searchUriFor('http://localhost:3000/user/repo').origin,
        'http://localhost:3000',
      );
    });

    test('honors a fallback host', () {
      expect(
        Codeberg.searchUriFor(null, fallbackHost: 'forgejo.example').origin,
        'https://forgejo.example',
      );
    });

    test('rejects unusable input', () {
      expect(
        () => Codeberg.searchUriFor('https://'),
        throwsA(isA<ObtainiumError>()),
      );
    });
  });
}
