import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// CoolApk app source.
///
/// The client version and device fingerprint are locked to a specific CoolAPK
/// client release. If the server enforces minimum-version requirements, these
/// must be periodically updated.
/// Token generation adapted from https://github.com/XiaoMengXinX/FuckCoolapkTokenV2
/// and https://github.com/Coolapk-UWP/Coolapk-UWP
class CoolApk extends AppSource {
  CoolApk() {
    name = tr('coolApk');
    hosts = ['coolapk.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    allowOverride = false;
    inferAppIdFromUrlPath = true;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'(www\.)?',
    pathPattern: r'/apk/[^/]+',
  );

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
      const String apiUrl = 'https://api2.coolapk.com';

      final detailUrl = '$apiUrl/v6/apk/detail?id=$appId';
      final res = await sourceRequest(detailUrl, additionalSettings);

      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(res.body);
      } catch (e) {
        unawaited(
          LogsProvider().add(
            'Failed to decode JSON response: $e',
            level: LogLevel.error,
          ),
        );
        throw NoReleasesError();
      }
      if (json['status'] == -2 || json['data'] == null) {
        throw NoReleasesError();
      }

      final detail = json['data'];
      final String version = detail['apkversionname'].toString();
      final String appName = detail['title'].toString();
      final String author = detail['developername']?.toString() ?? 'CoolApk';
      final String changelog = detail['changelog']?.toString() ?? '';
      int? releaseDate;
      final lastUpdate = detail['lastupdate'];
      if (lastUpdate is int) {
        releaseDate = lastUpdate * 1000;
      } else if (lastUpdate != null) {
        final parsed = int.tryParse(lastUpdate.toString());
        releaseDate = parsed != null ? parsed * 1000 : null;
      }
      final String aid = detail['id'].toString();

      final String apkUrl = await _getLatestApkUrl(
        apiUrl,
        appId,
        aid,
        version,
        additionalSettings,
      );
      if (apkUrl.isEmpty) {
        throw NoAPKError();
      }

      final String apkName = '${appId}_$version.apk';

      return APKDetails(
        version,
        [MapEntry(apkName, apkUrl)],
        AppNames(author, appName),
        releaseDate: releaseDate != null
            ? DateTime.fromMillisecondsSinceEpoch(releaseDate)
            : null,
        changeLog: changelog,
      );
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  Future<String> _getLatestApkUrl(
    String apiUrl,
    String appId,
    String aid,
    String version,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String url = '$apiUrl/v6/apk/download?pn=$appId&aid=$aid';
    final res = await sourceRequest(
      url,
      additionalSettings,
      followRedirects: false,
    );
    if (res.statusCode >= 300 && res.statusCode < 400) {
      final String location = res.headers['location'] ?? '';
      return location;
    }
    return '';
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final tokenPair = _getToken();
    return {
      'User-Agent':
          'Dalvik/2.1.0 (Linux; U; Android 9; MI 8 SE MIUI/9.5.9) (#Build; Xiaomi; MI 8 SE; PKQ1.181121.001; 9) +CoolMarket/12.4.2-2208241-universal',
      'X-App-Id': 'com.coolapk.market',
      'X-Requested-With': 'XMLHttpRequest',
      'X-Sdk-Int': '30',
      'X-App-Mode': 'universal',
      'X-App-Channel': 'coolapk',
      'X-Sdk-Locale': 'zh-CN',
      'X-App-Version': '12.4.2',
      'X-Api-Supported': '2208241',
      'X-App-Code': '2208241',
      'X-Api-Version': '12',
      'X-App-Device': tokenPair['deviceCode']!,
      'X-Dark-Mode': '0',
      'X-App-Token': tokenPair['token']!,
    };
  }

  Map<String, String> _getToken() {
    final rand = Random();

    String randHexString(int n) => List.generate(
      n,
      (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join().toUpperCase();

    String randMacAddress() => List.generate(
      6,
      (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(':');

    final String aid = randHexString(16);
    final String mac = randMacAddress();
    const manufactor = 'Google';
    const brand = 'Google';
    const model = 'Pixel 5a';
    const buildNumber = 'SQ1D.220105.007';

    final String deviceCode = base64.encode(
      '$aid; ; ; $mac; $manufactor; $brand; $model; $buildNumber'.codeUnits,
    );

    final String timeStamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final String base64TimeStamp = base64.encode(timeStamp.codeUnits);
    final String md5TimeStamp = md5.convert(timeStamp.codeUnits).toString();
    final String md5DeviceCode = md5.convert(deviceCode.codeUnits).toString();

    final String token =
        'token://com.coolapk.market/dcf01e569c1e3db93a3d0fcf191a622c?$md5TimeStamp\$$md5DeviceCode&com.coolapk.market';
    final String base64Token = base64.encode(token.codeUnits);
    final String md5Base64Token = md5.convert(base64Token.codeUnits).toString();
    final String md5Token = md5.convert(token.codeUnits).toString();

    final String bcryptSalt =
        '\$2a\$10\$${base64TimeStamp.substring(0, 14)}/${md5Token.substring(0, 6)}u';
    final String bcryptResult = BCrypt.hashpw(md5Base64Token, bcryptSalt);
    final String reBcryptResult = bcryptResult.replaceRange(0, 3, '\$2y');
    final String finalToken = 'v2${base64.encode(reBcryptResult.codeUnits)}';

    return {'deviceCode': deviceCode, 'token': finalToken};
  }
}
