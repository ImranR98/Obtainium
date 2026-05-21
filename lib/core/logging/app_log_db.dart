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
    return LogEntry(
      id: map[idColumn] as int,
      level: AppLogLevel.values[map[levelColumn] as int],
      message: map[messageColumn] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map[timestampColumn] as int,
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
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table if not exists $logTable (
  $idColumn integer primary key autoincrement,
  $levelColumn integer not null,
  $messageColumn text not null,
  $timestampColumn integer not null)
''');
      },
    );
    return _db!;
  }

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
