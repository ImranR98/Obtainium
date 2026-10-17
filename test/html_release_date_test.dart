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

  group('selected-link release dates', () {
    const page = '''
<html><body>
<div>
  <a href="https://example.com/app-x64.apk">App x64</a>
  <span>Last modified: Thu. September 3rd, 2026 - 11:41pm</span>
</div>
<div>
  <a href="https://example.com/app-arm64.apk">App arm64</a>
  <span>Last modified: Thu. September 3rd, 2026 - 11:34pm</span>
</div>
</body></html>
''';

    test('uses the date in the selected APK block, not the last one', () {
      expect(
        extractHtmlReleaseDate(
          r'Last modified: (.*)',
          r'$1',
          'EEE. MMMM d, yyyy - h:mma',
          page,
          pageHtml: page,
          selectedLink: 'https://example.com/app-arm64.apk',
          baseUri: Uri.parse('https://example.com/page'),
        ),
        DateTime(2026, 9, 3, 23, 34),
      );
    });

    test('matches an escaped-newline regex at the end of a block', () {
      const page = '''
<html><body><div>
<a href="https://example.com/app.apk">App</a>
<span>Last modified: Thu. September 3rd, 2026 - 11:41pm</span>
</div></body></html>
''';
      expect(
        extractHtmlReleaseDate(
          r'Last modified: (.*?)\\n',
          r'$1',
          'EEE. MMMM d, yyyy - h:mma',
          page,
          pageHtml: page,
          selectedLink: 'https://example.com/app.apk',
          baseUri: Uri.parse('https://example.com/'),
        ),
        DateTime(2026, 9, 3, 23, 41),
      );
    });

    test('resolves relative links against the page URL', () {
      const relativePage = '''
<html><body>
<div>
  <a href="app-x64.apk">App x64</a>
  <span>Last modified: Thu. September 3rd, 2026 - 11:41pm</span>
</div>
<div>
  <a href="app-arm64.apk">App arm64</a>
  <span>Last modified: Thu. September 3rd, 2026 - 11:34pm</span>
</div>
</body></html>
''';
      expect(
        extractHtmlReleaseDate(
          r'Last modified: (.*)',
          r'$1',
          'EEE. MMMM d, yyyy - h:mma',
          relativePage,
          pageHtml: relativePage,
          selectedLink: 'https://example.com/downloads/app-x64.apk',
          baseUri: Uri.parse('https://example.com/downloads/'),
        ),
        DateTime(2026, 9, 3, 23, 41),
      );
    });
  });
}
