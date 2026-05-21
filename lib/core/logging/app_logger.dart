import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:obtainium/core/logging/app_log_db.dart';

class AppLogger {
  AppLogger._();

  static AppLogDb? _db;

  static final Logger _logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: !kReleaseMode,
      printEmojis: false,
      noBoxingByDefault: true,
    ),
  );

  static Future<void> init() async {
    if (_db != null) return;
    _db = AppLogDb();
    await _db!.purgeOlderThan(const Duration(days: 7));
  }

  static Future<List<LogEntry>> getLogs({
    DateTime? before,
    DateTime? after,
  }) async {
    if (_db == null) return [];
    return _db!.query(before: before, after: after);
  }

  static Future<int> clearLogs({DateTime? before, DateTime? after}) async {
    if (_db == null) return 0;
    return _db!.delete(before: before, after: after);
  }

  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.warning, message, error: error, stackTrace: stackTrace);
  }

  static void error(Object error, {StackTrace? stackTrace, String? message}) {
    final text = message ?? 'Unexpected error';
    _logToConsole(
      AppLogLevel.error,
      text,
      error: error,
      stackTrace: stackTrace,
    );
    _persist(
      LogEntry(
        message: _formatPersistedError(text, error),
        level: AppLogLevel.error,
      ),
    );
  }

  static void _log(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logToConsole(level, message, error: error, stackTrace: stackTrace);
    if (level != AppLogLevel.debug) {
      _persist(
        LogEntry(
          message: _formatPersistedMessage(message, error),
          level: level,
        ),
      );
    }
  }

  static void _logToConsole(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    switch (level) {
      case AppLogLevel.debug:
        _logger.d(message, error: error, stackTrace: stackTrace);
      case AppLogLevel.info:
        _logger.i(message, error: error, stackTrace: stackTrace);
      case AppLogLevel.warning:
        _logger.w(message, error: error, stackTrace: stackTrace);
      case AppLogLevel.error:
        _logger.e(message, error: error, stackTrace: stackTrace);
    }
  }

  static void _persist(LogEntry entry) {
    final db = _db;
    if (db == null) return;
    unawaited(db.insert(entry));
  }

  static String _formatPersistedMessage(String message, Object? error) {
    if (error == null) return message;
    return '$message: $error';
  }

  static String _formatPersistedError(String message, Object error) {
    return '$message: $error';
  }
}
