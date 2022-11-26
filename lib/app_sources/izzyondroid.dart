import 'package:http/http.dart';
import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class IzzyOnDroid extends AppSource {
  IzzyOnDroid() {
    host = 'android.izzysoft.de';
  }

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/repo/apk/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(runtimeType.toString());
    }
    return url.substring(0, match.end);
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) => null;

  @override
  String? tryInferringAppId(String standardUrl) {
    return FDroid().tryInferringAppId(standardUrl);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
      String standardUrl, List<String> additionalData,
      {bool trackOnly = false}) async {
    String? appId = tryInferringAppId(standardUrl);
    return FDroid().getAPKUrlsFromFDroidPackagesAPIResponse(
        await get(
            Uri.parse('https://apt.izzysoft.de/fdroid/api/v1/packages/$appId')),
        'https://android.izzysoft.de/frepo/$appId');
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames('IzzyOnDroid', Uri.parse(standardUrl).pathSegments.last);
  }
}
