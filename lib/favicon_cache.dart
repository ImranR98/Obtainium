import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:obtainium/app_distribution.dart';
import 'package:path_provider/path_provider.dart';

/// Two-layer (memory + disk) cache for source host favicons.
///
/// Memory layer: static map, lives for the process lifetime.
/// Disk layer: files under `<cacheDir>/favicons/`, survive app restarts.
class FaviconCache {
  FaviconCache._();

  static final Map<String, Uint8List> _mem = {};

  /// Hosts for which favicon resolution already failed (all attempts exhausted).
  /// Prevents re-running the network requests on every widget rebuild for a
  /// host with no resolvable favicon. Lives for the process lifetime, matching
  /// the positive [_mem] layer.
  static final Set<String> _negative = {};

  static String _fileName(String cacheKey) =>
      '${cacheKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.ico';

  static Future<File> _fileFor(String cacheKey) async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/favicons');
    // Async existence/creation: this runs on the UI isolate (called from a
    // widget's async icon load), so the blocking existsSync/createSync used
    // before stalled the frame the first time each host scrolled in.
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${_fileName(cacheKey)}');
  }

  /// Returns favicon bytes for [host], fetching and caching on first call.
  /// Returns null if the favicon is unavailable or the network request fails.
  static Future<Uint8List?> get(String host) async {
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty) return null;
    if (_negative.contains(normalizedHost)) return null;

    final directBytes = await _getFromCacheOrFetch(
      'direct_$normalizedHost',
      Uri.https(normalizedHost, '/favicon.ico'),
    );
    if (directBytes != null) return directBytes;

    if (AppDistribution.allowDuckDuckGoFavicons) {
      final ddgBytes = await _getFromCacheOrFetch(
        'duckduckgo_$normalizedHost',
        Uri.parse('https://icons.duckduckgo.com/ip3/$normalizedHost.ico'),
      );
      if (ddgBytes != null) return ddgBytes;
    }

    // All resolution attempts failed; negative-cache the host so repeated
    // widget builds don't re-run the (up to two) network requests.
    _negative.add(normalizedHost);
    return null;
  }

  static Future<Uint8List?> _getFromCacheOrFetch(
    String cacheKey,
    Uri uri,
  ) async {
    if (_mem.containsKey(cacheKey)) return _mem[cacheKey];

    final file = await _fileFor(cacheKey);
    // Async read (was readAsBytesSync) — see [_fileFor]; keeps the disk hit
    // off the UI thread so scrolling in a cached-favicon row doesn't hitch.
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _mem[cacheKey] = bytes;
      return bytes;
    }

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (_isValidFaviconResponse(response)) {
        await file.writeAsBytes(response.bodyBytes);
        _mem[cacheKey] = response.bodyBytes;
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  static bool _isValidFaviconResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    if (response.bodyBytes.isEmpty) return false;

    final contentType = response.headers[HttpHeaders.contentTypeHeader]
        ?.toLowerCase();
    if (contentType != null &&
        (contentType.startsWith('image/') ||
            contentType.contains('icon') ||
            contentType.contains('octet-stream'))) {
      return true;
    }

    final bytes = response.bodyBytes;
    if (bytes.length >= 4 &&
        bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        (bytes[2] == 0x01 || bytes[2] == 0x02) &&
        bytes[3] == 0x00) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return true;
    }
    return false;
  }
}
