import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/apkmirror.dart';

void main() {
  group('apkMirrorVersionFromTitle', () {
    test('extracts a dotted version and ignores arch/android suffixes', () {
      expect(
        apkMirrorVersionFromTitle(
          'Spotify 9.0.36.643 (arm64-v8a) (Android 7.0+) APK Download by Spotify AB',
        ),
        '9.0.36.643',
      );
    });

    test('skips digits at the start of the app name', () {
      expect(
        apkMirrorVersionFromTitle(
          '7-Zip 25.01 (arm64-v8a) (Android 4.4+) APK Download by Igor Pavlov',
        ),
        '25.01',
      );
    });

    test('ignores bracketed build metadata after the version', () {
      expect(
        apkMirrorVersionFromTitle(
          'Google Play Store 42.5.15-21 [0] [PR] 630551585 (arm64-v8a) (Android 12+) by Google LLC',
        ),
        '42.5.15-21',
      );
    });

    test('skips a version-like token in the app name', () {
      expect(
        apkMirrorVersionFromTitle(
          '1.1.1.1: Faster & Safer Internet 6.32 (arm64-v8a) (Android 5.0+) by Cloudflare, Inc.',
        ),
        '6.32',
      );
    });

    test('handles a decorated name and a plain version', () {
      expect(
        apkMirrorVersionFromTitle(
          'APKMirror Installer (Official) 1.1.5 (arm64-v8a) (Android 8.0+) by APKMirror',
        ),
        '1.1.5',
      );
    });

    test('returns null when the title has no version', () {
      expect(
        apkMirrorVersionFromTitle('Some App (Android 8.0+) by Author'),
        isNull,
      );
    });
  });

  group('apkMirrorCleanReleaseTitle', () {
    test('strips author and parenthesized/bracketed groups', () {
      expect(
        apkMirrorCleanReleaseTitle(
          'App 1.2.3 [0] (arm64-v8a) (Android 8.0+) by Author',
        ),
        'App 1.2.3',
      );
    });
  });

  group('apkMirrorReleaseUrlFromFeedBodyForItemIndex', () {
    const feed = '''
<?xml version="1.0"?>
<rss><channel>
<item>
<title>App One 1.0 by A</title>
<link>https://www.apkmirror.com/apk/dev/app-one/app-one-1-0-release/</link>
<pubDate>Sun, 13 Sep 2026 01:02:27 +0000</pubDate>
</item>
<item>
<title>App One 1.1 by A</title>
<link>https://www.apkmirror.com/apk/dev/app-one/app-one-1-1-release/</link>
<pubDate>Mon, 14 Sep 2026 01:02:27 +0000</pubDate>
</item>
</channel></rss>
''';

    test('extracts the release URL for a given item index', () {
      expect(
        apkMirrorReleaseUrlFromFeedBodyForItemIndex(feed, 0),
        'https://www.apkmirror.com/apk/dev/app-one/app-one-1-0-release/',
      );
      expect(
        apkMirrorReleaseUrlFromFeedBodyForItemIndex(feed, 1),
        'https://www.apkmirror.com/apk/dev/app-one/app-one-1-1-release/',
      );
    });

    test('returns null for out-of-range or missing links', () {
      expect(apkMirrorReleaseUrlFromFeedBodyForItemIndex(feed, 5), isNull);
      expect(apkMirrorReleaseUrlFromFeedBodyForItemIndex(feed, -1), isNull);
      expect(
        apkMirrorReleaseUrlFromFeedBodyForItemIndex('<item></item>', 0),
        isNull,
      );
    });
  });

  group('apkMirrorPackageFromIconUrl', () {
    test('extracts the package segment from an og:image filename', () {
      expect(
        apkMirrorPackageFromIconUrl(
          'https://downloadr2.apkmirror.com/wp-content/uploads/2024/01/11/65a71d34ecd19_com.android.chrome.png',
        ),
        'com.android.chrome',
      );
    });

    test('returns null for hash-only or invalid filenames', () {
      expect(
        apkMirrorPackageFromIconUrl(
          'https://downloadr2.apkmirror.com/wp-content/uploads/2024/01/11/65a71d34ecd19.png',
        ),
        isNull,
      );
      expect(apkMirrorPackageFromIconUrl(null), isNull);
      expect(apkMirrorPackageFromIconUrl(''), isNull);
    });
  });

  group('apkMirrorSizeBytesFromPageText', () {
    test('parses a file size with a newline between label and value', () {
      expect(
        apkMirrorSizeBytesFromPageText('File size:\n270.70 MB'),
        (270.70 * 1024 * 1024).round(),
      );
    });

    test('parses KB and GB units', () {
      expect(apkMirrorSizeBytesFromPageText('File size: 12 KB'), 12 * 1024);
      expect(
        apkMirrorSizeBytesFromPageText('File size: 1.5 GB'),
        1.5 * 1073741824,
      );
    });

    test('returns null when no size is present', () {
      expect(apkMirrorSizeBytesFromPageText('No size here'), isNull);
    });
  });

  group('apkMirrorDownloadPageUrlFromReleasePage', () {
    const html = '''
<html><body>
<a href="/apk/dev/app/app-1-2-3-release/app-1-2-3-android-apk-download/">APK</a>
<a href="/apk/other/thing/other-1-0-release/other-1-0-android-apk-download/">Other</a>
<a href="https://example.com/">External</a>
</body></html>
''';

    test('resolves the first same-release download page link', () {
      expect(
        apkMirrorDownloadPageUrlFromReleasePage(
          html,
          'https://www.apkmirror.com/apk/dev/app/app-1-2-3-release/',
        ),
        'https://www.apkmirror.com/apk/dev/app/app-1-2-3-release/app-1-2-3-android-apk-download/',
      );
    });

    test('returns null when there is no download link', () {
      expect(
        apkMirrorDownloadPageUrlFromReleasePage(
          '<a href="/apk/other/x/">x</a>',
          'https://www.apkmirror.com/apk/dev/app/app-1-2-3-release/',
        ),
        isNull,
      );
    });
  });

  group('apkMirrorChangeLogFromReleasePageHtml', () {
    test('extracts the What\'s new block and stops at About', () {
      const html = '''
<html><body>
<h2><a href="#whatsnew">What's new in App 1.2.3</a></h2>
<div>
<p>Thanks for choosing App!</p>
<p>Fixed bugs.</p>
<ul><li>Faster startup</li><li>New icon</li></ul>
</div>
<p>Verified safe to install (read more)</p>
<p>Scroll to available downloads</p>
<h2>About App 1.2.3</h2>
<p>This text must not be included.</p>
</body></html>
''';
      final changeLog = apkMirrorChangeLogFromReleasePageHtml(html);
      expect(changeLog, contains('Thanks for choosing App!'));
      expect(changeLog, contains('Fixed bugs.'));
      expect(changeLog, contains('- Faster startup'));
      expect(changeLog, contains('- New icon'));
      expect(changeLog, isNot(contains('Verified safe')));
      expect(changeLog, isNot(contains('This text must not be included.')));
    });

    test('returns null when there is no What\'s new section', () {
      expect(
        apkMirrorChangeLogFromReleasePageHtml(
          '<html><body><h2>About App</h2><p>x</p></body></html>',
        ),
        isNull,
      );
    });
  });
}
