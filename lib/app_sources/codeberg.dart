import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Codeberg extends AppSource {
  Codeberg() {
    host = 'codeberg.org';

    additionalSourceSpecificSettingFormItems = [];

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('includePrereleases',
            label: tr('includePrereleases'), defaultValue: false)
      ],
      [
        GeneratedFormSwitch('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'), defaultValue: true)
      ],
      [
        GeneratedFormTextField('filterReleaseTitlesByRegEx',
            label: tr('filterReleaseTitlesByRegEx'),
            required: false,
            additionalValidators: [
              (value) {
                if (value == null || value.isEmpty) {
                  return null;
                }
                try {
                  RegExp(value);
                } catch (e) {
                  return tr('invalidRegEx');
                }
                return null;
              }
            ])
      ]
    ];

    canSearch = true;
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    bool includePrereleases = additionalSettings['includePrereleases'];
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'];
    String? regexFilter =
        (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                    ?.isNotEmpty ==
                true
            ? additionalSettings['filterReleaseTitlesByRegEx']
            : null;
    Response res = await get(Uri.parse(
        'https://$host/api/v1/repos${standardUrl.substring('https://$host'.length)}/releases'));
    if (res.statusCode == 200) {
      var releases = jsonDecode(res.body) as List<dynamic>;

      List<String> getReleaseAPKUrls(dynamic release) =>
          (release['assets'] as List<dynamic>?)
              ?.map((e) {
                return e['name'] != null && e['browser_download_url'] != null
                    ? MapEntry(e['name'] as String,
                        e['browser_download_url'] as String)
                    : const MapEntry('', '');
              })
              .where((element) => element.key.toLowerCase().endsWith('.apk'))
              .map((e) => e.value)
              .toList() ??
          [];

      dynamic targetRelease;

      for (int i = 0; i < releases.length; i++) {
        if (!fallbackToOlderReleases && i > 0) break;
        if (!includePrereleases && releases[i]['prerelease'] == true) {
          continue;
        }
        if (releases[i]['draft'] == true) {
          // Draft releases not supported
        }
        var nameToFilter = releases[i]['name'] as String?;
        if (nameToFilter == null || nameToFilter.trim().isEmpty) {
          // Some leave titles empty so tag is used
          nameToFilter = releases[i]['tag_name'] as String;
        }
        if (regexFilter != null &&
            !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
          continue;
        }
        var apkUrls = getReleaseAPKUrls(releases[i]);
        if (apkUrls.isEmpty && additionalSettings['trackOnly'] != true) {
          continue;
        }
        targetRelease = releases[i];
        targetRelease['apkUrls'] = apkUrls;
        break;
      }
      if (targetRelease == null) {
        throw NoReleasesError();
      }
      String? version = targetRelease['tag_name'];
      if (version == null) {
        throw NoVersionError();
      }
      return APKDetails(version, targetRelease['apkUrls'] as List<String>,
          getAppNames(standardUrl));
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }

  @override
  Future<Map<String, String>> search(String query) async {
    Response res = await get(Uri.parse(
        'https://$host/api/v1/repos/search?q=${Uri.encodeQueryComponent(query)}&limit=100'));
    if (res.statusCode == 200) {
      Map<String, String> urlsWithDescriptions = {};
      for (var e in (jsonDecode(res.body)['data'] as List<dynamic>)) {
        urlsWithDescriptions.addAll({
          e['html_url'] as String: e['description'] != null
              ? e['description'] as String
              : tr('noDescription')
        });
      }
      return urlsWithDescriptions;
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
