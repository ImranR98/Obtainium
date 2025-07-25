import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Mullvad extends AppSource {
  Mullvad() {
    hosts = ['mullvad.net'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      'https://github.com/mullvad/mullvadvpn-app/blob/master/CHANGELOG.md';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await sourceRequest(
      '$standardUrl/en/download/android',
      additionalSettings,
    );
    if (res.statusCode == 200) {
      var versions = parse(res.body)
          .querySelectorAll('p')
          .map((e) => e.innerHtml)
          .where((p) => p.contains('Latest version: '))
          .map((e) {
            var match = RegExp('[0-9]+(\\.[0-9]+)*').firstMatch(e);
            if (match == null) {
              return '';
            } else {
              return e.substring(match.start, match.end);
            }
          })
          .where((element) => element.isNotEmpty)
          .toList();
      if (versions.isEmpty) {
        throw NoVersionError();
      }
      String? changeLog;
      try {
        changeLog = (await GitHub(hostChanged: true).getLatestAPKDetails(
          'https://github.com/mullvad/mullvadvpn-app',
          {'fallbackToOlderReleases': true},
        )).changeLog;
      } catch (e) {
        // Ignore
      }
      return APKDetails(
        versions[0],
        getApkUrlsFromUrls(['https://mullvad.net/download/app/apk/latest']),
        AppNames(name, 'Mullvad-VPN'),
        changeLog: changeLog,
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
