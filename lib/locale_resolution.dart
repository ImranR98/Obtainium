import 'dart:ui';

Locale? parseStoredLocaleTag(String? localeTag) {
  if (localeTag == null || localeTag.trim().isEmpty) return null;

  final List<String> segments = localeTag
      .trim()
      .replaceAll('_', '-')
      .split('-')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.isEmpty) return null;

  String? scriptCode;
  String? countryCode;
  if (segments.length > 1) {
    if (segments[1].length == 4) {
      scriptCode = segments[1];
      if (segments.length > 2) {
        countryCode = segments[2];
      }
    } else {
      countryCode = segments[1];
    }
  }

  return Locale.fromSubtags(
    languageCode: segments.first,
    scriptCode: scriptCode,
    countryCode: countryCode,
  );
}

Locale resolveBestSupportedLocale({
  required Locale deviceLocale,
  required List<Locale> supportedLocales,
  required Locale fallbackLocale,
}) {
  for (final Locale supportedLocale in supportedLocales) {
    if (supportedLocale.languageCode == deviceLocale.languageCode &&
        supportedLocale.scriptCode == deviceLocale.scriptCode &&
        supportedLocale.countryCode == deviceLocale.countryCode) {
      return supportedLocale;
    }
  }

  if (deviceLocale.scriptCode?.isNotEmpty == true) {
    for (final Locale supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == deviceLocale.languageCode &&
          supportedLocale.scriptCode == deviceLocale.scriptCode &&
          (supportedLocale.countryCode == null ||
              supportedLocale.countryCode == deviceLocale.countryCode)) {
        return supportedLocale;
      }
    }
  }

  if (deviceLocale.countryCode?.isNotEmpty == true) {
    for (final Locale supportedLocale in supportedLocales) {
      final bool scriptIsCompatible =
          deviceLocale.scriptCode == null ||
          supportedLocale.scriptCode == null ||
          supportedLocale.scriptCode == deviceLocale.scriptCode;
      if (supportedLocale.languageCode == deviceLocale.languageCode &&
          supportedLocale.countryCode == deviceLocale.countryCode &&
          scriptIsCompatible) {
        return supportedLocale;
      }
    }
  }

  for (final Locale supportedLocale in supportedLocales) {
    if (supportedLocale.languageCode == deviceLocale.languageCode &&
        supportedLocale.scriptCode == null &&
        supportedLocale.countryCode == null) {
      return supportedLocale;
    }
  }

  for (final Locale supportedLocale in supportedLocales) {
    if (supportedLocale.languageCode == deviceLocale.languageCode) {
      return supportedLocale;
    }
  }

  return fallbackLocale;
}
