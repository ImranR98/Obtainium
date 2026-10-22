import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/services/http_service.dart';

void main() {
  HttpService serviceFor(MockClient client) =>
      HttpService(clientFactory: (_) async => client);

  Map<String, dynamic> settings(String url, {bool allowInsecure = false}) => {
    'url': url,
    'allowInsecure': allowInsecure,
  };

  group('HttpService redirects', () {
    test('follows same-origin redirects and forwards cookies', () async {
      final seen = <http.Request>[];
      final client = MockClient((request) async {
        seen.add(request);
        if (request.url.path == '/start') {
          return http.Response(
            '',
            302,
            headers: {
              'location': '/final',
              'set-cookie': 'session=abc; Path=/',
            },
          );
        }
        return http.Response('ok', 200);
      });
      final service = serviceFor(client);

      final response = await service.request('GET', {
        'X-Api-Key': 'secret',
        'Accept': 'application/json',
      }, settings('https://origin.example/start'));

      expect(response.statusCode, 200);
      expect(response.request?.url, Uri.parse('https://origin.example/final'));
      expect(seen, hasLength(2));
      expect(seen.last.headers['x-api-key'], 'secret');
      expect(seen.last.headers['accept'], 'application/json');
      expect(seen.last.headers['cookie'], 'session=abc');
    });

    test(
      'strips caller headers and cookies on cross-origin redirects',
      () async {
        final seen = <http.Request>[];
        final client = MockClient((request) async {
          seen.add(request);
          if (request.url.host == 'origin.example') {
            return http.Response(
              '',
              302,
              headers: {
                'location': 'https://other.example/final',
                'set-cookie': 'session=abc; Path=/',
              },
            );
          }
          return http.Response('ok', 200);
        });
        final service = serviceFor(client);

        await service.request('GET', {
          'X-Api-Key': 'secret',
          'Accept': 'application/json',
        }, settings('https://origin.example/start'));

        expect(seen, hasLength(2));
        expect(seen.last.headers['x-api-key'], isNull);
        expect(seen.last.headers['cookie'], isNull);
        expect(seen.last.headers['accept'], 'application/json');
      },
    );

    test('refuses an HTTPS to HTTP redirect', () async {
      final client = MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'http://origin.example/final'},
        ),
      );
      final service = serviceFor(client);

      await expectLater(
        service.request('GET', null, settings('https://origin.example/start')),
        throwsA(isA<ObtainiumError>()),
      );
    });

    test('stops after the redirect limit', () async {
      final client = MockClient(
        (request) async => http.Response(
          '',
          302,
          headers: {
            'location':
                '${request.url.path}?n=${request.url.queryParameters['n'] ?? '0'}',
          },
        ),
      );
      final service = serviceFor(client);

      await expectLater(
        service.request('GET', null, settings('https://origin.example/loop')),
        throwsA(isA<ObtainiumError>()),
      );
    });

    test('returns the redirect response when redirects are disabled', () async {
      final client = MockClient(
        (_) async => http.Response('', 302, headers: {'location': '/final'}),
      );
      final service = serviceFor(client);

      final result = await service.requestStream(
        'GET',
        null,
        settings('https://origin.example/start'),
        followRedirects: false,
      );

      expect(result.value.statusCode, 302);
      expect(result.key, Uri.parse('https://origin.example/start'));
    });
  });

  test('encodes map bodies as JSON', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response('ok', 200);
    });
    final service = serviceFor(client);

    await service.request(
      'POST',
      null,
      settings('https://origin.example/start'),
      postBody: {'a': 1},
    );

    expect(seen.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(seen.body), {'a': 1});
  });

  group('HttpService error mapping', () {
    test('maps 404 to NoReleasesError', () {
      final error = HttpService().getHttpError(http.Response('', 404));
      expect(error, isA<NoReleasesError>());
    });

    test('maps 429 with Retry-After to RateLimitError', () {
      final error = HttpService().getHttpError(
        http.Response('', 429, headers: {'retry-after': '120'}),
      );
      expect(error, isA<RateLimitError>());
      expect((error as RateLimitError).remainingMinutes, 2);
    });

    test('maps other statuses to a generic HTTP error', () {
      final error = HttpService().getHttpError(http.Response('', 500));
      expect(error.code, 'HTTP_ERROR');
    });
  });
}
