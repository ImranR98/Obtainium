import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Aptoide extends AppSource {
  Aptoide() {
    host = 'aptoide.com';
    name = tr('Aptoide');
    allowSubDomains = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://([^\\.]+\\.){2,}$host');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    return (await getLatestAPKDetails(standardUrl, additionalSettings)).version;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(standardUrl);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var idMatch = RegExp('"app":{"id":[0-9]+').firstMatch(res.body);
    String? id;
    if (idMatch != null) {
      id = res.body.substring(idMatch.start + 12, idMatch.end);
    } else {
      throw NoReleasesError();
    }
    var res2 =
        await sourceRequest('https://ws2.aptoide.com/api/7/getApp/app_id/$id');
    if (res2.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var appDetails = jsonDecode(res2.body)?['nodes']?['meta']?['data'];
    String appName = appDetails?['name'] ?? tr('app');
    String author = appDetails?['developer']?['name'] ?? name;
    String? dateStr = appDetails?['updated'];
    String? version = appDetails?['file']?['vername'];
    String? apkUrl = appDetails?['file']?['path'];
    if (version == null) {
      throw NoVersionError();
    }
    if (apkUrl == null) {
      throw NoAPKError();
    }
    DateTime? relDate;
    if (dateStr != null) {
      relDate = DateTime.parse(dateStr);
    }

    return APKDetails(
        version, getApkUrlsFromUrls([apkUrl]), AppNames(author, appName),
        releaseDate: relDate);
  }

  @override
  Future<Map<String, List<String>>> search(String query,
      {Map<String, dynamic> querySettings = const {}}) async {
    Response res = await sourceRequest(
        'https://search.$host/?q=${Uri.encodeQueryComponent(query)}');
    if (res.statusCode == 200) {
      Map<String, List<String>> urlsWithDescriptions = {};
      parse(res.body).querySelectorAll('.package-header').forEach((e) {
        String? url = e.attributes['href'];
        if (url != null) {
          try {
            standardizeUrl(url);
          } catch (e) {
            url = null;
          }
        }
        if (url != null) {
          urlsWithDescriptions[url] = [
            e.querySelector('.package-name')?.text.trim() ?? '',
            e.querySelector('.package-summary')?.text.trim() ??
                tr('noDescription')
          ];
        }
      });
      return urlsWithDescriptions;
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
