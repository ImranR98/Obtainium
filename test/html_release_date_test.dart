import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/html.dart';

void main() {
  group('extractHtmlReleaseDate', () {
    test('parses an ISO date captured by a regex', () {
      expect(
        extractHtmlReleaseDate(
          r'Last modified: (\S+)',
          r'$1',
          null,
          'App 1.0\nLast modified: 2026-09-03\n',
        ),
        DateTime(2026, 9, 3),
      );
    });

    test('parses a custom format like the MiXplorer beta page', () {
      expect(
        extractHtmlReleaseDate(
          r'Last modified: (.*)',
          r'$1',
          'EEE. MMMM d, yyyy - h:mma',
          'MiXplorer_v6.71.15-BETA_B26090414-x64.apk\n'
              'Size: 5.17mbLast modified: Thu. September 3rd, 2026 - 11:41pm\n',
        ),
        DateTime(2026, 9, 3, 23, 41),
      );
    });

    test('uses the whole match when no match group is given', () {
      expect(
        extractHtmlReleaseDate(
          r'\d{4}-\d{2}-\d{2}',
          null,
          null,
          'Published 2026-01-31 by someone',
        ),
        DateTime(2026, 1, 31),
      );
    });

    test('returns null when the regex does not match', () {
      expect(
        extractHtmlReleaseDate(r'Last modified: (.*)', null, null, 'No date'),
        isNull,
      );
    });

    test('returns null when the captured text is not a date', () {
      expect(
        extractHtmlReleaseDate(
          r'Last modified: (.*)',
          r'$1',
          null,
          'Last modified: yesterday',
        ),
        isNull,
      );
    });

    test('returns null for an invalid date format pattern', () {
      expect(
        extractHtmlReleaseDate(
          r'Last modified: (.*)',
          r'$1',
          'not a valid pattern: !!!',
          'Last modified: Thu. September 3rd, 2026 - 11:41pm',
        ),
        isNull,
      );
    });

    test('returns null when no regex is configured', () {
      expect(extractHtmlReleaseDate(null, null, null, 'anything'), isNull);
      expect(extractHtmlReleaseDate('', null, null, 'anything'), isNull);
    });
  });
}
