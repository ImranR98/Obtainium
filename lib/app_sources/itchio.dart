import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:html/dom.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:html/parser.dart';

/// AppSource implementation for itch.io.
///
/// Itch.io uses a multi-step dynamic download flow that often requires
/// bypassing "Name your price" lightboxes and resolving tokenized download
/// pages to find direct asset links.
class ItchIO extends AppSource {
  ItchIO() {
    hosts = ['itch.io'];
    name = 'itch.io';
    allowSubDomains = true;
    appIdInferIsOptional = true;
  }

  @override
  String sourceSpecificStandardizeURL(
    String url, {
    bool forSelection = false,
  }) => standardizeUrlWithRegex(
    url,
    subdomainPrefix: r'[a-z0-9-]+\.',
    pathPattern: r'/[^/]+',
  );

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final headers = <String, String>{};
    if (additionalSettings['extraHeaders'] != null) {
      headers.addAll(
        Map<String, String>.from(additionalSettings['extraHeaders']),
      );
    }
    return headers.isNotEmpty ? headers : null;
  }

  /// Extracts the CSRF token from the page body (either from an input or JSON).
  String? _findCsrf(String body) {
    final RegExp csrfInputRegEx = RegExp(r'name="csrf_token" value="([^"]+)"');
    var match = csrfInputRegEx.firstMatch(body);
    if (match != null) return match.group(1);

    final RegExp csrfJsonRegEx = RegExp(r'csrf_token":"([^"]+)"');
    match = csrfJsonRegEx.firstMatch(body);
    return match?.group(1);
  }

  /// Extracts release names and download IDs from the page.
  List<(String, String, bool)> _extractDownload(String body) {
    final parser = parse(body);

    final List<(String, String, bool)> downloads = [];

    // It seems that in every spot, the download buttons are in this container.
    final List<Element> uploadDivs = parser.querySelectorAll('div.upload');

    if (uploadDivs.isNotEmpty) {
      for (var uploadDiv in uploadDivs) {
        // Extract the file ID
        final Element? nameDiv = uploadDiv.querySelector(
          'div.upload_name strong.name',
        );
        final String uploadName = nameDiv?.attributes['title'] ?? 'App title';

        // OS Check
        final bool osInfo =
            uploadDiv.querySelector(
              'span.download_platforms span.icon-android',
            ) !=
            null;

        // Try to extract the upload ID; fails if no download button
        final downloadButton = uploadDiv.querySelector('a.download_btn');
        final String? uploadId = downloadButton?.attributes['data-upload_id'];

        if (uploadId != null) {
          downloads.add((uploadName, uploadId, osInfo));
        }
      }
    }
    return downloads;
  }

  /// Extracts the version string from the page body.
  ///
  /// There is no standard on itch.io for declaring asset versions, so this
  /// falls back through info table data, upload names, then 'Updated' date.
  String? _parseVersion(Document document) {
    // Limit our search to the main game info section.
    final pageWidget = document.querySelector('div.page_widget');
    if (pageWidget == null) return null;

    final String searchArea = pageWidget.innerHtml;

    final List<String> supportedVersionStrings = [
      r'[vV](\d+\.\d+(?:\.\d+)*)',
      r'Version (\d+\.\d+(?:\.\d+)*)',
    ];
    final Set<String> matches = {};

    for (var versionRegexString in supportedVersionStrings) {
      final RegExp versionRegex = RegExp(versionRegexString);
      final regexMatches = versionRegex.allMatches(searchArea);
      for (var regexMatch in regexMatches) {
        matches.add(regexMatch.group(1)!);
      }
    }

    if (matches.isEmpty) return null;

    int compareVersions(String v1, String v2) {
      final List<int> c1 = v1
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      final List<int> c2 = v2
          .split('.')
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      final int maxLen = c1.length > c2.length ? c1.length : c2.length;
      for (int i = 0; i < maxLen; i++) {
        final int p1 = i < c1.length ? c1[i] : 0;
        final int p2 = i < c2.length ? c2[i] : 0;
        if (p1 != p2) return p1.compareTo(p2);
      }
      return 0;
    }

    final String bestMatch = matches.reduce(
      (a, b) => compareVersions(a, b) > 0 ? a : b,
    );

    return bestMatch;
  }

  /// Extracts the "Updated" date and formats it as YYYYMMDD for versioning.
  String? _getDateVersion(Document document) {
    // Check if we have any "abbr" dates. If none exit early.
    final List<Element> abbrElements = document.querySelectorAll('abbr');
    if (abbrElements.isEmpty) return null;

    final DateFormat abbrTimeFormat = DateFormat(
      "dd MMMM yyyy '@' HH:mm 'UTC'",
    );
    final List<DateTime> abbrDates = [];
    for (var abbrElement in abbrElements) {
      final title = abbrElement.attributes['title'];
      if (title == null) continue;
      final DateTime abbrDate = abbrTimeFormat.parseUtc(title);
      abbrDates.add(abbrDate);
    }

    if (abbrDates.isEmpty) return null;

    DateTime dateTimeFilter(DateTime a, DateTime b) {
      return a.microsecondsSinceEpoch > b.microsecondsSinceEpoch ? a : b;
    }

    final DateTime latest = abbrDates.reduce(dateTimeFilter);

    return '${latest.year}${latest.month}${latest.day}';
  }

  /// Extracts the app title from the page title.
  String _parseTitle(Document document) {
    final titleElements = document.getElementsByTagName('title');
    if (titleElements.isEmpty) {
      return '';
    }
    final String title = titleElements.first.text;
    // The title is in format: GAMENAME by GAMEAUTHOR
    // Then, get just the first part
    return title.split(' by ').first.trim();
  }

  /// Resolves the app author from subdomain or author span.
  String _parseAuthor(Document document, String standardUrl) {
    final Element? followSpan = document.querySelector(
      'span.on_follow span.full_label',
    );
    if (followSpan != null) {
      final authorMatch = RegExp(r'Follow (.+)').firstMatch(followSpan.text);
      final String? author = authorMatch?.group(1)?.trim();
      if (author != null) return author;
    }
    return Uri.parse(standardUrl).host.split('.').first;
  }

  /// Internal method for retrieving CSRF token and cookies for multiple requests.
  Future<(String?, String?)> _setupDownload(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');

    final warmUpRes = await sourceRequest(baseUrl, additionalSettings);
    if (warmUpRes.statusCode != 200) return (null, null);

    final csrfToken = _findCsrf(warmUpRes.body);
    final cookies = warmUpRes.headers['set-cookie'];
    return (csrfToken, cookies);
  }

  /// Encapsulates the multi-step bypass flow to retrieve the download page body.
  Future<String> _getDownloadPageBody(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    String initialBody,
    String? initialCsrfToken,
    String? initialCookies,
  ) async {
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');
    var currentBody = initialBody;

    String? csrfToken = initialCsrfToken;
    String? cookies = initialCookies;

    // Easy case: download buttons are on the first page.
    final ids = _extractDownload(currentBody);

    // No buttons found, we need to bypass the "Name your price" lightbox
    if (ids.isEmpty) {
      if (csrfToken == null || cookies == null) {
        (csrfToken, cookies) = await _setupDownload(
          standardUrl,
          additionalSettings,
        );
      }

      // Step 1: POST to /download_url to generate a tokenized URL
      final bypassRes = await sourceRequest(
        '$baseUrl/download_url',
        {
          ...additionalSettings,
          'extraHeaders': {
            'X-Requested-With': 'XMLHttpRequest',
            'Cookie': cookies,
          },
        },
        postBody: {'csrf_token': csrfToken},
      );
      if (bypassRes.statusCode == 200) {
        // The call returns JSON: {"url": "download_url"}
        final tokenizedUrl = jsonDecode(bypassRes.body)['url'] as String?;
        if (tokenizedUrl != null) {
          final downloadPageRes = await sourceRequest(tokenizedUrl, {
            ...additionalSettings,
            'extraHeaders': {'Cookie': cookies},
          });
          if (downloadPageRes.statusCode == 200) {
            currentBody = downloadPageRes.body;
          }
        }
      }
    }

    return currentBody;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    try {
      final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');

      // Retrieve the body for parsing
      final res = await sourceRequest(standardUrl, additionalSettings);
      if (res.statusCode != 200) {
        throw getObtainiumHttpError(res);
      }
      final body = res.body;

      // Retrieve CSRF token and cookies
      final (csrfToken, cookies) = await _setupDownload(
        standardUrl,
        additionalSettings,
      );

      final Document storePage = parse(body);
      final String title = _parseTitle(storePage);
      final String author = _parseAuthor(storePage, standardUrl);
      String? dateVersion = _getDateVersion(storePage);
      String? version = _parseVersion(storePage);

      final String downloadPageBody = await _getDownloadPageBody(
        standardUrl,
        additionalSettings,
        body,
        csrfToken,
        cookies,
      );

      // Fetch better version from the download page, if any
      final Document downloadPage = parse(downloadPageBody);
      dateVersion ??= _getDateVersion(downloadPage);
      version ??= _parseVersion(downloadPage);

      // Rules for defaulting the version
      // 1. Nice version, if found
      // 2. Date of last update
      // 3. Fallback to 'latest'
      version = version ?? dateVersion ?? 'latest';

      // Create all relevant APK links
      final List<MapEntry<String, String>> apkLinks = [];

      final downloadIds = _extractDownload(downloadPageBody);

      for (var downloadInfo in downloadIds) {
        final (name, id, isAndroid) = downloadInfo;

        if (isAndroid) {
          // Try retrieving the correct file
          final realName = await _resolveRealFileName(
            id,
            standardUrl,
            additionalSettings,
            csrfToken,
            cookies,
          );
          // Use the real name if possible, otherwise fallback to the one on the page.
          final label = realName ?? name;

          apkLinks.add(MapEntry(label, '$baseUrl/download/$id'));
        }
      }

      if (apkLinks.isEmpty) throw NoAPKError();

      return APKDetails(version, apkLinks, AppNames(author, title));
    } catch (e) {
      rethrowOrWrapError(e);
    }
  }

  /// Internal method for finding the correct Cloudflare R2 URL for any given
  /// asset.
  Future<String?> _retrieveCloudflareUrl(
    String uploadId,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    String? csrfToken,
    String? cookies,
  ) async {
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');

    if (csrfToken == null || cookies == null) {
      (csrfToken, cookies) = await _setupDownload(
        standardUrl,
        additionalSettings,
      );
      if (csrfToken == null || cookies == null) return null;
    }

    final fileApiUrl =
        '$baseUrl/file/$uploadId?as_props=1&source=game_download';
    final downloadRequestRes = await sourceRequest(
      fileApiUrl,
      {
        ...additionalSettings,
        'extraHeaders': {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$baseUrl/download/$uploadId',
          'Cookie': cookies,
        },
      },
      postBody: {'csrf_token': csrfToken},
    );

    if (downloadRequestRes.statusCode != 200) return null;

    // This is a JSON with the url within
    final directUrl = jsonDecode(downloadRequestRes.body)['url'] as String?;
    return directUrl;
  }

  /// Resolves the real filename of an asset by following the download flow.
  ///
  /// This retrieves the direct download URL (often Cloudflare R2) and
  /// extracts the filename from the Content-Disposition header.
  Future<String?> _resolveRealFileName(
    String uploadId,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    String? csrfToken,
    String? cookies,
  ) async {
    final directUrl = await _retrieveCloudflareUrl(
      uploadId,
      standardUrl,
      additionalSettings,
      csrfToken,
      cookies,
    );

    if (directUrl == null) return null;

    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');
    final streamRes = await sourceRequestStreamResponse('GET', directUrl, {
      'Referer': '$baseUrl?download',
    }, additionalSettings);

    // Peek into the Content-Disposition header
    final response = streamRes.value.value;
    final cd = response.headers.value('content-disposition');
    streamRes.value.key.close(force: true);

    if (cd == null) return null;

    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    return match?.group(1);
  }

  /// Custom itch.io URL fetcher.
  ///
  /// Since the filehost is on Cloudflare R2, we need to resolve the asset URL
  /// after we identified the download.
  @override
  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    // We store the upload ID in the last chunk of the URL.
    // We can then use it to retrive the Cloudflare R2 real URL.
    final uploadId = assetUrl.split('/').last;

    final String? cloudFlareUrl = await _retrieveCloudflareUrl(
      uploadId,
      standardUrl,
      additionalSettings,
      // We are outside of regular fetching, so we need fresh cookies and token
      null,
      null,
    );

    if (cloudFlareUrl != null) return cloudFlareUrl;

    return assetUrl;
  }
}
