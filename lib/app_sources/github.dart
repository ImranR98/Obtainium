import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

Map<String, dynamic>? _jsonObjectFromResponseBody(String responseBody) {
  try {
    final dynamic decodedBody = jsonDecode(responseBody);
    if (decodedBody is Map<String, dynamic>) {
      return decodedBody;
    }
  } catch (_) {
    return null;
  }
  return null;
}

class GitHub extends AppSource {
  static const String githubCredsKey = 'github-creds';
  static const String githubReqPrefixKey = 'GHReqPrefix';
  static const String githubReqPrefixUseTokenKey = 'GHReqPrefixUseToken';
  static const String enforceAttestationsKey = 'enforceGitHubAttestations';
  static const String buildVerificationModeKey = 'githubBuildVerificationMode';
  static const String buildVerificationOff = 'off';
  static const String buildVerificationAudit = 'audit';
  static const String buildVerificationEnforce = 'enforce';
  static const String validatedPATFingerprintKey =
      'githubValidatedPATFingerprint';

  GitHub({bool hostChanged = false}) {
    name = 'GitHub';
    hosts = ['github.com'];
    appIdInferIsOptional = true;
    // All four alternate version-string sources are offered via the unified
    // versionStringSource dropdown (see SourceProvider.versionStringSourceOptions).
    showReleaseDateAsVersionToggle = true;
    showReleaseTitleAsVersionToggle = true;
    showExtractVersionFromAssetNameToggle = true;
    showReleaseCommitShaAsVersionToggle = true;
    this.hostChanged = hostChanged;
    allowIncludeZips = true;
    allowIncludeTarballs = true;
    canSearch = true;
  }

  @override
  List<GeneratedFormItem> get sourceConfigSettingFormItems => [
    GeneratedFormTextField(
      githubCredsKey,
      label: tr('githubPATLabel'),
      password: true,
      required: false,
      helpUrl:
          'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token',
      assistIcon: Icons.verified_user_outlined,
      assistTooltip: tr('validateGitHubPAT'),
      assistAction: _validatePATFromSettingsForm,
    ),
    GeneratedFormTextField(
      'GHReqPrefix',
      label: tr('GHReqPrefix'),
      hint: 'gh-proxy.org',
      required: false,
      additionalValidators: [
        (value) {
          try {
            if (value != null && Uri.parse(value).scheme.isNotEmpty) {
              throw true;
            }
            if (value != null) {
              Uri.parse('https://$value/api.github.com');
            }
          } catch (e) {
            return tr('invalidInput');
          }
          return null;
        },
      ],
      helpUrl: 'https://github.com/sky22333/hubproxy',
    ),
    // Fork addition: companion to GHReqPrefix. When the proxy is set, the PAT
    // is stripped from proxied requests by default (see getTokenIfAny). Enabling
    // this opts back in to sending the token through the proxy.
    GeneratedFormSwitch(
      'GHReqPrefixUseToken',
      label: tr('GHReqPrefixUseToken'),
      value: false,
    ),
    GeneratedFormSwitch(
      'checkRepoRename',
      label: tr('repoRenamedCheck'),
      value: false,
    ),
  ];

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [
      GeneratedFormSwitch(
        'includePrereleases',
        label: tr('includePrereleases'),
        value: false,
      ),
    ],
    [GeneratedFormSwitch('verifyLatestTag', label: tr('verifyLatestTag'))],
    AppSource.fallbackToOlderReleasesFormItem,
    [
      GeneratedFormTextField(
        'filterReleaseTitlesByRegEx',
        label: tr('filterReleaseTitlesByRegEx'),
        required: false,
        additionalValidators: [
          (value) {
            return regExValidator(value);
          },
        ],
      ),
    ],
    [
      GeneratedFormTextField(
        'filterReleaseNotesByRegEx',
        label: tr('filterReleaseNotesByRegEx'),
        required: false,
        additionalValidators: [
          (value) {
            return regExValidator(value);
          },
        ],
      ),
    ],
    [
      GeneratedFormDropdown(
        buildVerificationModeKey,
        [
          MapEntry(buildVerificationOff, tr('githubBuildVerificationOff')),
          MapEntry(buildVerificationAudit, tr('githubBuildVerificationAudit')),
          MapEntry(
            buildVerificationEnforce,
            tr('githubBuildVerificationEnforce'),
          ),
        ],
        label: tr('githubBuildVerificationMode'),
        value: buildVerificationOff,
        labelTooltip: tr('githubBuildVerificationTooltip'),
      ),
    ],
    [
      GeneratedFormDropdown(
        'sortMethodChoice',
        [
          MapEntry('date', tr('releaseDate')),
          MapEntry('smartname', tr('smartname')),
          MapEntry('none', tr('none')),
          MapEntry(
            'smartname-datefallback',
            '${tr('smartname')} x ${tr('releaseDate')}',
          ),
          MapEntry('name', tr('name')),
        ],
        label: tr('sortMethod'),
        value: 'date',
      ),
    ],
    [
      GeneratedFormSwitch(
        'useLatestAssetDateAsReleaseDate',
        label: tr('useLatestAssetDateAsReleaseDate'),
        value: false,
      ),
    ],
    // 'releaseTitleAsVersion' is now offered through the unified
    // versionStringSource dropdown (showReleaseTitleAsVersionToggle), not a
    // standalone switch — syncVersionStringSourceSettings keeps the bool in sync.
  ];

  @override
  List<GeneratedFormItem> get searchQuerySettingFormItems => [
    GeneratedFormTextField(
      'minStarCount',
      label: tr('minStarCount'),
      value: '0',
      additionalValidators: [
        (value) {
          try {
            int.parse(value ?? '0');
          } catch (e) {
            return tr('invalidInput');
          }
          return null;
        },
      ],
    ),
  ];

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    const possibleBuildGradleLocations = [
      '/app/build.gradle',
      'android/app/build.gradle',
      'src/app/build.gradle',
    ];
    for (var path in possibleBuildGradleLocations) {
      try {
        final res = await sourceRequest(
          '${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/contents/$path',
          additionalSettings,
        );
        if (res.statusCode == 200) {
          try {
            final body = jsonDecode(res.body);
            final trimmedLines = utf8
                .decode(
                  base64.decode(
                    body['content'].toString().split('\n').join(''),
                  ),
                )
                .split('\n')
                .map((e) => e.trim());
            var appIds = trimmedLines.where(
              (l) =>
                  l.startsWith('applicationId "') ||
                  l.startsWith('applicationId \''),
            );
            appIds = appIds.map((appId) {
              final parts = appId.split(
                appId.startsWith('applicationId "') ? '"' : '\'',
              );
              return parts.length > 1 ? parts[1] : '';
            });
            appIds = appIds
                .map((appId) {
                  if (appId.startsWith('\${') && appId.endsWith('}')) {
                    final varLine = trimmedLines
                        .where(
                          (l) => l.startsWith(
                            'def ${appId.substring(2, appId.length - 1)}',
                          ),
                        )
                        .firstOrNull;
                    if (varLine == null) return '';
                    final parts = varLine.split(
                      varLine.contains('"') ? '"' : '\'',
                    );
                    appId = parts.length > 1 ? parts[1] : '';
                  }
                  return appId;
                })
                .where((appId) => appId.isNotEmpty);
            if (appIds.length == 1) {
              return appIds.first;
            }
          } catch (err) {
            unawaited(
              LogsProvider().add(
                'Error parsing build.gradle from ${res.request?.url.toString() ?? standardUrl}: ${err.toString()}',
              ),
            );
          }
        }
      } catch (err) {
        unawaited(
          LogsProvider().add(
            'Failed to extract ID from build.gradle or APK: ${err.toString()}',
          ),
        );
      }
    }
    return null;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'/[^/]+/[^/]+',
  );

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final token = await getTokenIfAny(additionalSettings);
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Token $token';
    }
    if (forAPKDownload == true) {
      headers[HttpHeaders.acceptHeader] = 'application/octet-stream';
    }
    if (headers.isNotEmpty) {
      return headers;
    } else {
      return null;
    }
  }

  Future<String?> getTokenIfAny(Map<String, dynamic> additionalSettings) async {
    final SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final sourceConfig = await getSourceConfigValues(
      additionalSettings,
      settingsProvider,
    );
    String? creds = sourceConfig['github-creds'];
    // Fork addition: only strip the PAT from proxied requests when the user has
    // NOT opted to send it through the proxy (GHReqPrefixUseToken == 'false').
    // The use-token flag is read from the resolved sourceConfig, matching how
    // GHReqPrefix itself is configured as a source-config setting.
    if ((additionalSettings['GHReqPrefix'] as String? ?? '').isNotEmpty &&
        (sourceConfig['GHReqPrefixUseToken'] ?? 'false') == 'false') {
      creds = null;
    }
    if (creds != null) {
      final userNameEndIndex = creds.indexOf(':');
      if (userNameEndIndex > 0) {
        creds = creds.substring(
          userNameEndIndex + 1,
        ); // For old username-included token inputs
      }
      return creds;
    } else {
      return null;
    }
  }

  // ── GitHub build-attestation verification + PAT validation (fork feature) ──
  // The attestation API requires an authenticated request, so verification is
  // only offered once the user has validated a Personal Access Token. Statuses
  // are the githubAttestationStatus* constants from source_provider.

  static String? tokenFromCreds(String? creds) {
    String? token = creds?.trim();
    if (token == null || token.isEmpty) {
      return null;
    }
    final int userNameEndIndex = token.indexOf(':');
    if (userNameEndIndex > 0) {
      token = token.substring(userNameEndIndex + 1);
    }
    return token.trim().isEmpty ? null : token.trim();
  }

  static String? patFingerprint(String? creds) {
    final String? token = tokenFromCreds(creds);
    if (token == null) {
      return null;
    }
    return sha256.convert(utf8.encode(token)).toString();
  }

  static bool hasValidatedPAT(
    String? creds,
    SettingsProvider settingsProvider,
  ) {
    final String? fingerprint = patFingerprint(creds);
    if (fingerprint == null) {
      return false;
    }
    return settingsProvider.getSettingString(validatedPATFingerprintKey) ==
        fingerprint;
  }

  static void clearPATValidation(SettingsProvider settingsProvider) {
    settingsProvider.setSettingString(validatedPATFingerprintKey, '');
  }

  static void storePATValidation(
    String creds,
    SettingsProvider settingsProvider,
  ) {
    final String? fingerprint = patFingerprint(creds);
    if (fingerprint == null) {
      clearPATValidation(settingsProvider);
      return;
    }
    settingsProvider.setSettingString(validatedPATFingerprintKey, fingerprint);
  }

  static Future<String?> validatePAT(String creds) async {
    final String? token = tokenFromCreds(creds);
    if (token == null) {
      return tr('githubPATRequiredForDefaultVerification');
    }
    try {
      final Response response = await get(
        Uri.parse('https://api.github.com/user'),
        headers: <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.acceptHeader: 'application/vnd.github+json',
          HttpHeaders.userAgentHeader: 'Obtainium',
        },
      );
      if (response.statusCode == 200) {
        return null;
      }
      if (response.statusCode == 401) {
        return tr('githubPATInvalid');
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        return tr('githubPATValidationRateLimited');
      }
      return tr('githubPATValidationFailed');
    } catch (_) {
      return tr('githubPATValidationFailed');
    }
  }

  static Future<void> _validatePATFromSettingsForm(
    BuildContext context,
    FormValuesTextPatch patch,
    Map<String, dynamic> values,
  ) async {
    final String creds = values[githubCredsKey]?.toString() ?? '';
    final SettingsProvider settingsProvider = context.read<SettingsProvider>();
    final String? error = await validatePAT(creds);
    if (!context.mounted) {
      return;
    }
    if (error == null) {
      storePATValidation(creds, settingsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('githubPATValidated'))));
    } else {
      clearPATValidation(settingsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  bool canVerifyAttestations(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) {
    final String? creds =
        additionalSettings[githubCredsKey]?.toString() ??
        settingsProvider.getSettingString(githubCredsKey);
    return hasValidatedPAT(creds, settingsProvider);
  }

  String buildVerificationMode(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) {
    final String mode =
        additionalSettings[buildVerificationModeKey]?.toString() ??
        (additionalSettings[enforceAttestationsKey] == true
            ? buildVerificationEnforce
            : buildVerificationOff);
    if (mode != buildVerificationAudit && mode != buildVerificationEnforce) {
      return buildVerificationOff;
    }
    if (!canVerifyAttestations(additionalSettings, settingsProvider)) {
      return buildVerificationOff;
    }
    return mode;
  }

  bool shouldVerifyAttestations(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) {
    return buildVerificationMode(additionalSettings, settingsProvider) !=
        buildVerificationOff;
  }

  bool shouldEnforceAttestations(
    Map<String, dynamic> additionalSettings,
    SettingsProvider settingsProvider,
  ) {
    return buildVerificationMode(additionalSettings, settingsProvider) ==
        buildVerificationEnforce;
  }

  Future<String> getAttestationStatusForSha256Digest(
    String standardUrl,
    String sha256Digest,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String digest = sha256Digest.startsWith('sha256:')
        ? sha256Digest.substring('sha256:'.length)
        : sha256Digest;
    if (digest.isEmpty) {
      return githubAttestationStatusError;
    }
    try {
      final Response response = await sourceRequest(
        '${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/attestations/sha256:$digest',
        additionalSettings,
      );
      if (response.statusCode == 404) {
        return githubAttestationStatusUnsupported;
      }
      if (response.statusCode != 200) {
        return githubAttestationStatusError;
      }
      final Map<String, dynamic>? body = _jsonObjectFromResponseBody(
        response.body,
      );
      final Object? attestations = body?['attestations'];
      if (attestations is List && attestations.isNotEmpty) {
        return githubAttestationStatusVerified;
      }
      return githubAttestationStatusUnsupported;
    } catch (_) {
      return githubAttestationStatusError;
    }
  }

  Future<bool?> hasAttestationForSha256Digest(
    String standardUrl,
    String sha256Digest,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String status = await getAttestationStatusForSha256Digest(
      standardUrl,
      sha256Digest,
      additionalSettings,
    );
    if (status == githubAttestationStatusVerified) {
      return true;
    }
    if (status == githubAttestationStatusUnsupported) {
      return false;
    }
    return null;
  }

  @override
  Future<String?> getSourceNote() async {
    if (!hostChanged && (await getTokenIfAny({})) == null) {
      return '${tr('githubSourceNote')} ${hostChanged ? tr('addInfoBelow') : tr('addInfoInSettings')}';
    }
    return null;
  }

  @override
  Future<String> generalReqPrefetchModifier(
    String reqUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    if ((additionalSettings['GHReqPrefix'] as String? ?? '').isNotEmpty) {
      final uri = Uri.parse(reqUrl);
      return 'https://${additionalSettings['GHReqPrefix']}/${uri.toString().substring('https://'.length)}';
    }
    return reqUrl;
  }

  Future<String> getAPIHost(Map<String, dynamic> additionalSettings) async =>
      'https://api.${hosts[0]}';

  Future<String> convertStandardUrlToAPIUrl(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async =>
      '${await getAPIHost(additionalSettings)}/repos${standardUrl.substring('https://${hosts[0]}'.length)}';

  /// Checks if the repository has been renamed or transferred.
  ///
  /// This method explicitly disables automatic redirect following to detect when
  /// GitHub returns a redirect (indicating the repository has moved). A redirect
  /// from the GitHub API for a repository endpoint definitively indicates that
  /// the repository has been renamed or transferred to a different owner.
  ///
  /// Throws [RepositoryRenamedError] if a redirect is detected.
  Future<void> checkForRepositoryRename(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    Map<String, String> sourceConfigSettingValues,
  ) async {
    if (sourceConfigSettingValues['checkRepoRename'] != 'true') {
      return;
    }
    final uri = Uri.tryParse(standardUrl);
    final host = uri?.host.toLowerCase() ?? '';
    // Guard against non-GitHub URLs
    if (host != hosts[0] && host != 'www.${hosts[0]}') {
      return;
    }
    final apiUrl = await convertStandardUrlToAPIUrl(
      standardUrl,
      additionalSettings,
    );
    final Response res = await sourceRequest(
      apiUrl,
      additionalSettings,
      followRedirects: false,
    );
    if (res.statusCode >= 300 && res.statusCode < 400) {
      final String? location =
          res.headers[HttpHeaders.locationHeader.toLowerCase()];
      if (location != null) {
        final Response res2 = await sourceRequest(
          location,
          additionalSettings,
          followRedirects: false,
        );
        String? newUrl;
        try {
          newUrl = jsonDecode(res2.body)['html_url'];
        } catch (e) {
          unawaited(
            LogsProvider().add(
              'Failed to parse redirect response for repo rename: ${e.toString()}',
            ),
          );
        }
        if (newUrl != null) {
          throw RepositoryRenamedError(standardUrl, newUrl);
        }
      }
    }
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  List<dynamic> _findReleaseAssetUrls(
    dynamic release,
    bool includeZips,
    bool includeTarballs,
    Map<String, String> sourceConfigSettingValues,
  ) =>
      (release['assets'] as List<dynamic>?)?.map((e) {
        final name = e['name'].toString();
        var url =
            !AppSource.isApkOrContainerFile(
              name,
              includeArchives: includeZips,
              includeTarballs: includeTarballs,
            )
            ? (e['browser_download_url'] ?? e['url'])
            : (e['url'] ?? e['browser_download_url']);
        url = undoGHProxyMod(url, sourceConfigSettingValues);
        e['final_url'] = (e['name'] != null) && (url != null)
            ? MapEntry(e['name'] as String, url as String)
            : const MapEntry('', '');
        return e;
      }).toList() ??
      [];

  DateTime? _getPublishDateFromRelease(dynamic rel) {
    final pub = rel?['published_at'];
    if (pub is String) return DateTime.tryParse(pub);
    final commitCreated = rel?['commit']?['created'];
    if (commitCreated is String) return DateTime.tryParse(commitCreated);
    return null;
  }

  DateTime? _getNewestAssetDateFromRelease(dynamic rel) {
    final allAssets = rel['assets'] as List<dynamic>?;
    final filteredAssets = rel['filteredAssets'] as List<dynamic>?;
    final t = (filteredAssets ?? allAssets)
        ?.map((e) {
          final updated = e?['updated_at'];
          return updated is String ? DateTime.tryParse(updated) : null;
        })
        .where((e) => e != null)
        .toList();
    t?.sort((a, b) => b!.compareTo(a!));
    if (t?.isNotEmpty == true) {
      return t!.first;
    }
    return null;
  }

  DateTime? _getReleaseDateFromRelease(dynamic rel, bool useAssetDate) =>
      !useAssetDate
      ? _getPublishDateFromRelease(rel)
      : _getNewestAssetDateFromRelease(rel);

  void _sortGitHubReleases(
    List<dynamic> releases,
    String sortMethod,
    bool useLatestAssetDateAsReleaseDate,
  ) {
    if (sortMethod == 'none') return;

    // Precompute dates and (for smartname/name sorts) per-release format
    // sets once. Memoization in findStandardFormatsForVersion already handles
    // the per-version cache; we still precompute here so the sort comparator
    // only performs O(1) lookups instead of O(n) per comparison.
    final isDateOnly = sortMethod == 'date';
    final Map<dynamic, DateTime?> dates = {};
    final Map<dynamic, Set<String>> formats = {};
    if (!isDateOnly) {
      for (final r in releases) {
        if (r == null) continue;
        final name = (r['tag_name'] ?? r['name'])?.toString() ?? '';
        formats[r] = findStandardFormatsForVersion(name, false);
      }
    }

    releases.sort((a, b) {
      if (a == null) return -1;
      if (b == null) return 1;

      if (isDateOnly) {
        final dateA = dates.putIfAbsent(
          a,
          () => _getReleaseDateFromRelease(a, useLatestAssetDateAsReleaseDate),
        );
        final dateB = dates.putIfAbsent(
          b,
          () => _getReleaseDateFromRelease(b, useLatestAssetDateAsReleaseDate),
        );
        return (dateA ?? DateTime(1)).compareTo(dateB ?? DateTime(0));
      }

      final nameA = a['tag_name'] ?? a['name'];
      final nameB = b['tag_name'] ?? b['name'];
      final stdFormats = formats[a]!.intersection(formats[b]!);

      if (sortMethod == 'smartname-datefallback' && stdFormats.isEmpty) {
        final dateA = _getReleaseDateFromRelease(
          a,
          useLatestAssetDateAsReleaseDate,
        );
        final dateB = _getReleaseDateFromRelease(
          b,
          useLatestAssetDateAsReleaseDate,
        );
        return (dateA ?? DateTime(1)).compareTo(dateB ?? DateTime(0));
      }

      if (sortMethod != 'name' && stdFormats.isNotEmpty) {
        final sortedFormats = stdFormats.toList()
          ..sort((x, y) => y.length.compareTo(x.length));
        final reg = RegExp(sortedFormats.first);
        final matchA = reg.firstMatch(nameA);
        final matchB = reg.firstMatch(nameB);
        if (matchA == null || matchB == null) {
          return compareAlphaNumeric(nameA as String, nameB as String);
        }
        return compareAlphaNumeric(
          (nameA as String).substring(matchA.start, matchA.end),
          (nameB as String).substring(matchB.start, matchB.end),
        );
      }

      return compareAlphaNumeric(nameA as String, nameB as String);
    });
  }

  void _positionLatestRelease(List<dynamic> releases, dynamic latestRelease) {
    if (latestRelease == null ||
        (latestRelease['tag_name'] ?? latestRelease['name']) == null ||
        releases.isEmpty ||
        (latestRelease['tag_name'] ?? latestRelease['name']) ==
            (releases[releases.length - 1]['tag_name'] ??
                releases[releases.length - 1]['name'])) {
      return;
    }
    final ind = releases.indexWhere(
      (element) =>
          (latestRelease['tag_name'] ?? latestRelease['name']) ==
          (element['tag_name'] ?? element['name']),
    );
    if (ind >= 0) {
      releases.add(releases.removeAt(ind));
    }
  }

  /// Resolves the commit SHA a release's tag points at (following annotated
  /// tags to their underlying commit), for "release commit SHA as version"
  /// mode. Returns null if it can't be determined.
  Future<String?> getReleaseCommitSha(
    dynamic release,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String? tagName = release['tag_name'] as String?;
    if (tagName == null || tagName.trim().isEmpty) {
      return null;
    }
    final String apiUrl = await convertStandardUrlToAPIUrl(
      standardUrl,
      additionalSettings,
    );
    final Response refResponse = await sourceRequest(
      '$apiUrl/git/ref/tags/${Uri.encodeComponent(tagName)}',
      additionalSettings,
    );
    if (refResponse.statusCode != 200) {
      return null;
    }
    final Map<String, dynamic>? refBody = _jsonObjectFromResponseBody(
      refResponse.body,
    );
    final dynamic refObject = refBody?['object'];
    if (refObject is! Map<String, dynamic>) {
      return null;
    }
    final String? objectSha = refObject['sha'] as String?;
    final String? objectType = refObject['type'] as String?;
    if (objectSha == null || objectSha.isEmpty) {
      return null;
    }
    if (objectType == 'commit') {
      return objectSha;
    }
    if (objectType != 'tag') {
      return null;
    }
    final Response tagResponse = await sourceRequest(
      '$apiUrl/git/tags/$objectSha',
      additionalSettings,
    );
    if (tagResponse.statusCode != 200) {
      return null;
    }
    final Map<String, dynamic>? tagBody = _jsonObjectFromResponseBody(
      tagResponse.body,
    );
    final dynamic tagObject = tagBody?['object'];
    if (tagObject is! Map<String, dynamic>) {
      return null;
    }
    final String? commitSha = tagObject['sha'] as String?;
    final String? commitType = tagObject['type'] as String?;
    return commitType == 'commit' ? commitSha : null;
  }

  dynamic _selectGitHubTargetRelease({
    required List<dynamic> releases,
    required bool fallbackToOlderReleases,
    required bool includePrereleases,
    required String? regexFilter,
    required String? regexNotesFilter,
    required bool includeZips,
    required bool includeTarballs,
    required Map<String, dynamic> additionalSettings,
    required Map<String, String> sourceConfigSettingValues,
  }) {
    var prereleaseSkipped = 0;
    for (int i = 0; i < releases.length; i++) {
      if (!fallbackToOlderReleases && i > prereleaseSkipped) break;
      if (!includePrereleases && releases[i]['prerelease'] == true) {
        prereleaseSkipped++;
        continue;
      }
      if (releases[i]['draft'] == true) {
        continue;
      }
      var nameToFilter = releases[i]['name'] as String?;
      if (nameToFilter == null || nameToFilter.trim().isEmpty) {
        nameToFilter = releases[i]['tag_name']?.toString() ?? '';
      }
      if (regexFilter != null &&
          !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
        continue;
      }
      if (regexNotesFilter != null &&
          !RegExp(
            regexNotesFilter,
          ).hasMatch(((releases[i]['body'] as String?) ?? '').trim())) {
        continue;
      }
      final allAssetsWithUrls = _findReleaseAssetUrls(
        releases[i],
        includeZips,
        includeTarballs,
        sourceConfigSettingValues,
      );
      final List<MapEntry<String, String>> allAssetUrls = allAssetsWithUrls
          .map((e) => e['final_url'] as MapEntry<String, String>)
          .toList();
      final apkAssetsWithUrls = allAssetsWithUrls.where((element) {
        final name = (element['final_url'] as MapEntry<String, String>).key;
        return AppSource.isApkOrContainerFile(
          name,
          includeArchives: includeZips,
          includeTarballs: includeTarballs,
        );
      }).toList();

      final filteredApkUrls = filterApks(
        apkAssetsWithUrls
            .map((e) => e['final_url'] as MapEntry<String, String>)
            .toList(),
        additionalSettings['apkFilterRegEx'],
        additionalSettings['invertAPKFilter'],
      );
      final filteredApks = apkAssetsWithUrls
          .where(
            (e) => filteredApkUrls
                .where(
                  (e2) =>
                      e2.key ==
                      (e['final_url'] as MapEntry<String, String>).key,
                )
                .isNotEmpty,
          )
          .toList();

      if (filteredApks.isEmpty && additionalSettings['trackOnly'] != true) {
        continue;
      }
      final targetRelease = releases[i];
      targetRelease['apkUrls'] = filteredApkUrls;
      targetRelease['filteredAssets'] = filteredApks;
      // Resolve the version string per the selected version-string source.
      // Asset-name + release-title are resolvable synchronously here; the
      // commit-SHA source needs an async API lookup + standardUrl, so it is
      // resolved by the caller (_fetchReleaseDetails) after selection.
      String? selectedVersionSource;
      if (additionalSettings['extractVersionFromAssetName'] == true) {
        if (filteredApkUrls.isEmpty) {
          throw NoVersionError();
        }
        selectedVersionSource = filteredApkUrls.last.key;
      } else if (additionalSettings['releaseTitleAsVersion'] == true) {
        selectedVersionSource = nameToFilter;
      }
      targetRelease['version'] =
          selectedVersionSource ??
          targetRelease['tag_name'] ??
          targetRelease['name'];
      if (targetRelease['tarball_url'] != null) {
        allAssetUrls.add(
          MapEntry(
            (targetRelease['version'] ?? 'source') + '.tar.gz',
            undoGHProxyMod(
              targetRelease['tarball_url'],
              sourceConfigSettingValues,
            ),
          ),
        );
      }
      if (targetRelease['zipball_url'] != null) {
        allAssetUrls.add(
          MapEntry(
            (targetRelease['version'] ?? 'source') + '.zip',
            undoGHProxyMod(
              targetRelease['zipball_url'],
              sourceConfigSettingValues,
            ),
          ),
        );
      }
      targetRelease['allAssetUrls'] = allAssetUrls;
      return targetRelease;
    }
    return null;
  }

  /// Fetches and parses GitHub releases, applying sort/filter/prelease settings,
  /// then resolves the best matching release to an [APKDetails] result.
  Future<APKDetails> _fetchReleaseDetails(
    String requestUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings, {
    Function(Response)? onHttpErrorCode,
  }) async {
    final SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final sourceConfigSettingValues = await getSourceConfigValues(
      additionalSettings,
      settingsProvider,
    );
    await checkForRepositoryRename(
      standardUrl,
      additionalSettings,
      sourceConfigSettingValues,
    );
    final bool includePrereleases =
        additionalSettings['includePrereleases'] == true;
    final bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    final String? regexFilter =
        (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                ?.isNotEmpty ==
            true
        ? additionalSettings['filterReleaseTitlesByRegEx']
        : null;
    final String? regexNotesFilter =
        (additionalSettings['filterReleaseNotesByRegEx'] as String?)
                ?.isNotEmpty ==
            true
        ? additionalSettings['filterReleaseNotesByRegEx']
        : null;
    final bool verifyLatestTag = additionalSettings['verifyLatestTag'] == true;
    final bool useLatestAssetDateAsReleaseDate =
        additionalSettings['useLatestAssetDateAsReleaseDate'] == true;
    final String sortMethod =
        additionalSettings['sortMethodChoice'] ?? 'smartname-datefallback';
    final bool includeZips = additionalSettings['includeZips'] == true;
    final bool includeTarballs = additionalSettings['includeTarballs'] == true;
    dynamic latestRelease;
    if (verifyLatestTag) {
      final uri = Uri.parse(requestUrl);
      final latestUrl = uri.replace(query: null, path: '${uri.path}/latest');
      final Response res = await sourceRequest(
        latestUrl.toString(),
        additionalSettings,
      );
      if (res.statusCode != 200) {
        if (onHttpErrorCode != null) {
          onHttpErrorCode(res);
        }
        throw getObtainiumHttpError(res);
      }
      latestRelease = jsonDecode(res.body);
    }
    final Response res = await sourceRequest(requestUrl, additionalSettings);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw NoReleasesError();
      }
      var releases = decoded;
      if (latestRelease != null) {
        final latestTag = latestRelease['tag_name'] ?? latestRelease['name'];
        if (releases
            .where(
              (element) =>
                  (element['tag_name'] ?? element['name']) == latestTag,
            )
            .isEmpty) {
          releases = [latestRelease, ...releases];
        }
      }

      if (sortMethod == 'none') {
        releases = releases.reversed.toList();
      } else {
        _sortGitHubReleases(
          releases,
          sortMethod,
          useLatestAssetDateAsReleaseDate,
        );
      }
      _positionLatestRelease(releases, latestRelease);
      releases = releases.reversed.toList();
      final targetRelease = _selectGitHubTargetRelease(
        releases: releases,
        fallbackToOlderReleases: fallbackToOlderReleases,
        includePrereleases: includePrereleases,
        regexFilter: regexFilter,
        regexNotesFilter: regexNotesFilter,
        includeZips: includeZips,
        includeTarballs: includeTarballs,
        additionalSettings: additionalSettings,
        sourceConfigSettingValues: sourceConfigSettingValues,
      );
      if (targetRelease == null) {
        throw NoReleasesError();
      }
      // Resolve commit-SHA-as-version here: it needs an async ref/tag API
      // lookup and standardUrl, so it can't run inside the sync release
      // selector. Overrides the tag-based version chosen there.
      if (additionalSettings['releaseCommitShaAsVersion'] == true) {
        final String? commitSha = await getReleaseCommitSha(
          targetRelease,
          standardUrl,
          additionalSettings,
        );
        if (commitSha == null) {
          throw NoVersionError();
        }
        targetRelease['version'] = commitSha;
      }
      final String? version = targetRelease['version'];
      final DateTime? releaseDate = _getReleaseDateFromRelease(
        targetRelease,
        useLatestAssetDateAsReleaseDate,
      );
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      final changeLog = (targetRelease['body'] ?? '').toString();
      final apkUrls =
          targetRelease['apkUrls'] as List<MapEntry<String, String>>;

      // Advance download size for the preferred APK, read from the GitHub API's
      // per-asset `size` field (no extra network request) — parity with fork
      // main (v2.9.3). This is what shows the update size on the update button;
      // dropping it in the sync is why GitHub (and Codeberg, which delegates
      // here) apps stopped showing a size.
      int? apkSizeBytes;
      if (apkUrls.isNotEmpty) {
        final sizeAssets =
            (targetRelease['filteredAssets'] as List<dynamic>?) ?? [];
        for (final asset in sizeAssets.whereType<Map<String, dynamic>>()) {
          final assetName =
              (asset['final_url'] as MapEntry<String, String>?)?.key;
          if (assetName == apkUrls.last.key) {
            final rawSize = asset['size'];
            if (rawSize is num) apkSizeBytes = rawSize.toInt();
            break;
          }
        }
      }

      // ── GitHub build-attestation status (fork feature) ──────────────────
      // Compute the attestation verdict at CHECK time from the preferred
      // asset's API-provided sha256 `digest`, so the app page can show
      // Verified / Unsupported / Can't-Check immediately — without waiting for
      // the APK to be downloaded (the /attestations lookup only needs the
      // digest, not the bytes). This is what drives the "Security" badge on the
      // update card; dropping it leaves latestAttestationStatus null, which the
      // UI renders as "Can't Check". Do NOT remove — attestation is only
      // otherwise recomputed at install time.
      final bool shouldCheckAttestation = shouldVerifyAttestations(
        additionalSettings,
        settingsProvider,
      );
      String? attestationStatus;
      if (shouldCheckAttestation) {
        final filteredAssets =
            (targetRelease['filteredAssets'] as List<dynamic>?) ?? [];
        Map<String, dynamic>? preferredAsset;
        if (apkUrls.isNotEmpty) {
          for (final asset
              in filteredAssets.whereType<Map<String, dynamic>>()) {
            final assetName =
                (asset['final_url'] as MapEntry<String, String>?)?.key;
            if (assetName == apkUrls.last.key) {
              preferredAsset = asset;
              break;
            }
          }
        }
        final String? preferredAssetDigest =
            preferredAsset?['digest'] as String?;
        // Skip the attestation API round-trip when the upstream release is
        // unchanged and we hold a CONCLUSIVE cached verdict. A GitHub
        // attestation is produced inside the release workflow run that builds
        // the asset and bound to its digest, so for an unchanged release both
        // 'verified' and 'unsupported' (no attestation for this digest) are
        // stable. Only a cached 'error' is re-checked, since that is a
        // transient lookup failure, not a real verdict.
        final App? prevApp = previouslyCheckedApp;
        final bool canReuseCachedAttestation =
            prevApp != null &&
            prevApp.rawLatestVersionFromSource != null &&
            prevApp.rawLatestVersionFromSource == version &&
            prevApp.latestAttestationStatus != null &&
            prevApp.latestAttestationStatus != githubAttestationStatusError;
        attestationStatus = canReuseCachedAttestation
            ? prevApp.latestAttestationStatus
            : preferredAssetDigest != null
            ? await getAttestationStatusForSha256Digest(
                standardUrl,
                preferredAssetDigest,
                additionalSettings,
              )
            : githubAttestationStatusError;
      }

      return APKDetails(
        version,
        apkUrls,
        getAppNames(standardUrl),
        releaseDate: releaseDate,
        changeLog: changeLog.isEmpty ? null : changeLog,
        allAssetUrls:
            targetRelease['allAssetUrls'] as List<MapEntry<String, String>>,
        apkSizeBytes: apkSizeBytes,
        attestationStatus: attestationStatus,
      );
    } else {
      if (onHttpErrorCode != null) {
        onHttpErrorCode(res);
      }
      throw getObtainiumHttpError(res);
    }
  }

  Future<APKDetails> fetchReleaseDetailsWithTagFallback(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    Future<String> Function(bool) reqUrlGenerator,
    dynamic Function(Response)? onHttpErrorCode,
  ) async {
    try {
      return await _fetchReleaseDetails(
        await reqUrlGenerator(false),
        standardUrl,
        additionalSettings,
        onHttpErrorCode: onHttpErrorCode,
      );
    } catch (err) {
      if (err is NoReleasesError && additionalSettings['trackOnly'] == true) {
        return await _fetchReleaseDetails(
          await reqUrlGenerator(true),
          standardUrl,
          additionalSettings,
          onHttpErrorCode: onHttpErrorCode,
        );
      } else {
        rethrowOrWrapError(err);
      }
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      return await fetchReleaseDetailsWithTagFallback(
        standardUrl,
        additionalSettings,
        (bool useTagUrl) async {
          return '${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/${useTagUrl ? 'tags' : 'releases'}?per_page=100';
        },
        (Response res) {
          rateLimitErrorCheck(res);
        },
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  AppNames getAppNames(String standardUrl) {
    final String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    final pathStart = temp.indexOf('/');
    if (pathStart < 0) throw InvalidURLError(name);
    final List<String> names = temp.substring(pathStart + 1).split('/');
    if (names.isEmpty || names[0].isEmpty) throw InvalidURLError(name);
    return AppNames(names[0], names.sublist(1).join('/'));
  }

  Future<Map<String, List<String>>> searchCommon(
    String query,
    String requestUrl,
    String rootProp, {
    Function(Response)? onHttpErrorCode,
    Map<String, dynamic> querySettings = const {},
  }) async {
    final Response res = await sourceRequest(requestUrl, {});
    if (res.statusCode == 200) {
      final int minStarCount =
          int.tryParse(querySettings['minStarCount']?.toString() ?? '') ?? 0;
      final Map<String, List<String>> urlsWithDescriptions = {};
      for (var e in (jsonDecode(res.body)[rootProp] as List<dynamic>)) {
        if ((e['stargazers_count'] ?? e['stars_count'] ?? 0) >= minStarCount) {
          urlsWithDescriptions.addAll({
            e['html_url'] as String: [
              e['full_name'] as String,
              ((e['archived'] == true ? '[ARCHIVED] ' : '') +
                  (e['description'] != null
                      ? e['description'] as String
                      : tr('noDescription'))),
            ],
          });
        }
      }
      return urlsWithDescriptions;
    } else {
      if (onHttpErrorCode != null) {
        onHttpErrorCode(res);
      }
      throw getObtainiumHttpError(res);
    }
  }

  String undoGHProxyMod(
    String reqUrl,
    Map<String, String> sourceConfigSettingValues,
  ) {
    final ghReqPrefix = sourceConfigSettingValues['GHReqPrefix'];
    if (ghReqPrefix == null || ghReqPrefix.isEmpty) return reqUrl;
    final prefix = 'https://$ghReqPrefix/';
    return reqUrl.startsWith(prefix) ? reqUrl.substring(prefix.length) : reqUrl;
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final sp = SettingsProvider();
    await sp.initializeSettings();
    final sourceConfigSettingValues = await getSourceConfigValues({}, sp);
    final results = await searchCommon(
      query,
      '${await getAPIHost({})}/search/repositories?q=${Uri.encodeQueryComponent(query)}&per_page=100',
      'items',
      onHttpErrorCode: (Response res) {
        rateLimitErrorCheck(res);
      },
      querySettings: querySettings,
    );
    if ((sourceConfigSettingValues['GHReqPrefix'] ?? '').isNotEmpty) {
      final Map<String, List<String>> results2 = {};
      results.forEach((k, v) {
        results2[undoGHProxyMod(k, sourceConfigSettingValues)] = v;
      });
      return results2;
    } else {
      return results;
    }
  }

  void rateLimitErrorCheck(Response res) {
    final reasonLower = res.reasonPhrase?.toLowerCase() ?? '';
    final bodySample = res.body.length > 1000
        ? res.body.substring(0, 1000).toLowerCase()
        : res.body.toLowerCase();
    final isRateLimit =
        res.headers['x-ratelimit-remaining'] == '0' ||
        res.statusCode == 429 ||
        res.statusCode == 403 ||
        reasonLower.contains('rate limit') ||
        reasonLower.contains('too many requests') ||
        bodySample.contains('rate limit') ||
        bodySample.contains('too many requests');

    if (isRateLimit) {
      final now = DateTime.now();
      final retryAfter = res.headers['retry-after'];
      final retryAfterSecs = retryAfter != null
          ? int.tryParse(retryAfter)
          : null;

      final resetEpochSeconds =
          int.tryParse(res.headers['x-ratelimit-reset'] ?? '') ??
          (retryAfterSecs != null
              ? (now.millisecondsSinceEpoch ~/ 1000 + retryAfterSecs)
              : (now.millisecondsSinceEpoch ~/ 1000 +
                    1800)); // Default to 30 minutes (1800 seconds)

      final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
      final remainingMinutes = ((resetEpochSeconds - nowSeconds) / 60)
          .ceil()
          .clamp(1, 9999);
      throw RateLimitError(remainingMinutes);
    }
  }
}
