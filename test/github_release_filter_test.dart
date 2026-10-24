import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/app_sources/github.dart';

void main() {
  const release = {'prerelease': false, 'draft': false};
  const prerelease = {'prerelease': true, 'draft': false};
  const draft = {'prerelease': false, 'draft': true};

  bool excluded(Map<String, bool> r, {bool pre = false, bool drafts = false}) =>
      isReleaseExcluded(r, includePrereleases: pre, includeDrafts: drafts);

  test('skips drafts unless they are included', () {
    expect(excluded(draft), isTrue);
    expect(excluded(draft, drafts: true), isFalse);
  });

  test('keeps the prerelease setting independent of drafts', () {
    expect(excluded(prerelease), isTrue);
    expect(excluded(prerelease, pre: true), isFalse);
    expect(excluded(prerelease, drafts: true), isTrue);
  });

  test('never skips a published release', () {
    expect(excluded(release), isFalse);
  });
}
