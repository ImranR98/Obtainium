import 'dart:convert';
import 'package:http/http.dart';
import 'package:markdown/markdown.dart';
import 'package:html/parser.dart';

// Sub-classes of App Source

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

// App Source abstract class (GitHub, GitLab, etc.)

abstract class AppSource {
  late RegExp standardURLRegEx;
  Future<APKDetails?> getLatestAPKUrl(String url);
  Future<String?> getReadMeHTML(String url);
  Future<String?> getBase64IconURLFromHTML(String url, String html);

  AppSource(this.standardURLRegEx);
}

// Specific App Source definitions

class GitHub extends AppSource {
  GitHub() : super(RegExp(r"^https?://github.com/[^/]*/[^/]*"));

  String getRawContentURL(String url) {
    int tempInd1 = url.indexOf('://') + 3;
    int tempInd2 = url.indexOf('://') + 13;
    return "${url.substring(0, tempInd1)}raw.githubusercontent.com${url.substring(tempInd2)}";
  }

  @override
  Future<APKDetails?> getLatestAPKUrl(String url) async {
    int tempInd = url.indexOf('://') + 3;
    Response res = await get(Uri.parse(
        "${url.substring(0, tempInd)}api.${url.substring(tempInd)}/releases/latest"));
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
  Future<String?> getReadMeHTML(String url) async {
    String uri = getRawContentURL(url);
    List<String> possibleSuffixes = ["main/README.md", "master/README.md"];
    for (var i = 0; i < possibleSuffixes.length; i++) {
      Response res = await get(Uri.parse("$uri/${possibleSuffixes[i]}"));
      if (res.statusCode == 200) {
        return markdownToHtml(res.body);
      }
    }
    return null;
  }

  @override
  Future<String?> getBase64IconURLFromHTML(String url, String html) async {
    var icon = parse(html).getElementsByClassName("img")?[0];
    if (icon != null) {
      String uri = getRawContentURL(url);
      List<String> possibleBranches = ["main", "master"];
      for (var i = 0; i < possibleBranches.length; i++) {
        var imgUrl = "$uri/${possibleBranches[i]}/${icon.attributes['src']}";
        Response res = await get(Uri.parse(imgUrl));
        if (res.statusCode == 200) {
          return imgUrl;
        }
      }
    }
    return null;
  }
}

class SourceService {
  String standardizeURL(String url, RegExp standardURLRegEx) {
    var match = standardURLRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw "Not a valid URL";
    }
    return url.substring(0, match.end);
  }

  AppNames getAppNames(String standardURL) {
    String temp = standardURL.substring(standardURL.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/')).split('/');
    return AppNames(names[0], names[1]);
  }

  // Add more source classes here so they are available via the service
  var github = GitHub();
  AppSource getSource(String url) {
    if (url.toLowerCase().contains('://github.com')) {
      return github;
    }
    throw "URL does not match a known source";
  }
}

/*
- Make a function that validates and standardizes github URLs, do the same for gitlab (fail = error)
- Make a function that gets the App title and Author name from a github URL, do the same for gitlab (can't fail)
- Make a function that takes a github URL and finds the latest APK release if any (with version), do the same for gitlab (fail = error)
- Make a function that takes a github URL and returns a README HTML if any, do the same for gitlab (fail = "no description")
- Make a function that looks for the first image in a README HTML and returns its url (fail = no icon)

- Make a function that integrates all above and returns an App object for a given github URL, do the same for gitlab

- Make a function that detects the URL (Github or Gitlab) and runs the right function above

- Make a function that can save/load an App object to/from persistent storage (JSON file with unique App ID as file name)

- Make a function (using the above fn) that loads an array of all Apps
*/