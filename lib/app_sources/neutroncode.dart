import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class NeutronCode extends AppSource {
  NeutronCode() {
    hosts = ['neutroncode.com'];
    showReleaseDateAsVersionToggle = true;
    changeLogPageIsStandardUrl = true;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'/downloads/file/[^/]+',
  );

  static const _monthMap = {
    'january': '01', 'february': '02', 'march': '03',
    'april': '04', 'may': '05', 'june': '06',
    'july': '07', 'august': '08', 'september': '09',
    'october': '10', 'november': '11', 'december': '12',
  };

  String monthNameToNumberString(String s) =>
      _monthMap[s.toLowerCase()] ?? (throw ArgumentError('Invalid month name: $s'));

  String? formatDateForParsing(String dateString) {
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
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      String? apkUrl = 'https://${hosts[0]}/download/$filename';
      var dateStringOriginal = http
          .querySelector('.pd-date-txt')
          ?.nextElementSibling
          ?.innerHtml;
      var dateString = dateStringOriginal != null
          ? (formatDateForParsing(dateStringOriginal))
          : null;
      var changeLogElements = http.querySelectorAll('.pd-fdesc p');
      return APKDetails(
        version,
        getApkUrlsFromUrls([apkUrl]),
        AppNames(sourceIdentifier, name ?? standardUrl.split('/').last),
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
