import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class HuaweiAppGallery extends AppSource {
  HuaweiAppGallery() {
    name = 'Huawei AppGallery';
    hosts = ['appgallery.huawei.com', 'appgallery.cloud.huawei.com'];
    versionDetectionDisallowed = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}(/#)?/(app|appdl)/[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  String getDlUrl(String standardUrl) =>
      'https://${hosts[0].replaceAll('appgallery.huawei', 'appgallery.cloud.huawei')}/appdl/${standardUrl.split('/').last}';

  Future<Response> requestAppdlRedirect(
    String dlUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    Response res = await sourceRequest(
      dlUrl,
      additionalSettings,
      followRedirects: false,
    );
    if (res.statusCode == 200 ||
        res.statusCode == 302 ||
        res.statusCode == 304) {
      return res;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  String appIdFromRedirectDlUrl(String redirectDlUrl) {
    var parts = redirectDlUrl
        .split('?')[0]
        .split('/')
        .last
        .split('.')
        .reversed
        .toList();
    parts.removeAt(0);
    parts.removeAt(0);
    return parts.reversed.join('.');
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    String dlUrl = getDlUrl(standardUrl);
    Response res = await requestAppdlRedirect(dlUrl, additionalSettings);
    return res.headers['location'] != null
        ? appIdFromRedirectDlUrl(res.headers['location']!)
        : null;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String dlUrl = getDlUrl(standardUrl);
    Response res = await requestAppdlRedirect(dlUrl, additionalSettings);
    if (res.headers['location'] == null) {
      throw NoReleasesError();
    }
    String appId = appIdFromRedirectDlUrl(res.headers['location']!);
    if (appId.isEmpty) {
      throw NoReleasesError();
    }
    var relDateStr = res.headers['location']
        ?.split('?')[0]
        .split('.')
        .reversed
        .toList()[1];
    if (relDateStr == null || relDateStr.length != 10) {
      throw NoVersionError();
    }
    var relDateStrAdj = relDateStr.split('');
    var tempLen = relDateStrAdj.length;
    var i = 2;
    while (i < tempLen) {
      relDateStrAdj.insert((i + i ~/ 2 - 1), '-');
      i += 2;
    }
    var relDate = DateFormat(
      'yy-MM-dd-HH-mm',
      'en_US',
    ).parse(relDateStrAdj.join(''));
    return APKDetails(
      relDateStr,
      [MapEntry('$appId.apk', dlUrl)],
      AppNames(name, appId),
      releaseDate: relDate,
    );
  }
}
