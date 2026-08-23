import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

class HuaweiAppGallery extends AppSource {
  @override
  String get name => tr('huaweiAppGallery');

  HuaweiAppGallery() {
    hosts = ['appgallery.huawei.com', 'appgallery.cloud.huawei.com'];
    trustedApkHosts = ['dbankcloud.com', 'dbankcloud.ru'];
  }

  static const String _sessionPrefsKey = 'huaweiAppGallery-session';

  static const String _apiPath = '/hwmarket/api/clientApi';
  static const String _userAgent = 'HiSpace##16.5.1.301##google##Pixel 8 Pro';
  static const String _clientVersion = '16.5.1';
  static const String _clientVersionCode = '160501301';
  static const String _hostCN = 'store-drcn.hispace.dbankcloud.com';
  static const String _hostAsia = 'store-dra.hispace.dbankcloud.com';
  static const String _hostEU = 'store-dre.hispace.dbankcloud.com';
  static const String _hostRU = 'store-drru.hispace.dbankcloud.ru';

  // DR2 (Asia/Africa/Latin America) country codes. CN and RU use their own
  // hosts. Anything not listed here defaults to the Europe host.
  static final Set<String> _dr2Zones =
      'AE AF AG AI AM AO AQ AR AS AW AZ BB BD BF BH BI BJ BL BM BN BO BR BS BT BV BW BY BZ CC CD CF CG CI CK CL CM CO CR CU CV CX DJ DM DO DZ EC EG EH ER ET FJ FK FM GA GD GE GF GH GM GN GP GQ GS GT GU GW GY HK HM HN HT ID IN IO IQ JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LK LR LS LY MA MG MH ML MM MN MO MP MQ MR MS MU MV MW MX MY MZ NA NC NE NF NG NI NP NR NU OM PA PE PF PG PH PK PN PR PS PW PY QA RE RW SA SB SC SD SG SH SL SN SO SR SS ST SV SY SZ TC TD TF TG TH TJ TK TL TM TN TO TT TV TW TZ UG UY UZ VE VG VI VN VU WF WS YE YT ZA ZM ZW'
          .split(' ')
          .toSet();

  static _Session? _session;

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'(/#)?/(app|appdl)/[^/]+',
  );

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    if (Uri.tryParse(url)?.path != _apiPath) {
      return null;
    }
    return {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final location = await _getAppdlRedirect(
      _getDlUrl(standardUrl),
      additionalSettings,
    );
    return location == null ? null : _parseRedirectApkName(location)?.$1;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final sp = SettingsProvider();
      await sp.initializeSettings();
      final mergedSettings = await buildMergedSettings(additionalSettings, sp);
      final cId = standardUrl.split('/').last;
      final info = await _fetchAppDetail(cId, mergedSettings, sp);
      if (info != null) {
        final version = info['versionName'].toString();
        final package = info['package']?.toString();
        final appName = info['name']?.toString() ?? package ?? tr('app');
        final developer = info['developer']?.toString();
        return APKDetails(
          version,
          [MapEntry('${package ?? cId}.apk', info['url'].toString())],
          AppNames(
            developer != null && developer.isNotEmpty ? developer : name,
            appName,
          ),
          releaseDate: DateTime.tryParse(info['releaseDate']?.toString() ?? ''),
        );
      }
      // Fallback: public appdl redirect, parsing package and a YYMMDDHHMM
      // timestamp (used as a pseudo-version) out of the APK filename.
      final location = await _getAppdlRedirect(
        _getDlUrl(standardUrl),
        additionalSettings,
      );
      if (location == null) {
        throw NoReleasesError();
      }
      final parsed = _parseRedirectApkName(location);
      if (parsed == null) throw NoReleasesError();
      final (appId, relDateStr) = parsed;
      final formattedDate =
          '${relDateStr.substring(0, 2)}-${relDateStr.substring(2, 4)}-${relDateStr.substring(4, 6)}-${relDateStr.substring(6, 8)}-${relDateStr.substring(8, 10)}';
      final relDate = DateFormat(
        'yy-MM-dd-HH-mm',
        'en_US',
      ).parseStrict(formattedDate);
      return APKDetails(
        relDateStr,
        [MapEntry('$appId.apk', location)],
        AppNames(name, appId),
        releaseDate: relDate,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  String _hostForZone(String? zone) => switch (zone) {
    'CN' => _hostCN,
    'RU' => _hostRU,
    _ when _dr2Zones.contains(zone) => _hostAsia,
    _ => _hostEU,
  };

  /// POSTs a sorted-key form body to the store API.
  Future<Map<String, dynamic>> _clientApiPost(
    String host,
    Map<String, String> params,
    Map<String, dynamic> mergedSettings,
  ) async {
    final sortedKeys = params.keys.toList()..sort();
    final body = sortedKeys
        .map(
          (k) =>
              '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(params[k]!).replaceAll('%20', '+')}',
        )
        .join('&');
    final apiUrl = 'https://$host$_apiPath';
    final res = await sourceRequest(apiUrl, mergedSettings, postBody: body);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    return decoded;
  }

  Map<String, String> _commonParams(String deviceId) => {
    'ver': '1.1',
    'locale': 'en_US',
    'serviceType': '0',
    'ts': '${DateTime.now().millisecondsSinceEpoch}',
    'net': '1',
    'brand': 'google',
    'manufacturer': 'Google',
    'subBrand': '0',
    'deviceId': deviceId,
    'deviceIdType': '9',
  };

  /// Calls the "home" API method. This is expensive (up to 2s and ~140KB response).
  Future<Map<String, dynamic>> _front2(
    String host,
    int needServiceZone,
    String deviceId,
    Map<String, dynamic> mergedSettings,
  ) => _clientApiPost(host, {
    ..._commonParams(deviceId),
    'method': 'client.front2',
    'version': _clientVersion,
    'versionCode': _clientVersionCode,
    'packageName': 'com.huawei.appmarket',
    'zone': '1',
    'phoneType': 'Pixel 8 Pro',
    'firmwareVersion': '16',
    'isFirstLaunch': '1',
    'oobe': '0',
    'needServiceZone': '$needServiceZone',
  }, mergedSettings);

  /// Runs the front2 handshake once and caches the session in memory and in
  /// prefs. Every handshake gets a fresh random device ID.
  Future<_Session> _ensureSession(
    Map<String, dynamic> mergedSettings,
    SettingsProvider sp, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final session =
          _session ?? _Session.tryParse(sp.getSettingString(_sessionPrefsKey));
      if (session != null && session.isUsable) {
        _session = session;
        return session;
      }
    }

    final random = Random();
    final deviceId = List.generate(
      64,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();

    final probe = await _front2(_hostEU, 1, deviceId, mergedSettings);
    final host = _hostForZone(probe['serviceZone']?.toString());
    String? sign = probe['sign']?.toString();
    if (forceRefresh || sign == null || sign.isEmpty) {
      // No sign from the probe, or force refresh - trying with our zone.
      sign = (await _front2(
        host,
        0,
        deviceId,
        mergedSettings,
      ))['sign']?.toString();
    }
    if (sign == null || sign.isEmpty) {
      throw ObtainiumError(tr('storeHandshakeNoSign', args: [host]));
    }
    final session = _Session(host, sign, deviceId, DateTime.now());
    _session = session;
    sp.setSettingString(_sessionPrefsKey, session.toBlob());
    return session;
  }

  /// Fetches app details from the store API. Returns null on any failure.
  Future<Map<String, dynamic>?> _fetchAppDetail(
    String cId,
    Map<String, dynamic> mergedSettings,
    SettingsProvider sp,
  ) async {
    try {
      String? lastError;
      for (var attempt = 0; attempt < 2; attempt++) {
        final session = await _ensureSession(
          mergedSettings,
          sp,
          forceRefresh: attempt > 0,
        );
        final resp = await _clientApiPost(session.host, {
          ..._commonParams(session.deviceId),
          'method': 'client.appDetailById',
          'sign': session.sign,
          'id': cId,
        }, mergedSettings);
        final rtnCode = resp['rtnCode'];
        if ('$rtnCode' == '0') {
          final detailInfo = resp['detailInfo'];
          if (detailInfo is List && detailInfo.isNotEmpty) {
            final info = detailInfo.first;
            if (info is Map &&
                info['versionName']?.toString().isNotEmpty == true &&
                info['url']?.toString().isNotEmpty == true) {
              return info.cast<String, dynamic>();
            }
          }
          // Unknown/removed app or unexpected payload.
          return null;
        }
        // Non-zero rtnCode - possibly an expired sign. Refresh once and retry.
        lastError = 'rtnCode=$rtnCode rtnDesc=${resp['rtnDesc']}';
      }
      unawaited(
        LogsProvider().add(
          '$name: appDetailById failed ($lastError), using appdl fallback',
          level: LogLevel.warning,
        ),
      );
      return null;
    } catch (e) {
      unawaited(
        LogsProvider().add(
          '$name: store API failed ($e), using appdl fallback',
          level: LogLevel.warning,
        ),
      );
      return null;
    }
  }

  String _getDlUrl(String standardUrl) {
    final dlHost = hosts.length > 1 ? hosts[1] : hosts[0];
    return 'https://$dlHost/appdl/${standardUrl.split('/').last}';
  }

  Future<String?> _getAppdlRedirect(
    String dlUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final res = await sourceRequest(
      dlUrl,
      additionalSettings,
      followRedirects: false,
    );
    if (res.statusCode != 200 && res.statusCode != 302) {
      throw getObtainiumHttpError(res);
    }
    return res.headers['location'];
  }

  /// Redirect APK filenames look like `<appId>.<YYMMDDHHMM>.apk`. Returns
  /// (appId, dateString), or null if the filename doesn't match.
  (String, String)? _parseRedirectApkName(String redirectUrl) {
    final pathSegments = Uri.tryParse(redirectUrl)?.pathSegments;
    if (pathSegments == null || pathSegments.isEmpty) return null;
    final match = RegExp(
      r'^(.+)\.(\d{10})\.apk$',
    ).firstMatch(pathSegments.last);
    return match == null ? null : (match[1]!, match[2]!);
  }
}

/// Cached front2 handshake result, persisted in prefs as a
/// `host|sign|deviceId|createdAtMs` blob.
class _Session {
  const _Session(this.host, this.sign, this.deviceId, this.createdAt);

  static _Session? tryParse(String? blob) {
    final parts = blob?.split('|') ?? [];
    final createdAtMs = parts.length == 4 ? int.tryParse(parts[3]) : null;
    if (parts.length != 4 ||
        parts[0].isEmpty ||
        parts[1].isEmpty ||
        parts[2].isEmpty ||
        createdAtMs == null) {
      return null;
    }
    return _Session(
      parts[0],
      parts[1],
      parts[2],
      DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    );
  }

  final String host;
  final String sign;
  final String deviceId;
  final DateTime createdAt;

  static const Duration _maxAge = Duration(hours: 24);

  /// Sessions expire after [_maxAge] so zone detection re-runs periodically.
  bool get isUsable => DateTime.now().difference(createdAt) <= _maxAge;

  String toBlob() =>
      '$host|$sign|$deviceId|${createdAt.millisecondsSinceEpoch}';
}
