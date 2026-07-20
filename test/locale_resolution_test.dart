import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/locale_resolution.dart';

const List<Locale> supportedLocales = <Locale>[
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
  Locale('zh'),
  Locale('pt', 'BR'),
  Locale('pt'),
];

void main() {
  test('matches a locale with both script and country subtags', () {
    const Locale deviceLocale = Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
      countryCode: 'TW',
    );

    expect(
      resolveBestSupportedLocale(
        deviceLocale: deviceLocale,
        supportedLocales: supportedLocales,
        fallbackLocale: const Locale('en'),
      ),
      supportedLocales[1],
    );
  });

  test('uses the country match when the device omits a script subtag', () {
    expect(
      resolveBestSupportedLocale(
        deviceLocale: const Locale('zh', 'TW'),
        supportedLocales: supportedLocales,
        fallbackLocale: const Locale('en'),
      ),
      supportedLocales[1],
    );
  });

  test('prefers a language-only locale for an unmatched region', () {
    expect(
      resolveBestSupportedLocale(
        deviceLocale: const Locale('pt', 'PT'),
        supportedLocales: supportedLocales,
        fallbackLocale: const Locale('en'),
      ),
      const Locale('pt'),
    );
  });

  test('falls back when the device language is unsupported', () {
    expect(
      resolveBestSupportedLocale(
        deviceLocale: const Locale('fi', 'FI'),
        supportedLocales: supportedLocales,
        fallbackLocale: const Locale('en'),
      ),
      const Locale('en'),
    );
  });

  test('parses legacy locale tags containing an underscore', () {
    expect(
      parseStoredLocaleTag('zh-Hant_TW'),
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    );
  });
}
