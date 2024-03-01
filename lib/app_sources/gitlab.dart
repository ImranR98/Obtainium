import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// This class is designed as an interface to define a .apk retrieval method
abstract class RetrievalStrategy {
  Future<Iterable<APKDetails>> retrieve();
}

/// This class is defined to retrieve .apk-details from gitlab API
class GitlabApiStrategy extends RetrievalStrategy {

  // Source context
  AppSource source;

  // Specific source parameters
  String standardUrl;
  Map<String, dynamic> additionalSettings;

  // Specific strategy parameters
  String privateAccessToken;

  /// Constructor with mandatory parameters
  GitlabApiStrategy(this.source, this.standardUrl, this.additionalSettings, this.privateAccessToken);

  /// Retrieves an iterable list of ApkDetails
  @override
  Future<Iterable<APKDetails>> retrieve() async {

    // Extract names from URL
    var names = GitHub().getAppNames(standardUrl);

    // Request "releases" data from API
    Response res = await source.sourceRequest(
        'https://${source.hosts[0]}/api/v4/projects/${names.author}%2F${names.name}/releases?private_token=$privateAccessToken',
        additionalSettings);

    // Check for HTTP errors
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }

    // Parse HTTP response data in JSON format
    var json = jsonDecode(res.body) as List<dynamic>;

    // Extract .apk-Details from received JSON data
    return json.map((e) {

      // ...search in related asset files
      var apkUrlsFromAssets = (e['assets']?['links'] as List<dynamic>? ?? [])
          .map((e) {
            return (e['direct_asset_url'] ?? e['url'] ?? '') as String;
          })
          .where((s) => s.isNotEmpty)
          .toList();

      // ...search in related description text
      List<String> uploadedAPKsFromDescription =
          ((e['description'] ?? '') as String)
              .split('](')
              .join('\n')
              .split('.apk)')
              .join('.apk\n')
              .split('\n')
              .where((s) => s.startsWith('/uploads/') && s.endsWith('apk'))
              .map((s) => '$standardUrl$s')
              .toList();

      // Merge extracted .apk URLs from both "Assets" and "Description" field
      var apkUrlsSet = apkUrlsFromAssets.toSet();
      apkUrlsSet.addAll(uploadedAPKsFromDescription);

      // Extract either released or created date as "release" property
      var releaseDateString = e['released_at'] ?? e['created_at'];

      // Create a time object out of the extracted release string
      DateTime? releaseDate =
          releaseDateString != null ? DateTime.parse(releaseDateString) : null;

      // Create a details object from retrieved information
      return APKDetails(
          e['tag_name'] ?? e['name'],
          getApkUrlsFromUrls(apkUrlsSet.toList()),
          GitHub().getAppNames(standardUrl),
          releaseDate: releaseDate);
    });
  }
}

/// This class is designed to retrieve .apk-details from gitlab's tags-page
class GitlabTagsPageStrategy extends RetrievalStrategy {

  // Source context
  AppSource source;

  // Specific source parameters
  String standardUrl;
  Map<String, dynamic> additionalSettings;

  /// Constructor with mandatory parameters
  GitlabTagsPageStrategy(this.source, this.standardUrl, this.additionalSettings);

  /// Retrieves an iterable list of ApkDetails
  @override
  Future<Iterable<APKDetails>> retrieve() async {

    // Request XML data from gitlab's tags-page
    Response res = await source.sourceRequest(
        '$standardUrl/-/tags?format=atom', additionalSettings);

    // Check for HTTP errors
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }

    // Create an uri object from URL string
    var standardUri = Uri.parse(standardUrl);

    // Parse received XML response
    var parsedHtml = parse(res.body);

    // Iterate each entry-element
    return parsedHtml.querySelectorAll('entry').map((entry) {

      // Extract html-content from entry-element and parse it
      var entryContent = parse(
          parseFragment(entry.querySelector('content')!.innerHtml).text);

      // Define a collection with .apk-URLs
      var apkUrls = [
        // Extract .apk-URLs from uploaded files with RegExp
        ...getLinksFromParsedHTML(
            entryContent,
            RegExp(
                '^${standardUri.path.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
                  return '\\${x[0]}';
                })}/uploads/[^/]+/[^/]+\\.apk\$',
                caseSensitive: false),
            standardUri.origin),
        // Extract .apk-URLs from other related links
        // NOTICE: GitLab releases may contain links to externally hosted APKs
        ...getLinksFromParsedHTML(entryContent,
            RegExp('/[^/]+\\.apk\$', caseSensitive: false), '')
            .where((element) => Uri.parse(element).host != '')
      ];

      // Extract an id from the current entry and make a version string out of it
      var entryId = entry.querySelector('id')?.innerHtml;
      var version = entryId == null ? null : Uri.parse(entryId).pathSegments.last;

      // Extract a release date from updated-element
      var releaseDateString = entry.querySelector('updated')?.innerHtml;

      // Create a time object from extracted release date
      DateTime? releaseDate = releaseDateString != null
          ? DateTime.parse(releaseDateString)
          : null;

      // Check for retrieval errors
      if (version == null) {
        throw NoVersionError();
      }

      // Create a details object from retrieved information
      return APKDetails(version, getApkUrlsFromUrls(apkUrls),
          GitHub().getAppNames(standardUrl),
          releaseDate: releaseDate);
    });
  }
}

class GitLab extends AppSource {
  GitLab() {
    hosts = ['gitlab.com'];
    canSearch = true;
    showReleaseDateAsVersionToggle = true;

    sourceConfigSettingFormItems = [
      GeneratedFormTextField('gitlab-creds',
          label: tr('gitlabPATLabel'),
          password: true,
          required: false,
          belowWidgets: [
            const SizedBox(
              height: 4,
            ),
            GestureDetector(
                onTap: () {
                  launchUrlString(
                      'https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#create-a-personal-access-token',
                      mode: LaunchMode.externalApplication);
                },
                child: Text(
                  tr('about'),
                  style: const TextStyle(
                      decoration: TextDecoration.underline, fontSize: 12),
                )),
            const SizedBox(
              height: 4,
            )
          ])
    ];

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch('fallbackToOlderReleases',
            label: tr('fallbackToOlderReleases'), defaultValue: true)
      ]
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp(
        '^https?://(www\\.)?${getSourceRegex(hosts)}/[^/]+/[^/]+',
        caseSensitive: false);
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  Future<String?> getPATIfAny(Map<String, dynamic> additionalSettings) async {
    SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    var sourceConfig =
        await getSourceConfigValues(additionalSettings, settingsProvider);
    String? creds = sourceConfig['gitlab-creds'];
    return creds != null && creds.isNotEmpty ? creds : null;
  }

  @override
  Future<String?> getSourceNote() async {
    if ((await getPATIfAny({})) == null) {
      return '${tr('gitlabSourceNote')} ${hostChanged ? tr('addInfoBelow') : tr('addInfoInSettings')}';
    }
    return null;
  }

  @override
  Future<Map<String, List<String>>> search(String query,
      {Map<String, dynamic> querySettings = const {}}) async {
    var url =
        'https://${hosts[0]}/api/v4/projects?search=${Uri.encodeQueryComponent(query)}';
    var res = await sourceRequest(url, {});
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var json = jsonDecode(res.body) as List<dynamic>;
    Map<String, List<String>> results = {};
    for (var element in json) {
      results['https://${hosts[0]}/${element['path_with_namespace']}'] = [
        element['name_with_namespace'],
        element['description'] ?? tr('noDescription')
      ];
    }
    return results;
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/-/releases';

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {

    // Load "fallback" setting
    bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;

    // Load Private Access Token
    String? PAT = await getPATIfAny(hostChanged ? additionalSettings : {});

    // Define a result list
    Iterable<APKDetails> apkDetailsList = [];

    // Decide between retrieval strategies
    if (PAT != null) {

      // Retrieve from Gitlab API
      GitlabApiStrategy apiStrategy = GitlabApiStrategy(this, standardUrl, additionalSettings, PAT);
      apkDetailsList = await apiStrategy.retrieve();

    } else {

      // Retrieve from "tags"-page
      GitlabTagsPageStrategy tagsPageStrategy = GitlabTagsPageStrategy(this, standardUrl, additionalSettings);
      apkDetailsList = await tagsPageStrategy.retrieve();

    }

    // Error recognition
    if (apkDetailsList.isEmpty) {
      throw NoReleasesError(note: tr('gitlabSourceNote'));
    }

    // Proceed fallback if enabled
    if (fallbackToOlderReleases) {
      if (additionalSettings['trackOnly'] != true) {
        apkDetailsList =
            apkDetailsList.where((e) => e.apkUrls.isNotEmpty).toList();
      }
      if (apkDetailsList.isEmpty) {
        throw NoReleasesError(note: tr('gitlabSourceNote'));
      }
    }

    // Return first of .apk details, which means "latest" version (?)
    return apkDetailsList.first;
  }
}
