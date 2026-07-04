import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Fetches the latest release from a SourceForge project's RSS feed.
///
/// Version is extracted from path segments after stripping the filename and
/// optionally a subdirectory. The URL should point to the project root
/// (e.g. `https://sourceforge.net/projects/example`).
class SourceForge extends AppSource {
  SourceForge() {
    name = 'SourceForge';
    suppressStandardVersionExtraction = true;
    hosts = ['sourceforge.net'];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final sourceRegex = getSourceRegex(hosts);
    final RegExp standardUrlRegExC = RegExp(
      '^https?://(www\\.)?$sourceRegex/p/.+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegExC.firstMatch(url);
    if (match != null) {
      url =
          'https://${Uri.parse(match.group(0)!).host}/projects/${url.substring(Uri.parse(match.group(0)!).host.length + '/projects/'.length + 1)}';
    }
    final RegExp standardUrlRegExB = RegExp(
      '^https?://(www\\.)?$sourceRegex/projects/[^/]+',
      caseSensitive: false,
    );
    match = standardUrlRegExB.firstMatch(url);
    if (match != null && match.group(0) == url) {
      url = '$url/files';
    }
    final RegExp standardUrlRegExA = RegExp(
      '^https?://(www\\.)?$sourceRegex/projects/[^/]+/files(/.+)?',
      caseSensitive: false,
    );
    match = standardUrlRegExA.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      var standardUri = Uri.parse(standardUrl);
      if (standardUri.pathSegments.length == 2) {
        standardUrl = '$standardUrl/files';
        standardUri = Uri.parse(standardUrl);
      }
      final Response res = await sourceRequest(
        '${standardUri.origin}/${standardUri.pathSegments.sublist(0, 2).join('/')}/rss?path=/',
        additionalSettings,
      );
      if (res.statusCode == 200) {
        final parsedHtml = parse(res.body);
        final allDownloadLinks = parsedHtml
            .querySelectorAll('guid')
            .map((e) => e.innerHtml)
            .where((element) => element.startsWith(standardUrl))
            .toList();
        String? getVersion(String url) {
          try {
            // Strips the last path segment (filename) and optionally another
            // (subdirectory) to extract the version from the remaining segments.
            final segments = url
                .substring(standardUrl.length)
                .split('/')
                .where((element) => element.isNotEmpty)
                .toList();
            if (segments.isNotEmpty) segments.removeLast();
            if (segments.length > 1) segments.removeLast();
            var version = segments.isNotEmpty ? segments.join('/') : null;
            if (version != null) {
              try {
                final extractedVersion = extractVersion(
                  additionalSettings['versionExtractionRegEx'] as String?,
                  additionalSettings['matchGroupToUse'] as String?,
                  version,
                );
                if (extractedVersion != null) {
                  version = extractedVersion;
                }
              } catch (e) {
                if (e is NoVersionError) {
                  version = null;
                } else {
                  rethrowOrWrapError(e);
                }
              }
            }
            return version;
          } catch (e) {
            // Any parsing/extraction failure just skips this release (matches
            // main), rather than aborting the whole update check.
            return null;
          }
        }

        // Compute each release's version exactly once (getVersion runs regex /
        // string work, so the previous repeated calls were wasteful).
        final releasesWithVersions = allDownloadLinks
            .where((element) {
              final lower = element.toLowerCase();
              return lower.endsWith('/download') &&
                  AppSource.isApkOrContainerFile(
                    lower.substring(0, lower.length - '/download'.length),
                  );
            })
            .map((element) => MapEntry(element, getVersion(element)))
            .where((entry) => entry.value != null)
            .toList();
        if (releasesWithVersions.isEmpty) {
          throw NoReleasesError();
        }
        final String? version = releasesWithVersions.first.value;
        if (version == null || version.isEmpty) {
          throw NoVersionError();
        }

        final apkUrlList = releasesWithVersions
            .where((entry) => entry.value == version)
            .map((entry) => entry.key)
            .toList();
        final segments = standardUrl.split('/');
        return APKDetails(
          version,
          getApkUrlsFromUrls(apkUrlList),
          AppNames(name, segments[segments.indexOf('files') - 1]),
        );
      } else {
        throw getObtainiumHttpError(res);
      }
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }
}
