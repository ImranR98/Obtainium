import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/easy_localization_controller.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/settings_provider.dart';

class TranslationLoader {
  static Future<void> load() async {
    await EasyLocalizationController.initEasyLocation();
    final s = SettingsProvider();
    await s.initializeSettings();
    final forceLocale = s.forcedLocale;
    final controller = EasyLocalizationController(
      saveLocale: true,
      forceLocale: forceLocale,
      fallbackLocale: fallbackLocale,
      supportedLocales: supportedLocales.map((e) => e.key).toList(),
      assetLoader: const RootBundleAssetLoader(),
      useOnlyLangCode: false,
      useFallbackTranslations: true,
      path: localeDir,
      onLoadError: (FlutterError e) {
        // Do not rethrow: a failed translation asset load (e.g. only the
        // fallback locale missing) must not abort the background task. The
        // translations that did load remain usable.
        debugPrint('Failed to load translations: ${e.message}');
      },
    );
    await controller.loadTranslations();
    Localization.load(
      controller.locale,
      translations: controller.translations,
      fallbackTranslations: controller.fallbackTranslations,
    );
    setAppLocale(controller.locale);
  }
}
