import 'dart:convert';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

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
      r'^https?://([a-z0-9\-]+\.itch\.io/[a-z0-9\-]+)',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return 'https://${match.group(1)!}';
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    var headers = <String, String>{};
    if (additionalSettings['tempHeaders'] != null) {
      headers.addAll(
        Map<String, String>.from(additionalSettings['tempHeaders']),
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

  /// Extracts all download IDs (upload_id or /download/ link IDs) from the page.
  List<String> _extractDownloadIds(String body) {
    var ids = <String>{};
    RegExp uploadIdRegEx = RegExp(r'data-upload_id="(\d+)"');
    for (var m in uploadIdRegEx.allMatches(body)) {
      ids.add(m.group(1)!);
    }
    RegExp downloadLinkRegEx = RegExp(r'/download/(\d+)');
    for (var m in downloadLinkRegEx.allMatches(body)) {
      ids.add(m.group(1)!);
    }
    return ids.toList();
  }

  /// Resolves the real filename of an asset by following the download flow.
  ///
  /// This retrieves the direct download URL (often Cloudflare R2) and
  /// extracts the filename from the Content-Disposition header.
  Future<String?> _resolveRealFileName(
    String uploadId,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    String? initialCookies,
  ) async {
    try {
      final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');
      var res1 = await sourceRequest(
        '$baseUrl/download/$uploadId',
        {
          ...additionalSettings,
          if (initialCookies != null) 'tempHeaders': {'Cookie': initialCookies},
        },
      );
      if (res1.statusCode != 200) return null;
      var csrfToken = _findCsrf(res1.body);
      var cookies = res1.headers['set-cookie'] ?? initialCookies;
      if (csrfToken == null) return null;

      var fileApiUrl = '$baseUrl/file/$uploadId?as_props=1&source=game_download';
      var res2 = await sourceRequest(
        fileApiUrl,
        {
          ...additionalSettings,
          'tempHeaders': {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/download/$uploadId',
            if (cookies != null) 'Cookie': cookies,
          },
        },
        postBody: {'csrf_token': csrfToken},
      );
      if (res2.statusCode != 200) return null;
      var directUrl = jsonDecode(res2.body)['url'] as String?;
      if (directUrl == null) return null;

      var streamRes = await sourceRequestStreamResponse('GET', directUrl, {
        'Referer': '$baseUrl?download',
        if (cookies != null) 'Cookie': cookies,
      }, additionalSettings);

      var response = streamRes.value.value;
      var cd = response.headers.value('content-disposition');
      streamRes.value.key.close(force: true);

      if (cd != null) {
        var match = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
        return match?.group(1);
      }
    } catch (_) {}
    return null;
  }

  /// Extracts the version string from the page body.
  /// Prioritizes info table data, then upload names, then 'Updated' date.
  String? _parseVersion(String body) {
    // 1. Info table version row
    var versionMatch = RegExp(
      r'<tr>\s*<td>Version</td>\s*<td>(.*?)</td>\s*</tr>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    if (versionMatch != null) {
      String v = versionMatch.group(1)!.trim();
      return v.replaceFirst(RegExp(r'^[vV]'), '');
    }

    // 2. Upload names in body
    var vMatch = RegExp(
      r'class="upload_name"><strong[^>]*>.*?([vV]?\d+\.\d+(?:\.\d+)*).*?</strong>',
      dotAll: true,
    ).firstMatch(body);
    if (vMatch != null) {
      String v = vMatch.group(1)!.trim();
      return v.replaceFirst(RegExp(r'^[vV]'), '');
    }

    return null;
  }

  /// Extracts the "Updated" date and formats it as YYYYMMDD for versioning.
  String? _getDateVersion(String body) {
    var dateMatch = RegExp(
      r'<abbr title="(\d{4})-(\d{2})-(\d{2})[^"]*"[^>]*>.*?Updated',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    if (dateMatch != null) {
      return '${dateMatch.group(1)}${dateMatch.group(2)}${dateMatch.group(3)}';
    }
    return null;
  }

  /// Extracts the app title from the page body.
  String? _parseTitle(String body) {
    var titleMatch = RegExp(
      r'<h1[^>]*class="[^"]*game_title[^"]*"[^>]*>(.*?)</h1>',
      dotAll: true,
    ).firstMatch(body);
    String? title = titleMatch?.group(1)?.trim();
    if (title == null || title.isEmpty) {
      title = RegExp(
        r'<meta property="og:title" content="([^"]+)"',
      ).firstMatch(body)?.group(1);
    }
    if (title == null || title.isEmpty) {
      title = RegExp(r'<title>(.*?)</title>').firstMatch(body)?.group(1);
    }
    if (title != null) {
      if (title.contains(' by ')) title = title.split(' by ').first.trim();
      title = title.replaceAll('Download ', '').trim();
    }
    return title;
  }

  /// Resolves the app author from subdomain or author span.
  String _parseAuthor(String body, String standardUrl) {
    var authorMatch = RegExp(
      r'<span itemprop="name">(.*?)</span>',
    ).firstMatch(body);
    String? author = authorMatch?.group(1)?.trim();
    if (author == null || author.isEmpty) {
      author = RegExp(
        r'by <a href="[^"]+">([^<]+)</a>',
      ).firstMatch(body)?.group(1)?.trim();
    }
    return author ?? Uri.parse(standardUrl).host.split('.').first;
  }

  /// Encapsulates the multi-step bypass flow to retrieve the download page body.
  Future<String> _getDownloadPageBody(
    String standardUrl,
    String initialBody,
    String? initialCookies,
    String? csrfToken,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');
    var currentBody = initialBody;
    var currentCookies = initialCookies;
    var ids = _extractDownloadIds(currentBody);

    if (ids.isEmpty && csrfToken != null) {
      // Step 1: POST to /download_url bypass (e.g. for "Name your price")
      var bypassRes = await sourceRequest(
        '$baseUrl/download_url',
        {
          ...additionalSettings,
          'tempHeaders': {
            'X-Requested-With': 'XMLHttpRequest',
            if (currentCookies != null) 'Cookie': currentCookies,
          },
        },
        postBody: {'csrf_token': csrfToken},
      );
      if (bypassRes.statusCode == 200) {
        var tokenizedUrl = jsonDecode(bypassRes.body)['url'] as String?;
        if (tokenizedUrl != null) {
          var tRes = await sourceRequest(tokenizedUrl, {
            ...additionalSettings,
            'tempHeaders': {if (currentCookies != null) 'Cookie': currentCookies},
          });
          if (tRes.statusCode == 200) {
            currentBody = tRes.body;
            currentCookies = tRes.headers['set-cookie'] ?? currentCookies;
            ids = _extractDownloadIds(currentBody);
          }
        }
      }
    }

    if (ids.isEmpty) {
      // Step 2: AJAX /purchase fallback
      var pRes = await sourceRequest('$baseUrl/purchase?lightbox=true', {
        ...additionalSettings,
        'tempHeaders': {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': standardUrl,
          if (currentCookies != null) 'Cookie': currentCookies,
        },
      });
      if (pRes.statusCode == 200) {
        var pBody = pRes.body;
        try {
          var data = jsonDecode(pBody);
          if (data['layout'] != null) pBody = data['layout'];
        } catch (_) {}
        var tUrlMatch = RegExp(r'href="([^"]*/download/[^"]+)"').firstMatch(pBody);
        if (tUrlMatch != null) {
          var tUrl = Uri.parse(standardUrl).resolve(tUrlMatch.group(1)!).toString();
          var tRes = await sourceRequest(tUrl, {
            ...additionalSettings,
            'tempHeaders': {if (currentCookies != null) 'Cookie': currentCookies},
          });
          if (tRes.statusCode == 200) {
            currentBody = tRes.body;
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
    var res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var body = res.body;
    var cookies = res.headers['set-cookie'];
    var csrfToken = _findCsrf(body);

    // Metadata extraction
    String? title = _parseTitle(body);
    String author = _parseAuthor(body, standardUrl);
    String? version = _parseVersion(body);
    String? dateVersion = _getDateVersion(body);

    // Resolve tokenized download page (if necessary)
    String downloadPageBody = await _getDownloadPageBody(
      standardUrl,
      body,
      cookies,
      csrfToken,
      additionalSettings,
    );

    // Final version fallback check
    version ??= _parseVersion(downloadPageBody);
    dateVersion ??= _getDateVersion(downloadPageBody);

    var downloadIds = _extractDownloadIds(downloadPageBody);
    var apkLinkFutures = <Future<MapEntry<String, String>?>>[];
    String? foundVersionInNames;

    for (var id in downloadIds) {
      RegExp idPattern = RegExp('data-upload_id="$id"|/download/$id');
      var idMatch = idPattern.firstMatch(downloadPageBody);
      bool isLikelyAndroid = false;
      String? presentedName;

      if (idMatch != null) {
        int contextStart = downloadPageBody.lastIndexOf(
          'class="upload"',
          idMatch.start,
        );
        if (contextStart == -1 || (idMatch.start - contextStart) > 1000) {
          contextStart = (idMatch.start - 500).clamp(0, downloadPageBody.length);
        }
        String blockContext = downloadPageBody.substring(
          contextStart,
          (idMatch.end + 200).clamp(0, downloadPageBody.length),
        );

        var nameMatch = RegExp(r'class="upload_name">([^<]+)<').firstMatch(blockContext);
        presentedName = nameMatch?.group(1)?.trim();

        if (blockContext.toLowerCase().contains('android') ||
            blockContext.toLowerCase().contains('.apk') ||
            (presentedName?.toLowerCase().contains('android') ?? false)) {
          isLikelyAndroid = true;
        }

        if (presentedName != null) {
          var vMatch = RegExp(r'[vV]?(\d+\.\d+(?:\.\d+)*)').firstMatch(presentedName);
          if (vMatch != null) foundVersionInNames ??= vMatch.group(1);
        }
      }

      if (isLikelyAndroid || downloadIds.length <= 3) {
        apkLinkFutures.add(
          _resolveRealFileName(id, standardUrl, additionalSettings, cookies).then((realName) {
            return MapEntry(
              realName ?? presentedName ?? id,
              '$baseUrl/download/$id',
            );
          }),
        );
      }
    }

    // Resolve filenames in parallel
    var apkLinks = (await Future.wait(apkLinkFutures)).whereType<MapEntry<String, String>>().toList();

    version = foundVersionInNames ?? version ?? dateVersion ?? 'latest';
    String cleanAuthor = author.replaceAll(' ', '_');

    // Clean and normalize labels
    apkLinks = apkLinks.map((entry) {
      String label = entry.key;
      if (label == entry.value.split('/').last || label.length < 5 || !label.contains('.')) {
        String cleanName = label.replaceAll(RegExp(r'[^\w\s\.\-\(\)]'), '').replaceAll(' ', '_');
        label = '${cleanName}_${cleanAuthor}_$version.apk';
      }
      return MapEntry(label, entry.value);
    }).toList();

    if (apkLinks.isEmpty) throw NoAPKError();

    return APKDetails(version, apkLinks, AppNames(author, title ?? 'App'));
  }

  @override
  Future<String> assetUrlPrefetchModifier(
    String assetUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String baseUrl = standardUrl.replaceAll(RegExp(r'/$'), '');
    var uploadId = assetUrl.split('/').last;
    var res = await sourceRequest(assetUrl, additionalSettings);
    if (res.statusCode != 200) throw getObtainiumHttpError(res);

    var body = res.body;
    var cookies = res.headers['set-cookie'];
    var csrfToken = _findCsrf(body);
    if (csrfToken == null) return assetUrl;

    var fileApiUrl = '$baseUrl/file/$uploadId?as_props=1&source=game_download';
    var apiRes = await sourceRequest(
      fileApiUrl,
      {
        ...additionalSettings,
        'tempHeaders': {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': assetUrl,
          if (cookies != null) 'Cookie': cookies,
        },
      },
      postBody: {'csrf_token': csrfToken},
    );

    if (apiRes.statusCode == 200) {
      var finalUrl = jsonDecode(apiRes.body)['url'] as String?;
      if (finalUrl != null) return finalUrl;
    }

    return assetUrl;
  }
}
