import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/models/app.dart';
import 'package:obtainium/providers/apps_provider.dart';

App _app({
  required String id,
  String? installedVersion,
  bool disabled = false,
  bool pinned = false,
}) => App(
  id: id,
  url: 'https://example.com/$id',
  author: 'Author',
  name: 'App $id',
  installedVersion: installedVersion,
  latestVersion: '2.0.0',
  preferredApkIndex: 0,
  additionalSettings: const {},
  pinned: pinned,
  disabled: disabled,
);

AppInMemory _aim(App app) => AppInMemory(app, null, null, null);

void main() {
  group('App disabled flag', () {
    test('defaults to false and round-trips through JSON', () {
      final app = _app(id: 'com.example.a');
      expect(app.disabled, isFalse);
      expect(App.fromJson(app.toJson()).disabled, isFalse);

      final disabled = app.copyWith(disabled: true);
      expect(disabled.disabled, isTrue);
      final decoded = App.fromJson(disabled.toJson());
      expect(decoded.disabled, isTrue);
      expect(decoded.id, app.id);
    });

    test('missing JSON field defaults to false', () {
      final json = _app(id: 'com.example.b').toJson()..remove('disabled');
      expect(App.fromJson(json).disabled, isFalse);
    });
  });

  group('AppListBuilder.reorder with disabled apps', () {
    test('moves disabled apps to the bottom when burying is off', () {
      final installed = _aim(_app(id: 'a', installedVersion: '2.0.0'));
      final disabledInstalled = _aim(
        _app(id: 'b', installedVersion: '2.0.0', disabled: true),
      );
      final notInstalled = _aim(_app(id: 'c'));
      final disabledNotInstalled = _aim(_app(id: 'd', disabled: true));

      final reordered = AppListBuilder.reorder(
        [notInstalled, disabledNotInstalled, installed, disabledInstalled],
        false,
        false,
        {},
      );
      expect(reordered.map((e) => e.app.id).toList(), ['c', 'a', 'd', 'b']);
    });

    test(
      'keeps disabled apps below installed and not-installed when burying',
      () {
        final installed = _aim(_app(id: 'a', installedVersion: '2.0.0'));
        final disabledInstalled = _aim(
          _app(id: 'b', installedVersion: '2.0.0', disabled: true),
        );
        final notInstalled = _aim(_app(id: 'c'));
        final disabledNotInstalled = _aim(_app(id: 'd', disabled: true));

        final reordered = AppListBuilder.reorder(
          [notInstalled, disabledNotInstalled, installed, disabledInstalled],
          false,
          true,
          {},
        );
        expect(reordered.map((e) => e.app.id).toList(), ['a', 'c', 'b', 'd']);
      },
    );

    test('keeps pinned disabled apps at the bottom', () {
      final pinned = _aim(
        _app(id: 'a', installedVersion: '2.0.0', pinned: true),
      );
      final disabledPinned = _aim(
        _app(id: 'b', installedVersion: '2.0.0', pinned: true, disabled: true),
      );
      final unpinned = _aim(_app(id: 'c', installedVersion: '2.0.0'));
      final disabled = _aim(
        _app(id: 'd', installedVersion: '2.0.0', disabled: true),
      );

      final reordered = AppListBuilder.reorder(
        [disabled, disabledPinned, unpinned, pinned],
        false,
        false,
        {},
      );
      expect(reordered.map((e) => e.app.id).toList(), ['a', 'c', 'd', 'b']);
    });
  });
}
