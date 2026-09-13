// HTTP client creation, streaming requests, redirect/error handling.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:obtainium/custom_errors.dart';

// ========================================================================
// HttpService — HTTP client creation, streaming requests, and error mapping.
// ========================================================================

class HttpService {
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

  static final Map<String, Future<List<Uint8List>>> _certificatePins = {
    'github.com': _loadCertificateFromAsset([
      'assets/ca-certs/sectigo-pub-serv-auth-r46.crt',
      'assets/ca-certs/sectigo-pub-serv-auth-e46.crt',

      // redirects from api.github.com for obtaining release assets point to
      // release-assets.githubusercontent.com which uses ISRG (Let's Encrypt)
      // adding that as another section doesn't work because of
      // HttpClient follows redirects (as intended)
      'assets/ca-certs/isrg-root-x1.crt',
      'assets/ca-certs/isrg-root-x2.crt',
      'assets/ca-certs/isrg-root-ye.crt',
      'assets/ca-certs/isrg-root-yr.crt',
    ]),
    'codeberg.org': _loadCertificateFromAsset([
      'assets/ca-certs/isrg-root-x1.crt',
      'assets/ca-certs/isrg-root-x2.crt',
      'assets/ca-certs/isrg-root-ye.crt',
      'assets/ca-certs/isrg-root-yr.crt',
    ]),
    'gitlab.com': _loadCertificateFromAsset([
      'assets/ca-certs/sectigo-pub-serv-auth-r46.crt',
      'assets/ca-certs/sectigo-pub-serv-auth-e46.crt',
    ]),
    'rustore.ru': _loadCertificateFromAsset([
      'assets/ca-certs/harica-tls-root-2021-rsa.crt',
      'assets/ca-certs/harica-tls-root-2021-ecc.crt',
      'assets/ca-certs/russian-mintsifry-root.crt',
    ]),
  };

  static Future<List<Uint8List>> _loadCertificateFromAsset(
    List<String> assetsPath,
  ) async {
    final List<Uint8List> certsBytes = [];
    for (final certPath in assetsPath) {
      final cert = await rootBundle.load(certPath);
      certsBytes.add(cert.buffer.asUint8List());
    }
    return certsBytes;
  }

  static String extractRootHost(String host) {
    final parts = host.split('.');
    return parts.length > 2 ? parts.sublist(parts.length - 2).join('.') : host;
  }

  Future<SecurityContext?> _createCertPinning(String url) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final rootHost = extractRootHost(host);
    if (_certificatePins.containsKey(host)) {
      final certsBytes = await _certificatePins[host]!;
      final securityContext = SecurityContext();
      for (final certBytes in certsBytes) {
        securityContext.setTrustedCertificatesBytes(certBytes);
      }
      return securityContext;
    } else if (_certificatePins.containsKey(rootHost)) {
      final certsBytes = await _certificatePins[rootHost]!;
      final securityContext = SecurityContext();
      for (final certBytes in certsBytes) {
        securityContext.setTrustedCertificatesBytes(certBytes);
      }
      return securityContext;
    } else {
      return null;
    }
  }

  /* Basically RuStore switched partially (and in the future it may be fully)
     to russian government Mintsifry CA, which isnt trusted by Android nor
     Chrome Root Store. This is workaround to trust Mintsifry CA for network
     requests made to RuStore domains and subdomains
   */
  Future<SecurityContext> _ruStoreWorkaroundSecurityContext() async {
    final securityContext = SecurityContext(withTrustedRoots: true);
    final cert = await rootBundle.load(
      'assets/ca-certs/russian-mintsifry-root.crt',
    );
    securityContext.setTrustedCertificatesBytes(cert.buffer.asUint8List());
    return securityContext;
  }

  Future<HttpClient> createHttpClient(
    Map<String, dynamic> additionalSettings,
  ) async {
    final insecure = additionalSettings['allowInsecure'] == true;
    final url = additionalSettings['url'] as String;
    final pinning = additionalSettings['enableCertificatePinning'] == true;
    SecurityContext? securityContext;
    final host = Uri.parse(url).host;
    if (pinning) {
      securityContext = await _createCertPinning(url);
    } else if (extractRootHost(host) == 'rustore.ru') {
      securityContext = await _ruStoreWorkaroundSecurityContext();
    }
    final client = securityContext != null
        ? HttpClient(context: securityContext)
        : HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    if (insecure) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
            if (pinning &&
                (_certificatePins.containsKey(host) ||
                    _certificatePins.containsKey(extractRootHost(host)))) {
              // Pinned sites (and subdomains of a pinned root) must still
              // reject bad certificates even when insecure mode is enabled.
              return false;
            }
            return true;
          };
    }
    return client;
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

  /// Performs an HTTP request with redirect following, returning the final URL, client, and streamed response.
  Future<MapEntry<Uri, MapEntry<HttpClient, HttpClientResponse>>>
  sourceRequestStreamResponse(
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
      final httpClient = await createHttpClient(hopSettings);
      try {
        final request = await httpClient.openUrl(method, currentUrl);
        if (requestHeaders != null) {
          requestHeaders.forEach((key, value) {
            request.headers.set(key, value);
          });
        }
        request.cookies.addAll(cookies);
        request.followRedirects = false;
        if (postBody != null) {
          if (postBody is String) {
            request.write(postBody);
          } else {
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode(postBody));
          }
        }
        final response = await request.close();

        if (followRedirects &&
            (response.statusCode >= 300 && response.statusCode <= 399)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null) {
            final nextUrl = Uri.parse(ensureAbsoluteUrl(location, currentUrl));
            if (currentUrl.scheme == 'https' &&
                nextUrl.scheme == 'http' &&
                additionalSettings['allowInsecure'] != true &&
                additionalSettings['allowInsecureRedirects'] != true) {
              // Never follow a redirect that downgrades to cleartext HTTP.
              throw ObtainiumError(tr('insecureRedirect'));
            }
            if (!isSameOrigin(currentUrl, nextUrl)) {
              // Do not forward credentials or any other caller-supplied
              // headers to a different origin; keep only protocol-level ones.
              requestHeaders = requestHeaders == null
                  ? null
                  : Map<String, String>.fromEntries(
                      requestHeaders.entries.where(
                        (e) =>
                            safeRedirectHeaders.contains(e.key.toLowerCase()),
                      ),
                    );
              cookies = [];
            } else {
              cookies = response.cookies;
            }
            currentUrl = nextUrl;
            redirectCount++;
            httpClient.close();
            continue;
          }
        }

        return MapEntry(currentUrl, MapEntry(httpClient, response));
      } catch (e) {
        // Never leak the client when a request or redirect handling throws.
        httpClient.close();
        rethrow;
      }
    }
    throw ObtainiumError(tr('tooManyRedirects'));
  }

  Future<http.Response> httpClientResponseStreamToFinalResponse(
    HttpClient httpClient,
    String method,
    String url,
    HttpClientResponse response,
  ) async {
    try {
      final bytes = (await response.fold<BytesBuilder>(
        BytesBuilder(),
        (b, d) => b..add(d),
      )).toBytes();

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });

      return http.Response.bytes(
        bytes,
        response.statusCode,
        headers: headers,
        request: http.Request(method, Uri.parse(url)),
      );
    } finally {
      httpClient.close();
    }
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

/// Delegates to [HttpService.createHttpClient].
Future<HttpClient> createHttpClient(
  Map<String, dynamic> additionalSettings,
) async => await HttpService().createHttpClient(additionalSettings);

// ------------------------------------------------------------------------
// More top-level delegation helpers (continued)
// ------------------------------------------------------------------------

/// Delegates to [HttpService.sourceRequestStreamResponse].
Future<MapEntry<Uri, MapEntry<HttpClient, HttpClientResponse>>>
sourceRequestStreamResponse(
  String method,
  Map<String, String>? requestHeaders,
  Map<String, dynamic> additionalSettings, {
  bool followRedirects = true,
  Object? postBody,
}) => HttpService().sourceRequestStreamResponse(
  method,
  requestHeaders,
  additionalSettings,
  followRedirects: followRedirects,
  postBody: postBody,
);

/// Delegates to [HttpService.httpClientResponseStreamToFinalResponse].
Future<http.Response> httpClientResponseStreamToFinalResponse(
  HttpClient httpClient,
  String method,
  String url,
  HttpClientResponse response,
) => HttpService().httpClientResponseStreamToFinalResponse(
  httpClient,
  method,
  url,
  response,
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
