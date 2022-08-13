import 'dart:convert';
import 'package:http/http.dart';

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
  String standardizeURL(String url);
  Future<APKDetails> getLatestAPKUrl(String standardUrl);
  AppNames getAppNames(String standardUrl);
}

// Specific App Source classes

class GitHub implements AppSource {
  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp(r"^https?://github.com/[^/]*/[^/]*");
    var match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw "Not a valid URL";
    }
    return url.substring(0, match.end);
  }

  String convertURLToRawContentURL(String url) {
    int tempInd1 = url.indexOf('://') + 3;
    int tempInd2 = url.substring(tempInd1).indexOf('/') + tempInd1;
    return "${url.substring(0, tempInd1)}raw.githubusercontent.com${url.substring(tempInd2)}";
  }

  @override
  Future<APKDetails> getLatestAPKUrl(String standardUrl) async {
    int tempInd = standardUrl.indexOf('://') + 3;
    Response res = await get(Uri.parse(
        "${standardUrl.substring(0, tempInd)}api.${standardUrl.substring(tempInd)}/releases/latest"));
    if (res.statusCode == 200) {
      var release = jsonDecode(res.body);
      for (var i = 0; i < release['assets'].length; i++) {
        if (release['assets'][i]
            .name
            .toString()
            .toLowerCase()
            .endsWith(".apk")) {
          return APKDetails(release['tag_name'],
              release['assets'][i]['browser_download_url']);
        }
      }
      throw "No APK found";
    } else {
      throw "Unable to fetch release info";
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/')).split('/');
    return AppNames(names[0], names[1]);
  }
}

class SourceService {
  // Add more source classes here so they are available via the service
  var github = GitHub();
  AppSource getSource(String url) {
    if (url.toLowerCase().contains('://github.com')) {
      return github;
    }
    throw "URL does not match a known source";
  }
}
