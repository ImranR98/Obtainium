import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class NeutronCode extends AppSource {
  NeutronCode() {
    hosts = ['neutroncode.com'];
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/downloads/file/[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => standardUrl;

  String monthNameToNumberString(String s) {
    switch (s.toLowerCase()) {
      case 'january':
        return '01';
      case 'february':
        return '02';
      case 'march':
        return '03';
      case 'april':
        return '04';
      case 'may':
        return '05';
      case 'june':
        return '06';
      case 'july':
        return '07';
      case 'august':
        return '08';
      case 'september':
        return '09';
      case 'october':
        return '10';
      case 'november':
        return '11';
      case 'december':
        return '12';
      default:
        throw ArgumentError('Invalid month name: $s');
    }
  }

  String? customDateParse(String dateString) {
    List<String> parts = dateString.split(' ');
    if (parts.length != 3) {
      return null;
    }
    String result = '';
    for (var s in parts.reversed) {
      try {
        try {
          int.parse(s);
          result += '$s-';
        } catch (e) {
          result += '${monthNameToNumberString(s)}-';
        }
      } catch (e) {
        return null;
      }
    }
    return result.substring(0, result.length - 1);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode == 200) {
      var http = parse(res.body);
      var name = http.querySelector('.pd-title')?.innerHtml;
      var filename = http.querySelector('.pd-filename .pd-float')?.innerHtml;
      if (filename == null) {
        throw NoReleasesError();
      }
      var version = http
          .querySelector('.pd-version-txt')
          ?.nextElementSibling
          ?.innerHtml;
      if (version == null) {
        throw NoVersionError();
      }
      String? apkUrl = 'https://${hosts[0]}/download/$filename';
      var dateStringOriginal = http
          .querySelector('.pd-date-txt')
          ?.nextElementSibling
          ?.innerHtml;
      var dateString = dateStringOriginal != null
          ? (customDateParse(dateStringOriginal))
          : null;
      var changeLogElements = http.querySelectorAll('.pd-fdesc p');
      return APKDetails(
        version,
        getApkUrlsFromUrls([apkUrl]),
        AppNames(runtimeType.toString(), name ?? standardUrl.split('/').last),
        releaseDate: dateString != null ? DateTime.parse(dateString) : null,
        changeLog: changeLogElements.isNotEmpty
            ? changeLogElements.last.innerHtml
            : null,
      );
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
