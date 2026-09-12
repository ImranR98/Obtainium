import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/parser.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/source_provider.dart';

typedef _Session = ({String token, int expiresAt});

// TODO: add search

class Uptodown extends AppSource {
  static const _apiHost = 'www.uptodown.app';
  static const _authPath = '/eapi/auth/token';
  static const _clientVersion = '739';
  static const _userAgent =
      'Dalvik/2.1.0 (Linux; U; Android 16; Pixel 8 Pro Build/BP4A.260205.001)';

  /// Anonymous client auth key. Looks like Base64, but isn't used like one
  static const _hmacKey = 'MDGMXUMdvHJBG/vjdFgmqX6LUdy7ecfwvYNd0gyfOCs=';

  _Session? _session;

  Uptodown() {
    name = 'Uptodown';
    hosts = ['uptodown.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    urlsAlwaysHaveExtension = true;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final uri = Uri.parse(url);
    if (uri.host == _apiHost) {
      final token = _session?.token;
      return {
        'User-Agent': _userAgent,
        'Identificador': 'Uptodown_Android',
        'Identificador-Version': _clientVersion,
        if (uri.path == _authPath)
          'Content-Type': 'application/x-www-form-urlencoded'
        else if (token != null)
          'Authorization': 'Bearer $token',
      };
    }
    return forAPKDownload ? {'User-Agent': _userAgent} : null;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    url = url.replaceFirst(
      RegExp(r'\.([a-z]{2,3})\.uptodown\.', caseSensitive: false),
      '.en.uptodown.',
    );
    return '${standardizeUrlWithRegex(url, subdomainPrefix: r'([^\\.]+\.)+', pathPattern: '')}/android/download';
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    return (await getAppDetailsFromPage(
      standardUrl,
      additionalSettings,
    ))['appId'];
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final appDetails = await getAppDetailsFromPage(
        standardUrl,
        additionalSettings,
      );
      final version = appDetails['version'];
      final appId = appDetails['appId'];
      final fileId = appDetails['fileId'];
      final extension = appDetails['extension'];
      if (version == null || version.isEmpty) {
        throw NoVersionError();
      }
      if (fileId == null) {
        throw NoAPKError();
      }
      final apkUrl = '$standardUrl/$fileId-x';
      if (appId == null) {
        throw NoReleasesError();
      }
      final String appName = appDetails['name'] ?? tr('app');
      final String author = appDetails['author'] ?? name;
      final String? dateStr = appDetails['dateStr'];
      DateTime? relDate;
      if (dateStr != null) {
        relDate = _parseUptodownDate(dateStr);
      }
      return APKDetails(
        version,
        [
          MapEntry(
            '$appId.${(extension != null && extension.isNotEmpty) ? extension : 'apk'}',
            apkUrl,
          ),
        ],
        AppNames(author, appName),
        releaseDate: relDate,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  @override
  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final res = await sourceRequest(assetUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final html = parse(res.body);
    final button = html.querySelector('#detail-download-button');
    final heading = html.querySelector('#detail-app-name');
    final appId =
        button?.attributes['data-app-id'] ?? heading?.attributes['data-code'];
    final fileId =
        button?.attributes['data-file-id'] ??
        heading?.attributes['data-file-id'];
    if (appId == null || fileId == null) {
      throw NoAPKError();
    }
    return _resolveDownload(appId, fileId, additionalSettings);
  }

  Future<Map<String, String?>> getAppDetailsFromPage(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final html = parse(res.body);
    final String? version = html.querySelector('div.version')?.text.trim();
    final String? name = html.querySelector('#detail-app-name')?.text.trim();
    final String? author = html.querySelector('#author-link')?.text.trim();
    final details = <String, String>{};
    for (final row in html.querySelectorAll('#technical-information tr')) {
      final label = row.querySelector('th')?.text.trim().toLowerCase();
      final value = row.querySelectorAll('td').lastOrNull?.text.trim();
      if (label != null && value != null && value.isNotEmpty) {
        details[label] = value;
      }
    }
    final appId = details['package name'];
    final dateStr = details['date'];
    final fileId =
        html
            .querySelector('#detail-download-button')
            ?.attributes['data-file-id'] ??
        html.querySelector('#detail-app-name')?.attributes['data-file-id'];
    final extension = details['file type']?.toLowerCase();
    return Map.fromEntries([
      MapEntry('version', version),
      MapEntry('appId', appId),
      MapEntry('name', name),
      MapEntry('author', author),
      MapEntry('dateStr', dateStr),
      MapEntry('fileId', fileId),
      MapEntry('extension', extension),
    ]);
  }

  Future<_Session> _getSession(
    Map<String, dynamic> settings, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!forceRefresh && _session != null && now < _session!.expiresAt - 60) {
      return _session!;
    }
    return await _auth(settings);
  }

  Future<_Session> _auth(Map<String, dynamic> settings) async {
    final random = Random();
    final identifier = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final signature = Hmac(
      sha256,
      utf8.encode(_hmacKey),
    ).convert(utf8.encode(timestamp)).toString();
    final response = await sourceRequest(
      Uri.https(_apiHost, _authPath, {'identifier': identifier}).toString(),
      settings,
      postBody: Uri(
        queryParameters: {
          'identifier': identifier,
          'id_plataforma': '13',
          'lang': 'en',
          'unixtime': timestamp,
          'hmac': signature,
        },
      ).query,
    );
    if (response.statusCode != 200) throw getObtainiumHttpError(response);
    final decoded = jsonDecode(response.body);
    final token = decoded is Map ? decoded['token'] : null;
    if (token is! String || token.split('.').length != 3) {
      throw ObtainiumError(tr('uptodownInvalidAuthResponse'));
    }
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    final expiresAt = claims is Map ? claims['exp'] as int? : null;
    if (expiresAt == null) {
      throw ObtainiumError(tr('uptodownInvalidAuthResponse'));
    }
    return _session = (token: token, expiresAt: expiresAt);
  }

  Future<String> _resolveDownload(
    String appId,
    String fileId,
    Map<String, dynamic> settings,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await _getSession(settings, forceRefresh: attempt > 0);
      final response = await sourceRequest(
        Uri.https(
          _apiHost,
          '/eapi/apps/$appId/file/$fileId/downloadUrl',
        ).toString(),
        settings,
      );
      if (response.statusCode == 401) continue;
      if (response.statusCode != 200) throw getObtainiumHttpError(response);
      final decoded = jsonDecode(response.body);
      final body = decoded is Map ? decoded : null;
      if (body == null || body['success'] != 1) {
        throw ObtainiumError(tr('uptodownDownloadError'));
      }
      final data = body['data'];
      final downloadUrl = data is Map ? data['downloadURL'] : null;
      if (downloadUrl == null) {
        throw NoAPKError();
      }
      return downloadUrl as String;
    }
    throw ObtainiumError(tr('uptodownDownloadError'));
  }
}

DateTime? _parseUptodownDate(String? dateString) {
  if (dateString == null) return null;
  try {
    return DateFormat('MMM dd, yyyy').parse(dateString);
  } catch (_) {
    AppLogger.error(
      'Failed to parse Uptodown release date (short format): $dateString',
      message:
          'Failed to parse Uptodown release date (short format): $dateString',
    );
  }
  try {
    return DateFormat('MMMM dd, yyyy').parse(dateString);
  } catch (_) {
    AppLogger.error(
      'Failed to parse Uptodown release date: $dateString',
      message: 'Failed to parse Uptodown release date: $dateString',
    );
  }
  return null;
}
