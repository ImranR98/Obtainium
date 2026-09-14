import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

import 'e2e_helpers.dart';

/// The ForgeJo (Codeberg) source must expose a ForgeJo token setting, send it
/// as an Authorization header, and only reuse it for codeberg.org (#2788).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ForgeJo token setting and header', (tester) async {
    if (await skipIfTV()) return;
    await launchApp(tester);

    const url = 'https://codeberg.org/example/repo';
    final source = SourceProvider().getSource(url, overrideSource: 'Codeberg');

    // The token moved from the app-specific form to source config (global for
    // codeberg.org, per-app when the host is overridden).
    final appItems = source.additionalSourceAppSpecificSettingFormItems
        .expand((row) => row)
        .toList();
    expect(appItems.where((e) => e.key == 'github-creds'), isEmpty);
    expect(appItems.where((e) => e.key == 'GHReqPrefix'), isEmpty);
    expect(appItems.where((e) => e.key == 'checkRepoRename'), isEmpty);
    expect(source.includeAdditionalOptsInMainSearch, isTrue);

    final tokenItem = source.sourceConfigSettingFormItems.firstWhere(
      (e) => e.key == 'forgejo-creds',
    );
    expect(tokenItem, isA<GeneratedFormTextField>());
    final tokenField = tokenItem as GeneratedFormTextField;
    // ignore: avoid_print
    print('FORGEJO_LABEL ${tokenField.label} help=${tokenField.helpUrl}');
    // This override instance points at codeberg.org, so it is labeled Codeberg.
    expect(tokenField.label, 'Codeberg access token');
    expect(tokenField.helpUrl, contains('forgejo.org'));
    expect(tokenField.password, isTrue);
    expect(
      (SourceProvider().sources
                  .firstWhere((s) => s.sourceIdentifier == 'Codeberg')
                  .sourceConfigSettingFormItems
                  .single
              as GeneratedFormTextField)
          .label,
      'Codeberg access token',
    );

    final sp = SettingsProvider();
    await sp.initializeSettings();
    final originalToken = sp.getSettingString('forgejo-creds');
    sp.setSettingString('forgejo-creds', 'saved-token');
    try {
      // The search dialog prefills the token for codeberg.org only.
      GeneratedFormTextField tokenFor(String searchUrl) =>
          source
                  .searchQuerySettingItemsForUrl(
                    searchUrl,
                    settingsProvider: sp,
                  )
                  .firstWhere((e) => e.key == 'forgejo-creds')
              as GeneratedFormTextField;
      expect(tokenFor('codeberg.org').value, 'saved-token');
      expect(tokenFor('codeberg.org').label, 'Codeberg access token');
      expect(tokenFor('https://codeberg.org/user/repo').value, 'saved-token');
      expect(tokenFor('git.example.com').value, '');
      expect(tokenFor('git.example.com').label, 'ForgeJo access token');

      // codeberg.org requests carry the saved token...
      final defaultHeaders = await source.getRequestHeaders({}, url);
      // ignore: avoid_print
      print('FORGEJO_AUTH ${defaultHeaders?['authorization']}');
      expect(defaultHeaders?['authorization'], 'Token saved-token');

      // ...including when a legacy GHReqPrefix is still stored.
      final legacyPrefixHeaders = await source.getRequestHeaders({
        'GHReqPrefix': 'gh-proxy.com',
      }, url);
      expect(legacyPrefixHeaders?['authorization'], 'Token saved-token');

      // Overridden hosts never receive the codeberg.org token, but do use
      // their own per-app token.
      final customSource = SourceProvider().getSource(
        'https://git.example.com/example/repo',
        overrideSource: 'Codeberg',
      );
      // Overridden instances keep the generic ForgeJo label.
      expect(
        (customSource.sourceConfigSettingFormItems.single
                as GeneratedFormTextField)
            .label,
        'ForgeJo access token',
      );
      final customHeaders = await customSource.getRequestHeaders(
        {},
        'https://git.example.com/example/repo',
      );
      expect(customHeaders?['authorization'], isNull);
      final customTokenHeaders = await customSource.getRequestHeaders({
        'forgejo-creds': 'custom-token',
      }, 'https://git.example.com/example/repo');
      expect(customTokenHeaders?['authorization'], 'Token custom-token');

      // Legacy per-app tokens (GitHub's key) still work for overridden hosts.
      final legacyTokenHeaders = await customSource.getRequestHeaders({
        'github-creds': 'legacy-token',
        'GHReqPrefix': 'gh-proxy.com',
      }, 'https://git.example.com/example/repo');
      expect(legacyTokenHeaders?['authorization'], 'Token legacy-token');
    } finally {
      sp.setSettingString('forgejo-creds', originalToken ?? '');
    }

    restoreErrorWidgetBuilder();
  });
}
