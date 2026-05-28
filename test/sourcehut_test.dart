import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/sourcehut.dart';

void main() {
  group('SourceHut', () {
    late SourceHut source;

    setUp(() {
      source = SourceHut();
    });

    test('standardizes git.sr.ht URLs correctly', () {
      expect(
        source.sourceSpecificStandardizeURL(
            'https://git.sr.ht/~user/repo'),
        equals('https://git.sr.ht/~user/repo'),
      );
      expect(
        source.sourceSpecificStandardizeURL(
            'https://www.git.sr.ht/~user/repo'),
        equals('https://www.git.sr.ht/~user/repo'),
      );
    });

    test('rejects invalid git.sr.ht URLs', () {
      expect(
        () => source.sourceSpecificStandardizeURL('https://github.com/user/repo'),
        throwsA(isA<Error>()),
      );
    });

    test('parses URLs with /refs suffix correctly', () {
      var url = 'https://git.sr.ht/~user/repo/refs';
      var standardized = source.sourceSpecificStandardizeURL(url);
      expect(standardized, equals('https://git.sr.ht/~user/repo'));
    });

    test('SourceHut has correct host', () {
      expect(source.hosts, equals(['git.sr.ht']));
    });

    test('SourceHut shows release date as version toggle', () {
      expect(source.showReleaseDateAsVersionToggle, isTrue);
    });

    test('SourceHut has fallbackToOlderReleases setting', () {
      expect(source.additionalSourceAppSpecificSettingFormItems.isNotEmpty,
          isTrue);
      var fallbackSetting =
          source.additionalSourceAppSpecificSettingFormItems.first;
      expect(
        fallbackSetting.any((item) => item.key == 'fallbackToOlderReleases'),
        isTrue,
      );
    });
  });
}