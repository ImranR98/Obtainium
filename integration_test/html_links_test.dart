import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/providers/source_provider.dart';

import 'e2e_helpers.dart';

/// Reproduces #2816: the HTML source must follow a relative `<script src>` and
/// extract an APK URL that sits inside quoted JavaScript followed by more
/// code, without swallowing the trailing characters into the URL.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('extracts clean APK links from relative and quoted JS URLs', (
    tester,
  ) async {
    if (await skipIfTV()) return;
    if (!await serverReachable('html/index.html')) {
      markTestSkipped(
        'Local e2e server not reachable at $e2eBaseUrl; run ./tool/e2e.sh',
      );
      return;
    }

    await clearAppData();
    await launchApp(tester);

    final sourceProvider = SourceProvider();
    const expectedApkUrl = '$e2eBaseUrl/srr230-b6.apk';
    const finalFilter = r'srr[0-9]+-b[0-9]+\.apk';

    // 1. Full chain: relative <script src> intermediate link, then a quoted
    //    APK URL with trailing JS code in the final response.
    const htmlUrl = '$e2eBaseUrl/html/index.html';
    final source = sourceProvider.getSource(htmlUrl, overrideSource: 'HTML');
    final details = await source.getLatestAPKDetails(htmlUrl, {
      'allowInsecure': true,
      'intermediateLink': [
        {
          'customLinkFilterRegex': r'/js/app.[0-9a-f]+.js',
          'matchLinksOutsideATags': true,
          'autoLinkFilterByArch': false,
        },
      ],
      'customLinkFilterRegex': finalFilter,
      'defaultPseudoVersioningMethod': 'APKLinkHash',
    });
    expect(
      details.apkUrls.map((e) => e.value),
      contains(expectedApkUrl),
      reason: 'relative intermediate link and quoted JS URL must resolve',
    );

    // 2. Direct JS body: the URL must stop at the closing quote instead of
    //    keeping the `"}}),e(...` that follows it.
    const jsUrl = '$e2eBaseUrl/js/app.0334504e.js';
    final jsDetails = await source.getLatestAPKDetails(jsUrl, {
      'allowInsecure': true,
      'customLinkFilterRegex': finalFilter,
      'defaultPseudoVersioningMethod': 'APKLinkHash',
    });
    expect(
      jsDetails.apkUrls.map((e) => e.value),
      contains(expectedApkUrl),
      reason: 'trailing JS characters must not become part of the URL',
    );

    restoreErrorWidgetBuilder();
  });
}
