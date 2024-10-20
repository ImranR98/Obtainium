import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

parseDateTimeMMMddCommayyyy(String? dateString) {
  DateTime? releaseDate;
  try {
    releaseDate = dateString != null
        ? DateFormat('MMM dd, yyyy').parse(dateString)
        : null;
    releaseDate = dateString != null && releaseDate == null
        ? DateFormat('MMMM dd, yyyy').parse(dateString)
        : releaseDate;
  } catch (err) {
    // ignore
  }
  return releaseDate;
}

class APKPure extends AppSource {
  APKPure() {
    hosts = ['apkpure.net', 'apkpure.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'), defaultValue: true)
      ],
      [
        GeneratedFormSwitch('stayOneVersionBehind',
            label: tr('stayOneVersionBehind'), defaultValue: false)
      ]
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegExB = RegExp(
        '^https?://m.${getSourceRegex(hosts)}(/+[^/]{2})?/+[^/]+/+[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegExB.firstMatch(url);
    if (match != null) {
      var uri = Uri.parse(url);
      url = 'https://${uri.host.substring(2)}${uri.path}';
    }
    RegExp standardUrlRegExA = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}(/+[^/]{2})?/+[^/]+/+[^/]+',
        caseSensitive: false);
    match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    return Uri.parse(standardUrl).pathSegments.last;
  }

  getDetailsForVersionLink(
      String standardUrl,
      String appId,
      String host,
      List<String> supportedArchs,
      String link,
      Map<String, dynamic> additionalSettings) async {
    var res = await sourceRequest(link, additionalSettings);
    if (res.statusCode == 200) {
      var html = parse(res.body);
      var apksDiv =
          html.querySelector('#version-list div div.show-more-content');
      DateTime? topReleaseDate;
      var apkUrls = apksDiv
              ?.querySelectorAll('div.group-title')
              .map((e) {
                String architectureString = e.text.trim();
                if (architectureString.toLowerCase() == 'unlimited' ||
                    architectureString.toLowerCase() == 'universal') {
                  architectureString = '';
                }
                List<String> architectures = architectureString
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                // Only take the first APK for each architecture, ignore others for now, for simplicity
                // Unclear why there can even be multiple APKs for the same version and arch
                var apkInfo = e.nextElementSibling?.querySelector('div.info');
                String? versionCode = RegExp('[0-9]+')
                    .firstMatch(
                        apkInfo?.querySelector('div.info-top .code')?.text ??
                            '')
                    ?.group(0)
                    ?.trim();
                var types = apkInfo
                        ?.querySelectorAll('div.info-top span.tag')
                        .map((e) => e.text.trim())
                        .map((t) => t == 'APKs' ? 'APK' : t) ??
                    [];
                String type = types.isEmpty
                    ? 'APK'
                    : types.length == 1
                        ? types.first
                        : types.last;
                String? dateString = apkInfo
                    ?.querySelector('div.info-bottom span.time')
                    ?.text
                    .trim();
                DateTime? releaseDate = parseDateTimeMMMddCommayyyy(dateString);
                if (additionalSettings['autoApkFilterByArch'] == true &&
                    architectures.isNotEmpty &&
                    architectures
                        .where((a) => supportedArchs.contains(a))
                        .isEmpty) {
                  return const MapEntry('', '');
                }
                topReleaseDate ??=
                    releaseDate; // Just use the release date of the first APK in the list as the release date for this version
                return MapEntry(
                    '$appId-$versionCode-$architectureString.${type.toLowerCase()}',
                    'https://d.${hosts.contains(host) ? 'cdnpure.com' : host}/b/$type/$appId?versionCode=$versionCode');
              })
              .where((e) => e.key.isNotEmpty)
              .toList() ??
          [];
      if (apkUrls.isEmpty) {
        throw NoAPKError();
      }
      String version = Uri.parse(link).pathSegments.last;
      String author = html
              .querySelector('span.info-sdk')
              ?.text
              .trim()
              .substring(version.length + 4) ??
          Uri.parse(standardUrl).pathSegments.reversed.last;
      String appName =
          html.querySelector('h1.info-title')?.text.trim() ?? appId;
      String? changeLog = html
          .querySelector('div.module.change-log')
          ?.innerHtml
          .trim()
          .replaceAll("<br>", "  \n");
      return APKDetails(version, apkUrls, AppNames(author, appName),
          releaseDate: topReleaseDate, changeLog: changeLog);
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String appId = (await tryInferringAppId(standardUrl))!;
    String host = Uri.parse(standardUrl).host;

    var res0 = await sourceRequest('$standardUrl/versions', additionalSettings);
    var versionLinks = await grabLinksCommon(res0, {
      'skipSort': true,
      'customLinkFilterRegex': '${Uri.decodeFull(standardUrl)}/download/[^/]+\$'
    });

    var supportedArchs = (await DeviceInfoPlugin().androidInfo).supportedAbis;

    if (additionalSettings['autoApkFilterByArch'] != true) {
      // No need to request multiple versions when we're not going to filter them (always pick the top one)
      versionLinks = versionLinks.sublist(0, 1);
    }
    if (versionLinks.isEmpty) {
      throw NoReleasesError();
    }

    for (var i = 0; i < versionLinks.length; i++) {
      var link = versionLinks[i];
      try {
        if (i == 0 && additionalSettings['stayOneVersionBehind'] == true) {
          throw NoReleasesError();
        }
        return await getDetailsForVersionLink(standardUrl, appId, host,
            supportedArchs, link.key, additionalSettings);
      } catch (e) {
        if (additionalSettings['fallbackToOlderReleases'] != true ||
            i == versionLinks.length - 1) {
          rethrow;
        }
      }
    }
    throw NoAPKError();
  }
}
