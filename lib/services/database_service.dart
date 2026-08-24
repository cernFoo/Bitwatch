import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/daily_usage.dart';

/// Wraps a local SQLite database (via sqflite) that stores one row per
/// calendar day with the cumulative mobile/Wi-Fi byte totals for that day.
///
/// The native side is the source of truth for "today" (queried live from
/// NetworkStatsManager), while this table stores the historical rollup for
/// the previous 30 days so the History screen can render instantly without
/// re-querying native stats for every past day on every launch.
class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  static const _dbName = 'bitwatch.db';
  static const _dbVersion = 1;
  static const table = 'daily_usage';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $table (
            date TEXT PRIMARY KEY,
            mobile_bytes INTEGER NOT NULL DEFAULT 0,
            wifi_bytes INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  /// Insert or replace the row for [usage.date].
  Future<void> upsertDay(DailyUsage usage) async {
    final db = await database;
    await db.insert(
      table,
      usage.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetch a single day's row, or null if we have no record for that date.
  Future<DailyUsage?> getDay(String date) async {
    final db = await database;
    final rows = await db.query(table, where: 'date = ?', whereArgs: [date]);
    if (rows.isEmpty) return null;
    return DailyUsage.fromMap(rows.first);
  }

  /// Fetch all stored days between [startDate] and [endDate] inclusive
  /// (yyyy-MM-dd strings, which sort lexicographically same as chronologically).
  Future<List<DailyUsage>> getRange(String startDate, String endDate) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date DESC',
    );
    return rows.map(DailyUsage.fromMap).toList();
  }

  /// Wipes every stored historical row. Used by the "Reset Stats" menu action.
  Future<void> resetAll() async {
    final db = await database;
    await db.delete(table);
  }
}
