import 'package:obtainium/app_sources/fdroid.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class IzzyOnDroid extends AppSource {
  final FDroid fd = FDroid();

  IzzyOnDroid() {
    name = 'IzzyOnDroid';
    hosts = ['izzysoft.de'];
    allowSubDomains = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems =>
      fd.additionalSourceAppSpecificSettingFormItems;

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final host = Uri.parse(url).host;
    if (host.startsWith('android.')) {
      return standardizeUrlWithRegex(
        url,
        subdomainPrefix: r'android\.',
        pathPattern: r'/repo/apk/[^/]+',
      );
    }
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'apt\.',
      pathPattern: r'/fdroid/index/apk/[^/]+',
    );
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
    try {
      final String? appId = await tryInferringAppId(standardUrl);
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
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
