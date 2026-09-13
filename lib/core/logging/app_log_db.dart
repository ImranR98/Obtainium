import 'package:sqflite/sqflite.dart';

const String _logTable = 'logs';
const String _idColumn = '_id';
const String _levelColumn = 'level';
const String _messageColumn = 'message';
const String _timestampColumn = 'timestamp';
const String _dbPath = 'logs.db';

/// Order must match legacy [LogLevels] indices in logs.db.
enum AppLogLevel { debug, info, warning, error }

class LogEntry {
  LogEntry({
    required this.message,
    required this.level,
    DateTime? timestamp,
    this.id,
  }) : timestamp = timestamp ?? DateTime.now();

  int? id;
  final AppLogLevel level;
  final String message;
  final DateTime timestamp;

  Map<String, Object?> toMap() {
    return {
      _idColumn: id,
      _levelColumn: level.index,
      _messageColumn: message,
      _timestampColumn: timestamp.millisecondsSinceEpoch,
    };
  }

  factory LogEntry.fromMap(Map<String, Object?> map) {
    final rawLevel = map[_levelColumn];
    final level =
        rawLevel is int && rawLevel >= 0 && rawLevel < AppLogLevel.values.length
        ? AppLogLevel.values[rawLevel]
        : AppLogLevel.info;
    return LogEntry(
      id: map[_idColumn] as int?,
      level: level,
      message: map[_messageColumn]?.toString() ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map[_timestampColumn] as int?) ?? 0,
      ),
    );
  }

  @override
  String toString() {
    return '${timestamp.toString()}: ${level.name}: $message';
  }
}

class AppLogDb {
  Database? _db;

  Future<Database> _open() async {
    _db ??= await openDatabase(
      _dbPath,
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table if not exists $_logTable (
  $_idColumn integer primary key autoincrement,
  $_levelColumn integer not null,
  $_messageColumn text not null,
  $_timestampColumn integer not null)
''');
        await _createTimestampIndex(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await _createTimestampIndex(db);
        }
      },
    );
    return _db!;
  }

  /// `query`, `delete` and `purgeOlderThan` all filter on the timestamp, so
  /// without this index they scan the entire table.
  Future<void> _createTimestampIndex(Database db) => db.execute(
    'create index if not exists logs_timestamp_idx '
    'on $_logTable ($_timestampColumn)',
  );

  Future<void> insert(LogEntry entry) async {
    final map = entry.toMap();
    map.remove(_idColumn);
    entry.id = await (await _open()).insert(_logTable, map);
  }

  Future<List<LogEntry>> query({DateTime? before, DateTime? after}) async {
    final where = _whereDates(before: before, after: after);
    final rows = await (await _open()).query(
      _logTable,
      where: where.key,
      whereArgs: where.value,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<int> delete({DateTime? before, DateTime? after}) async {
    final where = _whereDates(before: before, after: after);
    return (await _open()).delete(
      _logTable,
      where: where.key,
      whereArgs: where.value,
    );
  }

  Future<int> purgeOlderThan(Duration maxAge) async {
    return delete(before: DateTime.now().subtract(maxAge));
  }

  MapEntry<String?, List<int>?> _whereDates({
    DateTime? before,
    DateTime? after,
  }) {
    final where = <String>[];
    final whereArgs = <int>[];
    if (before != null) {
      where.add('$_timestampColumn < ?');
      whereArgs.add(before.millisecondsSinceEpoch);
    }
    if (after != null) {
      where.add('$_timestampColumn > ?');
      whereArgs.add(after.millisecondsSinceEpoch);
    }
    return whereArgs.isEmpty
        ? const MapEntry(null, null)
        : MapEntry(where.join(' and '), whereArgs);
  }
}
