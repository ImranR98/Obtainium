import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:xml/xml.dart';

class _OdsRejected extends ObtainiumError {
  _OdsRejected(super.message);
}

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
    changeLogIfAnyIsMarkDown = false;
    canSearch = true;
  }

  @override
  List<SourceSearchProfile> get searchProfiles => [
    SourceSearchProfile(
      id: 'SamsungGalaxyStore/global',
      name: name,
      querySettings: const {'deviceId': 'SM-S948B', 'csc': 'DBT'},
      appSettings: const {'deviceId': 'SM-S948B', 'csc': 'DBT'},
    ),
    SourceSearchProfile(
      id: 'SamsungGalaxyStore/china',
      name: tr('samsungGalaxyStoreCN'),
      querySettings: const {'deviceId': 'SM-S9480', 'csc': 'CHC'},
      appSettings: const {'deviceId': 'SM-S9480', 'csc': 'CHC'},
    ),
  ];

  static const _chinaEndpoint = 'https://cn-ms.galaxyappstore.com/ods.as';
  static const _globalEndpoint = 'https://us-odc.samsungapps.com/ods.as';
  static const _globalHub = 'https://hub-odc.samsungapps.com/ods.as';
  static const _globalCountries = {
    'us-odc.samsungapps.com': 'USA',
    'il-odc.samsungapps.com': 'ISR',
  };
  static const _criticalFields = {
    'GUID',
    'appId',
    'productID',
    'productId',
    'productName',
    'sellerName',
    'version',
    'versionName',
    'versionCode',
    'realContentsSize',
    'contentsSize',
    'contentSize',
    'downLoadURI',
    'downloadURI',
    'needToLogin',
    'installableYN',
    'linkProductYn',
    'countryURL',
    'countryCode',
    'MCC',
    'lastUpdateDate',
    'updateDescription',
    'returnCode',
    'errorCode',
    'errorString',
  };

  bool _isChina(Map<String, String> device) =>
      device['csc'] == 'CHC' && device['mcc'] == '460';

  String _newIdentity() {
    final random = Random.secure();
    return List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  DateTime? _storeDate(String? value) {
    final match = RegExp(r'^(\d{4});(\d{2});(\d{2});$').firstMatch(value ?? '');
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    return year > 0 &&
            date.year == year &&
            date.month == month &&
            date.day == day
        ? date
        : null;
  }

  AppNames _storeNames(
    Map<String, String> fields,
    String packageName, {
    AppNames? fallback,
  }) {
    final author = fields['sellerName']?.trim() ?? '';
    final product = fields['productName']?.trim() ?? '';
    return AppNames(
      author.isNotEmpty ? author : (fallback?.author ?? name),
      fallback != null && fallback.name != packageName
          ? fallback.name
          : product.isNotEmpty
          ? product
          : packageName,
    );
  }

  XmlElement _xmlRoot(Response response, String rootName) {
    try {
      if (response.bodyBytes.isEmpty || response.bodyBytes.length > 2000000) {
        throw const FormatException();
      }
      final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
      final root = document.rootElement;
      if (root.name.local != rootName ||
          document.children.any((node) => node is XmlDoctype)) {
        throw const FormatException();
      }
      return root;
    } on FormatException {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
  }

  XmlElement _odsResponse(Response response, String? requestId) {
    try {
      final root = _xmlRoot(response, 'SamsungProtocol');
      final responses = root.findElements('response').toList();
      if (responses.length != 1) throw const FormatException();
      final protocol = responses.single;
      if (protocol.getAttribute('id') != requestId) {
        throw const FormatException();
      }
      final errors = protocol.findElements('errorInfo').toList();
      if (errors.length != 1) throw const FormatException();
      final strings = errors.single.findElements('errorString').toList();
      if (strings.length != 1 || strings.single.childElements.isNotEmpty) {
        throw const FormatException();
      }
      return protocol;
    } on FormatException {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
  }

  Map<String, String> _odsStatus(XmlElement protocol) {
    final error = protocol
        .findElements('errorInfo')
        .single
        .findElements('errorString')
        .single;
    return {
      'returnCode': protocol.getAttribute('returnCode') ?? '',
      'errorCode': error.getAttribute('errorCode') ?? '',
      'errorString': error.innerText.trim(),
    };
  }

  Map<String, String> _xmlFields(
    Response response,
    String rootName, {
    String? requestId,
  }) {
    final fields = <String, String>{};
    try {
      Iterable<XmlElement> values;
      if (rootName == 'SamsungProtocol') {
        final protocol = _odsResponse(response, requestId);
        fields.addAll(_odsStatus(protocol));
        final lists = protocol.findElements('list').toList();
        if (lists.length > 1) throw const FormatException();
        if (lists.isNotEmpty &&
            lists.single.childElements.any(
              (node) =>
                  node.name.local != 'value' &&
                  _criticalFields.contains(
                    node.getAttribute('name') ?? node.name.local,
                  ),
            )) {
          throw const FormatException();
        }
        // Complex extList branches contain unrelated repeated display components.
        values = lists.isEmpty ? const [] : lists.single.findElements('value');
      } else {
        values = _xmlRoot(response, rootName).childElements;
      }
      return _xmlValues(values, fields);
    } on FormatException {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
  }

  Map<String, String> _xmlValues(
    Iterable<XmlElement> values,
    Map<String, String> fields,
  ) {
    for (final node in values) {
      if (node.childElements.isNotEmpty) throw const FormatException();
      final key = node.getAttribute('name') ?? node.name.local;
      if (fields.containsKey(key)) throw const FormatException();
      fields[key] = key == 'updateDescription'
          ? node.innerText
          : node.innerText.trim();
    }
    return fields;
  }

  Uri _downloadUri(String raw, {bool forLinkedProduct = false}) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasFragment ||
        RegExp(r'[\s\\]').hasMatch(raw) ||
        uri.pathSegments.where((segment) => segment.isNotEmpty).isEmpty ||
        !([
              'samsungapps.com',
              'galaxyappstore.com',
            ].any((host) => uri.host == host || uri.host.endsWith('.$host')) ||
            (forLinkedProduct && uri.host == 'auto-dd.myapp.com'))) {
      throw NoAPKError();
    }
    return uri;
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
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    if (!forAPKDownload &&
        [
          'cn-ms.galaxyappstore.com',
          'hub-odc.samsungapps.com',
          ..._globalCountries.keys,
        ].contains(Uri.parse(url).host) &&
        Uri.parse(url).path == '/ods.as') {
      return {
        'Content-Type': 'text/plain; charset=UTF-8',
        'Accept': 'image/webp',
      };
    }
    return null;
  }

  String _odsEnvelope(
    String method,
    String requestId,
    Map<String, String> params,
    Map<String, String> device,
    String identity,
  ) {
    // Samsung's session/transaction IDs use China standard time.
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final language = _isChina(device) ? 'zh_CN' : 'en_US';
    String pad(int value) => value.toString().padLeft(2, '0');
    final hour = '${now.year}${pad(now.month)}${pad(now.day)}${pad(now.hour)}';
    final digest = sha256.convert(utf8.encode('$identity${hour}GalaxyApps'));
    final transaction = '${now.day}${digest.toString().substring(0, 7)}';
    final builder = XmlBuilder()
      ..processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'SamsungProtocol',
      attributes: {
        'networkType': '0',
        'version2': '0',
        'lang': language,
        'openApiVersion': device['sdkVer']!,
        'deviceModel': device['deviceId']!,
        'deviceMakerName': 'samsung',
        'deviceMakerType': '0',
        'mcc': device['mcc']!,
        'mnc': device['mnc']!,
        'csc': device['csc']!,
        'odcVersion': '4.6.11.4',
        'storeFilter': 'themeDeviceModel=${device['deviceId']}_TM',
        'supportFeature': '',
        'version': '7.9',
        'filter': '1',
        'odcType': '01',
        'storeMode': '0',
        'cacheVersion': '1',
        'systemId': DateTime.now().millisecondsSinceEpoch.toString(),
        'sessionId': '$transaction$hour${pad(now.minute)}',
        'logId': identity,
        'deviceFeature':
            'locale=$language||abi32=armeabi-v7a:armeabi||abi64=arm64-v8a',
        'userMode': '0',
        'asaaMode': '0',
      },
      nest: () {
        builder.element(
          'request',
          attributes: {
            'name': method,
            'id': requestId,
            'numParam': params.length.toString(),
            'transactionId': transaction,
          },
          nest: () {
            for (final entry in params.entries) {
              builder.element(
                'param',
                attributes: {'name': entry.key},
                nest: entry.value,
              );
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString();
  }

  Future<Map<String, String>> _odsRequest(
    String method,
    String requestId,
    Map<String, String> params,
    Map<String, String> device,
    String identity,
    Map<String, dynamic> settings, {
    String endpoint = _chinaEndpoint,
  }) async {
    final response = await _odsHttpRequest(
      method,
      requestId,
      params,
      device,
      identity,
      settings,
      endpoint: endpoint,
    );
    final fields = _xmlFields(
      response,
      'SamsungProtocol',
      requestId: requestId,
    );
    _validateOdsStatus(fields);
    return fields;
  }

  Future<Response> _odsHttpRequest(
    String method,
    String requestId,
    Map<String, String> params,
    Map<String, String> device,
    String identity,
    Map<String, dynamic> settings, {
    required String endpoint,
  }) async {
    final response = await sourceRequest(
      '$endpoint?reqId=$requestId&ot=01&ct=B',
      settings,
      followRedirects: false,
      postBody: _odsEnvelope(method, requestId, params, device, identity),
    ).timeout(const Duration(seconds: 40));
    if (response.statusCode != 200 &&
        (response.statusCode < 400 || response.statusCode > 599)) {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    if (response.statusCode != 200) {
      final error = getObtainiumHttpError(response);
      if (error is RateLimitError) throw error;
      throw _OdsRejected(error.message);
    }
    return response;
  }

  void _validateOdsStatus(Map<String, String> fields) {
    if (!RegExp(r'^-?\d{1,19}$').hasMatch(fields['errorCode'] ?? '') ||
        !RegExp(r'^\d{1,19}$').hasMatch(fields['returnCode'] ?? '')) {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    if (fields['errorCode'] != '0') {
      throw _OdsRejected(tr('samsungGalaxyStoreApiError'));
    }
    if (fields['returnCode'] != '0') {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    if (![
      '',
      'success',
    ].contains((fields['errorString'] ?? '').toLowerCase())) {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
  }

  Future<String> _discoverEndpoint(
    Map<String, String> device,
    String identity,
    Map<String, dynamic> settings,
  ) async {
    final china = _isChina(device);
    final fallback = china ? _chinaEndpoint : _globalEndpoint;
    try {
      final fields = await _odsRequest(
        'countrySearchEx',
        '2300',
        {
          'accountCountry': '',
          'accountMcc': '',
          'latestCountryCode': device['mcc']!,
          'whoAmI': 'odc',
        },
        device,
        identity,
        settings,
        endpoint: china ? _chinaEndpoint : _globalHub,
      );
      final raw = fields['countryURL'] ?? '';
      final uri = Uri.tryParse(raw);
      final country = china ? 'CHN' : _globalCountries[uri?.host];
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          (china && uri.host != 'cn-ms.galaxyappstore.com') ||
          country == null ||
          uri.userInfo.isNotEmpty ||
          uri.port != (uri.scheme == 'http' ? 80 : 443) ||
          uri.path != '/ods.as' ||
          uri.hasQuery ||
          uri.hasFragment ||
          RegExp(r'[\s\\]').hasMatch(raw) ||
          fields['countryCode'] != country ||
          fields['MCC'] != device['mcc']) {
        return fallback;
      }
      return uri.replace(scheme: 'https', port: 443).toString();
    } on RateLimitError {
      rethrow;
    } catch (e) {
      AppLogger.info(
        'Galaxy Store endpoint discovery failed, using $fallback: ${e.runtimeType}',
      );
      return fallback;
    }
  }

  Future<APKDetails> _withStoreDetails(
    APKDetails result,
    String packageName,
    String productId,
    String version,
    int versionCode,
    int size,
    Map<String, String> device,
    String identity,
    Map<String, dynamic> settings,
    String endpoint,
  ) async {
    bool matches(Map<String, String> fields) =>
        fields['GUID'] == packageName &&
        fields['productID'] == productId &&
        fields['version'] == version &&
        int.tryParse(fields['versionCode'] ?? '') == versionCode &&
        int.tryParse(fields['realContentsSize'] ?? '') == size;
    final params = {
      'GUID': packageName,
      'productID': productId,
      'imei': identity,
      'extuk': identity,
      'stduk': identity,
    };
    final mainParams = {
      ...params,
      'productImgWidth': '135',
      'productImgHeight': '135',
      'lkAppIncludedYN': 'Y',
      'predeployed': '0',
      'triggeredFrom': 'detail',
    };
    try {
      final main = await _odsRequest(
        'guidProductDetailExMain',
        '2290',
        mainParams,
        device,
        identity,
        settings,
        endpoint: endpoint,
      );
      if (!matches(main)) return result;
      result = result.copyWith(
        names: _storeNames(main, packageName, fallback: result.names),
      );
      final overview = await _odsRequest(
        'guidProductDetailExOverview',
        '2291',
        {
          ...params,
          'imgWidth': '1080',
          'imgHeight': '1920',
          'runestoneYn': 'N',
          'userAge': '',
        },
        device,
        identity,
        settings,
        endpoint: endpoint,
      );
      if (overview['version'] != version ||
          int.tryParse(overview['realContentsSize'] ?? '') != size ||
          (overview.containsKey('GUID') && overview['GUID'] != packageName) ||
          (overview.containsKey('productID') &&
              overview['productID'] != productId) ||
          (overview.containsKey('versionCode') &&
              int.tryParse(overview['versionCode']!) != versionCode)) {
        return result;
      }
      // Overview omits package/code; stable main responses bind it to this release.
      final after = await _odsRequest(
        'guidProductDetailExMain',
        '2290',
        mainParams,
        device,
        identity,
        settings,
        endpoint: endpoint,
      );
      if (!matches(after)) return result;
      return result.copyWith(
        releaseDate: _storeDate(overview['lastUpdateDate']),
        changeLog: overview['updateDescription']?.trim().isNotEmpty == true
            ? overview['updateDescription']
            : null,
      );
    } catch (e) {
      // Optional store details cannot invalidate an already authorized APK.
      AppLogger.info('Galaxy Store details unavailable: ${e.runtimeType}');
      return result;
    }
  }

  Future<APKDetails> _getOdsDetails(
    String packageName,
    Map<String, String> device,
    Map<String, dynamic> settings,
  ) async {
    final identity = _newIdentity();
    final endpoint = await _discoverEndpoint(device, identity, settings);
    final identifiers = {
      'imei': identity,
      'extuk': identity,
      'stduk': identity,
    };
    final metadata = await _odsRequest(
      'getDownloadInfo',
      '2298',
      {
        'mode': 'directDownload',
        'guid': packageName,
        'productID': '',
        ...identifiers,
        'predeployed': '0',
        'unifiedPaymentYN': 'Y',
        'lkAppIncludedYN': 'Y',
        'betaTestYN': 'N',
        'minorYN': 'N',
        'stateCode': '',
      },
      device,
      identity,
      settings,
      endpoint: endpoint,
    );
    final productId = metadata['productID'] ?? '';
    final version = metadata['version'] ?? '';
    final versionCode = int.tryParse(metadata['versionCode'] ?? '') ?? 0;
    final metadataSize = int.tryParse(metadata['realContentsSize'] ?? '');
    if (metadata['GUID'] != packageName ||
        !RegExp(r'^\d{1,30}$').hasMatch(productId) ||
        version.isEmpty ||
        versionCode <= 0 ||
        (metadata.containsKey('realContentsSize') &&
            (metadataSize == null || metadataSize <= 0)) ||
        (metadata.containsKey('linkProductYn') &&
            !['0', '1'].contains(metadata['linkProductYn'])) ||
        !['0', '1'].contains(metadata['needToLogin']) ||
        !['Y', 'N'].contains(metadata['installableYN'])) {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    if (metadata['needToLogin'] == '1') {
      throw ObtainiumError(tr('samsungGalaxyStoreLoginRequired'));
    }
    if (metadata['installableYN'] != 'Y') throw NoAPKError();
    final linkedProduct = metadata['linkProductYn'] == '1';
    if (linkedProduct && (!_isChina(device) || metadataSize == null)) {
      throw NoAPKError();
    }
    Future<Map<String, String>> mirrorGrant() => _odsRequest(
      'downloadInfoForTencent',
      '2801',
      {
        'GUID': packageName,
        'stduk': identity,
        'extuk': identity,
        'tencentSource': 'general',
        'lastInterfaceName': 'searchProductListEx2Notc',
      },
      device,
      identity,
      settings,
      endpoint: endpoint,
    );
    final authorizationParams = {
      'GUID': packageName,
      'productID': productId,
      ...identifiers,
      'autoUpdateYN': 'N',
      'predeployed': '0',
      'resumeYN': 'N',
    };
    Map<String, String> grant;
    var usedRestoreAuthorization = false;
    var usedMirror = false;
    if (linkedProduct) {
      usedMirror = true;
      grant = await mirrorGrant();
    } else {
      try {
        // versionCode here describes an installed version, not the target APK.
        // Omitting it requests a full package without assuming local installation.
        grant = await _odsRequest(
          'downloadEx2',
          '2311',
          {...authorizationParams, 'dowloadType': 'new', 'deepLinkSource': 'N'},
          device,
          identity,
          settings,
          endpoint: endpoint,
        );
      } on _OdsRejected {
        usedRestoreAuthorization = true;
        try {
          grant = await _odsRequest(
            'downloadForRestore',
            '2316',
            {
              ...authorizationParams,
              'downloadType': 'new',
              'triggeredFrom': 'DETAIL_PAGE',
              'deepLinkSource': '',
            },
            device,
            identity,
            settings,
            endpoint: endpoint,
          );
        } on _OdsRejected {
          if (!_isChina(device) || metadataSize == null) rethrow;
          usedMirror = true;
          grant = await mirrorGrant();
        }
      }
    }
    final size = int.tryParse(grant['contentsSize'] ?? '') ?? 0;
    // Linked replies omit package/product echoes; bind their release to 2298.
    if (((!linkedProduct || grant.containsKey('productID')) &&
            grant['productID'] != productId) ||
        (((usedMirror && !linkedProduct) || grant.containsKey('GUID')) &&
            grant['GUID'] != packageName) ||
        ((!usedRestoreAuthorization ||
                usedMirror ||
                grant.containsKey('version')) &&
            grant['version'] != version) ||
        ((!usedRestoreAuthorization ||
                usedMirror ||
                grant.containsKey('versionCode')) &&
            int.tryParse(grant['versionCode'] ?? '') != versionCode) ||
        size <= 0 ||
        (metadataSize != null && size != metadataSize)) {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    // downLoadURI is the full APK, including universal 32n64 packages.
    // binaryArch does not indicate whether an APK is a delta.
    final apkUrl = _downloadUri(
      grant['downLoadURI'] ?? '',
      forLinkedProduct: linkedProduct,
    );
    return _withStoreDetails(
      APKDetails(
        settings['useVersionCodeAsOSVersion'] == true
            ? versionCode.toString()
            : version,
        [MapEntry('$packageName.apk', apkUrl.toString())],
        _storeNames(metadata, packageName),
      ),
      packageName,
      productId,
      version,
      versionCode,
      size,
      device,
      identity,
      settings,
      endpoint,
    );
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
    [GeneratedFormHeader(label: tr('sectionDeviceOptions'))],
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
  List<List<GeneratedFormItem>> get combinedAppSpecificSettingFormItems {
    final items = super.combinedAppSpecificSettingFormItems;
    final rowIndex = items.indexWhere(
      (row) => row.any(
        (item) =>
            item is GeneratedFormSwitch &&
            item.key == 'shizukuPretendToBeGooglePlay',
      ),
    );
    if (rowIndex == -1) return items;
    final row = items[rowIndex];
    final googlePlay =
        row.firstWhere((item) => item.key == 'shizukuPretendToBeGooglePlay')
            as GeneratedFormSwitch;
    row[row.indexOf(googlePlay)] = GeneratedFormSwitch(
      googlePlay.key,
      label: googlePlay.label,
      value: googlePlay.value,
      disabled: googlePlay.disabled,
      additionalValidators: List.from(googlePlay.additionalValidators),
      mutuallyExclusiveWith: [
        ...googlePlay.mutuallyExclusiveWith,
        'shizukuPretendToBeGalaxyStore',
      ],
    );
    items.insert(rowIndex + 1, [
      GeneratedFormSwitch(
        'shizukuPretendToBeGalaxyStore',
        label: tr('shizukuPretendToBeGalaxyStore'),
        value: false,
        mutuallyExclusiveWith: ['shizukuPretendToBeGooglePlay'],
      ),
    ]);
    return items;
  }

  Future<Map<String, String>> _deviceSettings(
    Map<String, dynamic> additionalSettings,
  ) async {
    final deviceId =
        additionalSettings['deviceId']?.toString().isNotEmpty == true
        ? additionalSettings['deviceId'].toString()
        : 'SM-S948B';
    final csc = additionalSettings['csc']?.toString().isNotEmpty == true
        ? additionalSettings['csc'].toString()
        : 'DBT';
    final isChina = csc.trim().toUpperCase() == 'CHC';
    final mcc = additionalSettings['mcc']?.toString().trim() ?? '';
    final mnc = additionalSettings['mnc']?.toString().trim() ?? '';
    return {
      'deviceId': deviceId,
      'csc': isChina ? 'CHC' : csc,
      'sdkVer': await _getSdkVersion(),
      'mcc': mcc.isEmpty ? (isChina ? '460' : '425') : mcc,
      'mnc': mnc.isEmpty ? (isChina ? '00' : '01') : mnc,
    };
  }

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    if (query.trim().isEmpty) return {};
    final device = await _deviceSettings(querySettings);
    final identity = _newIdentity();
    final endpoint = await _discoverEndpoint(device, identity, querySettings);
    final response = await _odsHttpRequest(
      'searchProductListEx2Notc',
      '2040',
      {
        'keyword': query.trim(),
        'imgWidth': '135',
        'imgHeight': '135',
        'alignOrder': 'bestMatch',
        'startNum': '1',
        'endNum': '20',
        'contentType': 'all',
        'storeContentType': 'Apps',
        'status': '0',
        'qlDomainCode': 'sa',
        'qlDeviceType': 'phone',
        'qlInputMethod': '',
        'imei': identity,
        'stduk': identity,
        'extuk': identity,
        'runestoneYn': 'N',
      },
      device,
      identity,
      querySettings,
      endpoint: endpoint,
    );
    final protocol = _odsResponse(response, '2040');
    _validateOdsStatus(_odsStatus(protocol));
    final results = <String, List<String>>{};
    try {
      for (final list in protocol.findElements('list')) {
        if (list.childElements.any(
          (node) =>
              node.name.local != 'value' &&
              _criticalFields.contains(
                node.getAttribute('name') ?? node.name.local,
              ),
        )) {
          throw const FormatException();
        }
        final fields = _xmlValues(list.findElements('value'), {});
        final package = fields['GUID'] ?? '';
        if (!RegExp(
              r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
            ).hasMatch(package) ||
            fields['playStoreProductYN']?.toUpperCase() == 'Y' ||
            fields['installable']?.toUpperCase() == 'N' ||
            fields['installableYN']?.toUpperCase() == 'N') {
          continue;
        }
        final names = _storeNames(fields, package);
        results.putIfAbsent(
          'https://apps.galaxyappstore.com/detail/$package',
          () => [names.name, names.author],
        );
      }
    } on FormatException {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    return results;
  }

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
    final device = await _deviceSettings(additionalSettings);
    try {
      return await _getStubDetails(
        standardUrl,
        packageName,
        device,
        additionalSettings,
      );
    } on RateLimitError {
      rethrow;
    } catch (e) {
      AppLogger.info(
        'Galaxy Store stub unavailable, trying ODS: ${e.runtimeType}',
      );
      return _getOdsDetails(packageName, device, additionalSettings);
    }
  }

  Future<APKDetails> _getStubDetails(
    String standardUrl,
    String packageName,
    Map<String, String> device,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String vasUrl =
        Uri.parse('https://vas.samsungapps.com/stub/stubDownload.as')
            .replace(
              queryParameters: {
                'appId': packageName,
                ...device,
                'systemId': '1608665720954',
                'abiType': '64',
                'extuk': '0191d6627f38685f',
              },
            )
            .toString();

    final Response response = await sourceRequest(
      vasUrl,
      additionalSettings,
    ).timeout(const Duration(seconds: 40));
    ensureHttpSuccess(response);
    final fields = _xmlFields(response, 'result');
    if (fields['resultCode'] != '1') {
      throw ObtainiumError(tr('samsungGalaxyStoreApiError'));
    }
    final productId = fields['productId'] ?? '';
    final version = fields['versionName'] ?? '';
    final versionCode = int.tryParse(fields['versionCode'] ?? '') ?? 0;
    final size = int.tryParse(fields['contentSize'] ?? '') ?? 0;
    if (fields['appId'] != packageName ||
        !RegExp(r'^\d{1,30}$').hasMatch(productId) ||
        version.isEmpty ||
        versionCode <= 0 ||
        size <= 0) {
      throw ObtainiumError(tr('unexpectedStoreApiResponse'), unexpected: true);
    }
    final apkUrl = _downloadUri(fields['downloadURI'] ?? '');
    final result = APKDetails(
      additionalSettings['useVersionCodeAsOSVersion'] == true
          ? versionCode.toString()
          : version,
      [MapEntry('$packageName.apk', apkUrl.toString())],
      _storeNames(fields, packageName),
    );
    final identity = _newIdentity();
    final String endpoint;
    try {
      endpoint = await _discoverEndpoint(device, identity, additionalSettings);
    } on RateLimitError {
      return result;
    }
    return _withStoreDetails(
      result,
      packageName,
      productId,
      version,
      versionCode,
      size,
      device,
      identity,
      additionalSettings,
      endpoint,
    );
  }
}
