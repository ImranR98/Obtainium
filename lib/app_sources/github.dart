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
    var includePrereleases =
        additionalData.isNotEmpty && additionalData[0] == "true";
    var fallbackToOlderReleases =
        additionalData.length >= 2 && additionalData[1] == "true";
    var regexFilter = additionalData.length >= 3 && additionalData[2].isNotEmpty
        ? additionalData[2]
        : null;
    Response res = await get(Uri.parse(
        'https://api.$host/repos${standardUrl.substring('https://$host'.length)}/releases'));
    if (res.statusCode == 200) {
      var releases = jsonDecode(res.body) as List<dynamic>;
      // TODO: Loop through each release and pick the latest one that matches:
      //        The regex if any
      //        The prerelease/not if any
      //        Only latest if fallback is false
      //        Will remain w zero or one release

      List<String> getReleaseAPKUrls(dynamic release) =>
          (release['assets'] as List<dynamic>?)
              ?.map((e) {
                return e['browser_download_url'] != null
                    ? e['browser_download_url'] as String
                    : '';
              })
              .where((element) => element.toLowerCase().endsWith('.apk'))
              .toList() ??
          [];

      dynamic targetRelease;

      for (int i = 0; i < releases.length; i++) {
        if (!fallbackToOlderReleases && i > 0) break;
        if (!includePrereleases && releases[i]['prerelease'] == true) {
          continue;
        }
        if (regexFilter != null &&
            !RegExp(regexFilter)
                .hasMatch((releases[i]['name'] as String).trim())) {
          continue;
        }
        var apkUrls = getReleaseAPKUrls(releases[i]);
        if (apkUrls.isEmpty) {
          continue;
        }
        targetRelease = releases[i];
        targetRelease['apkUrls'] = apkUrls;
        break;
      }
      if (targetRelease == null) {
        throw couldNotFindReleases;
      }
      if ((targetRelease['apkUrls'] as List<String>).isEmpty) {
        throw noAPKFound;
      }
      String? version = targetRelease['tag_name'];
      if (version == null) {
        throw couldNotFindLatestVersion;
      }
      return APKDetails(version, targetRelease['apkUrls']);
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
          label: "Filter Release Titles by Regular Expression",
          type: FormItemType.string,
          required: false,
          additionalValidators: [
            (value) {
              if (value == null || value.isEmpty) {
                return null;
              }
              try {
                RegExp(value);
              } catch (e) {
                return "Invalid regular expression";
              }
            }
          ])
    ]
  ];

  @override
  List<String> additionalDataDefaults = ["true", "", ""];
}
