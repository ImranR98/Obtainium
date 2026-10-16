import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rethrowOrWrapError', () {
    test('flags wrapped raw errors as unexpected', () {
      expect(
        () => rethrowOrWrapError(const SocketException('no route to host')),
        throwsA(
          isA<ObtainiumError>()
              .having((e) => e.unexpected, 'unexpected', isTrue)
              .having((e) => e.code, 'code', 'UNEXPECTED'),
        ),
      );
    });

    test('passes typed errors through unchanged', () {
      expect(
        () => rethrowOrWrapError(NoReleasesError()),
        throwsA(
          isA<NoReleasesError>().having(
            (e) => e.unexpected,
            'unexpected',
            isFalse,
          ),
        ),
      );
    });
  });

  group('buildPlaceholderApp', () {
    final sourceProvider = SourceProvider();
    final source = sourceProvider.getSource('https://github.com/gz83/thorium');

    test('builds a placeholder entry with URL name and source author', () {
      final app = sourceProvider.buildPlaceholderApp(
        source,
        'https://github.com/gz83/thorium',
        const {'trackOnly': false},
      );
      expect(app.url, 'https://github.com/gz83/thorium');
      expect(app.name, app.url);
      expect(app.author, source.name);
      expect(app.apkUrls, const [MapEntry('placeholder', 'placeholder')]);
      expect(app.preferredApkIndex, 0);
      expect(app.lastUpdateCheck, isNull);
      expect(app.latestVersion, isNotEmpty);
      expect(RegExp(r'^[0-9a-f]{12}$').hasMatch(app.id), isTrue);
      expect(app.overrideSource, isNull);
    });

    test('temp ID is deterministic per URL and settings', () {
      final a = sourceProvider.buildPlaceholderApp(
        source,
        'https://github.com/gz83/thorium',
        const {'trackOnly': false},
      );
      final b = sourceProvider.buildPlaceholderApp(
        source,
        'https://github.com/gz83/thorium',
        const {'trackOnly': false},
      );
      final c = sourceProvider.buildPlaceholderApp(
        source,
        'https://github.com/gz83/thorium',
        const {'trackOnly': true},
      );
      expect(a.id, b.id);
      expect(a.id, isNot(c.id));
    });

    test('records an override source', () {
      final app = sourceProvider.buildPlaceholderApp(
        source,
        'https://github.com/gz83/thorium',
        const {},
        sourceIsOverriden: true,
      );
      expect(app.overrideSource, source.sourceIdentifier);
    });
  });

  group('allowAddingAppsWithoutCheck setting', () {
    test('defaults to false and round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      settings.prefs = await SharedPreferences.getInstance();
      expect(settings.allowAddingAppsWithoutCheck, isFalse);
      settings.allowAddingAppsWithoutCheck = true;
      expect(settings.allowAddingAppsWithoutCheck, isTrue);
    });
  });
}
