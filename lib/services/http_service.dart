// HTTP client creation, streaming requests, redirect/error handling.

import 'dart:convert';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show HeadersWithSplitValues;
import 'package:http/io_client.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/services/pin_store.dart';
import 'package:obtainium/services/pinned_certificates.dart';

// ========================================================================
// HttpService — HTTP client creation, streaming requests, and error mapping.
// ========================================================================

typedef HttpServiceClientFactory =
    Future<http.Client> Function(Map<String, dynamic> settings);

class HttpService {
  HttpService({HttpServiceClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFor;

  final HttpServiceClientFactory _clientFactory;

  static const int maxRedirects = 10;

  /// Headers that may be forwarded to a different origin on redirect.
  /// Source-configured auth headers (e.g. PRIVATE-TOKEN, X-Api-Key) and other
  /// caller-supplied headers are dropped, since a redirect can point at an
  /// arbitrary third-party host.
  static const Set<String> safeRedirectHeaders = {
    'accept',
    'accept-charset',
    'accept-encoding',
    'accept-language',
    'cache-control',
    'content-length',
    'content-type',
    'if-modified-since',
    'if-none-match',
    'if-range',
    'origin',
    'pragma',
    'range',
    'referer',
    'user-agent',
    'x-requested-with',
  };

  static String extractRootHost(String host) {
    final parts = host.split('.');
    return parts.length > 2 ? parts.sublist(parts.length - 2).join('.') : host;
  }

  static final Map<String, Future<http.Client>> _pinnedClients = {};
  static final Map<String, Future<http.Client>> _ioClients = {};
  static http.Client? _cronetClient;
  static bool _cronetUnavailable = false;
  static bool _defaultCertificatePinning = false;

  static bool get isCronetInUse => _cronetClient != null;

  static void setDefaultCertificatePinning(bool enabled) {
    _defaultCertificatePinning = enabled;
  }

  static Future<http.Client> _defaultClientFor(
    Map<String, dynamic> settings,
  ) async {
    final url = settings['url'] as String;
    final host = Uri.parse(url).host;
    final pinning =
        (settings['enableCertificatePinning'] as bool?) ??
        _defaultCertificatePinning;
    final insecure = settings['allowInsecure'] == true;

    if (pinning && Uri.parse(url).scheme == 'https') {
      final store = PinStore.instance;
      await store.ensureLoaded();
      final resolved = store.resolve(host);
      if (resolved != null) {
        final cacheKey = '${resolved.id}:${resolved.revision}';
        return _pinnedClients.putIfAbsent(cacheKey, () async {
          final securityContext = SecurityContext();
          for (final certificate in resolved.certificates) {
            final pem = await certificate.loadPem();
            securityContext.setTrustedCertificatesBytes(utf8.encode(pem));
          }
          final httpClient = HttpClient(context: securityContext)
            ..connectionTimeout = const Duration(seconds: 30)
            ..badCertificateCallback = (cert, host, port) => false;
          return IOClient(httpClient);
        });
      }
    }

    if (insecure) {
      return _ioClients.putIfAbsent('insecure', () async {
        final httpClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 30)
          ..badCertificateCallback = (cert, host, port) => true;
        return IOClient(httpClient);
      });
    }

    final cronetClient = _tryCronetClient();
    if (cronetClient != null) return cronetClient;

    if (extractRootHost(host) == 'rustore.ru') {
      return _ioClients.putIfAbsent('rustore', () async {
        final securityContext = SecurityContext(withTrustedRoots: true);
        final cert = await rootBundle.load(russianMintsifryAssetPath);
        securityContext.setTrustedCertificatesBytes(
          cert.buffer.asUint8List(cert.offsetInBytes, cert.lengthInBytes),
        );
        final httpClient = HttpClient(context: securityContext)
          ..connectionTimeout = const Duration(seconds: 30);
        return IOClient(httpClient);
      });
    }

    return _ioClients.putIfAbsent('default', () async {
      final httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      return IOClient(httpClient);
    });
  }

  static http.Client? _tryCronetClient() {
    if (!Platform.isAndroid || _cronetUnavailable) return null;
    if (_cronetClient != null) return _cronetClient;
    try {
      final engine = CronetEngine.build(
        userAgent: 'Dart/${Platform.version.split(' ').first} (dart:io)',
        enableQuic: false,
        useBuiltInDnsResolver: false,
      );
      _cronetClient = CronetClient.fromCronetEngine(engine);
      AppLogger.info('HTTP: using embedded Cronet');
      return _cronetClient;
    } catch (e, stackTrace) {
      _cronetUnavailable = true;
      AppLogger.error(
        e,
        stackTrace: stackTrace,
        message: 'HTTP: Cronet initialization failed; using dart:io',
      );
      return null;
    }
  }

  /// Whether two URIs share the same origin (scheme, host, and port — Dart
  /// normalizes default ports for http/https, so explicit and implicit
  /// default ports compare equal).
  static bool isSameOrigin(Uri a, Uri b) =>
      a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      a.port == b.port;

  String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) {
    try {
      ambiguousUrl = ambiguousUrl.trim();
      if (Uri.parse(ambiguousUrl).isAbsolute) {
        return ambiguousUrl;
      }
    } on FormatException {
      // Non-parsable URL, fall through to resolve logic below
    }
    return referenceAbsoluteUrl.resolve(ambiguousUrl).toString();
  }

  /// Performs an HTTP request with redirect following, returning the final URL
  /// and streamed response.
  Future<MapEntry<Uri, http.StreamedResponse>> requestStream(
    String method,
    Map<String, String>? requestHeaders,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    final url = additionalSettings['url'] as String;
    var currentUrl = Uri.parse(url);
    var redirectCount = 0;
    List<Cookie> cookies = [];
    while (redirectCount < maxRedirects) {
      // Build the client from the hop's URL so certificate pinning and other
      // host-specific contexts follow redirects instead of sticking to the
      // original URL.
      final hopSettings = Map<String, dynamic>.from(additionalSettings)
        ..['url'] = currentUrl.toString();
      final client = await _clientFactory(hopSettings);
      final request = http.Request(method, currentUrl)
        ..followRedirects = false
        ..maxRedirects = maxRedirects;
      if (requestHeaders != null) {
        request.headers.addAll(requestHeaders);
      }
      if (cookies.isNotEmpty) {
        final cookieHeader = cookies
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; ');
        final existing = request.headers['cookie'];
        request.headers['cookie'] = existing == null
            ? cookieHeader
            : '$existing; $cookieHeader';
      }
      if (postBody != null) {
        if (postBody is String) {
          request.bodyBytes = utf8.encode(postBody);
        } else {
          request.headers['content-type'] = ContentType.json.toString();
          request.body = jsonEncode(postBody);
        }
      }
      final response = await client.send(request);

      if (followRedirects &&
          (response.statusCode >= 300 && response.statusCode <= 399)) {
        final location = response.headers[HttpHeaders.locationHeader];
        if (location != null) {
          final nextUrl = Uri.parse(ensureAbsoluteUrl(location, currentUrl));
          if (currentUrl.scheme == 'https' &&
              nextUrl.scheme == 'http' &&
              additionalSettings['allowInsecure'] != true &&
              additionalSettings['allowInsecureRedirects'] != true) {
            // Never follow a redirect that downgrades to cleartext HTTP.
            await cancelStreamedResponse(response);
            throw ObtainiumError(tr('insecureRedirect'));
          }
          if (!isSameOrigin(currentUrl, nextUrl)) {
            // Do not forward credentials or any other caller-supplied
            // headers to a different origin; keep only protocol-level ones.
            requestHeaders = requestHeaders == null
                ? null
                : Map<String, String>.fromEntries(
                    requestHeaders.entries.where(
                      (e) => safeRedirectHeaders.contains(e.key.toLowerCase()),
                    ),
                  );
            cookies = [];
          } else {
            cookies = _cookiesFromResponse(response);
          }
          currentUrl = nextUrl;
          redirectCount++;
          await cancelStreamedResponse(response);
          continue;
        }
      }

      return MapEntry(currentUrl, response);
    }
    throw ObtainiumError(tr('tooManyRedirects'));
  }

  Future<http.Response> request(
    String method,
    Map<String, String>? requestHeaders,
    Map<String, dynamic> additionalSettings, {
    bool followRedirects = true,
    Object? postBody,
  }) async {
    final result = await requestStream(
      method,
      requestHeaders,
      additionalSettings,
      followRedirects: followRedirects,
      postBody: postBody,
    );
    return streamedResponseToFinalResponse(
      result.value,
      method,
      result.key.toString(),
    );
  }

  Future<http.Response> streamedResponseToFinalResponse(
    http.StreamedResponse response,
    String method,
    String url,
  ) async {
    final bytes = await response.stream.toBytes();
    return http.Response.bytes(
      bytes,
      response.statusCode,
      headers: response.headers,
      request: http.Request(method, Uri.parse(url)),
      isRedirect: response.isRedirect,
      reasonPhrase: response.reasonPhrase,
    );
  }

  List<Cookie> _cookiesFromResponse(http.StreamedResponse response) {
    final values = HeadersWithSplitValues(
      response,
    ).headersSplitValues['set-cookie'];
    if (values == null) return [];
    final cookies = <Cookie>[];
    for (final value in values) {
      try {
        cookies.add(Cookie.fromSetCookieValue(value));
      } on FormatException {
        // Ignore malformed Set-Cookie values instead of failing the response.
      }
    }
    return cookies;
  }

  ObtainiumError getHttpError(http.Response res) {
    if (res.statusCode == 404) return NoReleasesError();
    if (res.statusCode == 429 || res.statusCode == 403) {
      final retryAfter = res.headers['retry-after'];
      final secs = retryAfter != null ? int.tryParse(retryAfter) : null;
      if (secs != null) return RateLimitError((secs / 60).ceil());
      return RateLimitError(1);
    }
    return ObtainiumError(
      (res.reasonPhrase != null && res.reasonPhrase!.isNotEmpty)
          ? res.reasonPhrase!
          : tr('errorWithHttpStatusCode', args: [res.statusCode.toString()]),
      code: 'HTTP_ERROR',
    );
  }
}

/// Delegates to [HttpService.ensureAbsoluteUrl].
String ensureAbsoluteUrl(String ambiguousUrl, Uri referenceAbsoluteUrl) =>
    HttpService().ensureAbsoluteUrl(ambiguousUrl, referenceAbsoluteUrl);

/// Cancels an unread streamed response, releasing the underlying connection.
Future<void> cancelStreamedResponse(http.StreamedResponse response) async {
  try {
    final subscription = response.stream.listen(null, onError: (_) {});
    await subscription.cancel();
  } catch (_) {
    // The stream may already have been consumed or cancelled.
  }
}

/// Delegates to [HttpService.requestStream].
Future<MapEntry<Uri, http.StreamedResponse>> sourceRequestStreamResponse(
  String method,
  Map<String, String>? requestHeaders,
  Map<String, dynamic> additionalSettings, {
  bool followRedirects = true,
  Object? postBody,
}) => HttpService().requestStream(
  method,
  requestHeaders,
  additionalSettings,
  followRedirects: followRedirects,
  postBody: postBody,
);

/// Delegates to [HttpService.getHttpError].
ObtainiumError getObtainiumHttpError(http.Response res) =>
    HttpService().getHttpError(res);

/// Throws an [ObtainiumError] carrying [res]'s status code unless the response
/// is a 200 OK.
void ensureHttpSuccess(http.Response res) {
  if (res.statusCode != 200) {
    throw getObtainiumHttpError(res);
  }
}
