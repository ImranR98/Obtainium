import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/utils/string_utils.dart';

void main() {
  final nightly = RegExp('nightly', caseSensitive: false);

  test('passes matching values by default', () {
    expect(passesRegExFilter(nightly, 'Nightly 2026-10-14'), isTrue);
    expect(passesRegExFilter(nightly, 'v1.2.3'), isFalse);
  });

  test('inverts the match when requested', () {
    expect(
      passesRegExFilter(nightly, 'Nightly 2026-10-14', invert: true),
      isFalse,
    );
    expect(passesRegExFilter(nightly, 'v1.2.3', invert: true), isTrue);
  });
}
