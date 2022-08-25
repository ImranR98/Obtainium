// Exposes functions related to interacting with App sources and retrieving App info
// Stateless - not a provider

import 'package:http/http.dart';
import 'package:html/parser.dart';

// Sub-classes used in App Source

class AppNames {
  late String author;
  late String name;

  AppNames(this.author, this.name);
}

class APKDetails {
  late String version;
  late String downloadUrl;

  APKDetails(this.version, this.downloadUrl);
}

// App Source abstract class (diff. implementations for GitHub, GitLab, etc.)

abstract class AppSource {
  late String sourceId;
  String standardizeURL(String url);
  Future<APKDetails> getLatestAPKDetails(String standardUrl);
  AppNames getAppNames(String standardUrl);
}

escapeRegEx(String s) {
  return s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
    return "\\${x[0]}";
  });
}

// App class

class App {
  late String id;
  late String url;
  late String author;
  late String name;
  String? installedVersion;
  late String latestVersion;
  late String apkUrl;
  App(this.id, this.url, this.author, this.name, this.installedVersion,
      this.latestVersion, this.apkUrl);

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrl';
  }

  factory App.fromJson(Map<String, dynamic> json) => App(
      json['id'] as String,
      json['url'] as String,
      json['author'] as String,
      json['name'] as String,
      json['installedVersion'] == null
          ? null
          : json['installedVersion'] as String,
      json['latestVersion'] as String,
      json['apkUrl'] as String);

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'author': author,
        'name': name,
        'installedVersion': installedVersion,
        'latestVersion': latestVersion,
        'apkUrl': apkUrl,
      };
}

// Specific App Source classes

class GitHub implements AppSource {
  @override
  String sourceId = 'github';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp(r'^https?://github.com/[^/]*/[^/]*');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw 'Not a valid URL';
    }
    return url.substring(0, match.end);
  }

  String convertURL(String url, String replaceText) {
    int tempInd1 = url.indexOf('://') + 3;
    int tempInd2 = url.substring(tempInd1).indexOf('/') + tempInd1;
    return '${url.substring(0, tempInd1)}$replaceText${url.substring(tempInd2)}';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    Response res = await get(Uri.parse('$standardUrl/releases/latest'));
    if (res.statusCode == 200) {
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      var apkUrlList = parsedHtml.querySelectorAll('a').where((element) {
        return RegExp(
                '^${escapeRegEx(standardUri.path)}/releases/download/*/(?!/).*.apk\$',
                caseSensitive: false)
            .hasMatch(element.attributes['href']!);
      }).toList();
      String? version = parsedHtml
          .querySelector('.octicon-tag')
          ?.nextElementSibling
          ?.innerHtml
          .trim();
      if (apkUrlList.isEmpty || version == null) {
        throw 'No APK found';
      }
      return APKDetails(
          version, '${standardUri.origin}${apkUrlList[0].attributes['href']!}');
    } else {
      throw 'Unable to fetch release info';
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }
}

class SourceService {
  // Add more source classes here so they are available via the service
  AppSource github = GitHub();
  AppSource getSource(String url) {
    if (url.toLowerCase().contains('://github.com')) {
      return github;
    }
    throw 'URL does not match a known source';
  }

  Future<App> getApp(String url) async {
    if (url.toLowerCase().indexOf('http://') != 0 &&
        url.toLowerCase().indexOf('https://') != 0) {
      url = 'https://$url';
    }
    AppSource source = getSource(url);
    String standardUrl = source.standardizeURL(url);
    AppNames names = source.getAppNames(standardUrl);
    APKDetails apk = await source.getLatestAPKDetails(standardUrl);
    return App(
        '${names.author}_${names.name}_${source.sourceId}',
        standardUrl,
        names.author[0].toUpperCase() + names.author.substring(1),
        names.name[0].toUpperCase() + names.name.substring(1),
        null,
        apk.version,
        apk.downloadUrl);
  }
}
