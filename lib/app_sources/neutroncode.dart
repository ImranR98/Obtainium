import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class NeutronCode extends AppSource {
  NeutronCode() {
    host = 'neutroncode.com';
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/downloads/file/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
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

  customDateParse(String dateString) {
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
    Response res = await get(Uri.parse(standardUrl));
    if (res.statusCode == 200) {
      var http = parse(res.body);
      var name = http.querySelector('.pd-title')?.innerHtml;
      var filename = http.querySelector('.pd-filename .pd-float')?.innerHtml;
      if (filename == null) {
        throw NoReleasesError();
      }
      var version =
          http.querySelector('.pd-version-txt')?.nextElementSibling?.innerHtml;
      if (version == null) {
        throw NoVersionError();
      }
      String? apkUrl = 'https://$host/download/$filename';
      var dateStringOriginal =
          http.querySelector('.pd-date-txt')?.nextElementSibling?.innerHtml;
      var dateString = dateStringOriginal != null
          ? (customDateParse(dateStringOriginal))
          : null;
      var changeLogElements = http.querySelectorAll('.pd-fdesc p');
      return APKDetails(version, getApkUrlsFromUrls([apkUrl]),
          AppNames(runtimeType.toString(), name ?? standardUrl.split('/').last),
          releaseDate: dateString != null ? DateTime.parse(dateString) : null,
          changeLog: changeLogElements.isNotEmpty
              ? changeLogElements.last.innerHtml
              : null);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
