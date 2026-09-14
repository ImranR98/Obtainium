import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/utils/version_normalization.dart';

void main() {
  group('normalizeVersionForComparison', () {
    test('strips a leading v before a digit', () {
      expect(normalizeVersionForComparison('v1.2.3'), '1.2.3');
      expect(normalizeVersionForComparison('V1.2.3'), '1.2.3');
    });

    test('keeps a leading word that is not just v', () {
      expect(normalizeVersionForComparison('version1.2.3'), 'version.1.2.3');
    });

    test('drops packaging words', () {
      expect(normalizeVersionForComparison('0.9.108 strip'), '0.9.108');
      expect(normalizeVersionForComparison('1.6.15-debug'), '1.6.15');
      expect(normalizeVersionForComparison('1.0.5-release'), '1.0.5');
      expect(normalizeVersionForComparison('2.0.0-universal'), '2.0.0');
      expect(normalizeVersionForComparison('1.0.0-signed'), '1.0.0');
    });

    test('keeps pre-release qualifiers', () {
      expect(normalizeVersionForComparison('1.2.3-beta'), '1.2.3.beta');
      expect(normalizeVersionForComparison('1.2.3-rc1'), '1.2.3.rc.1');
      expect(normalizeVersionForComparison('1.2.3-alpha.1'), '1.2.3.alpha.1');
    });

    test('splits letter/digit runs so beta1 and beta.1 match', () {
      expect(
        normalizeVersionForComparison('1.2.3-beta1'),
        normalizeVersionForComparison('1.2.3-beta.1'),
      );
    });

    test('does not merge different numeric components', () {
      expect(normalizeVersionForComparison('1.2.30'), isNot('1.2.3'));
      expect(normalizeVersionForComparison('1.2.3'), isNot('1.2.30'));
    });

    test('excludes build metadata from the key', () {
      expect(normalizeVersionForComparison('1.0.5+26090410'), '1.0.5');
      expect(normalizeVersionForComparison('1.0.5+build.5'), '1.0.5');
    });

    test('keeps non-ASCII words', () {
      expect(normalizeVersionForComparison('1.2.3稳定版'), '1.2.3.稳定版');
      expect(normalizeVersionForComparison('1.2.3正式版'), '1.2.3.正式版');
    });

    test('normalizes separators and whitespace', () {
      expect(normalizeVersionForComparison('1_2_3'), '1.2.3');
      expect(normalizeVersionForComparison('  1.2.3  '), '1.2.3');
      expect(normalizeVersionForComparison('1-2-3'), '1.2.3');
    });

    test('blank or qualifier-only versions produce an empty key', () {
      expect(normalizeVersionForComparison(''), '');
      expect(normalizeVersionForComparison('   '), '');
      expect(normalizeVersionForComparison('release'), '');
      expect(normalizeVersionForComparison('v'), 'v');
    });
  });

  group('versionsAreCosmeticallyEqual (detection-oriented)', () {
    test('equal for identical and separator-only differences', () {
      expect(versionsAreCosmeticallyEqual('1.2.3', '1.2.3'), isTrue);
      expect(versionsAreCosmeticallyEqual('1_2_3', '1.2.3'), isTrue);
      expect(versionsAreCosmeticallyEqual('1-2-3', '1.2.3'), isTrue);
    });

    test('equal across a leading v', () {
      expect(versionsAreCosmeticallyEqual('v1.2.3', '1.2.3'), isTrue);
      expect(versionsAreCosmeticallyEqual('V1.2.3', 'v1.2.3'), isTrue);
    });

    test('equal when only packaging words differ', () {
      expect(versionsAreCosmeticallyEqual('1.6.15-debug', '1.6.15'), isTrue);
      expect(
        versionsAreCosmeticallyEqual('1.6.15-debug', '1.6.15-release'),
        isTrue,
      );
      expect(versionsAreCosmeticallyEqual('0.9.108 strip', '0.9.108'), isTrue);
    });

    test('equal for letter/digit punctuation differences in qualifiers', () {
      expect(
        versionsAreCosmeticallyEqual('1.2.3-beta1', '1.2.3-beta.1'),
        isTrue,
      );
    });

    test('not equal when a pre-release qualifier is present on one side', () {
      expect(versionsAreCosmeticallyEqual('1.2.3-beta', '1.2.3'), isFalse);
      expect(versionsAreCosmeticallyEqual('1.2.3-rc1', '1.2.3'), isFalse);
      expect(versionsAreCosmeticallyEqual('61.0-beta1', '61.0'), isFalse);
    });

    test('not equal for non-ASCII differences', () {
      expect(versionsAreCosmeticallyEqual('1.2.3稳定版', '1.2.3'), isFalse);
      expect(versionsAreCosmeticallyEqual('1.2.3稳定版', '1.2.3正式版'), isFalse);
    });

    test('build metadata must match when both sides carry it', () {
      expect(versionsAreCosmeticallyEqual('1.0.5+1', '1.0.5+2'), isFalse);
      expect(versionsAreCosmeticallyEqual('1.0.5+1', '1.0.5+1'), isTrue);
      expect(versionsAreCosmeticallyEqual('1.0.5+1', '1.0.5'), isTrue);
      expect(versionsAreCosmeticallyEqual('1.0.5', '1.0.5+1'), isTrue);
    });

    test('not equal for genuinely different or empty versions', () {
      expect(versionsAreCosmeticallyEqual('1.2.3', '1.2.4'), isFalse);
      expect(versionsAreCosmeticallyEqual('', '1.2.3'), isFalse);
      expect(versionsAreCosmeticallyEqual('release', '1.2.3'), isFalse);
      expect(versionsAreCosmeticallyEqual('', ''), isFalse);
    });
  });

  group('installedMatchesRemote (update-decision-oriented)', () {
    test('installed may carry extra packaging words', () {
      expect(
        installedMatchesRemote(installed: '1.6.15-debug', remote: '1.6.15'),
        isTrue,
      );
      expect(
        installedMatchesRemote(installed: '0.9.108 strip', remote: '0.9.108'),
        isTrue,
      );
      expect(
        installedMatchesRemote(
          installed: '1.6.15-debug-universal',
          remote: '1.6.15-debug',
        ),
        isTrue,
      );
    });

    test('remote packaging words must also be on the installed side', () {
      expect(
        installedMatchesRemote(installed: '1.6.15', remote: '1.6.15-debug'),
        isFalse,
      );
      expect(
        installedMatchesRemote(
          installed: '1.6.15-debug',
          remote: '1.6.15-release',
        ),
        isFalse,
      );
      expect(
        installedMatchesRemote(
          installed: '1.6.15-release',
          remote: '1.6.15-debug',
        ),
        isFalse,
      );
      expect(
        installedMatchesRemote(
          installed: '1.6.15-debug',
          remote: '1.6.15-debug-universal',
        ),
        isFalse,
      );
    });

    test('leading v is cosmetic in both directions', () {
      expect(
        installedMatchesRemote(installed: 'v1.2.3', remote: '1.2.3'),
        isTrue,
      );
      expect(
        installedMatchesRemote(installed: '1.2.3', remote: 'v1.2.3'),
        isTrue,
      );
    });

    test('installed-only build metadata is packaging noise', () {
      expect(
        installedMatchesRemote(
          installed: '1.0.5-release+26090410',
          remote: '1.0.5',
        ),
        isTrue,
      );
      expect(
        installedMatchesRemote(installed: '1.0.5+1', remote: '1.0.5'),
        isTrue,
      );
      expect(
        installedMatchesRemote(installed: '1.0.5+build.5', remote: '1.0.5'),
        isTrue,
      );
    });

    test('remote build metadata is a distinct build', () {
      expect(
        installedMatchesRemote(installed: '1.0.5', remote: '1.0.5+1'),
        isFalse,
      );
      expect(
        installedMatchesRemote(installed: '1.0.5+1', remote: '1.0.5+2'),
        isFalse,
      );
      expect(
        installedMatchesRemote(installed: '1.0.5+1', remote: '1.0.5+1'),
        isTrue,
      );
    });

    test('pre-release qualifiers stay significant', () {
      expect(
        installedMatchesRemote(installed: '61.0-beta1', remote: '61.0'),
        isFalse,
      );
      expect(
        installedMatchesRemote(
          installed: '1.2.3-beta1',
          remote: '1.2.3-beta.1',
        ),
        isTrue,
      );
      expect(
        installedMatchesRemote(installed: '1.2.3-beta1', remote: '1.2.3-beta2'),
        isFalse,
      );
    });

    test('non-ASCII words stay significant', () {
      expect(
        installedMatchesRemote(installed: '1.2.3稳定版', remote: '1.2.3'),
        isFalse,
      );
      expect(
        installedMatchesRemote(installed: '1.2.3', remote: '1.2.3稳定版'),
        isFalse,
      );
      expect(
        installedMatchesRemote(installed: '1.2.3稳定版', remote: '1.2.3稳定版'),
        isTrue,
      );
    });

    test('different versions do not match', () {
      expect(
        installedMatchesRemote(installed: '1.6.14', remote: '1.6.15'),
        isFalse,
      );
      expect(
        installedMatchesRemote(installed: '1.2.3', remote: '1.2.30'),
        isFalse,
      );
      expect(
        installedMatchesRemote(installed: 'release', remote: 'release'),
        isFalse,
      );
    });
  });

  group('isPreReleaseMajorMatch', () {
    test('matches a major-only rolling tag to the installed major', () {
      expect(isPreReleaseMajorMatch('v151_beta', '151.0.7922.47'), isTrue);
      expect(isPreReleaseMajorMatch('151_beta', '151.0.7922.47'), isTrue);
      expect(isPreReleaseMajorMatch('v151-beta', '151.0.7922.47'), isTrue);
      expect(isPreReleaseMajorMatch('v151_beta1', '151.0.7922.47'), isTrue);
      expect(isPreReleaseMajorMatch('v151_alpha', '151.0.7922.47'), isTrue);
      expect(isPreReleaseMajorMatch('v151_beta', '151'), isTrue);
    });

    test('does not match a different major', () {
      expect(isPreReleaseMajorMatch('v151_beta', '152.0.0'), isFalse);
      expect(isPreReleaseMajorMatch('v2_beta', '1.9.0'), isFalse);
    });

    test('does not match full versions or major-only versions', () {
      expect(isPreReleaseMajorMatch('v1.2.3', '1.2.3'), isFalse);
      expect(isPreReleaseMajorMatch('v151', '151.0.0'), isFalse);
      expect(isPreReleaseMajorMatch('v151_beta_extra', '151.0.0'), isFalse);
    });
  });
}
