import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_charset_detector/flutter_charset_detector.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class AppCenterMs extends AppSource {
  AppCenterMs() {
    hosts = ['appcenter.ms'];
    name = 'Microsoft App Center';
    // showReleaseDateAsVersionToggle = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    allowSubDomains = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://install\\.${getSourceRegex(hosts)}/orgs/[^/]+/apps/[^/]+/distribution_groups/[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  Future<dynamic> getRelApiJson(String relUrl) async {
    List<String> paths = Uri.parse(relUrl).pathSegments;
    final String orgName = paths[1];
    final String appName = paths[3];
    final String distGrp = paths[5];
    // FIXME: further implementation about additionalSettings, as this call is hard-coded to {}
    Response res = await sourceRequest(
        'https://install.appcenter.ms/api/v0.1/apps/$orgName/$appName/distribution_groups/$distGrp/releases/latest',
        {});
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var appDetails = jsonDecode(res.body);
    return appDetails;
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    return (await getRelApiJson(standardUrl))['bundle_identifier'];
  }

  // return stdUrl should be enough, as it is readable & more readable than api json.
  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => standardUrl;

  @override
  Future<String?> getSourceNote() async =>
    "Currently only able to fetch latest version.\n"
    "The additional information is for further possible implementation (like version match or `search`) if there are anyone want to try before M\$ deleted their database.\n"
    "Format:\n"
    "install.appcenter.ms/orgs/\$orgName/apps/\$appName/\$distribution_groups/\$distGrp\n"
    "=>\n"
    "https://install.appcenter.ms/api/v0.1/apps/\$orgName/\$appName/distribution_groups/\$distGrp/releases/latest\n"
    "History versions API:\n"
    "https://install.appcenter.ms/api/v0.1/apps/\$orgName/\$appName/distribution_groups/\$distGrp/public_releases\n"
  ;


  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var appDetails = await getRelApiJson(standardUrl);
    
    // handle not found
    if (appDetails['code'] == 'not_found') {
      throw NoReleasesError();
    }

    final String author = appDetails['owner']['display_name'];  // display_name should be enough, for user ;)
    String? dateStr = appDetails['uploaded_at'];
    String? version = appDetails['version'];
    String? changeLog = appDetails['release_notes'];
    if (version == null) {
      throw NoVersionError();
    }
    DateTime? relDate;
    if (dateStr != null) {
      relDate = DateTime.parse(dateStr);
    }

    if (appDetails['download_url'] == null) {
      throw NoAPKError();
    }
    final String apkLink = appDetails['download_url'];
    final String appDispName = appDetails['app_display_name'];

    return APKDetails(
        version,
        getApkUrlsFromUrls([apkLink]),
        AppNames(author, appDispName),
        releaseDate: relDate,
        changeLog: changeLog);
  }
}
