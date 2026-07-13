import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'notice_transmit.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        package_name TEXT NOT NULL,
        app_name TEXT NOT NULL,
        post_time INTEGER NOT NULL,
        time TEXT NOT NULL,
        type TEXT NOT NULL,
        device_name TEXT,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_notifications_post_time ON notifications(post_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_notifications_type ON notifications(type)
    ''');

    await db.execute('''
      CREATE INDEX idx_notifications_package ON notifications(package_name)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _onCreate(db, 1);
    }
  }

  Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = prefs.getString('records');
    if (recordsJson == null || recordsJson == '[]') return;

    try {
      final List<dynamic> records = json.decode(recordsJson);
      if (records.isEmpty) return;

      final db = await database;
      await db.transaction((txn) async {
        for (final record in records) {
          if (record is Map<String, dynamic>) {
            try {
              await txn.insert('notifications', {
                'id': record['id'] ?? '',
                'title': record['title'] ?? '',
                'content': record['content'] ?? '',
                'package_name': record['package_name'] ?? '',
                'app_name': record['app_name'] ?? '',
                'post_time': record['post_time'] ?? 0,
                'time': record['time'] ?? '',
                'type': record['type'] ?? 'other',
                'device_name': record['device_name'] ?? '',
                'timestamp': record['timestamp'] ?? 0,
                'created_at': DateTime.now().millisecondsSinceEpoch,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            } catch (_) {}
          }
        }
      });

      await prefs.remove('records');
    } catch (_) {}
  }

  Future<void> insertNotification(Map<String, dynamic> record) async {
    final db = await database;
    await db.insert('notifications', {
      'id': record['id'] ?? '',
      'title': record['title'] ?? '',
      'content': record['content'] ?? '',
      'package_name': record['package_name'] ?? '',
      'app_name': record['app_name'] ?? '',
      'post_time': record['post_time'] ?? 0,
      'time': record['time'] ?? '',
      'type': record['type'] ?? 'other',
      'device_name': record['device_name'] ?? '',
      'timestamp': record['timestamp'] ?? 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getNotifications({
    int limit = 100,
    String? type,
    String? packageName,
  }) async {
    final db = await database;
    var sql = 'SELECT * FROM notifications ORDER BY post_time DESC LIMIT ?';
    final args = <dynamic>[limit];

    if (type != null) {
      sql =
          'SELECT * FROM notifications WHERE type = ? ORDER BY post_time DESC LIMIT ?';
      args.insert(0, type);
    } else if (packageName != null) {
      sql =
          'SELECT * FROM notifications WHERE package_name = ? ORDER BY post_time DESC LIMIT ?';
      args.insert(0, packageName);
    }

    return await db.rawQuery(sql, args);
  }

  Future<int> getNotificationCount({String? type, String? packageName}) async {
    final db = await database;
    var sql = 'SELECT COUNT(*) FROM notifications';
    final args = <dynamic>[];

    if (type != null) {
      sql = 'SELECT COUNT(*) FROM notifications WHERE type = ?';
      args.add(type);
    } else if (packageName != null) {
      sql = 'SELECT COUNT(*) FROM notifications WHERE package_name = ?';
      args.add(packageName);
    }

    final result = await db.rawQuery(sql, args);
    return result.isNotEmpty ? (result.first.values.first as int) : 0;
  }

  Future<void> deleteNotification(String id) async {
    final db = await database;
    await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteOldNotifications(int keepDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: keepDays))
        .millisecondsSinceEpoch;
    await db.delete(
      'notifications',
      where: 'post_time < ?',
      whereArgs: [cutoffTime],
    );
  }

  Future<void> clearAllNotifications() async {
    final db = await database;
    await db.delete('notifications');
  }

  Future<List<Map<String, dynamic>>> getNotificationStats() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT type, app_name, COUNT(*) as count
      FROM notifications
      GROUP BY type, app_name
      ORDER BY count DESC
      LIMIT 20
    ''');
  }

  Future<List<Map<String, dynamic>>> getDailyStats(int days) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return await db.rawQuery(
      '''
      SELECT date(post_time / 1000, 'unixepoch') as date, COUNT(*) as count
      FROM notifications
      WHERE post_time >= ?
      GROUP BY date
      ORDER BY date DESC
    ''',
      [cutoffTime],
    );
  }
}
