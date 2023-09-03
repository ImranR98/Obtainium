import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class IzzyOnDroid extends AppSource {
  late FDroid fd;

  IzzyOnDroid() {
    host = 'android.izzysoft.de';
    fd = FDroid();
    additionalSourceAppSpecificSettingFormItems =
        fd.additionalSourceAppSpecificSettingFormItems;
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/repo/apk/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw InvalidURLError(name);
    }
    return url.substring(0, match.end);
  }

  @override
  Future<String?> tryInferringAppId(String standardUrl,
      {Map<String, dynamic> additionalSettings = const {}}) async {
    return fd.tryInferringAppId(standardUrl);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? appId = await tryInferringAppId(standardUrl);
    return fd.getAPKUrlsFromFDroidPackagesAPIResponse(
        await sourceRequest(
            'https://apt.izzysoft.de/fdroid/api/v1/packages/$appId'),
        'https://android.izzysoft.de/frepo/$appId',
        standardUrl,
        autoSelectHighestVersionCode:
            additionalSettings['autoSelectHighestVersionCode'] == true);
  }
}
