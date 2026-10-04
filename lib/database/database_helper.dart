import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/email_channel.dart';
import '../models/fnthink_inbox_message.dart';
import '../models/fnthink_peer.dart';
import '../models/fnthink_remote_execution_record.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/channel_display.dart';
import '../services/engine_rule_codec.dart';
import '../services/fnthink_remote_execution.dart';
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

/// 邮件通道存储抽象（可注入 fake 供测试）。
/// 有了它，备份恢复的 12 个类别才能在纯 Dart 测试里整体跑通 ——
/// 此前 EmailService 硬连 SQLCipher 单例，restorePayload 一律测不到邮件分支。
abstract class EmailChannelStore {
  Future<List<Map<String, dynamic>>> getEmailChannels();
  Future<void> saveEmailChannels(List<Map<String, dynamic>> channels);
}

/// 通知引擎规则存储抽象（T20）。可按族注入 fake，供服务层与 widget 测试使用。
/// 传/收的都是**归一后的 UI map**（id/type/value/enabled/title/content），
/// 列名只在本文件内部出现 —— 形状的契约在 `EngineRuleCodec`。
abstract class EngineRuleStore {
  Future<List<Map<String, dynamic>>> getEngineRules(String family);
  Future<void> saveEngineRules(String family, List<Map<String, dynamic>> rules);
}

class DatabaseHelper
    implements
        WebhookChannelStore,
        AppChannelStore,
        EmailChannelStore,
        EngineRuleStore {
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
  static const int dbVersion = 18;

  /// 仅供测试：把本类的读写指到调用方自备的 ffi 库上。
  ///
  /// 为什么开这个口子：`EngineRuleStore` 那几个方法里真正会咬人的是**SQL 本身**
  /// （整族替换写成了整表 `delete` 就会"存电量丢温度"），而注入 fake 存储测不出来 ——
  /// fake 里没有"删掉另一族"这回事。有了它，用例跑的是真 SQLite，又不必去碰
  /// SQLCipher 单例那个跨测试文件共享的库文件。⚠ 用完必须在 tearDown 里置回 null。
  @visibleForTesting
  Database? debugDatabase;

  Future<Database> get database async {
    final override = debugDatabase;
    if (override != null) return override;
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
        role TEXT NOT NULL DEFAULT 'primary',
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
        role TEXT NOT NULL DEFAULT 'primary',
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
        role TEXT NOT NULL DEFAULT 'primary',
        message_format TEXT NOT NULL DEFAULT 'default',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await _createEngineRules(db);
    await _createFnthinkInbox(db);
    await _createFnthinkPeers(db);
    await _createFnthinkRemoteExecutions(db);
  }

  /// v13 / T20：通知引擎规则表（电量族 + 温度族）。
  ///
  /// 两处建表（本方法被 `_onCreate` 与 `oldVersion < 13` 同时调用）列必须一致，
  /// 由 `test/database/engine_rules_schema_test.dart` 实测比对。
  /// `PRIMARY KEY (family, position)` 把"顺序即引擎判定优先级"写进结构：
  /// position 由列表下标生成，同族内不可能重复，而**规则 id 允许重复**
  /// （页面用毫秒时间戳生成 id，历史上就是"同 id 一起删"的列表语义，不能改成主键）。
  Future<void> _createEngineRules(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS engine_rules (
        family TEXT NOT NULL,
        position INTEGER NOT NULL,
        id TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL,
        threshold INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (family, position)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_engine_rules_family
      ON engine_rules(family, position)
    ''');
    await _importLegacyEngineRules(db);
  }

  /// 一次性把 prefs 里的旧规则搬进表。
  ///
  /// 建库（含"旧明文库 → 加密库"那条路径）与 v12→v13 升级都走这里，所以**每条能建出
  /// 本表的路径都灌过一次数据** —— 只在 onUpgrade 里迁会把"从没建过加密库的老设备"
  /// 漏掉（那些设备prefs 里有规则，库里却是空表，界面看起来就像规则被删了）。
  ///
  /// 失败不抛：旧键仍在，`EngineRuleRepository.load` 还能只读回退到它们；
  /// 而这里的异常若向上抛，`_initDatabase` 会走"备份原库 + 重建空库"，
  /// 等于为了搬规则把用户历史整库清掉。
  Future<void> _importLegacyEngineRules(Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in const {
        EngineRuleCodec.familyBattery: 'battery_rules',
        EngineRuleCodec.familyTemperature: 'temperature_rules',
      }.entries) {
        final legacy = EngineRuleCodec.parseLegacyJson(
          prefs.getString(entry.value),
          entry.key,
        );
        if (legacy == null || legacy.isEmpty) continue;
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < legacy.length; i++) {
          await db.insert(
            'engine_rules',
            EngineRuleCodec.toDbRow(legacy[i], entry.key, i, now),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    } catch (e) {
      debugPrint('引擎规则入 DB 迁移失败（旧键仍在，读取侧可回退）: $e');
    }
  }

  /// v14 / T47：幻念推送的收件表（别人推给本机的消息）。
  ///
  /// 两处建表（`_onCreate` 与 `oldVersion < 14`）共用本方法，列必须一致 ——
  /// 由 `test/database/fnthink_inbox_test.dart` 用 PRAGMA 实测比对（engine_rules 同一条纪律）。
  ///
  /// ⚠ 这张表**故意**没有的列，每一条都是因为此刻没有数据可灌，而不是没想到：
  /// - `sender_name`（对端自报的展示名）：poll 的回信里没有这一项，要它得先协议层带上；
  /// - `dedupe_id`：服务端只存它的**摘要**（落盘闸门要求任何 `*Digest` 都是 64 位十六进制），
  ///   原值不回传给设备；"刷新覆盖"那套语义现在靠 `message_id` 主键已够（同一条来两次就是它）；
  /// - `on_island`（有没有上过岛）：生产者是 T59/T60 的上岛链路，没做之前它永远是 0。
  /// 等有出处时加列（`_addColumnIfMissing`），别建一列空着让界面去猜"没上岛"。
  Future<void> _createFnthinkInbox(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${FnthinkInboxMessage.table} (
        message_id TEXT PRIMARY KEY,
        sender TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT '',
        item TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        received_at INTEGER NOT NULL,
        read INTEGER NOT NULL DEFAULT 0,
        ack_result TEXT NOT NULL DEFAULT '',
        acked_at INTEGER NOT NULL DEFAULT 0,
        -- T43：收件（in）与「我发过的」（out）同表不同档。老行由 DEFAULT 补成 in。
        direction TEXT NOT NULL DEFAULT 'in'
      )
    ''');
    // 收件列表按时间倒序翻页；未读数是首页那张入口卡每次都要算的。
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_fnthink_messages_received
      ON ${FnthinkInboxMessage.table}(received_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_fnthink_messages_read
      ON ${FnthinkInboxMessage.table}(read)
    ''');
  }

  /// v15 / T42 前置：本机配对名单（我允许了谁、给到哪一档）。
  ///
  /// 授权本体在服务端的 `grantsBy` 里，这张表是**本机那一份"我记得我同意过什么"**：
  /// 没有它，T42 那页要显示的"可信发送方列表"没有数据源，而"撤掉一个授权"在界面上也无从点起。
  /// ⚠ 故意没有 `peer_name`（对端名字从没流到本机，见模型的注释）；
  /// 也故意没有 `revoked_at`：吊销是服务端那一步（T31），本机这份跟着删除走，
  /// 留一个"已撤销但还在表里"的状态位会让两端各判一次"这个人还算不算数"。
  Future<void> _createFnthinkPeers(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${FnthinkPeer.table} (
        peer_address TEXT PRIMARY KEY,
        public_key TEXT NOT NULL,
        level TEXT NOT NULL,
        granted_at INTEGER NOT NULL,
        request_id TEXT NOT NULL DEFAULT '',
        items TEXT NOT NULL DEFAULT '',
        revision INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_fnthink_peers_granted
      ON ${FnthinkPeer.table}(granted_at DESC)
    ''');
  }

  /// v18 / 远程执行 片3b：远程执行历史（**区分收指令与发指令**，维护者 2026-10-03 定）。
  ///
  /// 两处建表（`_onCreate` 与 `oldVersion < 18`）共用本方法，列必须一致 ——
  /// 与 `_createFnthinkInbox` 同一条纪律（PRAGMA 实测比对在
  /// `test/database/fnthink_remote_executions_test.dart`）。
  ///
  /// ⚠ 这张表**故意**没有的列，每一条都有理由：
  /// - **凭据列（key / totp / secret）**：契约 `execution.forbiddenFields` 的同一份黑名单。
  ///   进这张表就等于给每个能读本机数据库的人发一把钥匙，而它们对"后来怎么了"这个问题
  ///   没有任何用处。
  /// - `body` / `title`：指令正文已经在那条消息自己的收件行里；这里再存一份就是
  ///   同一段内容两个留存点，而两者的删除策略不同。
  /// - `receipt`：两段回执是**发给对面**的消息，不是本机的状态。回执发没发出去这件事
  ///   要问对面那台（它才有那一份），本机存一份就成了两处各说各话的第二份。
  /// - `peer_name`：对端自报的名字从没流到本机（同 `FnthinkPeer` 的注释）。
  Future<void> _createFnthinkRemoteExecutions(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${FnthinkRemoteExecutionRecord.table} (
        exec_id TEXT PRIMARY KEY,
        direction TEXT NOT NULL DEFAULT 'in',
        peer_address TEXT NOT NULL DEFAULT '',
        level TEXT NOT NULL DEFAULT '',
        item TEXT NOT NULL DEFAULT '',
        argument TEXT NOT NULL DEFAULT '',
        state TEXT NOT NULL DEFAULT '',
        -- 白名单触发的那一路没有远端发送方 ⇒ peer_address 是空的，source 是唯一线索。
        source TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        result TEXT NOT NULL DEFAULT '',
        reason TEXT NOT NULL DEFAULT ''
      )
    ''');
    // 历史页按方向 + 时间倒序翻；"还没到终态的那几条"是状态栏撤销那一格要读的面。
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_fnthink_remote_exec_created
      ON ${FnthinkRemoteExecutionRecord.table}(created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_fnthink_remote_exec_direction
      ON ${FnthinkRemoteExecutionRecord.table}(direction, created_at DESC)
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
          role TEXT NOT NULL DEFAULT 'primary',
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
          role TEXT NOT NULL DEFAULT 'primary',
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
          role TEXT NOT NULL DEFAULT 'primary',
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
    if (oldVersion < 12) {
      // v12: 主备通道（T11）。三张通道表各加一列，**存量一律按"主"**：
      // 老库里所有通道本来都是全量推，默认 primary 才等于不改变既有语义。
      // 非法/缺失值在 Dart 侧统一按 primary 解释（宁可多推一条，也不静默不推）。
      for (final table in const [
        'webhook_channels',
        'app_channels',
        'email_channels',
      ]) {
        await _addColumnIfMissing(
          db,
          table,
          'role',
          "TEXT NOT NULL DEFAULT 'primary'",
        );
      }
    }
    if (oldVersion < 13) {
      // v13: 通知引擎规则入 DB（T20）。建表 + 把 prefs 里的旧规则灌进来。
      await _createEngineRules(db);
    }
    if (oldVersion < 14) {
      // v14: 幻念推送收件表（T47）。只建表，不动任何既有行 —— 收件是新增的一面，
      // 与 `notifications`（本机转发出去的历史）互不改写。
      await _createFnthinkInbox(db);
    }
    if (oldVersion < 15) {
      // v15: 本机配对名单（T42 前置）。同样是"只建表、不碰既有行"。
      await _createFnthinkPeers(db);
    }
    if (oldVersion < 16) {
      // v16: 收件表加方向列（T43）。**只加列、不动任何既有行**：已有的一律是收件（in），由
      // DEFAULT 补上；`_addColumnIfMissing` 先查 PRAGMA，所以重复跑到这一档也不会二次 ALTER。
      await _addColumnIfMissing(
        db,
        FnthinkInboxMessage.table,
        'direction',
        "TEXT NOT NULL DEFAULT 'in'",
      );
    }
    if (oldVersion < 17) {
      // v17: 配对名单加逐条清单与版本号（T49）。同样**只加列、不动任何既有行**，
      // 而"不动"在这里正是要的那个行为：存量授权的清单一律空 = 一条都没逐条给过。
      // 看着像"倒退"（那些行写着 L2/L3），但按 fail-closed 判，存量那些行从这一刻起
      // 只够发 L1 —— 与升级前它们实际能做的事相比是收紧的，方向对。
      // 补上"这些行以前按档位放行"才是危险的那一半：那会让升级变成一次静默的权限扩张。
      await _addColumnIfMissing(
        db,
        FnthinkPeer.table,
        'items',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        FnthinkPeer.table,
        'revision',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 18) {
      // v18: 远程执行历史表（远程执行 片3b）。**只建表、不碰任何既有行** ——
      // 这是本机第一次有远程执行功能，历史里不可能有它的行，而"造几行占位"会让
      // 界面上显示出没发生过的执行。
      await _createFnthinkRemoteExecutions(db);
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
          // T11 主备角色：调用方（ChannelConfigCodec）已归一化，这里只兜缺省。
          // 缺省 **primary** = 老库/老备份的既有语义（本来就全量推给每条通道）。
          'role': c['role']?.toString() ?? 'primary',
          'created_at': c['created_at'] ?? now,
          'updated_at': now,
        };
        await txn.insert('app_channels', row);
      }
    });
  }

  /// 通知引擎规则（T20）：按族读，顺序 = 引擎的判定优先级 = position。
  ///
  /// ⚠ 只读**本族**：电量页与温度页各持一族，两族规则类型不同（`level_below` 与
  /// `battery_temp_above`），混读会让一条电量规则被当成温度规则去判。
  @override
  Future<List<Map<String, dynamic>>> getEngineRules(String family) async {
    final db = await database;
    final rows = await db.query(
      'engine_rules',
      where: 'family = ?',
      whereArgs: [family],
      orderBy: 'position ASC',
    );
    return rows.map(EngineRuleCodec.fromDbRow).toList();
  }

  /// 整族替换（与三张通道表同规则：删该族 + 按下标逐行写）。
  /// 事务内完成 ⇒ 中途出错回滚成旧内容，不会留下"删了没写回"的空族。
  @override
  Future<void> saveEngineRules(
    String family,
    List<Map<String, dynamic>> rules,
  ) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete(
        'engine_rules',
        where: 'family = ?',
        whereArgs: [family],
      );
      for (var i = 0; i < rules.length; i++) {
        await txn.insert(
          'engine_rules',
          EngineRuleCodec.toDbRow(rules[i], family, i, now),
        );
      }
    });
  }

  // ── 幻念推送收件（T47，表 `fnthink_messages`）──────────────────────────────
  //
  // 这一族方法的返回值**不是**装饰：`insert` 回"是不是新的一条"、`markRead`/`recordAck`
  // 回"有没有命中"、`prune` 回"删了几条"。理由是投递语义 —— 服务端 at-least-once
  // （收到 ack 之前不删正文），所以同一条会来第二次；而"收件计入推送统计 + 首页未读卡"
  // 都要能区分**新到**与**重发**。把这些计数咽掉，表现就是未读数把同一条数两遍、
  // 或者裁掉的上限没人知道（#94 那条纪律）。

  /// 收件入库。**幂等且不覆盖**：同一 `message_id` 再来 ⇒ 返回 false，原行一个字节都不动。
  ///
  /// 为什么不是 replace：重发是常态，replace 会把用户已经「已读 / 已处理」的那一行洗回
  /// 未读（表现是看过的消息又跳红点），还会把 `ack_result` 抹空 —— 设备对自己报过什么
  /// 失去记忆，于是同一条结果报第二遍，服务端的回执计数跟着翻倍。
  Future<bool> insertFnthinkInbox(FnthinkInboxMessage message) async {
    final db = await database;
    return await db.transaction((txn) async {
      await txn.insert(
        FnthinkInboxMessage.table,
        message.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // "被忽略"时 insert 的返回值在不同后端不可信（0 或上一次的 rowid），
      // 所以问 changes() —— 它数的是本连接上刚跑完那条语句真改了几行。
      final changed = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT changes()'),
      );
      return (changed ?? 0) > 0;
    });
  }

  /// 收件列表，新到的在前。
  ///
  /// ⚠ 排序带 `message_id` 当 tie-breaker：同一毫秒到的两条若没有次序保证，
  /// 翻页会出现"第一页末尾那条在第二页再来一遍"。
  Future<List<FnthinkInboxMessage>> loadFnthinkInbox({
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
    String direction = kFnthinkDirectionIn,
  }) async {
    final db = await database;
    final rows = await db.query(
      FnthinkInboxMessage.table,
      // 方向**永远是 WHERE 的第一项**（不是可选筛）：这一列区分的是"两条不同的账"，
      // 少了它，收件档会把"我发过的"也列出来 —— 而用户会以为自己收到过。
      where: unreadOnly ? 'read = 0 AND direction = ?' : 'direction = ?',
      whereArgs: [direction],
      orderBy: 'received_at DESC, message_id ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(FnthinkInboxMessage.fromDbRow).toList();
  }

  /// 未读数（首页「幻念收件」入口卡每次都要算的那个数）。
  Future<int> countFnthinkInboxUnread() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${FnthinkInboxMessage.table} '
            "WHERE read = 0 AND direction = '$kFnthinkDirectionIn'",
          ),
        ) ??
        0;
  }

  /// 标已读。返回**有没有命中**那一行 —— false 表示这个 id 不在收件表里。
  /// 调用方是"点开一条 ⇒ 未读数减一"，不告诉它没命中就会把未读数减成负的。
  Future<bool> markFnthinkInboxRead(String messageId) async {
    final db = await database;
    final affected = await db.update(
      FnthinkInboxMessage.table,
      {'read': 1},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return affected > 0;
  }

  /// 记下本机对这一条报过的结果（T45 状态视图与"我报过没有"都读它）。
  Future<bool> recordFnthinkInboxAck({
    required String messageId,
    required String result,
    required int at,
  }) async {
    final db = await database;
    final affected = await db.update(
      FnthinkInboxMessage.table,
      {'ack_result': result, 'acked_at': at},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return affected > 0;
  }

  /// 保留与清理：先删掉早于 [olderThanDays] 天的，再把剩下的裁到 [maxRows] 条（删最旧）。
  ///
  /// 返回删掉的条数（`byAge` / `byCap` 分开）：**裁上限不是"删几行"，是一次要让人看见的事件**
  /// —— #94 那次 HistoryCache 静默丢最旧，界面上什么都没发生，用户以为历史都在。
  /// 两个数都必填且必须为正：`0` 在这里的字面意思是"一条都别留"，而它长得太像"没配"。
  Future<({int byAge, int byCap})> pruneFnthinkInbox({
    required int olderThanDays,
    required int maxRows,
    int? now,
  }) async {
    if (olderThanDays <= 0 || maxRows <= 0) {
      throw ArgumentError(
        'pruneFnthinkInbox 不接受非正数（olderThanDays=$olderThanDays, maxRows=$maxRows）：'
        '按 0 执行等于清空收件表，而那绝不是一个"没配"的默认值',
      );
    }
    final cutoff =
        (now ?? DateTime.now().millisecondsSinceEpoch) -
        olderThanDays * 86400000;
    final db = await database;
    return await db.transaction((txn) async {
      final byAge = await txn.delete(
        FnthinkInboxMessage.table,
        where: 'received_at < ?',
        whereArgs: [cutoff],
      );
      // `LIMIT -1 OFFSET n` = 跳过最新的那 n 条、其余都要：SQLite 里没有"删掉超出上限的部分"
      // 这种语句，只能先把这批 id 圈出来。先数再删是因为删完就数不着了。
      final doomed =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM ('
              ' SELECT message_id FROM ${FnthinkInboxMessage.table}'
              ' ORDER BY received_at DESC, message_id ASC LIMIT -1 OFFSET ?)',
              [maxRows],
            ),
          ) ??
          0;
      if (doomed > 0) {
        await txn.rawDelete(
          'DELETE FROM ${FnthinkInboxMessage.table} WHERE message_id IN ('
          ' SELECT message_id FROM ${FnthinkInboxMessage.table}'
          ' ORDER BY received_at DESC, message_id ASC LIMIT -1 OFFSET ?)',
          [maxRows],
        );
      }
      return (byAge: byAge, byCap: doomed);
    });
  }

  // ── 本机配对名单（T42 前置，表 `fnthink_peers`）────────────────────────────

  /// 写一条授权。⚠ 同码**不同公钥** ⇒ 一行都不改、只回 `keySwapped`：
  /// 静默覆盖的语义是"我把信任给了另一把钥匙"，而那正是契约在自登记那一步拦的事
  /// （`clientEvents.register`：同一地址码带另一把公钥来登记必须抛，不覆盖）。
  /// 本机这份如果悄悄跟着换，就等于设备侧替用户点了"同意换钥"。
  Future<FnthinkPeerWrite> upsertFnthinkPeer(FnthinkPeer peer) async {
    final db = await database;
    return await db.transaction((txn) async {
      final existing = await txn.query(
        FnthinkPeer.table,
        columns: ['public_key'],
        where: 'peer_address = ?',
        whereArgs: [peer.peerAddress],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(FnthinkPeer.table, peer.toDbRow());
        return FnthinkPeerWrite.created;
      }
      if ('${existing.first['public_key'] ?? ''}' != peer.publicKey) {
        return FnthinkPeerWrite.keySwapped;
      }
      await txn.update(
        FnthinkPeer.table,
        peer.toDbRow(),
        where: 'peer_address = ?',
        whereArgs: [peer.peerAddress],
      );
      return FnthinkPeerWrite.refreshed;
    });
  }

  /// 名单页要显示的全部条目，最近同意的在前。
  Future<List<FnthinkPeer>> loadFnthinkPeers() async {
    final db = await database;
    final rows = await db.query(
      FnthinkPeer.table,
      orderBy: 'granted_at DESC, peer_address ASC',
    );
    return rows.map(FnthinkPeer.fromDbRow).toList();
  }

  Future<bool> hasFnthinkPeer(String peerAddress) async {
    final db = await database;
    final rows = await db.query(
      FnthinkPeer.table,
      columns: ['peer_address'],
      where: 'peer_address = ?',
      whereArgs: [peerAddress],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 取消配对：删掉本机这一行。**服务端那份授权不在这里**（那是 T31 的吊销），
  /// 所以删除的返回值要说清有没有命中 —— 界面上"删掉了"而其实没有这一行，
  /// 用户会以为对面已经推不进来了，而对面还能推。
  Future<bool> removeFnthinkPeer(String peerAddress) async {
    final db = await database;
    final n = await db.delete(
      FnthinkPeer.table,
      where: 'peer_address = ?',
      whereArgs: [peerAddress],
    );
    return n > 0;
  }

  // ── 远程执行历史（远程执行 片3b，表 `fnthink_remote_executions`）──────────

  /// 写一条；已存在的那一条**整行覆盖**（状态迁移是这张表的主要写法）。
  ///
  /// ⚠ 用 `insert(..., conflictAlgorithm: replace)` 而不是 update-then-insert：
  /// 后者在"读回来发现没有"与"有人刚好插进来"之间留了一个窗口，而远程执行是**并发**
  /// 的活（后台轮次同时可能在落一条，而用户在界面上正要点撤销）。
  Future<void> saveRemoteExecutionRecord(
    FnthinkRemoteExecutionRecord record,
  ) async {
    final db = await database;
    await db.insert(
      FnthinkRemoteExecutionRecord.table,
      record.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 历史列表。`direction` 传 null = 两个档一起看（界面上的「全部」）。
  /// ⚠ 排序口径**只有这一处**（`created_at DESC, exec_id ASC`）：翻页与"最新那条是谁"
  /// 必须是同一个顺序，两处各写一次 `ORDER BY` 迟早会不一样。
  Future<List<FnthinkRemoteExecutionRecord>> loadRemoteExecutionRecords({
    String? direction,
    int limit = 200,
  }) async {
    final db = await database;
    final rows = await db.query(
      FnthinkRemoteExecutionRecord.table,
      orderBy: 'created_at DESC, exec_id ASC',
      where: direction == null ? null : 'direction = ?',
      whereArgs: direction == null ? null : [direction],
      limit: limit,
    );
    return rows.map(FnthinkRemoteExecutionRecord.fromMap).toList();
  }

  /// 还没到终态的那几条（`pending` / `executing`）。状态栏撤销那一格要读它们 ——
  /// 而它读的不是"全部历史再自己滤"，那会让撤销那一格在历史很长时翻不到。
  Future<List<FnthinkRemoteExecutionRecord>>
  loadUnsettledRemoteExecutions() async {
    final db = await database;
    final rows = await db.query(
      FnthinkRemoteExecutionRecord.table,
      orderBy: 'created_at DESC, exec_id ASC',
      where: 'state IN (?, ?)',
      whereArgs: [
        RemoteExecutionStates.pending,
        RemoteExecutionStates.executing,
      ],
    );
    return rows.map(FnthinkRemoteExecutionRecord.fromMap).toList();
  }

  /// 读一条。null = 没有这一条（界面那句"没找到"必须是这句话，不是"已取消"）。
  Future<FnthinkRemoteExecutionRecord?> remoteExecutionRecord(
    String execId,
  ) async {
    final db = await database;
    final rows = await db.query(
      FnthinkRemoteExecutionRecord.table,
      where: 'exec_id = ?',
      whereArgs: [execId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : FnthinkRemoteExecutionRecord.fromMap(rows.first);
  }

  /// 清掉这一条（T06 那条"删除一律二次确认"的落点之一；用户撤回自己发的一条指令时用）。
  Future<bool> removeRemoteExecutionRecord(String execId) async {
    final db = await database;
    final n = await db.delete(
      FnthinkRemoteExecutionRecord.table,
      where: 'exec_id = ?',
      whereArgs: [execId],
    );
    return n > 0;
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

  @override
  Future<List<Map<String, dynamic>>> getEmailChannels() async {
    final db = await database;
    return await db.query('email_channels', orderBy: 'updated_at DESC');
  }

  @override
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
          // T11 主备角色：调用方（ChannelConfigCodec）已归一化，这里只兜缺省。
          // 缺省 **primary** = 老库/老备份的既有语义（本来就全量推给每条通道）。
          'role': c['role']?.toString() ?? 'primary',
          'smtp_host': c['smtpHost'] ?? '',
          'smtp_port': c['smtpPort'] ?? EmailChannel.defaultSmtpPort,
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
          // ⚠ `channel_type`（列名）必须排在最前：调用方是 ChannelConfigCodec，
          // 它已经把 camel/snake 两套键归一化到这一列；这里再从 camel 重算会**倒着
          // 覆盖**归一化结果 —— 只带 snake 键的行（老备份文件、legacy 迁移）会被写成
          // generic，用户恢复一次备份就丢一次通道类型。
          'channel_type':
              c['channel_type']?.toString() ??
              c['channelType']?.toString() ??
              c['type']?.toString() ??
              'generic',
          'enabled': (c['enabled'] == true || c['enabled'] == 1) ? 1 : 0,
          // T11 主备角色：调用方（ChannelConfigCodec）已归一化，这里只兜缺省。
          // 缺省 **primary** = 老库/老备份的既有语义（本来就全量推给每条通道）。
          'role': c['role']?.toString() ?? 'primary',
          'secret': c['secret'],
          // v6: 推送模板系统字段（message_format / message_template）
          'message_format':
              c['message_format']?.toString() ??
              c['messageFormat']?.toString() ??
              'default',
          'message_template': c['message_template'] ?? c['messageTemplate'],
          // v9 的 extra_config 不再写（roadmap D4 / ㊷）：全链路无人消费它。
          // **列保留**（DDL 与 v9→v10 搬家 SELECT 都在下面），删列要迁用户数据、风险不对等。
          // 老行里已有的值会在下一次保存该通道时被置空 —— 该值从来没人读过，属预期清理。
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
