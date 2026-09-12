import 'package:sqflite/sqflite.dart';

const String logTable = 'logs';
const String idColumn = '_id';
const String levelColumn = 'level';
const String messageColumn = 'message';
const String timestampColumn = 'timestamp';
const String dbPath = 'logs.db';

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
      idColumn: id,
      levelColumn: level.index,
      messageColumn: message,
      timestampColumn: timestamp.millisecondsSinceEpoch,
    };
  }

  factory LogEntry.fromMap(Map<String, Object?> map) {
    final rawLevel = map[levelColumn];
    final level =
        rawLevel is int && rawLevel >= 0 && rawLevel < AppLogLevel.values.length
        ? AppLogLevel.values[rawLevel]
        : AppLogLevel.info;
    return LogEntry(
      id: map[idColumn] as int?,
      level: level,
      message: map[messageColumn]?.toString() ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map[timestampColumn] as int?) ?? 0,
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
      dbPath,
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table if not exists $logTable (
  $idColumn integer primary key autoincrement,
  $levelColumn integer not null,
  $messageColumn text not null,
  $timestampColumn integer not null)
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
    'on $logTable ($timestampColumn)',
  );

  Future<void> insert(LogEntry entry) async {
    final map = entry.toMap();
    map.remove(idColumn);
    entry.id = await (await _open()).insert(logTable, map);
  }

  Future<List<LogEntry>> query({DateTime? before, DateTime? after}) async {
    final where = _whereDates(before: before, after: after);
    final rows = await (await _open()).query(
      logTable,
      where: where.key,
      whereArgs: where.value,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<int> delete({DateTime? before, DateTime? after}) async {
    final where = _whereDates(before: before, after: after);
    return (await _open()).delete(
      logTable,
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
      where.add('$timestampColumn < ?');
      whereArgs.add(before.millisecondsSinceEpoch);
    }
    if (after != null) {
      where.add('$timestampColumn > ?');
      whereArgs.add(after.millisecondsSinceEpoch);
    }
    return whereArgs.isEmpty
        ? const MapEntry(null, null)
        : MapEntry(where.join(' and '), whereArgs);
  }
}
