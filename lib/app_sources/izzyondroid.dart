import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class IzzyOnDroid extends AppSource {
  late FDroid fd;

  IzzyOnDroid() {
    name = 'IzzyOnDroid';
    hosts = ['izzysoft.de'];
    fd = FDroid();
    additionalSourceAppSpecificSettingFormItems =
        fd.additionalSourceAppSpecificSettingFormItems;
    allowSubDomains = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    try {
      return standardizeUrlWithRegex(
        url,
        subdomainPrefix: r'android\.',
        pathPattern: r'/repo/apk/[^/]+',
      );
    } catch (_) {
      return standardizeUrlWithRegex(
        url,
        subdomainPrefix: r'apt\.',
        pathPattern: r'/fdroid/index/apk/[^/]+',
      );
    }
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return fd.tryInferringAppId(standardUrl);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? appId = await tryInferringAppId(standardUrl);
    if (appId == null) {
      throw NoReleasesError();
    }
    return fd.getAPKUrlsFromFDroidPackagesAPIResponse(
      await sourceRequest(
        'https://apt.izzysoft.de/fdroid/api/v1/packages/$appId',
        additionalSettings,
      ),
      'https://android.izzysoft.de/frepo/$appId',
      standardUrl,
      name,
      additionalSettings: additionalSettings,
    );
  }
}
