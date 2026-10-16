import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/source_provider.dart';

import 'e2e_helpers.dart';

class _FixedVersionSource extends AppSource {
  _FixedVersionSource(this.version, {bool hasTrimSetting = true}) {
    hosts = ['example.com'];
    if (!hasTrimSetting) {
      excludeCommonSettingKeys = ['versionExtractionRegEx', 'matchGroupToUse'];
    }
  }

  final String version;

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    return url;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return APKDetails(version, const [
      MapEntry('app.apk', 'https://example.com/app.apk'),
    ], const AppNames('Example', 'Example'));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('global version trimming regex applies to apps without one', (
    tester,
  ) async {
    if (await skipIfTV()) return;

    await seedPrefs(
      overrides: {'globalVersionExtractionRegEx': r'\d+(\.\d+)+'},
    );
    final sourceProvider = SourceProvider();
    const url = 'https://example.com/app';
    const settings = {
      'appId': 'com.example.app',
      'versionExtractionRegEx': '',
      'matchGroupToUse': '',
    };

    final scraped = _FixedVersionSource('v2.5.5.1 - Pro Latest');
    final trimmed = await sourceProvider.getApp(scraped, url, settings);
    expect(trimmed.latestVersion, '2.5.5.1');

    final own = await sourceProvider.getApp(scraped, url, {
      ...settings,
      'versionExtractionRegEx': r'v[\d.]+',
    });
    expect(own.latestVersion, 'v2.5.5.1');

    final pseudo = _FixedVersionSource('hash-12.34', hasTrimSetting: false);
    final untouched = await sourceProvider.getApp(pseudo, url, const {
      'appId': 'com.example.app',
    });
    expect(untouched.latestVersion, 'hash-12.34');
  });
}
