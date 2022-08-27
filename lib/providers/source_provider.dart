// Defines App sources and provides functions used to interact with them
// AppSource is an abstract class with a concrete implementation for each source

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:http/http.dart';
import 'package:html/parser.dart';

class AppNames {
  late String author;
  late String name;

  AppNames(this.author, this.name);
}

class APKDetails {
  late String version;
  late List<String> apkUrls;

  APKDetails(this.version, this.apkUrls);
}

class App {
  late String id;
  late String url;
  late String author;
  late String name;
  String? installedVersion;
  late String latestVersion;
  List<String> apkUrls = [];
  App(this.id, this.url, this.author, this.name, this.installedVersion,
      this.latestVersion, this.apkUrls);

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls';
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
      List<String>.from(jsonDecode(json['apkUrls'])));

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'author': author,
        'name': name,
        'installedVersion': installedVersion,
        'latestVersion': latestVersion,
        'apkUrls': jsonEncode(apkUrls),
      };
}

escapeRegEx(String s) {
  return s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
    return "\\${x[0]}";
  });
}

List<String> getLinksFromParsedHTML(
        Document dom, RegExp hrefPattern, String prependToLinks) =>
    dom
        .querySelectorAll('a')
        .where((element) {
          if (element.attributes['href'] == null) return false;
          return hrefPattern.hasMatch(element.attributes['href']!);
        })
        .map((e) => '$prependToLinks${e.attributes['href']!}')
        .toList();

abstract class AppSource {
  late String sourceId;
  String standardizeURL(String url);
  Future<APKDetails> getLatestAPKDetails(String standardUrl);
  AppNames getAppNames(String standardUrl);
}

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

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    // The GitHub RSS feed does not contain asset download details, so we use web scraping (avoid API due to rate limits)
    Response res = await get(Uri.parse('$standardUrl/releases/latest'));
    if (res.statusCode == 200) {
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      var apkUrlList = getLinksFromParsedHTML(
          parsedHtml,
          RegExp(
              '^${escapeRegEx(standardUri.path)}/releases/download/[^/]+/[^/]+\\.apk\$',
              caseSensitive: false),
          standardUri.origin);
      if (apkUrlList.isEmpty) {
        throw 'No APK found';
      }
      String getTag(String url) {
        List<String> parts = url.split('/');
        return parts[parts.length - 2];
      }

      String latestTag = getTag(apkUrlList[0]);
      String? version = parsedHtml
          .querySelector('.octicon-tag')
          ?.nextElementSibling
          ?.innerHtml
          .trim();
      if (version == null) {
        throw 'Could not determine latest release version';
      }
      return APKDetails(version,
          apkUrlList.where((element) => getTag(element) == latestTag).toList());
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

class GitLab implements AppSource {
  @override
  String sourceId = 'gitlab';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp(r'^https?://gitlab.com/[^/]*/[^/]*');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw 'Not a valid URL';
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    // GitLab provides an RSS feed with all the details we need
    Response res = await get(Uri.parse('$standardUrl/-/tags?format=atom'));
    if (res.statusCode == 200) {
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      var entry = parsedHtml.querySelector('entry');
      var entryContent =
          parse(parseFragment(entry!.querySelector('content')!.innerHtml).text);
      var apkUrlList = getLinksFromParsedHTML(
          entryContent,
          RegExp(
              '^${escapeRegEx(standardUri.path)}/uploads/[^/]+/[^/]+\\.apk\$',
              caseSensitive: false),
          standardUri.origin);
      if (apkUrlList.isEmpty) {
        throw 'No APK found';
      }

      var entryId = entry.querySelector('id')?.innerHtml;
      var version =
          entryId == null ? null : Uri.parse(entryId).pathSegments.last;
      if (version == null) {
        throw 'Could not determine latest release version';
      }
      return APKDetails(version, apkUrlList);
    } else {
      throw 'Unable to fetch release info';
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    // Same as GitHub
    return GitHub().getAppNames(standardUrl);
  }
}

class SourceProvider {
  // Add more source classes here so they are available via the service
  AppSource getSource(String url) {
    if (url.toLowerCase().contains('://github.com')) {
      return GitHub();
    } else if (url.toLowerCase().contains('://gitlab.com')) {
      return GitLab();
    }
    throw 'URL does not match a known source';
  }

  Future<App> getApp(String url) async {
    if (url.toLowerCase().indexOf('http://') != 0 &&
        url.toLowerCase().indexOf('https://') != 0) {
      url = 'https://$url';
    }
    if (url.toLowerCase().indexOf('https://www.') == 0) {
      url = 'https://${url.substring(12)}';
    }
    AppSource source = getSource(url);
    String standardUrl = source.standardizeURL(url);
    AppNames names = source.getAppNames(standardUrl);
    APKDetails apk = await source.getLatestAPKDetails(standardUrl);
    return App(
        '${names.author.toLowerCase()}_${names.name.toLowerCase()}_${source.sourceId}',
        standardUrl,
        names.author[0].toUpperCase() + names.author.substring(1),
        names.name[0].toUpperCase() + names.name.substring(1),
        null,
        apk.version,
        apk.apkUrls);
  }

  List<String> getSourceHosts() => ['github.com', 'gitlab.com'];
}
