import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/apps_provider.dart';

void main() {
  final primary = Directory('/storage/emulated/0/Android/data/app/files');

  test('selects the external cache that lives on the primary volume', () {
    final chosen = selectPrimaryExternalCache([
      Directory('/storage/6331-6435/Android/data/app/cache'),
      Directory('/storage/emulated/0/Android/data/app/cache'),
    ], primary);
    expect(chosen?.path, '/storage/emulated/0/Android/data/app/cache');
  });

  test('ignores secondary volumes', () {
    final chosen = selectPrimaryExternalCache([
      Directory('/storage/6331-6435/Android/data/app/cache'),
    ], primary);
    expect(chosen, isNull);
  });

  test('returns null when the primary root is unknown', () {
    final chosen = selectPrimaryExternalCache([
      Directory('/storage/emulated/0/Android/data/app/cache'),
    ], null);
    expect(chosen, isNull);
  });
}
