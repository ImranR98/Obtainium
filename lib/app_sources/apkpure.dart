import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/app_sources/html.dart';
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
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegExB = RegExp(
        '^https?://m.${getSourceRegex(hosts)}/+[^/]+/+[^/]+(/+[^/]+)?',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegExB.firstMatch(url);
    if (match != null) {
      url = 'https://${getSourceRegex(hosts)}${Uri.parse(url).path}';
    }
    RegExp standardUrlRegExA = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}/+[^/]+/+[^/]+(/+[^/]+)?',
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
      'customLinkFilterRegex': '$standardUrl/download/[^/]+\$'
    });

    // if (versionLinks.length > 7) {
    //   // Returns up to 30 which is too much - would take too long and possibly get blocked/rate-limited
    //   versionLinks = versionLinks.sublist(0, 7);
    // }

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
      var res = await sourceRequest(link.key, additionalSettings);
      if (res.statusCode == 200) {
        var html = parse(res.body);
        var apksDiv =
            html.querySelector('#version-list div div.show-more-content');
        DateTime? topReleaseDate;
        var apkUrls = apksDiv
                ?.querySelectorAll('div.group-title')
                .map((e) {
                  String? architecture = e.text.trim();
                  // Only take the first APK for each architecture, ignore others for now, for simplicity
                  // Unclear why there can even be multiple APKs for the same version and arch
                  var apkInfo = e.nextElementSibling?.querySelector('div.info');
                  String? versionCode = RegExp('[0-9]+')
                      .firstMatch(apkInfo
                              ?.querySelector('div.info-top span.code')
                              ?.text ??
                          '')
                      ?.group(0)
                      ?.trim();
                  String? type = apkInfo
                          ?.querySelector('div.info-top span.tag')
                          ?.text
                          .trim() ??
                      'APK';
                  String? dateString = apkInfo
                      ?.querySelector('div.info-bottom span.time')
                      ?.text
                      .trim();
                  DateTime? releaseDate =
                      parseDateTimeMMMddCommayyyy(dateString);
                  if (additionalSettings['autoApkFilterByArch'] == true &&
                      !supportedArchs.contains(architecture)) {
                    return const MapEntry('', '');
                  }
                  topReleaseDate ??=
                      releaseDate; // Just use the release date of the first APK in the list as the release date for this version
                  return MapEntry(
                      '$appId-$versionCode-$architecture.${type.toLowerCase()}',
                      'https://d.${hosts.contains(host) ? 'cdnpure.com' : host}/b/$type/$appId?versionCode=$versionCode');
                })
                .where((e) => e.key.isNotEmpty)
                .toList() ??
            [];
        if (apkUrls.isEmpty) {
          continue;
        }
        String version = Uri.parse(link.key).pathSegments.last;
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
    throw NoAPKError();
  }
}
