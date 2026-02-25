import 'dart:convert';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

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

  String? _findCsrf(String body) {
    RegExp csrfInputRegEx = RegExp(r'name="csrf_token" value="([^"]+)"');
    var match = csrfInputRegEx.firstMatch(body);
    if (match != null) return match.group(1);

    RegExp csrfJsonRegEx = RegExp(r'csrf_token":"([^"]+)"');
    match = csrfJsonRegEx.firstMatch(body);
    return match?.group(1);
  }

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

  Future<String?> _resolveRealFileName(
    String uploadId,
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    String? initialCookies,
  ) async {
    try {
      var res1 = await sourceRequest(
        '${standardUrl.replaceAll(RegExp(r'/$'), '')}/download/$uploadId',
        {
          ...additionalSettings,
          if (initialCookies != null) 'tempHeaders': {'Cookie': initialCookies},
        },
      );
      if (res1.statusCode != 200) return null;
      var csrfToken = _findCsrf(res1.body);
      var cookies = res1.headers['set-cookie'] ?? initialCookies;
      if (csrfToken == null) return null;

      var fileApiUrl =
          '${standardUrl.replaceAll(RegExp(r'/$'), '')}/file/$uploadId?as_props=1&source=game_download';
      var res2 = await sourceRequest(
        fileApiUrl,
        {
          ...additionalSettings,
          'tempHeaders': {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '${standardUrl.replaceAll(RegExp(r'/$'), '')}/download/$uploadId',
            if (cookies != null) 'Cookie': cookies,
          },
        },
        postBody: {'csrf_token': csrfToken},
      );
      if (res2.statusCode != 200) return null;
      var directUrl = jsonDecode(res2.body)['url'] as String?;
      if (directUrl == null) return null;

      var streamRes = await sourceRequestStreamResponse('GET', directUrl, {
        'Referer': '${standardUrl.replaceAll(RegExp(r'/$'), '')}?download',
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

  String? _parseVersion(String body) {
    // Try to find the version in the info table
    var versionMatch = RegExp(
      r'<tr>\s*<td>Version</td>\s*<td>(.*?)</td>\s*</tr>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    if (versionMatch != null) {
      String v = versionMatch.group(1)!.trim();
      return v.replaceFirst(RegExp(r'^[vV]'), '');
    }

    // Try parsing version from upload names in the body
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

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    var res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var body = res.body;
    var cookies = res.headers['set-cookie'];
    var csrfToken = _findCsrf(body);

    String? title;
    var titleMatch = RegExp(
      r'<h1[^>]*class="[^"]*game_title[^"]*"[^>]*>(.*?)</h1>',
      dotAll: true,
    ).firstMatch(body);
    title = titleMatch?.group(1)?.trim();
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

    String? author;
    var authorMatch = RegExp(
      r'<span itemprop="name">(.*?)</span>',
    ).firstMatch(body);
    author = authorMatch?.group(1)?.trim();
    if (author == null || author.isEmpty) {
      author = RegExp(
        r'by <a href="[^"]+">([^<]+)</a>',
      ).firstMatch(body)?.group(1)?.trim();
    }
    author ??= Uri.parse(standardUrl).host.split('.').first;

    String? version = _parseVersion(body);
    String? dateVersion = _getDateVersion(body);

    var downloadIds = _extractDownloadIds(body);
    var downloadPageBody = body;

    if (downloadIds.isEmpty && csrfToken != null) {
      var bypassRes = await sourceRequest(
        '${standardUrl.replaceAll(RegExp(r'/$'), '')}/download_url',
        {
          ...additionalSettings,
          'tempHeaders': {
            'X-Requested-With': 'XMLHttpRequest',
            if (cookies != null) 'Cookie': cookies,
          },
        },
        postBody: {'csrf_token': csrfToken},
      );
      if (bypassRes.statusCode == 200) {
        var tokenizedUrl = jsonDecode(bypassRes.body)['url'] as String?;
        if (tokenizedUrl != null) {
          var tRes = await sourceRequest(tokenizedUrl, {
            ...additionalSettings,
            'tempHeaders': {if (cookies != null) 'Cookie': cookies},
          });
          if (tRes.statusCode == 200) {
            downloadPageBody = tRes.body;
            downloadIds = _extractDownloadIds(downloadPageBody);
            cookies = tRes.headers['set-cookie'] ?? cookies;
          }
        }
      }
    }

    if (downloadIds.isEmpty) {
      var purchaseUrl =
          '${standardUrl.replaceAll(RegExp(r'/$'), '')}/purchase?lightbox=true';
      var pRes = await sourceRequest(purchaseUrl, {
        ...additionalSettings,
        'tempHeaders': {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': standardUrl,
          if (cookies != null) 'Cookie': cookies,
        },
      });
      if (pRes.statusCode == 200) {
        var pBody = pRes.body;
        try {
          var data = jsonDecode(pBody);
          if (data['layout'] != null) pBody = data['layout'];
        } catch (_) {}
        var tUrlMatch = RegExp(
          r'href="([^"]*/download/[^"]+)"',
        ).firstMatch(pBody);
        if (tUrlMatch != null) {
          var tUrl = Uri.parse(
            standardUrl,
          ).resolve(tUrlMatch.group(1)!).toString();
          var tRes = await sourceRequest(tUrl, {
            ...additionalSettings,
            'tempHeaders': {if (cookies != null) 'Cookie': cookies},
          });
          if (tRes.statusCode == 200) {
            downloadPageBody = tRes.body;
            downloadIds = _extractDownloadIds(downloadPageBody);
            cookies = tRes.headers['set-cookie'] ?? cookies;
          }
        }
      }
    }

    // Try parsing version again from the download page body if not found yet
    version ??= _parseVersion(downloadPageBody);
    dateVersion ??= _getDateVersion(downloadPageBody);

    var apkLinks = <MapEntry<String, String>>[];
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
          contextStart = (idMatch.start - 500).clamp(
            0,
            downloadPageBody.length,
          );
        }
        String blockContext = downloadPageBody.substring(
          contextStart,
          (idMatch.end + 200).clamp(0, downloadPageBody.length),
        );

        var nameMatch = RegExp(
          r'class="upload_name">([^<]+)<',
        ).firstMatch(blockContext);
        presentedName = nameMatch?.group(1)?.trim();

        if (blockContext.toLowerCase().contains('android') ||
            blockContext.toLowerCase().contains('.apk') ||
            (presentedName?.toLowerCase().contains('android') ?? false)) {
          isLikelyAndroid = true;
        }

        if (presentedName != null) {
          var vMatch = RegExp(
            r'[vV]?(\d+\.\d+(?:\.\d+)*)',
          ).firstMatch(presentedName);
          if (vMatch != null) {
            foundVersionInNames ??= vMatch.group(1);
          }
        }
      }

      if (isLikelyAndroid || downloadIds.length <= 3) {
        String? realName = await _resolveRealFileName(
          id,
          standardUrl,
          additionalSettings,
          cookies,
        );

        apkLinks.add(
          MapEntry(
            realName ?? presentedName ?? id,
            '${standardUrl.replaceAll(RegExp(r'/$'), '')}/download/$id',
          ),
        );
      }
    }

    version = foundVersionInNames ?? version ?? dateVersion ?? 'latest';

    String cleanAuthor = author.replaceAll(' ', '_');
    apkLinks = apkLinks.map((entry) {
      String label = entry.key;
      if (label == entry.value.split('/').last ||
          label.length < 5 ||
          !label.contains('.')) {
        String cleanName = label
            .replaceAll(RegExp(r'[^\w\s\.\-\(\)]'), '')
            .replaceAll(' ', '_');
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
    var uploadId = assetUrl.split('/').last;
    var res = await sourceRequest(assetUrl, additionalSettings);
    if (res.statusCode != 200) throw getObtainiumHttpError(res);

    var body = res.body;
    var cookies = res.headers['set-cookie'];
    var csrfToken = _findCsrf(body);
    if (csrfToken == null) return assetUrl;

    var fileApiUrl =
        '${standardUrl.replaceAll(RegExp(r'/$'), '')}/file/$uploadId?as_props=1&source=game_download';
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
