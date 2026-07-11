import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

class Farsroid extends AppSource {
  Farsroid() {
    hosts = ['farsroid.com'];
    name = 'Farsroid';
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [
      GeneratedFormSwitch(
        'useFirstApkOfVersion',
        label: tr('useFirstApkOfVersion'),
        value: true,
      ),
    ],
    [
      GeneratedFormSwitch(
        'releaseTitleAsVersion',
        label: tr('releaseTitleAsVersion'),
        value: false,
      ),
    ],
  ];

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return standardizeUrlWithRegex(
      url,
      subdomainPrefix: r'([^\.]+\.)',
      pathPattern: r'/[^/]+',
    );
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final String appName = Uri.parse(standardUrl).pathSegments.last;

      final res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }
      final html = parse(res.body);
      final dlinks = html.querySelectorAll('.download-links');
      if (dlinks.isEmpty) {
        throw NoReleasesError();
      }
      final postId = dlinks.first.attributes['data-post-id'] ?? '';
      var version = dlinks.first.attributes['data-post-version'] ?? '';

      if (postId.isEmpty || version.isEmpty) {
        throw NoVersionError();
      }

      final res2 = await sourceRequest(
        'https://${hosts[0]}/api/download-box/?post_id=$postId&post_version=$version',
        additionalSettings,
      );
      if (res2.statusCode != 200) {
        throw getObtainiumHttpError(res2);
      }
      Map<String, dynamic>? farsroidJson;
      try {
        farsroidJson = jsonDecode(res2.body) as Map<String, dynamic>?;
      } catch (e) {
        unawaited(
          LogsProvider().add(
            'Failed to decode Farsroid JSON: $e',
            level: LogLevel.error,
          ),
        );
        throw NoAPKError();
      }
      final html2 = farsroidJson?['data']?['content'] as String? ?? '';
      if (html2.isEmpty) {
        throw NoAPKError();
      }
      final requestUrl = res2.request?.url;
      if (requestUrl == null) throw NoAPKError();
      var apkLinks =
          (await grabLinksCommon(html2, requestUrl, {
                ...additionalSettings,
                'skipSort': true,
              }))
              .map((l) => MapEntry(Uri.parse(l.key).pathSegments.last, l.key))
              .toList();

      apkLinks = filterApks(
        apkLinks,
        additionalSettings['apkFilterRegEx'],
        additionalSettings['invertAPKFilter'],
      );
      if (apkLinks.isEmpty) {
        throw NoAPKError();
      }
      if (additionalSettings['autoApkFilterByArch'] == true) {
        apkLinks = await filterApksByArch(apkLinks);
      }
      if (additionalSettings['useFirstApkOfVersion'] == true) {
        apkLinks = [apkLinks.first];
      }

      if (additionalSettings['releaseTitleAsVersion'] == true) {
        if (apkLinks.length != 1) {
          throw NoVersionError();
        }
        version = apkLinks.single.key;
      }

      return APKDetails(version, apkLinks, AppNames(name, appName));
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
