import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/providers/source_provider.dart';

import 'e2e_helpers.dart';

/// The ForgeJo (Codeberg) source must expose a ForgeJo-labeled token field and
/// send it as an Authorization header (#2788).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ForgeJo token field and header', (tester) async {
    if (await skipIfTV()) return;
    await launchApp(tester);

    const url = 'https://codeberg.org/example/repo';
    final source = SourceProvider().getSource(url, overrideSource: 'Codeberg');
    final items = source.additionalSourceAppSpecificSettingFormItems
        .expand((row) => row)
        .toList();
    final tokenItem = items.firstWhere((e) => e.key == 'github-creds');
    expect(tokenItem, isA<GeneratedFormTextField>());
    final tokenField = tokenItem as GeneratedFormTextField;
    // ignore: avoid_print
    print('FORGEJO_LABEL ${tokenField.label} help=${tokenField.helpUrl}');
    expect(tokenField.label, 'ForgeJo access token');
    expect(tokenField.helpUrl, contains('forgejo.org'));

    final headers = await source.getRequestHeaders({
      'github-creds': 'test-token',
    }, url);
    // ignore: avoid_print
    print('FORGEJO_AUTH ${headers?['authorization']}');
    expect(headers?['authorization'], 'Token test-token');

    restoreErrorWidgetBuilder();
  });
}
