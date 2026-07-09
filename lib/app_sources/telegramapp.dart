import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class TelegramApp extends AppSource {
  TelegramApp() {
    hosts = ['telegram.org'];
    name = tr('telegramApp');
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    // Telegram has a single known APK download page — the user's exact URL
    // does not affect which APK is found, so normalize to the homepage.
    return 'https://${hosts[0]}';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final Response res = await sourceRequest(
        'https://t.me/s/TAndroidAPK',
        additionalSettings,
      );
      if (res.statusCode == 200) {
        final http = parse(res.body);
        final messages = http.querySelectorAll(
          '.tgme_widget_message_text.js-message_text',
        );
        final version = messages.isNotEmpty
            ? messages.last.innerHtml.split('\n').first.trim().split(' ').first
            : null;
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
        const String apkUrl = 'https://telegram.org/dl/android/apk';
        return APKDetails(version, [
          MapEntry<String, String>('telegram-$version.apk', apkUrl),
        ], AppNames('Telegram', 'Telegram'));
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
