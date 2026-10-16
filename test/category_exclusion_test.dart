import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsProvider();
    settings.prefs = await SharedPreferences.getInstance();
  });

  test('defaults to no excluded categories', () {
    expect(settings.categoriesExcludedFromChecks, isEmpty);
  });

  test('round-trips excluded categories', () {
    settings.categoriesExcludedFromChecks = {'Work', 'Games'};
    expect(settings.categoriesExcludedFromChecks, {'Work', 'Games'});
  });

  test('setCategories prunes exclusions for removed categories', () {
    settings.categoriesExcludedFromChecks = {'Work', 'Games'};
    settings.setCategories({'Games': 0xFF000000});
    expect(settings.categoriesExcludedFromChecks, {'Games'});
  });

  test('corrupted stored data resets to empty', () async {
    SharedPreferences.setMockInitialValues({
      'categoriesExcludedFromChecks': 'not json',
    });
    settings = SettingsProvider();
    settings.prefs = await SharedPreferences.getInstance();
    expect(settings.categoriesExcludedFromChecks, isEmpty);
  });
}
