import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form_model.dart';

class SamsungGalaxyStore extends AppSource {
  @override
  String get name => 'Samsung Galaxy Store';

  SamsungGalaxyStore() {
    hosts = [
      'galaxystore.samsung.com',
      'apps.samsung.com',
      'apps.samsung.cn',
      'galaxyappstore.com',
      'apps.galaxyappstore.com',
    ];
    inferAppIdFromUrlPath = false;
    showReleaseDateAsVersionToggle = true;
  }

  DateTime? _parseReleaseDateFromUrl(String apkUrl) {
    final filename = Uri.parse(
      apkUrl,
    ).pathSegments.where((s) => s.isNotEmpty).last;
    final match = RegExp(r'(\d{14,17})').firstMatch(filename);
    if (match == null) return null;
    final ts = match.group(1)!;
    return DateTime(
      int.parse(ts.substring(0, 4)),
      int.parse(ts.substring(4, 6)),
      int.parse(ts.substring(6, 8)),
      int.parse(ts.substring(8, 10)),
      int.parse(ts.substring(10, 12)),
      int.parse(ts.substring(12, 14)),
      ts.length >= 17 ? int.parse(ts.substring(14, 17)) : 0,
    );
  }

  Future<String> _getSdkVersion() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt.toString();
    } catch (e) {
      return '37';
    }
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final uri = Uri.parse(url);
    final host = uri.host;
    final validHosts = hosts + hosts.map((h) => 'www.$h').toList();
    if (!validHosts.contains(host)) {
      throw InvalidURLError(name)..url = url;
    }
    String? appId;
    if (uri.queryParameters.containsKey('appId')) {
      appId = uri.queryParameters['appId'];
    } else {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2) {
        appId = segments.last;
      } else if (segments.isNotEmpty) {
        appId = segments.last;
      }
    }
    if (appId == null || appId.isEmpty) {
      throw InvalidURLError(name)..url = url;
    }
    return 'https://apps.galaxyappstore.com/detail/$appId';
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final uri = Uri.parse(standardUrl);
    if (uri.queryParameters.containsKey('appId')) {
      return uri.queryParameters['appId'];
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      return segments.last;
    }
    return null;
  }

  @override
  List<List<GeneratedFormItem>>
  get additionalSourceAppSpecificSettingFormItems => [
    [
      GeneratedFormTextField(
        'deviceId',
        label: tr('deviceModel'),
        required: false,
        hint: 'SM-S948B',
      ),
    ],
    [
      GeneratedFormTextField(
        'csc',
        label: tr('cscCode'),
        required: false,
        hint: 'DBT',
      ),
    ],
  ];

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final uri = Uri.parse(standardUrl);
    final String packageName;
    if (uri.queryParameters.containsKey('appId')) {
      packageName = uri.queryParameters['appId']!;
    } else {
      packageName = uri.pathSegments.where((s) => s.isNotEmpty).last;
    }
    final deviceId =
        additionalSettings['deviceId']?.toString().isNotEmpty == true
        ? additionalSettings['deviceId'].toString()
        : 'SM-S948B';
    final csc = additionalSettings['csc']?.toString().isNotEmpty == true
        ? additionalSettings['csc'].toString()
        : 'DBT';

    final sdkVer = await _getSdkVersion();

    final String vasUrl =
        Uri.parse('https://vas.samsungapps.com/stub/stubDownload.as')
            .replace(
              queryParameters: {
                'appId': packageName,
                'deviceId': deviceId,
                'mcc': '425',
                'mnc': '01',
                'csc': csc,
                'sdkVer': sdkVer,
                'systemId': '1608665720954',
                'abiType': '64',
                'extuk': '0191d6627f38685f',
              },
            )
            .toString();

    final Response response = await sourceRequest(vasUrl, additionalSettings);
    if (response.statusCode != 200) {
      throw getObtainiumHttpError(response);
    }
    final String body = response.body;

    final resultCode = RegExp(
      r'<resultCode>(\d+)</resultCode>',
    ).firstMatch(body)?.group(1);
    if (resultCode != '1') {
      final msg = RegExp(
        r'<resultMsg>([^<]*)</resultMsg>',
      ).firstMatch(body)?.group(1);
      throw ObtainiumError(msg ?? tr('samsungGalaxyStoreApiError'));
    }

    final apkMatch = RegExp(
      r'<downloadURI><!\[CDATA\[([^\]]+)\]\]></downloadURI>',
    ).firstMatch(body);
    if (apkMatch == null) {
      throw NoAPKError()..url = standardUrl;
    }
    final String apkUrl = apkMatch.group(1)!;

    final versionMatch = RegExp(
      r'<versionName>([^<]+)</versionName>',
    ).firstMatch(body);
    if (versionMatch == null) {
      throw NoVersionError();
    }
    final String version = versionMatch.group(1)!;

    final nameMatch = RegExp(
      r'<productName>(?:<!\[CDATA\[)?([^<\]]+)(?:\]\]>)?</productName>',
    ).firstMatch(body);
    final String appName = nameMatch?.group(1)?.trim() ?? packageName;

    final DateTime? releaseDate = _parseReleaseDateFromUrl(apkUrl);

    return APKDetails(
      version,
      [MapEntry('$packageName.apk', apkUrl)],
      AppNames(name, appName),
      releaseDate: releaseDate,
    );
  }
}
