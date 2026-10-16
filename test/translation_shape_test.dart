import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';

Map<String, dynamic> _locale(String name) =>
    jsonDecode(File('assets/translations/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every locale mirrors the template value shapes', () {
    final dir = Directory('assets/translations');
    final template = _locale('en');
    final files = dir.listSync().whereType<File>().where((f) {
      final name = f.uri.pathSegments.last;
      return name.endsWith('.json') &&
          name != 'en.json' &&
          !name.startsWith('package');
    }).toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      final locale =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in template.entries) {
        expect(
          locale.containsKey(entry.key),
          isTrue,
          reason: '${file.path}: missing ${entry.key}',
        );
        expect(
          locale[entry.key] is Map,
          entry.value is Map,
          reason:
              '${file.path}: ${entry.key} is ${locale[entry.key].runtimeType}, '
              'template is ${entry.value.runtimeType}',
        );
      }
    }
  });

  test('the aggregated error cap resolves in a locale with plural forms', () {
    Localization.load(
      const Locale('de'),
      translations: Translations(_locale('de')),
      fallbackTranslations: Translations(_locale('en')),
    );

    final errors = MultiAppMultiError();
    errors.idsByErrorString['first error'] = ['com.example.one'];
    errors.idsByErrorString['second error'] = ['com.example.two'];
    errors.idsByErrorString['third error'] = ['com.example.three'];

    final summary = errors.notificationErrorString(maxChars: 1);
    expect(summary, contains('2'));
    expect(summary, isNot(contains('{}')));
  });
}
