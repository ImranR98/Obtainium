import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/services/host_request_gate.dart';

void main() {
  group('HostRequestGate', () {
    test('caps per-host concurrency', () async {
      final gate = HostRequestGate();
      var active = 0;
      var maxActive = 0;
      await Future.wait(
        List.generate(6, (_) {
          return gate.run('host-a', 'host-a|api', 2, () async {
            active++;
            maxActive = max(maxActive, active);
            await Future.delayed(const Duration(milliseconds: 20));
            active--;
          });
        }),
      );
      expect(maxActive, 2);
    });

    test('blocks one request class on challenge, not others', () async {
      var now = DateTime.utc(2026, 1, 1);
      final gate = HostRequestGate(now: () => now);
      gate.observe('host-b|html', 403, {'cf-mitigated': 'challenge'});
      expect(
        () => gate.run('host-b', 'host-b|html', 2, () async {}),
        throwsA(isA<RateLimitError>()),
      );
      await gate.run('host-b', 'host-b|api', 2, () async {});
      now = now.add(const Duration(minutes: 6));
      await gate.run('host-b', 'host-b|html', 2, () async {});
    });

    test('honors Retry-After and defaults to 60s', () async {
      var now = DateTime.utc(2026, 1, 1);
      final gate = HostRequestGate(now: () => now);
      gate.observe('host-c|api', 429, {'retry-after': '2'});
      expect(
        () => gate.run('host-c', 'host-c|api', 2, () async {}),
        throwsA(isA<RateLimitError>()),
      );
      now = now.add(const Duration(seconds: 3));
      await gate.run('host-c', 'host-c|api', 2, () async {});

      gate.observe('host-d|feed', 503, {});
      expect(
        () => gate.run('host-d', 'host-d|feed', 2, () async {}),
        throwsA(isA<RateLimitError>()),
      );
      now = now.add(const Duration(seconds: 61));
      await gate.run('host-d', 'host-d|feed', 2, () async {});
    });

    test('plain 403 does not block', () async {
      var now = DateTime.utc(2026, 1, 1);
      final gate = HostRequestGate(now: () => now);
      gate.observe('host-e|api', 403, {});
      await gate.run('host-e', 'host-e|api', 2, () async {});
      now = now.add(const Duration(seconds: 1));
      await gate.run('host-e', 'host-e|api', 2, () async {});
    });
  });
}
