import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/channel_display.dart';
import '../services/secure_storage_service.dart';

/// 数据库加密密钥丢失/损坏异常。
/// 由 [_initDatabase] 捕获后走「备份原库 + 重建」路径，禁止静默删库。
class DatabaseKeyLostException implements Exception {}

/// Webhook 通道存取抽象。
/// 默认实现为 SQLCipher 加密库 [DatabaseHelper]；测试可注入伪实现，
/// 以覆盖「UI 通道 → DB 行 → 原生同步」的完整保存链路而不依赖原生加密库。
abstract class WebhookChannelStore {
  Future<List<Map<String, dynamic>>> getWebhookChannels();
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels);
}

/// 自建应用通道存储抽象（可注入 fake 供测试）
abstract class AppChannelStore {
  Future<List<Map<String, dynamic>>> getAppChannels();
  Future<void> saveAppChannels(List<Map<String, dynamic>> channels);
}

class DatabaseHelper implements WebhookChannelStore, AppChannelStore {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const _encryptedDbName = 'notice_transmit_encrypted.db';
  static const _oldDbName = 'notice_transmit.db';
  static const _encryptionKeyStoreKey = 'db_encryption_key';

  /// 当前 schema 版本。**任何** openDatabase 调用（含迁移期新建的加密库）都必须用它，
  /// 否则库会被贴上旧版本号（历史缺陷：迁移期用 version:3 建库，而 _onCreate 已是全量
  /// schema）→ 下次启动触发 onUpgrade(3→N)，对已存在的列重复 ALTER 抛 duplicate column，
  /// 打开失败即备份重建空库，用户历史与库内通道配置全丢。
  static const int dbVersion = 11;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 获取数据库加密密钥（AES-256，存储在 Android Keystore 中）。
  ///
  /// 仅在加密数据库尚不存在时允许生成新密钥（首次启动）。若加密库已存在而密钥
  /// 缺失/长度不符，说明是密钥丢失而非首次启动——此时禁止用新密钥覆盖存储，
  /// 抛出 [DatabaseKeyLostException] 交由上层备份原库，避免旧库永久无法打开、
  /// 数据被静默清空。
  Future<String> _getEncryptionKey() async {
    final secureStorage = SecureStorageService();
    var key = await secureStorage.read(_encryptionKeyStoreKey);
    if (key == null || key.length != 64) {
      final databasesPath = await getDatabasesPath();
      final encryptedExists = await File(
        join(databasesPath, _encryptedDbName),
      ).exists();
      if (!encryptedExists) {
        // 首次启动（无库无钥）：生成 256 位随机十六进制密钥
        key = _generateRandomHexKey();
        await secureStorage.write(_encryptionKeyStoreKey, key);
      } else {
        throw DatabaseKeyLostException();
      }
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

    // 密钥丢失时先备份原库（保留恢复路径），再为新库生成新密钥；
    // 绝不静默覆盖密钥 → 旧库彻底无法打开、数据被悄悄清空。
    String password;
    try {
      password = await _getEncryptionKey();
    } on DatabaseKeyLostException {
      await _backupDatabaseFile(encryptedPath);
      await _backupDatabaseFile(oldPath);
      password = _generateRandomHexKey();
      await SecureStorageService().write(_encryptionKeyStoreKey, password);
    }

    // 从旧明文数据库迁移数据到新加密数据库
    await _migrateOldDatabaseIfNeeded(oldPath, encryptedPath, password);

    try {
      return await openDatabase(
        encryptedPath,
        password: password,
        version: dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      // 打开失败（密钥不符 / 库文件损坏）：先备份原文件再重建，避免数据被静默清空。
      // 备份文件保留在磁盘上，作为人工恢复路径。
      await _backupDatabaseFile(encryptedPath);
      await _backupDatabaseFile(oldPath);

      return await openDatabase(
        encryptedPath,
        password: password,
        version: dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  /// 把指定数据库文件重命名为带时间戳的备份文件（保留原数据供恢复）。
  /// 返回备份路径；文件不存在或重命名失败时返回 null。
  Future<String?> _backupDatabaseFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final backupPath =
          '$path.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      await file.rename(backupPath);
      return backupPath;
    } catch (_) {
      return null;
    }
  }

  /// 从旧明文数据库迁移数据到新加密数据库。
  ///
  /// 仅在旧数据库存在且新加密数据库不存在时执行。
  /// 迁移完成后删除旧数据库文件。
  Future<void> _migrateOldDatabaseIfNeeded(
    String oldPath,
    String encryptedPath,
    String password,
  ) async {
    final oldExists = await File(oldPath).exists();
    final encryptedExists = await File(encryptedPath).exists();

    // 只有旧库存在且新库不存在时才迁移
    if (!oldExists || encryptedExists) return;

    List<Map<String, dynamic>> oldNotifications = [];
    List<Map<String, dynamic>> oldPending = [];

    // 1. 打开旧明文数据库（不传 password，SQLCipher 可读取明文库）
    try {
      final oldDb = await openDatabase(oldPath, version: 3);
      try {
        oldNotifications = await oldDb.query('notifications');
      } catch (_) {}
      try {
        oldPending = await oldDb.query('pending_notifications');
      } catch (_) {}
      await oldDb.close();
    } catch (_) {
      // 旧库无法打开 — 删除后跳过迁移
      try {
        await File(oldPath).delete();
      } catch (_) {}
      return;
    }

    // 没有数据可迁移 — 直接删除旧库
    if (oldNotifications.isEmpty && oldPending.isEmpty) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
      return;
    }

    // 2. 创建新加密数据库并导入数据
    Database? newDb;
    try {
      newDb = await openDatabase(
        encryptedPath,
        password: password,
        // 与生产打开路径同版本号：迁移期建的是「当前全量 schema」的库，贴旧号会让
        // 下次启动跑 onUpgrade 并对已存在的列重复 ALTER（曾整库被备份重建）。
        version: dbVersion,
        onCreate: _onCreate,
      );

      if (oldNotifications.isNotEmpty) {
        await newDb.transaction((txn) async {
          for (final record in oldNotifications) {
            try {
              await txn.insert(
                'notifications',
                record,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            } catch (_) {}
          }
        });
      }

      if (oldPending.isNotEmpty) {
        await newDb.transaction((txn) async {
          for (final record in oldPending) {
            try {
              await txn.insert(
                'pending_notifications',
                record,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            } catch (_) {}
          }
        });
      }

      await newDb.close();
      newDb = null;
    } catch (_) {
      // 迁移失败 — 删除残损的加密库，下次启动重试
      if (newDb != null) {
        try {
          await newDb.close();
        } catch (_) {}
      }
      try {
        await File(encryptedPath).delete();
      } catch (_) {}
      return;
    }

    // 3. 迁移成功 — 删除旧明文数据库
    try {
      await File(oldPath).delete();
    } catch (_) {}
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
        priority INTEGER NOT NULL DEFAULT 1,
        delivery_info TEXT,
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

    await db.execute('''
      CREATE TABLE email_channels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        smtp_host TEXT NOT NULL,
        smtp_port INTEGER NOT NULL DEFAULT 465,
        username TEXT NOT NULL,
        password TEXT NOT NULL DEFAULT '',
        from_email TEXT NOT NULL,
        to_email TEXT NOT NULL,
        use_ssl INTEGER NOT NULL DEFAULT 1,
        subject_template TEXT,
        body_template TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE webhook_channels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        channel_type TEXT NOT NULL DEFAULT 'generic',
        enabled INTEGER NOT NULL DEFAULT 1,
        secret TEXT,
        message_format TEXT NOT NULL DEFAULT 'default',
        message_template TEXT,
        extra_config TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // v5: Webhook 送达日志表（用于送达校验失败/成功记录归档）
    await db.execute('''
      CREATE TABLE webhook_delivery_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_url TEXT NOT NULL,
        notification_id TEXT,
        tag TEXT,
        status TEXT NOT NULL,
        http_code INTEGER,
        message TEXT,
        retryable INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_delivery_log_timestamp ON webhook_delivery_log(timestamp)
    ''');
    await db.execute('''
      CREATE INDEX idx_delivery_log_status ON webhook_delivery_log(status)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_channels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        app_type TEXT NOT NULL,
        base_url TEXT NOT NULL DEFAULT '',
        secret TEXT,
        config TEXT,
        message_format TEXT NOT NULL DEFAULT 'default',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  /// 仅供测试：在 sqflite_common_ffi 下直接跑建表 / 升级逻辑，验证迁移幂等。
  @visibleForTesting
  Future<void> createSchemaForTest(Database db) => _onCreate(db, dbVersion);

  @visibleForTesting
  Future<void> upgradeSchemaForTest(Database db, int oldV, int newV) =>
      _onUpgrade(db, oldV, newV);

  /// 幂等加列：列已存在时直接跳过。
  ///
  /// 迁移路径曾把「当前全量 schema」的库贴上旧版本号，onUpgrade 于是对已存在的列重复
  /// ALTER 并抛 duplicate column —— 打开失败会被 _initDatabase 的 catch 备份成
  /// `.corrupt-*` 再重建空库，历史与库内通道配置就此丢失。版本号已统一为 [dbVersion]，
  /// 这层存在性判定兜住**已被错号标记的存量库**（它们每次启动都会重演该路径）。
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((r) => r['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _onCreate(db, 1);
    }
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_notifications (
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
      await _addColumnIfMissing(db, 'notifications', 'sub_text', 'TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS email_channels (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          smtp_host TEXT NOT NULL,
          smtp_port INTEGER NOT NULL DEFAULT 465,
          username TEXT NOT NULL,
          password TEXT NOT NULL DEFAULT '',
          from_email TEXT NOT NULL,
          to_email TEXT NOT NULL,
          use_ssl INTEGER NOT NULL DEFAULT 1,
          subject_template TEXT,
          body_template TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS webhook_channels (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          url TEXT NOT NULL,
          channel_type TEXT NOT NULL DEFAULT 'generic',
          enabled INTEGER NOT NULL DEFAULT 1,
          secret TEXT,
          message_format TEXT NOT NULL DEFAULT 'default',
          message_template TEXT,
        extra_config TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      // v5: Webhook 送达日志表（用于送达校验失败/成功记录归档）
      await db.execute('''
        CREATE TABLE IF NOT EXISTS webhook_delivery_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          channel_url TEXT NOT NULL,
          notification_id TEXT,
          tag TEXT,
          status TEXT NOT NULL,
          http_code INTEGER,
          message TEXT,
          retryable INTEGER NOT NULL DEFAULT 0,
          timestamp INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_delivery_log_timestamp
        ON webhook_delivery_log(timestamp)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_delivery_log_status
        ON webhook_delivery_log(status)
      ''');
    }
    if (oldVersion < 6) {
      // v6: Webhook 推送模板系统
      // - message_format: default/text/markdown/json/xml
      // - message_template: 用户自定义模板（含 %appName% 等变量占位符，空则用预置模板）
      await _addColumnIfMissing(
        db,
        'webhook_channels',
        'message_format',
        "TEXT NOT NULL DEFAULT 'default'",
      );
      await _addColumnIfMissing(
        db,
        'webhook_channels',
        'message_template',
        'TEXT',
      );
    }
    if (oldVersion < 7) {
      // v7: 通知记录逐条送达状态（JSON：{"chan:wechat_work": {"status":"success","message":"..."}}）
      // 键在 v11 前存的是本地化显示名，见 v11 分支
      await _addColumnIfMissing(db, 'notifications', 'delivery_info', 'TEXT');
    }
    if (oldVersion < 8) {
      // v8: 通知优先级分级（0=低 / 1=中 / 2=高），旧数据默认中优先级
      await _addColumnIfMissing(
        db,
        'notifications',
        'priority',
        'INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 9) {
      // v9: 通道扩展配置（企业微信自建应用 corpid/agentid/touser 等，JSON 键值）
      await _addColumnIfMissing(db, 'webhook_channels', 'extra_config', 'TEXT');
    }
    if (oldVersion < 10) {
      // v10: 自建应用通道独立表（应用通道体系，与 webhook 分离）；
      // 迁移 webhook_channels 中的 wecom_app 行，并在迁移后从 webhook 表清除
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_channels (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          app_type TEXT NOT NULL,
          base_url TEXT NOT NULL DEFAULT '',
          secret TEXT,
          config TEXT,
          message_format TEXT NOT NULL DEFAULT 'default',
          enabled INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO app_channels
          (id, name, app_type, base_url, secret, config, message_format, enabled, created_at, updated_at)
        SELECT id, name, 'wecom_app', url, secret, COALESCE(extra_config, '{}'),
               COALESCE(message_format, 'default'), enabled, created_at, updated_at
        FROM webhook_channels WHERE channel_type = 'wecom_app'
      ''');
      await db.execute(
        "DELETE FROM webhook_channels WHERE channel_type = 'wecom_app'",
      );
    }
    if (oldVersion < 11) {
      // v11: 送达键去本地化（不改表结构，只改写值）
      await _migrateDeliveryKeysToCanonical(db);
    }
  }

  /// 把逐条送达状态与送达日志里的「通道标识」改写为稳定键 `chan:<slug>`。
  ///
  /// v11 之前存的是**显示名**（`webhook:企业微信` / `邮件`，英文环境是
  /// `webhook:WeCom` / `Email`），于是切换语言或改一次文案就会让同一通道的
  /// 键分裂（表现为某些通道永远「发送中」、送达健康统计按语言拆成两行）。
  /// 幂等：已归一的键写回同值，重复执行结果不变。
  Future<void> _migrateDeliveryKeysToCanonical(Database db) async {
    // 迁移异常**不向上抛**：onUpgrade 抛错会让 _initDatabase 走「备份原库 +
    // 重建空库」分支，等于把用户历史连库里已配置的通道一起清掉。
    // 读取侧（NotificationRecord.fromMap → normalizeDeliveryKeys）本就兼容旧键，
    // 所以此处失败最多是旧键留在库里、记录下次写回时自愈，不会显示错状态。
    try {
      // 不在这里再开 transaction()：onUpgrade 本身已跑在 sqflite 打开库的事务里，
      // 嵌套 BEGIN 在 SQLite 层是错误，逐条 db.update 已被外层事务批量吞掉。
      final rows = await db.query(
        'notifications',
        columns: ['id', 'delivery_info'],
        where: 'delivery_info IS NOT NULL AND delivery_info != \'\'',
      );
      for (final row in rows) {
        final raw = row['delivery_info'];
        if (raw is! String || raw.isEmpty) continue;
        dynamic decoded;
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          // 单行坏 JSON 只跳过本行：整批抛出会让下面的 catch 吞掉全部迁移
          continue;
        }
        if (decoded is! Map) continue;
        final normalized = normalizeDeliveryKeys(
          Map<String, dynamic>.from(decoded),
        );
        final encoded = jsonEncode(normalized);
        if (encoded == raw) continue;
        await db.update(
          'notifications',
          {'delivery_info': encoded},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }

      // 送达日志的 tag 同理：GROUP BY tag 的送达健康统计、按 (tag,status,code,msg)
      // 折叠的展示层去重，都要求同一通道只有一个拼写。
      final tags = await db.rawQuery(
        'SELECT DISTINCT tag FROM webhook_delivery_log '
        'WHERE tag IS NOT NULL AND tag NOT LIKE ?',
        ['$kDeliveryKeyPrefix%'],
      );
      for (final row in tags) {
        final old = row['tag'];
        if (old is! String || old.isEmpty) continue;
        await db.update(
          'webhook_delivery_log',
          {'tag': channelDeliveryKey(old)},
          where: 'tag = ?',
          whereArgs: [old],
        );
      }
    } catch (e) {
      debugPrint('送达键归一迁移失败（读取侧兼容旧键，不影响数据）: $e');
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
                'priority': record['priority'] ?? 1,
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
      'priority': record['priority'] ?? 1,
      'delivery_info':
          record['deliveryStatus'] != null &&
              (record['deliveryStatus'] as Map).isNotEmpty
          ? jsonEncode(record['deliveryStatus'])
          : null,
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

  /// 全量通知记录（导出用），按 post_time 倒序，不受分页上限约束
  Future<List<Map<String, dynamic>>> getAllNotifications() async {
    final db = await database;
    return await db.rawQuery(
      'SELECT * FROM notifications ORDER BY post_time DESC',
    );
  }

  /// LIKE 通配符转义（配合 ESCAPE '\'，避免用户输入 % _ 引起意外匹配）
  static String escapeLike(String v) => v
      .trim()
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  /// 构建推送历史搜索的 WHERE 子句（纯函数，单测锁定行为）。
  ///
  /// 两层筛选设计（P1）：
  /// - SQLite LIKE 粗筛：keyword 命中 title/content/app_name/package_name，
  ///   送达状态对 delivery_info JSON 文本做 LIKE 粗筛（不引 JSON1 扩展依赖）；
  /// - 精确判定由调用方在 Dart 端 jsonDecode delivery_info 后完成
  ///   （见 NotificationService.searchRecords）。
  static (String where, List<dynamic> args) buildSearchSql({
    String? keyword,
    int? startTime,
    int? endTime,
    String? appName,
    String? packageName,
    String? deliveryFilter,
  }) {
    final conds = <String>[];
    final args = <dynamic>[];
    if (keyword != null && keyword.trim().isNotEmpty) {
      final like = '%${escapeLike(keyword)}%';
      conds.add(
        "(title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' "
        "OR app_name LIKE ? ESCAPE '\\' OR package_name LIKE ? ESCAPE '\\')",
      );
      args.addAll([like, like, like, like]);
    }
    if (startTime != null) {
      conds.add('post_time >= ?');
      args.add(startTime);
    }
    if (endTime != null) {
      conds.add('post_time < ?');
      args.add(endTime);
    }
    if (appName != null && appName.trim().isNotEmpty) {
      conds.add("app_name LIKE ? ESCAPE '\\'");
      args.add('%${escapeLike(appName)}%');
    }
    if (packageName != null && packageName.trim().isNotEmpty) {
      conds.add("package_name LIKE ? ESCAPE '\\'");
      args.add('%${escapeLike(packageName)}%');
    }
    if (deliveryFilter == 'failed') {
      conds.add('delivery_info LIKE ?');
      args.add('%failed%');
    } else if (deliveryFilter == 'success') {
      conds.add('delivery_info LIKE ?');
      args.add('%success%');
    }
    final where = conds.isEmpty ? '' : 'WHERE ${conds.join(' AND ')}';
    return (where, args);
  }

  /// 全量历史搜索（P1）：按关键字/时间范围/应用名/包名/送达状态筛选，
  /// post_time DESC 排序，LIMIT/OFFSET 分页。post_time 已有索引。
  Future<List<Map<String, dynamic>>> searchNotifications({
    String? keyword,
    int? startTime,
    int? endTime,
    String? appName,
    String? packageName,
    String? deliveryFilter,
    int limit = 200,
    int offset = 0,
  }) async {
    final (where, args) = buildSearchSql(
      keyword: keyword,
      startTime: startTime,
      endTime: endTime,
      appName: appName,
      packageName: packageName,
      deliveryFilter: deliveryFilter,
    );
    final db = await database;
    return await db.rawQuery(
      'SELECT * FROM notifications $where '
      'ORDER BY post_time DESC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
  }

  /// 写入一条 Webhook 送达日志（webhook_delivery_log，DB v5 落地）。
  /// 写入时顺带清理 30 天前的旧记录，防止表无限膨胀。
  Future<void> insertDeliveryLog({
    required String channelUrl,
    required String notificationId,
    required String tag,
    required String status,
    int? httpCode,
    String? message,
    int retryable = 0,
  }) async {
    final db = await database;
    await db.insert('webhook_delivery_log', {
      'channel_url': channelUrl,
      'notification_id': notificationId,
      'tag': tag,
      'status': status,
      'http_code': httpCode,
      'message': message,
      'retryable': retryable,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await db.delete(
      'webhook_delivery_log',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  /// 查询送达日志（调试/对账用），按时间倒序，limit 默认 200
  Future<List<Map<String, dynamic>>> getDeliveryLogs({int limit = 200}) async {
    final db = await database;
    return await db.rawQuery(
      'SELECT * FROM webhook_delivery_log ORDER BY timestamp DESC LIMIT ?',
      [limit],
    );
  }

  // ── 自建应用通道（app_channels，DB v10）──

  @override
  Future<List<Map<String, dynamic>>> getAppChannels() async {
    final db = await database;
    return await db.query('app_channels', orderBy: 'updated_at DESC');
  }

  @override
  Future<void> saveAppChannels(List<Map<String, dynamic>> channels) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('app_channels');
      var i = 0;
      for (final c in channels) {
        final rawId = c['id'] as String?;
        final row = <String, dynamic>{
          'id': (rawId != null && rawId.isNotEmpty)
              ? rawId
              : 'app_${now}_${i++}',
          'name': c['name'] ?? '',
          'app_type':
              c['appType']?.toString() ??
              c['app_type']?.toString() ??
              'wecom_app',
          'base_url':
              c['baseUrl']?.toString() ?? c['base_url']?.toString() ?? '',
          'secret': c['secret'],
          // config 为 Map → JSON 字符串落库
          'config': c['config'] is Map
              ? jsonEncode(c['config'])
              : (c['config'] ?? '{}'),
          'message_format': c['message_format']?.toString() ?? 'default',
          'enabled': (c['enabled'] == true || c['enabled'] == 1) ? 1 : 0,
          'created_at': c['created_at'] ?? now,
          'updated_at': now,
        };
        await txn.insert('app_channels', row);
      }
    });
  }

  /// 送达健康统计：N 天内各通道 推送数/成功数（webhook_delivery_log 聚合）
  Future<List<Map<String, dynamic>>> getChannelSuccessRates({
    int days = 7,
  }) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return await db.rawQuery(
      'SELECT tag, COUNT(*) AS total, '
      "SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success "
      'FROM webhook_delivery_log WHERE timestamp >= ? '
      'GROUP BY tag ORDER BY total DESC',
      [since],
    );
  }

  /// 失败原因 TOP：N 天内按 HTTP 码聚类（code 为空 = 网络/连接类失败）
  Future<List<Map<String, dynamic>>> getTopFailureReasons({
    int days = 7,
    int limit = 5,
  }) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return await db.rawQuery(
      'SELECT COALESCE(http_code, -1) AS code, COUNT(*) AS cnt '
      'FROM webhook_delivery_log '
      "WHERE status != 'success' AND timestamp >= ? "
      'GROUP BY code ORDER BY cnt DESC LIMIT ?',
      [since, limit],
    );
  }

  /// 高峰时段分布：N 天内通知记录按小时（0-23）计数（notifications 聚合）
  Future<List<Map<String, dynamic>>> getHourlyDistribution({
    int days = 7,
  }) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return await db.rawQuery(
      "SELECT CAST(strftime('%H', post_time / 1000, 'unixepoch', 'localtime') AS INTEGER) AS hour, "
      'COUNT(*) AS cnt FROM notifications WHERE post_time >= ? '
      'GROUP BY hour',
      [since],
    );
  }

  /// 按通知 ID 查询送达日志（历史详情弹层展示），按时间倒序。
  ///
  /// 展示层去重：历史版本存在广播+补偿拉取双写导致的重复终态行，
  /// 折叠后保留最新一条，兼容清理存量重复数据
  /// （新写入已由 insertDeliveryLog 幂等拦截）。
  Future<List<Map<String, dynamic>>> getDeliveryLogsByNotification(
    String notificationId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT * FROM webhook_delivery_log '
      'WHERE notification_id = ? ORDER BY timestamp DESC',
      [notificationId],
    );
    return dedupeDeliveryLogs(rows);
  }

  /// 送达日志展示层折叠：按 (tag, status, http_code, message) 去重，
  /// 保留顺序中的首条（调用方按 timestamp DESC 排序时即最新一条）。
  static List<Map<String, dynamic>> dedupeDeliveryLogs(
    List<Map<String, dynamic>> rows,
  ) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final r in rows) {
      final key =
          '${r['tag']}|${r['status']}|${r['http_code']}|${r['message']}';
      if (seen.add(key)) result.add(r);
    }
    return result;
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

  /// 当日（本地时区 0 点至次日 0 点）记录数，用于统一三处统计口径
  Future<int> getTodayCount() async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final end = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).millisecondsSinceEpoch;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM notifications WHERE post_time >= ? AND post_time < ?',
      [start, end],
    );
    return result.isNotEmpty ? (result.first.values.first as int) : 0;
  }

  /// 更新单条通知记录的送达状态（delivery_info JSON 列）
  /// 按 id 查询单条通知（原始行，含 delivery_info JSON 字符串）。
  /// 用于送达回传兜底：内存列表未命中时仍可更新 DB（分页未加载/裁剪场景）。
  Future<Map<String, dynamic>?> getNotificationById(String id) async {
    final db = await database;
    final rows = await db.query(
      'notifications',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateNotificationDelivery(
    String id,
    Map<String, dynamic> delivery,
  ) async {
    final db = await database;
    await db.update(
      'notifications',
      {'delivery_info': delivery.isEmpty ? null : jsonEncode(delivery)},
      where: 'id = ?',
      whereArgs: [id],
    );
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
      SELECT date(post_time / 1000, 'unixepoch', 'localtime') as date, COUNT(*) as count
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

  // ========== 邮件通道（email_channels） ==========

  Future<List<Map<String, dynamic>>> getEmailChannels() async {
    final db = await database;
    return await db.query('email_channels', orderBy: 'updated_at DESC');
  }

  Future<void> saveEmailChannels(List<Map<String, dynamic>> channels) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('email_channels');
      var i = 0;
      for (final c in channels) {
        final rawId = c['id']?.toString();
        final row = <String, dynamic>{
          // 与 saveWebhookChannels / saveAppChannels 同规则：id 缺失或为空时兜底生成。
          // 此前写死 `c['id'] ?? ''`，两条无 id 的通道会以同一个空主键落库，
          // 后一条 replace 掉前一条 ⇒ 保存一次静默丢一条邮箱通道。
          'id': (rawId != null && rawId.isNotEmpty)
              ? rawId
              : 'em_${now}_${i++}',
          'name': c['name'] ?? '',
          'enabled': (c['enabled'] == true || c['enabled'] == 1) ? 1 : 0,
          'smtp_host': c['smtpHost'] ?? '',
          'smtp_port': c['smtpPort'] ?? 465,
          'username': c['username'] ?? '',
          'password': c['password'] ?? '',
          'from_email': c['fromEmail'] ?? '',
          'to_email': c['toEmail'] ?? '',
          'use_ssl': (c['useSSL'] != false) ? 1 : 0,
          'subject_template': c['subjectTemplate'],
          'body_template': c['bodyTemplate'],
          'created_at': c['created_at'] ?? now,
          'updated_at': now,
        };
        await txn.insert(
          'email_channels',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ========== Webhook 通道（webhook_channels） ==========

  @override
  Future<List<Map<String, dynamic>>> getWebhookChannels() async {
    final db = await database;
    return await db.query('webhook_channels', orderBy: 'updated_at DESC');
  }

  @override
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('webhook_channels');
      var i = 0;
      for (final c in channels) {
        final rawId = c['id'] as String?;
        final row = <String, dynamic>{
          // id 为空时兜底生成，避免主键冲突导致 replace 覆盖前一条记录
          'id': (rawId != null && rawId.isNotEmpty)
              ? rawId
              : 'wh_${now}_${i++}',
          'name': c['name'] ?? '',
          'url': c['url'] ?? '',
          'channel_type':
              c['channelType']?.toString() ??
              c['type']?.toString() ??
              'generic',
          'enabled': (c['enabled'] == true || c['enabled'] == 1) ? 1 : 0,
          'secret': c['secret'],
          // v6: 推送模板系统字段（message_format / message_template）
          'message_format':
              c['message_format']?.toString() ??
              c['messageFormat']?.toString() ??
              'default',
          'message_template': c['message_template'] ?? c['messageTemplate'],
          // v9: 通道扩展配置（wecom_app corpid/agentid/touser，Map → JSON 字符串）
          'extra_config': (c['extra_config'] ?? c['extraConfig']) is Map
              ? jsonEncode(c['extra_config'] ?? c['extraConfig'])
              : c['extra_config'] ?? c['extraConfig'],
          'created_at': c['created_at'] ?? now,
          'updated_at': now,
        };
        await txn.insert(
          'webhook_channels',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
