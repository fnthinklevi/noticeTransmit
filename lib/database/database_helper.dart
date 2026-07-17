import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/secure_storage_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const _encryptedDbName = 'notice_transmit_encrypted.db';
  static const _oldDbName = 'notice_transmit.db';
  static const _encryptionKeyStoreKey = 'db_encryption_key';

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 获取或生成数据库加密密钥（AES-256，存储在 Android Keystore 中）
  Future<String> _getEncryptionKey() async {
    final secureStorage = SecureStorageService();
    var key = await secureStorage.read(_encryptionKeyStoreKey);
    if (key == null || key.length != 64) {
      // 首次启动或密钥损坏：生成 256 位随机十六进制密钥
      key = _generateRandomHexKey();
      await secureStorage.write(_encryptionKeyStoreKey, key);
    }
    return key;
  }

  String _generateRandomHexKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final encryptedPath = join(databasesPath, _encryptedDbName);
    final oldPath = join(databasesPath, _oldDbName);
    final password = await _getEncryptionKey();

    try {
      // 尝试打开加密数据库
      return await openDatabase(
        encryptedPath,
        password: password,
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      // 打开失败：可能仍是旧版明文数据库
      // 删除明文旧文件和残损文件，重新创建加密数据库
      try {
        await File(oldPath).delete();
      } catch (_) {}
      try {
        await File(encryptedPath).delete();
      } catch (_) {}

      return await openDatabase(
        encryptedPath,
        password: password,
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        sub_text TEXT,
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

    await db.execute('''
      CREATE TABLE pending_notifications (
        id TEXT PRIMARY KEY,
        notification_data TEXT NOT NULL,
        webhook_url TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_retry_time INTEGER DEFAULT 0,
        added_time INTEGER NOT NULL,
        status_code INTEGER,
        error_message TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _onCreate(db, 1);
    }
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE pending_notifications (
          id TEXT PRIMARY KEY,
          notification_data TEXT NOT NULL,
          webhook_url TEXT NOT NULL,
          retry_count INTEGER DEFAULT 0,
          last_retry_time INTEGER DEFAULT 0,
          added_time INTEGER NOT NULL,
          status_code INTEGER,
          error_message TEXT
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE notifications ADD COLUMN sub_text TEXT
      ''');
    }
  }

  Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = prefs.getString('notification_records');
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
                'sub_text': record['subText'] ?? '',
                'package_name':
                    record['packageName'] ?? record['package_name'] ?? '',
                'app_name': record['appName'] ?? record['app_name'] ?? '',
                'post_time': record['postTime'] ?? record['post_time'] ?? 0,
                'time': record['time'] ?? '',
                'type': record['type'] ?? 'other',
                'device_name':
                    record['deviceName'] ?? record['device_name'] ?? '',
                'timestamp': record['timestamp'] ?? 0,
                'created_at': DateTime.now().millisecondsSinceEpoch,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            } catch (_) {}
          }
        }
      });

      await prefs.remove('notification_records');
    } catch (_) {}
  }

  Future<void> insertNotification(Map<String, dynamic> record) async {
    final db = await database;
    final dbMap = <String, dynamic>{
      'id': record['id'] ?? '',
      'title': record['title'] ?? '',
      'content': record['content'] ?? '',
      'sub_text': record['subText'] ?? record['sub_text'] ?? '',
      'package_name': record['packageName'] ?? record['package_name'] ?? '',
      'app_name': record['appName'] ?? record['app_name'] ?? '',
      'post_time': record['postTime'] ?? record['post_time'] ?? 0,
      'time': record['time'] ?? '',
      'type': record['type'] ?? 'other',
      'device_name': record['deviceName'] ?? record['device_name'] ?? '',
      'timestamp': record['timestamp'] ?? 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
    await db.insert(
      'notifications',
      dbMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      SELECT type, app_name AS appName, package_name AS packageName, COUNT(*) as count
      FROM notifications
      GROUP BY type, app_name, package_name
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

  Future<void> insertPendingNotification(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'pending_notifications',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingNotifications() async {
    final db = await database;
    return await db.query(
      'pending_notifications',
      orderBy: 'added_time DESC',
      limit: 100,
    );
  }

  Future<void> deletePendingNotification(String id) async {
    final db = await database;
    await db.delete('pending_notifications', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePendingNotification(Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'pending_notifications',
      data,
      where: 'id = ?',
      whereArgs: [data['id']],
    );
  }

  Future<void> clearAllPendingNotifications() async {
    final db = await database;
    await db.delete('pending_notifications');
  }
}
