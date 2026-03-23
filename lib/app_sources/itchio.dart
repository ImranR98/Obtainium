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
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://[a-z0-9-]+.${getSourceRegex(hosts)}/[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    var headers = <String, String>{};
    if (additionalSettings['extraHeaders'] != null) {
      headers.addAll(
        Map<String, String>.from(additionalSettings['extraHeaders']),
      );
    }
    return headers.isNotEmpty ? headers : null;
  }

  /// Extracts the CSRF token from the page body (either from an input or JSON).
  String? _findCsrf(String body) {
    RegExp csrfInputRegEx = RegExp(r'name="csrf_token" value="([^"]+)"');
    var match = csrfInputRegEx.firstMatch(body);
    if (match != null) return match.group(1);

    RegExp csrfJsonRegEx = RegExp(r'csrf_token":"([^"]+)"');
    match = csrfJsonRegEx.firstMatch(body);
    return match?.group(1);
  }

  /// Extracts all app titles and download IDs (upload_id or /download/ link IDs) from the page.
  ///
  /// The format of the element is the following:
  /// 1. Release name
  /// 2. Upload ID
  /// 3. Whether it is an Android download
  List<(String, String, bool)> _extractDownload(String body) {
    var parser = parse(body);

    // Results containers
    List<(String, String, bool)> downloads = [];

    // It seems that in every spot, the download buttons are in this container.
    List<Element> uploadDivs = parser.querySelectorAll('div.upload');

    if (uploadDivs.isNotEmpty) {
      for (var uploadDiv in uploadDivs) {
        // Extract the file ID
        Element? nameDiv = uploadDiv.querySelector(
          'div.upload_name strong.name',
        );
        String uploadName = nameDiv?.attributes['title'] ?? 'App title';

        // OS Check
        bool osInfo =
            uploadDiv.querySelector(
              'span.download_platforms span.icon-android',
            ) !=
            null;

        // Try to extract the upload ID; fails if no download button
        var downloadButton = uploadDiv.querySelector('a.download_btn');
        String? uploadId = downloadButton?.attributes['data-upload_id'];

        if (uploadId != null) {
          downloads.add((uploadName, uploadId, osInfo));
        }
      }
    }
    return downloads;
  }

  /// Extracts the version string from the page body.
  ///
  /// Prioritizes info table data, then upload names, then 'Updated' date.
  ///
  /// This method has room for improvement; however, there is no defined
  /// standard on itch.io for declaring assets versions.
  String? _parseVersion(Document document) {
    // Limit our search to specific areas.
    // In the main page, use the section for the game information.
    String searchArea = document.querySelector("div.page_widget")!.innerHtml;

    List<String> supportedVersionStrings = [
      r'[vV](\d+\.\d+(?:\.\d+)*)',
      r'Version (\d+\.\d+(?:\.\d+)*)',
    ];
    Set<String> matches = {};

    for (var versionRegexString in supportedVersionStrings) {
      RegExp versionRegex = RegExp(versionRegexString);
      var regexMatches = versionRegex.allMatches(searchArea);
      for (var regexMatch in regexMatches) {
        matches.add(regexMatch.group(1)!);
      }
    }

    if (matches.isEmpty) return null;

    // Manual comparison, up to 3 digits
    int compareVersions(String v1, String v2) {
      List<int> c1 = v1.split('.').map(int.parse).toList();
      List<int> c2 = v2.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        int p1 = i < c1.length ? c1[i] : 0;
        int p2 = i < c2.length ? c2[i] : 0;
        if (p1 != p2) return p1.compareTo(p2);
      }
      return 0;
    }

    String bestMatch = matches.reduce(
      (a, b) => compareVersions(a, b) > 0 ? a : b,
    );

    return bestMatch;
  }

  /// Extracts the "Updated" date and formats it as YYYYMMDD for versioning.
  String? _getDateVersion(Document document) {
    // Check if we have any "abbr" dates. If now exit early.
    List<Element> abbrElements = document.querySelectorAll('abbr');
    if (abbrElements.isEmpty) return null;

    DateFormat abbrTimeFormat = DateFormat("dd MMMM yyyy '@' HH:mm 'UTC'");
    List<DateTime> abbrDates = [];
    for (var abbrElement in abbrElements) {
      DateTime abbrDate = abbrTimeFormat.parseUtc(
        abbrElement.attributes['title']!,
      );
      abbrDates.add(abbrDate);
    }

    DateTime dateTimeFilter(DateTime a, b) {
      return a.microsecondsSinceEpoch > b.microsecondsSinceEpoch ? a : b;
    }

    DateTime latest = abbrDates.reduce(dateTimeFilter);

    return '${latest.year}${latest.month}${latest.day}';
  }

  /// Extracts the app title from the page title.
  String _parseTitle(Document document) {
    String? title;
    Element titleElement = document.getElementsByTagName('title')[0];
    title = titleElement.text;
    // The title is in format: GAMENAME by GAMEAUTHOR
    // Then, get just the first part
    title = title.split(' by ').first.trim();
    return title;
  }

  /// Resolves the app author from subdomain or author span.
  String _parseAuthor(Document document, String standardUrl) {
    Element? followSpan = document.querySelector(
      'span.on_follow span.full_label',
    );
    var authorMatch = RegExp(r'Follow (.+)').firstMatch(followSpan!.text);
    String? author = authorMatch?.group(1)?.trim();
    return author ?? Uri.parse(standardUrl).host.split('.').first;
  }

  /// Internal method for retrieving CSRF token and cookies for multiple requests.
  Future<(String?, String?)> _setupDownload(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');

    var warmUpRes = await sourceRequest(baseUrl, {...additionalSettings});
    if (warmUpRes.statusCode != 200) return (null, null);

    var csrfToken = _findCsrf(warmUpRes.body)!;
    var cookies = warmUpRes.headers['set-cookie']!;
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
    // Start the setup
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');
    var currentBody = initialBody;

    String? csrfToken, cookies;

    if (initialCsrfToken != null && initialCookies != null) {
      (csrfToken, cookies) = (initialCsrfToken, initialCookies);
    } else {
      (csrfToken, cookies) = await _setupDownload(
        standardUrl,
        additionalSettings,
      );
    }

    // Easy case: download buttons are on the first page.
    // All next if checks are skipped.
    var ids = _extractDownload(currentBody);

    // No buttons have been found, we need to "purchase"
    if (ids.isEmpty) {
      // Step 1: POST to /download_url bypass (e.g. for "Name your price")
      var bypassRes = await sourceRequest(
        '$baseUrl/download_url',
        {
          ...additionalSettings,
          'extraHeaders': {
            'X-Requested-With': 'XMLHttpRequest',
            if (cookies != null) 'Cookie': cookies,
          },
        },
        postBody: {'csrf_token': csrfToken},
      );
      if (bypassRes.statusCode == 200) {
        // The call returns a JSON like: {"url":"download_url"}
        var tokenizedUrl = jsonDecode(bypassRes.body)['url'] as String?;
        if (tokenizedUrl != null) {
          // We are now in GAME_URL/download/HASH
          var downloadPageRes = await sourceRequest(tokenizedUrl, {
            ...additionalSettings,
            'extraHeaders': {if (cookies != null) 'Cookie': cookies},
          });
          if (downloadPageRes.statusCode == 200) {
            // We are now at the download page, with shiny buttons
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
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');

    // Retrieve the body for parsing
    var res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var body = res.body;

    // Retrieve CSRF token and cookies
    var (csrfToken, cookies) = await _setupDownload(
      standardUrl,
      additionalSettings,
    );

    // Metadata extraction
    Document storePage = parse(body);
    String title = _parseTitle(storePage);
    String author = _parseAuthor(storePage, standardUrl);
    String? dateVersion = _getDateVersion(storePage);
    String? version = _parseVersion(storePage);

    // Resolve tokenized download page
    String downloadPageBody = await _getDownloadPageBody(
      standardUrl,
      additionalSettings,
      body,
      csrfToken,
      cookies,
    );

    // Fetch better version from the download page, if any
    Document downloadPage = parse(downloadPageBody);
    dateVersion ??= _getDateVersion(downloadPage);
    version ??= _parseVersion(downloadPage);

    // Rules for defaulting the version
    // 1. Nice version, if found
    // 2. Date of last update
    // 3. Fallback to 'latest'
    version = version ?? dateVersion ?? 'latest';

    // Create all relevant APK links
    List<MapEntry<String, String>> apkLinks = [];

    var downloadIds = _extractDownload(downloadPageBody);

    for (var downloadInfo in downloadIds) {
      var (name, id, isAndroid) = downloadInfo;

      if (isAndroid) {
        // Try retrieving the correct file
        var realName = await _resolveRealFileName(
          id,
          standardUrl,
          additionalSettings,
          csrfToken,
          cookies,
        );
        // Use the real name if possible, otherwise fallback to the one on the page.
        var label = realName ?? name;

        apkLinks.add(MapEntry(label, '$baseUrl/download/$id'));
      }
    }

    if (apkLinks.isEmpty) throw NoAPKError();

    return APKDetails(version, apkLinks, AppNames(author, title));
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
    }

    var fileApiUrl = '$baseUrl/file/$uploadId?as_props=1&source=game_download';
    var downloadRequestRes = await sourceRequest(
      fileApiUrl,
      {
        ...additionalSettings,
        'extraHeaders': {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$baseUrl/download/$uploadId',
          if (cookies != null) 'Cookie': cookies,
        },
      },
      postBody: {'csrf_token': csrfToken},
    );

    if (downloadRequestRes.statusCode != 200) return null;

    // This is a JSON with the url within
    var directUrl = jsonDecode(downloadRequestRes.body)['url'] as String?;
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
    var directUrl = await _retrieveCloudflareUrl(
      uploadId,
      standardUrl,
      additionalSettings,
      csrfToken,
      cookies,
    );

    if (directUrl == null) return null;

    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');
    var streamRes = await sourceRequestStreamResponse('GET', directUrl, {
      'Referer': '$baseUrl?download',
    }, additionalSettings);

    // Peek into the Content-Disposition header
    var response = streamRes.value.value;
    var cd = response.headers.value('content-disposition');
    streamRes.value.key.close(force: true);

    if (cd == null) return null;

    var match = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
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
    var uploadId = assetUrl.split('/').last;

    String? cloudFlareUrl = await _retrieveCloudflareUrl(
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
