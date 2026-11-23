import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GitHub Enterprise Server', () {
    test('uses /api/v3 on a custom host', () async {
      final gh = GitHub(hostChanged: true);
      gh.hosts = ['git.example.com'];
      expect(await gh.getAPIHost({}), 'https://git.example.com/api/v3');
    });

    test('uses api.github.com normally', () async {
      final gh = GitHub();
      expect(await gh.getAPIHost({}), 'https://api.github.com');
    });

    test('scopes credentials to the overridden host', () async {
      SharedPreferences.setMockInitialValues({'github-creds': 'global-token'});
      final settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();

      final gh = GitHub(hostChanged: true);
      gh.hosts = ['git.example.com'];

      final perApp = await gh.getSourceConfigValues({
        'github-creds': 'add-page-token',
      }, settings);
      expect(perApp['github-creds'], 'add-page-token');

      final empty = await gh.getSourceConfigValues({}, settings);
      expect(empty['github-creds'], '');
      expect(empty['GHReqPrefix'], '');
      expect(empty['checkRepoRename'], 'false');
    });
  });
}
