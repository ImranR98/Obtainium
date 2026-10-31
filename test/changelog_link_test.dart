import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/github.dart';
import 'package:obtainium/app_sources/gitlab.dart';
import 'package:obtainium/models/app.dart';

void main() {
  App app({
    required String url,
    String latestVersion = 'v3.27',
    String? releaseUrl,
  }) => App(
    id: 'com.example.app',
    url: url,
    author: 'Example',
    name: 'Example',
    latestVersion: latestVersion,
    apkUrls: const [],
    preferredApkIndex: 0,
    additionalSettings: const {},
    releaseUrl: releaseUrl,
  );

  test('GitHub resolves relative links against the release tag', () {
    final link = GitHub().resolveChangeLogLink(
      app(
        url: 'https://github.com/user/repo',
        releaseUrl: 'https://github.com/user/repo/releases/tag/v3.27',
      ),
      'CHANGELOG.md',
    );

    expect(link, 'https://github.com/user/repo/blob/v3.27/CHANGELOG.md');
  });

  test('GitHub falls back to the latest version without a release URL', () {
    final link = GitHub().resolveChangeLogLink(
      app(url: 'https://github.com/user/repo', latestVersion: 'v2.1.0'),
      'docs/CHANGELOG.md',
    );

    expect(link, 'https://github.com/user/repo/blob/v2.1.0/docs/CHANGELOG.md');
  });

  test('GitHub leaves absolute links unchanged', () {
    final link = GitHub().resolveChangeLogLink(
      app(url: 'https://github.com/user/repo'),
      'https://example.com/changelog',
    );

    expect(link, 'https://example.com/changelog');
  });

  test('GitLab resolves relative links against the release tag', () {
    final link = GitLab().resolveChangeLogLink(
      app(
        url: 'https://gitlab.com/group/project',
        releaseUrl: 'https://gitlab.com/group/project/-/releases/v3.27',
      ),
      'CHANGELOG.md',
    );

    expect(link, 'https://gitlab.com/group/project/-/blob/v3.27/CHANGELOG.md');
  });

  test('fragments and protocol-relative links are left usable', () {
    final github = GitHub();
    final appWithUrl = app(url: 'https://github.com/user/repo');

    expect(github.resolveChangeLogLink(appWithUrl, '#notes'), '#notes');
    expect(
      github.resolveChangeLogLink(appWithUrl, '//example.com/file'),
      'https://example.com/file',
    );
  });
}
