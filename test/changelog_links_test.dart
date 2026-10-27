import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/components/app_list_tile.dart';
import 'package:obtainium/providers/source_provider.dart';

void main() {
  const repo = 'https://github.com/chenxiaolong/BasicSync';
  const release = '$repo/releases/tag/v3.27';
  const blob = '$repo/blob/v3.27';
  const app = App(
    id: 'org.example.app',
    url: repo,
    author: 'chenxiaolong',
    name: 'BasicSync',
    latestVersion: '3.27',
    preferredApkIndex: 0,
    additionalSettings: {},
    releaseUrl: release,
  );

  test('resolves GitHub release links using the raw tag, not the version', () {
    final cases = {
      'CHANGELOG.md': '$blob/CHANGELOG.md',
      './README.md#verifying-digital-signatures':
          '$blob/README.md#verifying-digital-signatures',
      '/docs/CHANGELOG.md?raw=1#changes':
          'https://github.com/docs/CHANGELOG.md?raw=1#changes',
      '/chenxiaolong/BasicSync/issues/42': '$repo/issues/42',
      'docs/../CHANGELOG.md': '$blob/CHANGELOG.md',
      '../CHANGELOG.md': '$blob/CHANGELOG.md',
      '//example.org/notes': 'https://example.org/notes',
      '#changes': '$release#changes',
      '?expanded=true': '$release?expanded=true',
      'https://example.org/notes?raw=1#changes':
          'https://example.org/notes?raw=1#changes',
      'http://example.org/notes': 'http://example.org/notes',
    };
    for (final entry in cases.entries) {
      expect(
        resolveChangeLogLink(app, GitHub(), entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('preserves encoded tags and filenames', () {
    expect(
      resolveChangeLogLink(
        app.copyWith(releaseUrl: '$repo/releases/tag/release%2Fv3.27%2B1'),
        GitHub(),
        './Release%20notes.md',
      ),
      '$repo/blob/release%2Fv3.27%2B1/Release%20notes.md',
    );
  });

  test('honors source overrides without changing other sources', () {
    final custom = app.copyWith(
      url: 'https://git.example.org/owner/repo',
      releaseUrl: 'https://git.example.org/owner/repo/releases/tag/v3.27',
      overrideSource: 'GitHub',
    );
    final source = SourceProvider().getSource(
      custom.url,
      overrideSource: custom.overrideSource,
    );
    expect(
      resolveChangeLogLink(custom, source, 'CHANGELOG.md'),
      'https://git.example.org/owner/repo/blob/v3.27/CHANGELOG.md',
    );
    expect(
      resolveChangeLogLink(
        app,
        SourceProvider().getSource(app.url, overrideSource: 'HTML'),
        'CHANGELOG.md',
      ),
      'https://github.com/CHANGELOG.md',
    );
  });

  test('keeps the origin fallback without a tagged release URL', () {
    for (final releaseUrl in [null, '', '$repo/releases']) {
      expect(
        resolveChangeLogLink(
          app.copyWith(releaseUrl: releaseUrl),
          GitHub(),
          'CHANGELOG.md',
        ),
        'https://github.com/CHANGELOG.md',
      );
    }
  });
}
