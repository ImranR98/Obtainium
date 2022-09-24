import 'dart:convert';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/source_provider.dart';

class GitHub implements AppSource {
  @override
  late String host = 'github.com';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw notValidURL(runtimeType.toString());
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    // TODO: use additionalData
    Response res = await get(Uri.parse(
        'https://api.$host/repos${standardUrl.substring('https://$host'.length)}/releases'));
    if (res.statusCode == 200) {
      var releases = jsonDecode(res.body) as List<dynamic>;
      // Right now, the latest non-prerelease version is picked
      // If none exists, the latest prerelease version is picked
      // In the future, the user could be given a choice
      var nonPrereleaseReleases =
          releases.where((element) => element['prerelease'] != true).toList();
      var latestRelease = nonPrereleaseReleases.isNotEmpty
          ? nonPrereleaseReleases[0]
          : releases.isNotEmpty
              ? releases[0]
              : null;
      if (latestRelease == null) {
        throw couldNotFindReleases;
      }
      List<dynamic>? assets = latestRelease['assets'];
      List<String>? apkUrlList = assets
          ?.map((e) {
            return e['browser_download_url'] != null
                ? e['browser_download_url'] as String
                : '';
          })
          .where((element) => element.toLowerCase().endsWith('.apk'))
          .toList();
      if (apkUrlList == null || apkUrlList.isEmpty) {
        throw noAPKFound;
      }
      String? version = latestRelease['tag_name'];
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      return APKDetails(version, apkUrlList);
    } else {
      if (res.headers['x-ratelimit-remaining'] == '0') {
        throw 'Rate limit reached - try again in ${(int.parse(res.headers['x-ratelimit-reset'] ?? '1800000000') / 60000000).toString()} minutes';
      }

      throw couldNotFindReleases;
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [
    [GeneratedFormItem(label: "Include prereleases", type: FormItemType.bool)],
    [
      GeneratedFormItem(
          label: "Fallback to older releases", type: FormItemType.bool)
    ],
    [
      GeneratedFormItem(
          label: "Filter APKs by Regular Expression",
          type: FormItemType.string,
          required: false)
    ]
  ];

  @override
  List<String> additionalDataDefaults = ["", "", ""];
}
