import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/version_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scraped = 'v2.5.5.1 - Pro Latest';

Future<SettingsProvider> _settings([
  Map<String, Object> prefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return SettingsProvider()..prefs = await SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extractVersionWithGlobalDefault', () {
    test('trims with the global regex when the app has none', () async {
      final settings = await _settings({
        'globalVersionExtractionRegEx': r'\d+(\.\d+)+',
      });
      expect(
        extractVersionWithGlobalDefault(
          const {'versionExtractionRegEx': '', 'matchGroupToUse': ''},
          settings,
          _scraped,
        ),
        '2.5.5.1',
      );
    });

    test('uses the global match group', () async {
      final settings = await _settings({
        'globalVersionExtractionRegEx': r'v(\d+(\.\d+)+) - (\w+)',
        'globalMatchGroupToUse': r'$1-$3',
      });
      expect(
        extractVersionWithGlobalDefault(const {}, settings, _scraped),
        '2.5.5.1-Pro',
      );
    });

    test('prefers the app regex and match group', () async {
      final settings = await _settings({
        'globalVersionExtractionRegEx': r'\d+(\.\d+)+',
        'globalMatchGroupToUse': '0',
      });
      expect(
        extractVersionWithGlobalDefault(
          const {'versionExtractionRegEx': r'v(\d+)\.', 'matchGroupToUse': '1'},
          settings,
          _scraped,
        ),
        '2',
      );
    });

    test('keeps the version when the global regex does not match', () async {
      final settings = await _settings({
        'globalVersionExtractionRegEx': r'^\d+$',
      });
      expect(
        extractVersionWithGlobalDefault(const {}, settings, _scraped),
        isNull,
      );
    });

    test('still fails when the app regex does not match', () async {
      final settings = await _settings({
        'globalVersionExtractionRegEx': r'\d+(\.\d+)+',
      });
      expect(
        () => extractVersionWithGlobalDefault(
          const {'versionExtractionRegEx': r'^\d+$'},
          settings,
          _scraped,
        ),
        throwsA(isA<NoVersionError>()),
      );
    });

    test('ignores the global regex for sources without the setting', () async {
      final settings = await _settings({
        'globalVersionExtractionRegEx': r'\d+',
      });
      expect(
        extractVersionWithGlobalDefault(
          const {},
          settings,
          '-1234567890',
          allowGlobalDefault: false,
        ),
        isNull,
      );
    });

    test('does nothing without any regex', () async {
      final settings = await _settings();
      expect(
        extractVersionWithGlobalDefault(const {}, settings, _scraped),
        isNull,
      );
    });
  });

  test('global trimming settings are trimmed and cleared when empty', () async {
    final settings = await _settings();
    settings.globalVersionExtractionRegEx = r'  \d+(\.\d+)+ ';
    settings.globalMatchGroupToUse = ' 0 ';
    expect(settings.globalVersionExtractionRegEx, r'\d+(\.\d+)+');
    expect(settings.globalMatchGroupToUse, '0');
    settings.globalVersionExtractionRegEx = '';
    settings.globalMatchGroupToUse = null;
    expect(
      settings.prefs!.containsKey('globalVersionExtractionRegEx'),
      isFalse,
    );
    expect(settings.prefs!.containsKey('globalMatchGroupToUse'), isFalse);
  });
}
