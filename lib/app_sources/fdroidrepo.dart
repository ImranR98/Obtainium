import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class FDroidRepo extends AppSource {
  FDroidRepo() {
    name = tr('fdroidThirdPartyRepo');
    overrideEligible = true;

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormTextField('appIdOrName',
            label: tr('appIdOrName'),
            hint: tr('reposHaveMultipleApps'),
            required: true)
      ]
    ];
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    String? appIdOrName = additionalSettings['appIdOrName'];
    if (appIdOrName == null) {
      throw NoReleasesError();
    }
    var res = await sourceRequest('$standardUrl/index.xml');
    if (res.statusCode == 200) {
      var body = parse(res.body);
      var foundApps = body.querySelectorAll('application').where((element) {
        return element.attributes['id'] == appIdOrName;
      }).toList();
      if (foundApps.isEmpty) {
        foundApps = body.querySelectorAll('application').where((element) {
          return element.querySelector('name')?.innerHtml.toLowerCase() ==
              appIdOrName.toLowerCase();
        }).toList();
      }
      if (foundApps.isEmpty) {
        foundApps = body.querySelectorAll('application').where((element) {
          return element
                  .querySelector('name')
                  ?.innerHtml
                  .toLowerCase()
                  .contains(appIdOrName.toLowerCase()) ??
              false;
        }).toList();
      }
      if (foundApps.isEmpty) {
        throw ObtainiumError(tr('appWithIdOrNameNotFound'));
      }
      var authorName = body.querySelector('repo')?.attributes['name'] ?? name;
      var appName =
          foundApps[0].querySelector('name')?.innerHtml ?? appIdOrName;
      var releases = foundApps[0].querySelectorAll('package');
      String? latestVersion = releases[0].querySelector('version')?.innerHtml;
      String? added = releases[0].querySelector('added')?.innerHtml;
      DateTime? releaseDate = added != null ? DateTime.parse(added) : null;
      if (latestVersion == null) {
        throw NoVersionError();
      }
      List<String> apkUrls = releases
          .where((element) =>
              element.querySelector('version')?.innerHtml == latestVersion &&
              element.querySelector('apkname') != null)
          .map((e) => '$standardUrl/${e.querySelector('apkname')!.innerHtml}')
          .toList();
      return APKDetails(latestVersion, getApkUrlsFromUrls(apkUrls),
          AppNames(authorName, appName),
          releaseDate: releaseDate);
    } else {
      throw getObtainiumHttpError(res);
    }
  }
}
