import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

extension Unique<E, Id> on List<E> {
  List<E> unique([Id Function(E element)? id, bool inplace = true]) {
    final ids = <dynamic>{};
    var list = inplace ? this : List<E>.from(this);
    list.retainWhere((x) => ids.add(id != null ? id(x) : x as Id));
    return list;
  }
}

class APKPure extends AppSource {
  APKPure() {
    hosts = ['apkpure.net', 'apkpure.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    additionalSourceAppSpecificSettingFormItems = [
      AppSource.fallbackToOlderReleasesFormItem,
      [
        GeneratedFormSwitch(
          'stayOneVersionBehind',
          label: tr('stayOneVersionBehind'),
          defaultValue: false,
        ),
      ],
      [
        GeneratedFormSwitch(
          'useFirstApkOfVersion',
          label: tr('useFirstApkOfVersion'),
          defaultValue: true,
        ),
      ],
    ];
    inferAppIdFromUrlPath = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegExB = RegExp(
      '^https?://m.${getSourceRegex(hosts)}(/+[^/]{2})?/+[^/]+/+[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegExB.firstMatch(url);
    if (match != null) {
      var uri = Uri.parse(url);
      url = 'https://${uri.host.substring(2)}${uri.path}';
    }
    RegExp standardUrlRegExA = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}(/+[^/]{2})?/+[^/]+/+[^/]+',
      caseSensitive: false,
    );
    match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  Future<APKDetails> getDetailsForVersion(
    List<Map<String, dynamic>> versionVariants,
    List<String> supportedArchs,
    Map<String, dynamic> additionalSettings,
  ) async {
    var apkUrls = versionVariants
        .map((e) {
          String? appId = e['package_name']?.toString();
          String? versionCode = e['version_code']?.toString();
          if (appId == null || versionCode == null) {
            return null;
          }

          List<String> architectures =
              e['native_code']?.cast<String>() ?? <String>[];
          String architectureString = architectures.join(',');
          if (architectures.contains("universal") ||
              architectures.contains("unlimited")) {
            architectures = [];
          }
          if (additionalSettings['autoApkFilterByArch'] == true &&
              architectures.isNotEmpty &&
              architectures.where((a) => supportedArchs.contains(a)).isEmpty) {
            return null;
          }

          var asset = e['asset'];
          String? type = asset is Map ? asset['type']?.toString() : null;
          String? downloadUri = asset is Map ? asset['url']?.toString() : null;
          if (type == null || downloadUri == null) {
            return null;
          }

          var archSuffix = architectureString.isNotEmpty ? '-$architectureString' : '';
          return MapEntry(
            '$appId-$versionCode$archSuffix.${type.toLowerCase()}',
            downloadUri,
          );
        })
        .nonNulls
        .toList()
        .unique((e) => e.key);

    if (apkUrls.isEmpty) {
      throw NoAPKError();
    }

    var v = versionVariants.first;
    String? version = v['version_name']?.toString();
    if (version == null || version.isEmpty) {
      throw NoVersionError();
    }
    String author = v['developer']?.toString() ?? name;
    String appName = v['title']?.toString() ?? tr('app');
    DateTime? releaseDate = v['update_date'] != null
        ? DateTime.tryParse(v['update_date'].toString())
        : null;
    String? changeLog = v['whatsnew'];
    if (changeLog != null && changeLog.isEmpty) {
      changeLog = null;
    }

    if (additionalSettings['useFirstApkOfVersion'] == true) {
      apkUrls = [apkUrls.first];
    }

    return APKDetails(
      version,
      apkUrls,
      AppNames(author, appName),
      releaseDate: releaseDate,
      changeLog: changeLog,
    );
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    if (forAPKDownload) {
      return null;
    } else {
      try {
        var androidInfo = await DeviceInfoPlugin().androidInfo;
        return {
          "Ual-Access-Businessid": "projecta",
          "Ual-Access-ProjectA":
              '{"device_info":{"os_ver":"${androidInfo.version.sdkInt}"}}',
        };
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? appId = await tryInferringAppId(standardUrl);
    if (appId == null) {
      throw NoReleasesError();
    }

    List<String> supportedArchs;
    try {
      supportedArchs =
          (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {
      supportedArchs = [];
    }

    var res = await sourceRequest(
      "https://tapi.pureapk.com/v3/get_app_his_version?package_name=$appId&hl=en",
      additionalSettings,
    );
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    List<Map<String, dynamic>> apks;
    try {
      apks = (jsonDecode(res.body)['version_list'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      throw NoReleasesError();
    }

    // group by version
    List<List<Map<String, dynamic>>> versions = apks
        .fold<Map<String, List<Map<String, dynamic>>>>({}, (
          Map<String, List<Map<String, dynamic>>> val,
          Map<String, dynamic> element,
        ) {
          var v = element['version_name'] as String? ?? '';
          if (!val.containsKey(v)) {
            val[v] = [];
          }
          val[v]?.add(element);
          return val;
        })
        .values
        .toList();

    if (versions.isEmpty) {
      throw NoReleasesError();
    }

    for (var i = 0; i < versions.length; i++) {
      var v = versions[i];
      try {
        if (i == 0 && additionalSettings['stayOneVersionBehind'] == true) {
          if (additionalSettings['fallbackToOlderReleases'] != true && versions.length < 2) {
            throw NoReleasesError();
          }
          continue;
        }
        return await getDetailsForVersion(
          v,
          supportedArchs,
          additionalSettings,
        );
      } catch (e) {
        if (additionalSettings['fallbackToOlderReleases'] != true ||
            i == versions.length - 1) {
          rethrow;
        }
      }
    }
    throw NoAPKError();
  }
}
