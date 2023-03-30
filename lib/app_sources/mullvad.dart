import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Mullvad extends AppSource {
  Mullvad() {
    host = 'mullvad.net';
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      'https://github.com/mullvad/mullvadvpn-app/blob/master/CHANGELOG.md';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var details = await HTML().getLatestAPKDetails(
        '$standardUrl/en/download/android', additionalSettings);
    var fileName = details.apkUrls[0].split('/').last;
    var versionMatch = RegExp('[0-9]+(\\.[0-9]+)+').firstMatch(fileName);
    if (versionMatch == null) {
      throw NoVersionError();
    }
    details.version = fileName.substring(versionMatch.start, versionMatch.end);
    details.names = AppNames(name, 'Mullvad-VPN');
    try {
      details.changeLog = (await GitHub().getLatestAPKDetails(
              'https://github.com/mullvad/mullvadvpn-app',
              {'fallbackToOlderReleases': true}))
          .changeLog;
    } catch (e) {
      print(e);
      // Ignore
    }
    return details;
  }
}
