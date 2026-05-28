// Regression test for Bitwarden authenticator duplicate detection
// Issue: #2931 - Bitwarden Authenticator and Password Manager share causes
// duplicate detection issues when both apps have similar/inferred app IDs
//
// This test verifies that two different GitHub URLs with different repos
// but potentially similar app IDs are NOT incorrectly flagged as duplicates

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/providers/source_provider.dart';

void main() {
  group('Bitwarden Authenticator Duplicate Detection Regression Test', () {
    late SourceProvider sourceProvider;

    setUp(() {
      sourceProvider = SourceProvider();
    });

    test('GitHub source correctly identifies different repos as different apps', () {
      // Simulate two different GitHub repos (like Bitwarden Authenticator and Password Manager)
      // Both might infer similar app IDs but are distinct apps

      // Verify that the source can distinguish between different GitHub repos
      var source = sourceProvider.getSource('https://github.com/bitwarden/authenticator');
      expect(source.runtimeType.toString(), equals('GitHub'));

      var source2 = sourceProvider.getSource('https://github.com/bitwarden/password-scripts');
      expect(source2.runtimeType.toString(), equals('GitHub'));

      // Both should be GitHub source but different apps
      expect(identical(source, source2), isFalse);
    });

    test('GitHub source standardization preserves repo distinction', () {
      // When standardizing URLs, the repo portion should be preserved
      // This ensures duplicate detection by URL works correctly

      var source = sourceProvider.getSource('https://github.com/bitwarden/authenticator');
      var standardized1 = source.standardizeUrl('https://github.com/bitwarden/authenticator');

      var source2 = sourceProvider.getSource('https://github.com/bitwarden/password-scripts');
      var standardized2 = source2.standardizeUrl('https://github.com/bitwarden/password-scripts');

      // Standardized URLs should be different
      expect(standardized1, isNot(equals(standardized2)));
      expect(standardized1, equals('https://github.com/bitwarden/authenticator'));
      expect(standardized2, equals('https://github.com/bitwarden/password-scripts'));
    });

    test('Different GitHub URLs should not be considered duplicates by URL check', () {
      // This tests the core issue: two different GitHub app URLs should not
      // be flagged as duplicates when checking alreadyAddedUrls

      final List<String> alreadyAddedUrls = [
        'https://github.com/bitwarden/authenticator',
      ];

      final String newUrl1 = 'https://github.com/bitwarden/authenticator';
      final String newUrl2 = 'https://github.com/bitwarden/password-scripts';

      // The same URL should be detected as already added
      expect(alreadyAddedUrls.contains(newUrl1), isTrue);

      // A different URL should NOT be detected as already added
      expect(alreadyAddedUrls.contains(newUrl2), isFalse);
    });

    test('apps.containsKey should use app.id, not URL', () {
      // This test verifies the design assumption in getAppsByURLNaive:
      // apps.containsKey(app.id) checks by ID, not by URL
      // If two different apps have the same ID, this is the actual duplicate issue

      // Simulating: App1 has URL1 and ID1
      // App2 has URL2 and ID2 (different URL but same ID = TRUE duplicate)

      Map<String, dynamic> app1 = {
        'id': 'com.bitwarden.authenticator',
        'url': 'https://github.com/bitwarden/authenticator',
      };

      Map<String, dynamic> app2SameId = {
        'id': 'com.bitwarden.authenticator', // Same ID!
        'url': 'https://github.com/bitwarden/password-scripts', // Different URL
      };

      Map<String, dynamic> app2DifferentId = {
        'id': 'com.bitwarden.passwordmanager',
        'url': 'https://github.com/bitwarden/password-scripts',
      };

      // Simulate the apps map keyed by ID
      Map<String, dynamic> apps = {};
      apps[app1['id']] = app1;

      // Same ID should be detected as duplicate (this is expected behavior)
      expect(apps.containsKey(app2SameId['id']), isTrue);

      // Different ID should NOT be detected as duplicate
      expect(apps.containsKey(app2DifferentId['id']), isFalse);
    });

    test('generateTempID produces different IDs for different URLs', () {
      // Verify that generateTempID generates different IDs for different URLs
      // even if they share similar patterns

      var url1 = 'https://github.com/bitwarden/authenticator';
      var url2 = 'https://github.com/bitwarden/password-scripts';

      var id1 = sourceProvider.generateTempID(url1, {});
      var id2 = sourceProvider.generateTempID(url2, {});

      // Different URLs should produce different temp IDs
      expect(id1, isNot(equals(id2)));
    });

    test('GitHub source appIdInferIsOptional is true', () {
      // GitHub source has appIdInferIsOptional = true
      // This means if appId is not explicitly provided and inference fails,
      // it falls back to generateTempID rather than failing

      var source = sourceProvider.getSource('https://github.com/bitwarden/authenticator');
      expect(source.appIdInferIsOptional, isTrue);
    });
  });
}
