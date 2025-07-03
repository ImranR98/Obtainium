import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class IzzyOnDroid extends AppSource {
  late FDroid fd;

  IzzyOnDroid() {
    hosts = ['izzysoft.de'];
    fd = FDroid();
    additionalSourceAppSpecificSettingFormItems =
        fd.additionalSourceAppSpecificSettingFormItems;
    allowSubDomains = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegExA = RegExp(
      '^https?://android.${getSourceRegex(hosts)}/repo/apk/[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      RegExp standardUrlRegExB = RegExp(
        '^https?://apt.${getSourceRegex(hosts)}/fdroid/index/apk/[^/]+',
        caseSensitive: false,
      );
      match = standardUrlRegExB.firstMatch(url);
    }
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
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
