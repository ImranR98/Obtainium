import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class HTML extends AppSource {
  @override
  String standardizeURL(String url) {
    return url;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var uri = Uri.parse(standardUrl);
    Response res = await get(uri);
    if (res.statusCode == 200) {
      List<String> links = parse(res.body)
          .querySelectorAll('a')
          .map((element) => element.attributes['href'] ?? '')
          .where((element) => element.toLowerCase().endsWith('.apk'))
          .toList();
      links.sort((a, b) => a.split('/').last.compareTo(b.split('/').last));
      if (additionalSettings['apkFilterRegEx'] != null) {
        var reg = RegExp(additionalSettings['apkFilterRegEx']);
        links = links.where((element) => reg.hasMatch(element)).toList();
      }
      if (links.isEmpty) {
        throw NoReleasesError();
      }
      var rel = links.last;
      var apkName = rel.split('/').last;
      var version = apkName.substring(0, apkName.length - 4);
      List<String> apkUrls = [rel].map((e) {
        try {
          Uri.parse(e).origin;
          return e;
        } catch (err) {
          // is relative
        }
        var currPathSegments = uri.path.split('/');
        if (e.startsWith('/') || currPathSegments.isEmpty) {
          return '${uri.origin}/$e';
        } else {
          return '${uri.origin}/${currPathSegments.sublist(0, currPathSegments.length - 1).join('/')}/$e';
        }
      }).toList();
      return APKDetails(
          version, getApkUrlsFromUrls(apkUrls), AppNames(uri.host, tr('app')));
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
