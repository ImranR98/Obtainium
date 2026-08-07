import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class HuaweiAppGallery extends AppSource {
  @override
  String get name => tr('huaweiAppGallery');

  HuaweiAppGallery() {
    hosts = ['appgallery.huawei.com', 'appgallery.cloud.huawei.com'];
    versionDetectionDisallowed = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'(/#)?/(app|appdl)/[^/]+',
  );

  String _getDlUrl(String standardUrl) {
    final dlHost = hosts.length > 1 ? hosts[1] : hosts[0];
    return 'https://$dlHost/appdl/${standardUrl.split('/').last}';
  }

  Future<Response> requestAppdlRedirect(
    String dlUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final Response res = await sourceRequest(
      dlUrl,
      additionalSettings,
      followRedirects: false,
    );
    if (res.statusCode == 200 || res.statusCode == 302) {
      return res;
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  String _appIdFromRedirectDlUrl(String redirectDlUrl) {
    final parts = redirectDlUrl
        .split('?')[0]
        .split('/')
        .last
        .split('.')
        .reversed
        .toList();
    if (parts.length < 2) {
      return '';
    }
    parts.removeAt(0);
    parts.removeAt(0);
    return parts.reversed.join('.');
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final String dlUrl = _getDlUrl(standardUrl);
    final Response res = await requestAppdlRedirect(dlUrl, additionalSettings);
    return res.headers['location'] != null
        ? _appIdFromRedirectDlUrl(res.headers['location']!)
        : null;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final String dlUrl = _getDlUrl(standardUrl);
      final Response res = await requestAppdlRedirect(
        dlUrl,
        additionalSettings,
      );
      if (res.headers['location'] == null) {
        throw NoReleasesError();
      }
      final String appId = _appIdFromRedirectDlUrl(res.headers['location']!);
      if (appId.isEmpty) {
        throw NoReleasesError();
      }
      // Drop the file extension, then the `appdl` segment, keeping the version
      // segment (the 3rd-from-last reversed).  Guard against short lists.
      final locSegments = res.headers['location']!
          .split('?')[0]
          .split('.')
          .reversed
          .toList();
      final relDateStr = locSegments.length > 1 ? locSegments[1] : null;
      if (relDateStr == null || relDateStr.length != 10) {
        throw NoVersionError();
      }
      // The date string is a 10-digit compact format (YYMMDDHHMM).
      // Insert hyphens to produce YY-MM-DD-HH-MM for DateFormat parsing.
      final formatted = '${relDateStr.substring(0, 2)}-${relDateStr.substring(2, 4)}-${relDateStr.substring(4, 6)}-${relDateStr.substring(6, 8)}-${relDateStr.substring(8, 10)}';
      final relDate = DateFormat(
        'yy-MM-dd-HH-mm',
        'en_US',
      ).parse(formatted);
      return APKDetails(
        relDateStr,
        [MapEntry('$appId.apk', dlUrl)],
        AppNames(name, appId),
        releaseDate: relDate,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
