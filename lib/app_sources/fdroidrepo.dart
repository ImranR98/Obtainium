import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/source_provider.dart';

/// A single APK release in an F-Droid repository index.
class _FdroidVersion {
  final String versionName;
  final int versionCode;
  final String apkName;
  final List<String> nativecode;
  final DateTime? added;

  /// Release channels this build is published under (index-v2's
  /// `releaseChannels`, e.g. `["Beta"]`); empty for v1 entries.
  final List<String> releaseChannels;
  const _FdroidVersion({
    required this.versionName,
    required this.versionCode,
    required this.apkName,
    this.nativecode = const [],
    this.added,
    this.releaseChannels = const [],
  });
}

/// One app in an F-Droid repository index (v1 or v2 format).
class _FdroidIndexEntry {
  final String id;
  final String name;
  final String summary;
  final String? author;
  final String? changelog;

  /// v1-only "suggested" version code (index-v2 has no equivalent).
  final int? marketVersionCode;

  /// Newest-first.
  final List<_FdroidVersion> versions;
  const _FdroidIndexEntry({
    required this.id,
    required this.name,
    this.summary = '',
    this.author,
    this.changelog,
    this.marketVersionCode,
    required this.versions,
  });
}

/// A parsed F-Droid repository index plus the base URL its APKs live under.
class _FdroidIndex {
  final String baseUrl;
  final List<_FdroidIndexEntry> entries;
  const _FdroidIndex({required this.baseUrl, required this.entries});
}

class FDroidRepo extends AppSource {
  @override
  String get name => tr('fdroidThirdPartyRepo');

  FDroidRepo() {
    canSearch = true;
    includeAdditionalOptsInMainSearch = true;
    neverAutoSelect = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [
      GeneratedFormTextField(
        'appIdOrName',
        label: tr('appIdOrName'),
        hint: tr('reposHaveMultipleApps'),
        required: true,
      ),
    ],
    [
      GeneratedFormSwitch(
        'pickHighestVersionCode',
        label: tr('pickHighestVersionCode'),
        value: false,
      ),
    ],
    [
      GeneratedFormSwitch(
        'trySelectingSuggestedVersionCode',
        label: tr('trySelectingSuggestedVersionCode'),
        value: true,
      ),
    ],
  ];

  String _removeQueryParamsFromUrl(String url, {List<String> keep = const []}) {
    final uri = Uri.parse(url);
    final Map<String, dynamic> resultParams = {};
    uri.queryParameters.forEach((key, value) {
      if (keep.contains(key)) {
        resultParams[key] = value;
      }
    });
    url = uri.replace(queryParameters: resultParams).toString();
    if (url.endsWith('?')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    var standardUri = Uri.parse(url);
    final pathSegments = standardUri.pathSegments;
    if (pathSegments.isNotEmpty &&
        (pathSegments.last == 'index.xml' ||
            pathSegments.last == 'index-v2.json')) {
      pathSegments.removeLast();
      standardUri = standardUri.replace(path: pathSegments.join('/'));
    }
    return _removeQueryParamsFromUrl(standardUri.toString(), keep: ['appId']);
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    String? url = querySettings['url'];
    if (url == null) {
      throw NoReleasesError();
    }
    url = _removeQueryParamsFromUrl(standardizeUrl(url));
    final index = await _fetchIndex(url, {});
    final Map<String, List<String>> results = {};
    for (final entry in index.entries) {
      if (query.isEmpty ||
          entry.id.contains(query) ||
          entry.name.contains(query) ||
          entry.summary.contains(query)) {
        results['${index.baseUrl}?appId=${entry.id}'] = [
          entry.name,
          entry.summary,
        ];
      }
    }
    return results;
  }

  @override
  Map<String, dynamic> runOnAddAppInputChange(String inputUrl) {
    try {
      final String? appId = Uri.parse(inputUrl).queryParameters['appId'];
      if (appId != null) {
        return {'appIdOrName': appId};
      }
    } catch (e) {
      AppLogger.info('Failed to parse appId from URL: $e');
    }
    return {};
  }

  @override
  App postProcessApp(App app) {
    final uri = Uri.parse(app.url);
    String? appId;
    if (!isTempId(app)) {
      appId = app.id;
    } else if (uri.queryParameters['appId'] != null) {
      appId = uri.queryParameters['appId'];
    }
    if (appId != null) {
      app = app.copyWith(
        url: uri
            .replace(
              queryParameters: Map.fromEntries([
                ...uri.queryParameters.entries,
                MapEntry('appId', appId),
              ]),
            )
            .toString(),
      );
      app = app.copyWith(
        additionalSettings: Map<String, dynamic>.from(app.additionalSettings)
          ..['appIdOrName'] = appId,
      );
      app = app.copyWith(id: appId);
    }
    return app;
  }

  Future<Response> sourceRequestWithURLVariants(
    String url,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(
      '$url${url.endsWith('/index.xml') ? '' : '/index.xml'}',
      additionalSettings,
    );
    if (res.statusCode != 200) {
      final base = url.endsWith('/index.xml')
          ? AppSource.stripLastPathSegment(url)
          : url;
      res = await sourceRequest('$base/repo/index.xml', additionalSettings);
      if (res.statusCode != 200) {
        res = await sourceRequest(
          '$base/fdroid/repo/index.xml',
          additionalSettings,
        );
      }
    }
    return res;
  }

  /// Fetches and parses the repository index. Prefers the canonical
  /// `index-v2.json` (the only index some modern repos publish, and the only
  /// one that lists every architecture — see #3249); falls back to the legacy
  /// `index.xml` format otherwise.
  Future<_FdroidIndex> _fetchIndex(
    String url,
    Map<String, dynamic> additionalSettings,
  ) async {
    final v2 = await _tryFetchIndexV2(url, additionalSettings);
    if (v2 != null) return v2;
    return _fetchIndexV1(url, additionalSettings);
  }

  Future<_FdroidIndex?> _tryFetchIndexV2(
    String url,
    Map<String, dynamic> additionalSettings,
  ) async {
    final base = url.endsWith('/index-v2.json')
        ? AppSource.stripLastPathSegment(url)
        : url;
    final candidates = <String>[
      '$url${url.endsWith('/index-v2.json') ? '' : '/index-v2.json'}',
      '$base/repo/index-v2.json',
      '$base/fdroid/repo/index-v2.json',
    ];
    for (final candidate in candidates) {
      try {
        final res = await sourceRequest(candidate, additionalSettings);
        if (res.statusCode != 200) continue;
        final index = _parseIndexV2(res);
        if (index != null) return index;
      } catch (_) {
        // Not a usable index-v2.json at this path; try the next variant.
      }
    }
    return null;
  }

  /// Parses an `index-v2.json` response (fdroidserver's current format:
  /// packages keyed by app ID, each with `metadata` plus a hash-keyed
  /// `versions` map holding `file` and `manifest` objects). Returns null if
  /// the body is not a usable v2 index.
  _FdroidIndex? _parseIndexV2(Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final packages = decoded['packages'];
      if (packages is! Map<String, dynamic>) return null;
      final baseUrl = AppSource.stripLastPathSegment(
        (res.request?.url ?? Uri.parse('')).toString(),
      );
      final entries = <_FdroidIndexEntry>[];
      packages.forEach((id, pkg) {
        if (pkg is! Map<String, dynamic>) return;
        final versions = pkg['versions'];
        if (versions is! Map<String, dynamic>) return;
        final versionList = <_FdroidVersion>[];
        versions.forEach((hash, v) {
          if (v is! Map<String, dynamic>) return;
          final manifest = v['manifest'];
          final file = v['file'];
          if (manifest is! Map<String, dynamic> ||
              file is! Map<String, dynamic>) {
            return;
          }
          final versionName = manifest['versionName']?.toString();
          final versionCode = manifest['versionCode'];
          final apkName = file['name']?.toString();
          if (versionName == null ||
              versionCode is! int ||
              apkName == null ||
              apkName.isEmpty) {
            return;
          }
          final nativecode = manifest['nativecode'];
          final channels = v['releaseChannels'];
          versionList.add(
            _FdroidVersion(
              versionName: versionName,
              versionCode: versionCode,
              apkName: apkName.startsWith('/') ? apkName.substring(1) : apkName,
              nativecode: nativecode is List
                  ? nativecode.whereType<String>().toList()
                  : const [],
              added: _parseV2Timestamp(v['added']),
              releaseChannels: channels is List
                  ? channels.whereType<String>().toList()
                  : const [],
            ),
          );
        });
        if (versionList.isEmpty) return;
        versionList.sort((a, b) => b.versionCode.compareTo(a.versionCode));
        final metadata = pkg['metadata'];
        final name =
            _localizedString(metadata is Map ? metadata['name'] : null) ?? id;
        entries.add(
          _FdroidIndexEntry(
            id: id,
            name: name,
            summary:
                _localizedString(
                  metadata is Map ? metadata['summary'] : null,
                ) ??
                '',
            author: _localizedString(
              metadata is Map ? metadata['authorName'] : null,
            ),
            changelog: _localizedString(
              metadata is Map ? metadata['changelog'] : null,
            ),
            versions: versionList,
          ),
        );
      });
      if (entries.isEmpty) return null;
      return _FdroidIndex(baseUrl: baseUrl, entries: entries);
    } catch (_) {
      return null;
    }
  }

  Future<_FdroidIndex> _fetchIndexV1(
    String url,
    Map<String, dynamic> additionalSettings,
  ) async {
    final res = await sourceRequestWithURLVariants(url, additionalSettings);
    if (res.statusCode == 200) {
      return _parseIndexV1(res);
    } else {
      throw getObtainiumHttpError(res);
    }
  }

  _FdroidIndex _parseIndexV1(Response res) {
    final body = parse(res.body);
    final baseUrl = AppSource.stripLastPathSegment(
      (res.request?.url ?? Uri.parse('')).toString(),
    );
    final entries = <_FdroidIndexEntry>[];
    body.querySelectorAll('application').toList().forEach((app) {
      final String? id = app.attributes['id'];
      if (id == null) return;
      final versions = <_FdroidVersion>[];
      for (final pkg in app.querySelectorAll('package')) {
        final versionName = pkg.querySelector('version')?.innerHtml;
        final versionCode = int.tryParse(
          pkg.querySelector('versioncode')?.innerHtml ?? '',
        );
        final apkName = pkg.querySelector('apkname')?.innerHtml;
        if (versionName == null ||
            versionCode == null ||
            apkName == null ||
            apkName.isEmpty) {
          continue;
        }
        final nativecode = (pkg.querySelector('nativecode')?.innerHtml ?? '')
            .trim()
            .split(RegExp(r'\s+'))
            .where((e) => e.isNotEmpty)
            .toList();
        final added = pkg.querySelector('added')?.innerHtml;
        versions.add(
          _FdroidVersion(
            versionName: versionName,
            versionCode: versionCode,
            apkName: apkName,
            nativecode: nativecode,
            added: added != null ? DateTime.tryParse(added) : null,
          ),
        );
      }
      versions.sort((a, b) => b.versionCode.compareTo(a.versionCode));
      entries.add(
        _FdroidIndexEntry(
          id: id,
          name: app.querySelector('name')?.innerHtml ?? id,
          summary: app.querySelector('summary')?.innerHtml ?? '',
          author: app.querySelector('author')?.innerHtml,
          changelog: app.querySelector('changelog')?.innerHtml,
          marketVersionCode: int.tryParse(
            app.querySelector('marketvercode')?.innerHtml ?? '',
          ),
          versions: versions,
        ),
      );
    });
    return _FdroidIndex(baseUrl: baseUrl, entries: entries);
  }

  /// index-v2 metadata strings are locale maps (`{'en-US': '...'}`) or plain
  /// strings; returns the English/plain/first value, or null.
  String? _localizedString(dynamic value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) {
      for (final key in ['en-US', 'en']) {
        final v = value[key];
        if (v is String && v.isNotEmpty) return v;
      }
      for (final v in value.values) {
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  DateTime? _parseV2Timestamp(dynamic added) {
    if (added is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        added > 1e12 ? added : added * 1000,
      );
    }
    if (added is String) return DateTime.tryParse(added);
    return null;
  }

  _FdroidIndexEntry? _findIndexEntry(
    List<_FdroidIndexEntry> entries,
    String appIdOrName,
  ) {
    for (final e in entries) {
      if (e.id == appIdOrName) return e;
    }
    for (final e in entries) {
      if (e.name.toLowerCase() == appIdOrName.toLowerCase()) return e;
    }
    for (final e in entries) {
      if (e.name.toLowerCase().contains(appIdOrName.toLowerCase())) return e;
    }
    return null;
  }

  /// Narrows [versions] to those compatible with this device's ABIs using the
  /// index's nativecode metadata (entries without nativecode are universal).
  /// Falls back to the full list when nothing matches.
  Future<List<_FdroidVersion>> _filterVersionsByArch(
    List<_FdroidVersion> versions,
  ) async {
    if (versions.length <= 1) return versions;
    if (versions.every((v) => v.nativecode.isEmpty)) return versions;
    final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    final compatible = versions
        .where((v) => v.nativecode.isEmpty || v.nativecode.any(abis.contains))
        .toList();
    return compatible.isNotEmpty ? compatible : versions;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      String? appIdOrName = additionalSettings['appIdOrName'];
      final standardUri = Uri.parse(standardUrl);
      if (standardUri.queryParameters['appId'] != null) {
        appIdOrName = standardUri.queryParameters['appId'];
      }
      standardUrl = _removeQueryParamsFromUrl(standardUrl);
      final bool pickHighestVersionCode =
          additionalSettings['pickHighestVersionCode'] == true;
      final bool trySelectingSuggestedVersionCode =
          additionalSettings['trySelectingSuggestedVersionCode'] == true;
      if (appIdOrName == null) {
        throw NoReleasesError();
      }
      additionalSettings['appIdOrName'] = appIdOrName;
      final index = await _fetchIndex(standardUrl, additionalSettings);
      final entry = _findIndexEntry(index.entries, appIdOrName);
      if (entry == null) {
        throw ObtainiumError(tr('appWithIdOrNameNotFound'));
      }
      final releases = entry.versions;
      if (releases.isEmpty) {
        throw NoReleasesError();
      }
      List<_FdroidVersion> selected = [];
      if (trySelectingSuggestedVersionCode && entry.marketVersionCode != null) {
        selected = releases
            .where((v) => v.versionCode == entry.marketVersionCode)
            .toList();
      }
      var candidates = releases;
      if (selected.isEmpty && trySelectingSuggestedVersionCode) {
        // index-v2 has no suggested version code; the toggle instead means
        // "prefer stable" — drop builds marked as non-stable (e.g. Beta).
        final nonStable = releases
            .where(
              (v) =>
                  v.releaseChannels.isNotEmpty &&
                  !v.releaseChannels.any((c) => c.toLowerCase() == 'stable'),
            )
            .toList();
        if (nonStable.isNotEmpty && nonStable.length < releases.length) {
          candidates = releases.where((v) => !nonStable.contains(v)).toList();
        }
      }
      if (selected.isEmpty) {
        if (pickHighestVersionCode) {
          selected = [candidates.first];
        } else {
          final latestVersionName = candidates.first.versionName;
          selected = candidates
              .where((v) => v.versionName == latestVersionName)
              .toList();
        }
      }
      if (selected.isEmpty) {
        throw NoReleasesError();
      }
      selected = await _filterVersionsByArch(selected);
      if (selected.isEmpty) {
        throw NoReleasesError();
      }
      final useVersionCode =
          additionalSettings['useVersionCodeAsOSVersion'] == true;
      return APKDetails(
        useVersionCode
            ? selected.first.versionCode.toString()
            : selected.first.versionName,
        getApkUrlsFromUrls(
          selected.map((v) => '${index.baseUrl}/${v.apkName}').toList(),
        ),
        AppNames(entry.author ?? name, entry.name),
        releaseDate: selected.first.added,
        changeLog: entry.changelog,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
