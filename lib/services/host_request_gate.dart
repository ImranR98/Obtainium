// Per-host request limiting for metadata requests: bounds concurrency and
// short-circuits requests to hosts that recently challenged or rate-limited us.

import 'dart:async';
import 'dart:math';

import 'package:obtainium/custom_errors.dart';

class HostRequestGate {
  HostRequestGate({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final HostRequestGate instance = HostRequestGate();

  static const Duration challengeBlockDuration = Duration(minutes: 5);
  static const Duration defaultRateLimitBlockDuration = Duration(seconds: 60);

  final DateTime Function() _now;
  final Map<String, _HostState> _hosts = {};
  final Map<String, DateTime> _blockedUntil = {};

  _HostState _state(String host) => _hosts.putIfAbsent(host, _HostState.new);

  int? _remainingBlockMinutes(String blockKey) {
    final until = _blockedUntil[blockKey];
    if (until == null) return null;
    final now = _now();
    if (!now.isBefore(until)) {
      _blockedUntil.remove(blockKey);
      return null;
    }
    return max(1, (until.difference(now).inSeconds / 60).ceil());
  }

  /// Runs [action] honoring [host]'s concurrency limit. [blockKey] identifies
  /// the request class (e.g. api/feed/html) so a challenge on one class does
  /// not suppress the others. Throws [RateLimitError] without invoking
  /// [action] while the class is blocked.
  Future<T> run<T>(
    String host,
    String blockKey,
    int maxConcurrent,
    Future<T> Function() action,
  ) {
    final remainingMinutes = _remainingBlockMinutes(blockKey);
    if (remainingMinutes != null) {
      throw RateLimitError(remainingMinutes);
    }
    return _state(host).run(maxConcurrent, action);
  }

  /// Records a completed response and blocks that request class when it
  /// carries a Cloudflare challenge or a rate-limit signal.
  void observe(String blockKey, int statusCode, Map<String, String> headers) {
    if (statusCode != 403 && statusCode != 429 && statusCode != 503) return;
    final challenge =
        headers['cf-mitigated']?.toLowerCase().trim() == 'challenge';
    if (challenge) {
      _blockUntil(blockKey, _now().add(challengeBlockDuration));
      return;
    }
    if (statusCode == 429 || statusCode == 503) {
      final retryAfter = int.tryParse(headers['retry-after']?.trim() ?? '');
      _blockUntil(
        blockKey,
        _now().add(
          retryAfter != null && retryAfter > 0
              ? Duration(seconds: retryAfter)
              : defaultRateLimitBlockDuration,
        ),
      );
    }
  }

  void _blockUntil(String blockKey, DateTime until) {
    final current = _blockedUntil[blockKey];
    if (current == null || until.isAfter(current)) {
      _blockedUntil[blockKey] = until;
    }
  }
}

class _HostState {
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  Future<T> run<T>(int maxConcurrent, Future<T> Function() action) async {
    while (_active >= maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }
}
