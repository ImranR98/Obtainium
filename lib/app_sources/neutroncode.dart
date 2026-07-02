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
    'january': '01',
    'february': '02',
    'march': '03',
    'april': '04',
    'may': '05',
    'june': '06',
    'july': '07',
    'august': '08',
    'september': '09',
    'october': '10',
    'november': '11',
    'december': '12',
  };

  String monthNameToNumberString(String s) =>
      _monthMap[s.toLowerCase()] ??
      (throw ArgumentError('Invalid month name: $s'));

  String? formatDateForParsing(String dateString) {
    final List<String> parts = dateString.split(' ');
    if (parts.length != 3) {
      return null;
    }
    final monthIdx = parts.indexWhere((s) => int.tryParse(s) == null);
    if (monthIdx < 0) return null;
    final month = monthNameToNumberString(parts[monthIdx]);
    final numericParts = [
      for (var i = 0; i < 3; i++)
        if (i != monthIdx) int.tryParse(parts[i]),
    ];
    if (numericParts.contains(null) || numericParts.length != 2) return null;
    final a = numericParts[0]!, b = numericParts[1]!;
    final year = a > 31 ? a : (b > 31 ? b : (a.toString().length == 4 ? a : b));
    final day = a == year ? b : a;
    return '$year-$month-${day.toString().padLeft(2, '0')}';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final Response res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode == 200) {
        final http = parse(res.body);
        final name = http.querySelector('.pd-title')?.innerHtml;
        final filename = http
            .querySelector('.pd-filename .pd-float')
            ?.innerHtml;
        if (filename == null) {
          throw NoReleasesError();
        }
        final version = http
            .querySelector('.pd-version-txt')
            ?.nextElementSibling
            ?.innerHtml;
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }
        final String apkUrl = 'https://${hosts[0]}/download/$filename';
        final dateStringOriginal = http
            .querySelector('.pd-date-txt')
            ?.nextElementSibling
            ?.innerHtml;
        final dateString = dateStringOriginal != null
            ? (formatDateForParsing(dateStringOriginal))
            : null;
        final changeLogElements = http.querySelectorAll('.pd-fdesc p');
        return APKDetails(
          version,
          getApkUrlsFromUrls([apkUrl]),
          AppNames(sourceIdentifier, name ?? standardUrl.split('/').last),
          releaseDate: dateString != null
              ? DateTime.tryParse(dateString)
              : null,
          changeLog: changeLogElements.isNotEmpty
              ? changeLogElements.last.innerHtml
              : null,
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
