import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/providers/source_provider.dart';

class APKMirror implements AppSource {
  @override
  late String host = 'apkmirror.com';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/apk/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw notValidURL(runtimeType.toString());
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl#whatsnew';

  @override
  Future<String> apkUrlPrefetchModifier(String apkUrl) async {
    var originalUri = Uri.parse(apkUrl);
    var res = await get(originalUri);
    if (res.statusCode != 200) {
      throw false;
    }
    var href =
        parse(res.body).querySelector('.downloadButton')?.attributes['href'];
    if (href == null) {
      throw false;
    }
    var res2 = await get(Uri.parse('${originalUri.origin}$href'), headers: {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64; rv:105.0) Gecko/20100101 Firefox/105.0'
    });
    if (res2.statusCode != 200) {
      throw false;
    }
    var links = parse(res2.body)
        .querySelectorAll('a')
        .where((element) => element.innerHtml == 'here')
        .map((e) => e.attributes['href'])
        .where((element) => element != null)
        .toList();
    if (links.isEmpty) {
      throw false;
    }
    return '${originalUri.origin}${links[0]}';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData) async {
    Response res = await get(Uri.parse('$standardUrl/feed'));
    if (res.statusCode != 200) {
      throw couldNotFindReleases;
    }
    var nextUrl = parse(res.body)
        .querySelector('item')
        ?.querySelector('link')
        ?.nextElementSibling
        ?.innerHtml;
    if (nextUrl == null) {
      throw couldNotFindReleases;
    }
    Response res2 = await get(Uri.parse(nextUrl), headers: {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64; rv:105.0) Gecko/20100101 Firefox/105.0'
    });
    if (res2.statusCode != 200) {
      throw couldNotFindReleases;
    }
    var html2 = parse(res2.body);
    var origin = Uri.parse(standardUrl).origin;
    List<String> apkUrls = html2
        .querySelectorAll('.apkm-badge')
        .map((e) => e.innerHtml != 'APK'
            ? ''
            : e.previousElementSibling?.attributes['href'] ?? '')
        .where((element) => element.isNotEmpty)
        .map((e) => '$origin$e')
        .toList();
    if (apkUrls.isEmpty) {
      throw noAPKFound;
    }
    var version = html2.querySelector('span.active.accent_color')?.innerHtml;
    if (version == null) {
      throw couldNotFindLatestVersion;
    }
    return APKDetails(version, apkUrls);
  }

  @override
  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[1], names[2]);
  }

  @override
  List<List<GeneratedFormItem>> additionalDataFormItems = [];

  @override
  List<String> additionalDataDefaults = [];

  @override
  List<GeneratedFormItem> moreSourceSettingsFormItems = [];
}
