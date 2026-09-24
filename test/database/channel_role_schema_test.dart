import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/services/active_channels.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_config_codec.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

import '../test_setup.dart';

/// T11 主备角色：列的存在性、缺省语义、以及"改一条"的写回链路。
///
/// 三条不变量（任何一条破了都会静默改变推送行为）：
/// 1. **新建库与升级库的最终列集合一致**，且老行一律落到 `primary` ——
///    老库里每条通道都是全量推，落到别的值就是"升级之后某些通道不再收到通知"；
/// 2. 缺列 / 缺键 / 认不出的值都归一成 `primary`（宁可多推，不可静默不推）；
/// 3. 改角色走各族**既有的**保存链路（归一化 → DB → 同步原生），不另开写路径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  final helper = DatabaseHelper();
  late final String dbPath;

  setUpAll(() async {
    dbPath = join((await getDatabasesPath()), 'role_schema_test.db');
  });

  Future<Database> open({int version = DatabaseHelper.dbVersion}) async {
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (d, v) => helper.createSchemaForTest(d),
        onUpgrade: (d, o, n) => helper.upgradeSchemaForTest(d, o, n),
      ),
    );
  }

  Future<Set<String>> columnsOf(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'].toString()).toSet();
  }

  tearDownAll(() async {
    if (await databaseFactory.databaseExists(dbPath)) {
      await databaseFactory.deleteDatabase(dbPath);
    }
  });

  group('T11 schema：role 列', () {
    test('三张通道表都有 role 列（新建库）', () async {
      final db = await open();
      for (final table in const [
        'webhook_channels',
        'app_channels',
        'email_channels',
      ]) {
        expect(
          await columnsOf(db, table),
          contains('role'),
          reason: '$table 缺 role 列：保存会报 no such column（或静默丢弃）',
        );
      }
      await db.close();
    });

    test('v11 老库升上来：列补齐，且存量行读到 primary', () async {
      final db = await open();
      // 造一个"v11 形状"的库：把列删掉并塞一行不带 role 的记录
      await db.execute('ALTER TABLE webhook_channels DROP COLUMN role');
      await db.execute(
        'INSERT INTO webhook_channels (id, name, url, channel_type, enabled, created_at, updated_at)'
        " VALUES ('wh-old', '老通道', 'https://oapi.dingtalk.com/robot/send', 'dingtalk', 1, 1, 1)",
      );
      await db.close();

      // 直接跑升级（版本号写死 11→12，绕开 openDatabase 的版本判定）
      final db2 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.dbVersion,
          onUpgrade: (d, o, n) => helper.upgradeSchemaForTest(d, o, n),
        ),
      );
      await helper.upgradeSchemaForTest(db2, 11, 12);
      expect(
        await columnsOf(db2, 'webhook_channels'),
        contains('role'),
        reason: '升级没补列 ⇒ 老库保存通道直接报 no such column',
      );
      final row = (await db2.query(
        'webhook_channels WHERE id = ?',
        whereArgs: ['wh-old'],
      )).single;
      expect(
        ChannelConfigCodec.normalizeRole(row['role']),
        ChannelConfigCodec.rolePrimary,
        reason: '存量通道必须仍是主通道（老语义=全量推）',
      );
      await db2.close();
    });

    test('v11→v12 升级幂等（跑两遍不抛 duplicate column）', () async {
      final db = await open();
      await db.execute('ALTER TABLE webhook_channels DROP COLUMN role');
      await helper.upgradeSchemaForTest(db, 11, 12);
      await helper.upgradeSchemaForTest(db, 11, 12);
      expect(await columnsOf(db, 'webhook_channels'), contains('role'));
      await db.close();
    });
  });

  group('T11 取值归一', () {
    test('缺省、脏值、大小写与 0/1 形状', () {
      const norm = ChannelConfigCodec.normalizeRole;
      expect(norm(null), 'primary');
      expect(norm(''), 'primary');
      expect(norm('primary'), 'primary');
      expect(norm(' BACKUP '), 'backup');
      expect(norm('none'), 'none');
      // 认不出的值（更新版本写的、手改文件写的）归主：宁可多推也不静默不推
      expect(norm('tertiary'), 'primary');
      expect(norm(jsonDecode('{"role":null}')['role']), 'primary');
    });

    test('webhook / app 的 UI↔DB 往返回保 role', () {
      final ui = {
        'id': 'wh-1',
        'name': '告警',
        'url': 'https://example.com/hook',
        'type': 'generic',
        'enabled': true,
        'role': 'backup',
      };
      final back = ChannelConfigCodec.webhookFromDb(
        ChannelConfigCodec.webhookToDb(ui),
      );
      expect(back['role'], 'backup', reason: '保存一次就把角色洗掉 = 用户设置丢失');
      expect(
        ChannelConfigCodec.webhookToNative(ui)['role'],
        'backup',
        reason: '原生发发送时要按角色分流（T12），载荷里必须有它',
      );

      final appBack = ChannelConfigCodec.appFromDb(
        ChannelConfigCodec.appToDb({
          'id': 'app-1',
          'name': '应用',
          'appType': 'feishu_app',
          'baseUrl': 'https://open.feishu.cn',
          'enabled': true,
          'role': 'none',
        }),
      );
      expect(appBack['role'], 'none');
    });

    test('EmailChannel 的 map / DB 行两个入口都带 role', () {
      final channel = EmailChannel.fromMap(_emailMap);
      expect(channel.role, 'backup', reason: '备份恢复走 fromMap：丢了就是恢复一次改一次设置');
      expect(channel.copyWith(role: 'none').role, 'none');
      expect(channel.toMap()['role'], 'backup');

      // DB 行是 snake_case 且**没有** role 列（v11 之前的老库）时落到 primary
      final fromRow = EmailChannel.fromDbRow(const {
        'id': 'e1',
        'name': '邮箱',
        'enabled': 1,
        'smtp_host': 'smtp.example.com',
        'smtp_port': 465,
        'username': 'u@example.com',
        'from_email': 'u@example.com',
        'to_email': 't@example.com',
      });
      expect(fromRow.role, 'primary');
    });
  });

  group('T11 写回链路', () {
    late AppChannelService appService;
    late WebhookService webhookService;
    late EmailService emailService;

    setUp(() async {
      await GetIt.instance.reset();
      SharedPreferences.setMockInitialValues({});
      stubNativeChannels();
      appService = AppChannelService(store: _AppStore());
      webhookService = WebhookService(store: _HookStore());
      emailService = EmailService(store: _EmailStore());
      GetIt.instance.registerSingleton<AppChannelService>(appService);
      GetIt.instance.registerSingleton<WebhookService>(webhookService);
      GetIt.instance.registerSingleton<EmailService>(emailService);
      GetIt.instance.registerSingleton<ChannelHealthStore>(
        ChannelHealthStore(),
      );
      await appService.saveChannels([
        {
          'id': 'app-1',
          'name': '办公',
          'appType': 'wecom_app',
          'baseUrl': 'https://qyapi.weixin.qq.com',
          'config': <String, dynamic>{},
          'enabled': true,
        },
      ]);
      await webhookService.saveChannels([
        {
          'id': 'wh-1',
          'name': '告警群',
          'type': 'dingtalk',
          'url': 'https://oapi.dingtalk.com/robot/send?access_token=t',
          'enabled': true,
        },
      ]);
      emailService.cachedChannels = [
        const EmailChannel(
          id: 'e1',
          name: '主邮箱',
          enabled: true,
          smtpHost: 'smtp.example.com',
          smtpPort: 465,
          username: 'u@example.com',
          fromEmail: 'u@example.com',
          toEmail: 'to@example.com',
        ),
      ];
    });

    tearDown(() async => GetIt.instance.reset());

    test('三族都能改，且改完 collectActiveChannels 读得到', () async {
      expect(collectActiveChannels().map((c) => c.role).toSet(), {
        'primary',
      }, reason: '新建通道默认主通道');

      expect(await updateChannelRole('webhook', 'wh-1', 'backup'), isTrue);
      expect(await updateChannelRole('app', 'app-1', 'none'), isTrue);
      expect(await updateChannelRole('email', 'e1', 'backup'), isTrue);

      final roles = {for (final c in collectActiveChannels()) c.family: c.role};
      expect(roles['webhook'], 'backup');
      expect(roles['app'], 'none');
      expect(roles['email'], 'backup');

      // 真的落到 DB（不是只改了内存列表）
      expect(webhookService.channels.first['role'], 'backup');
      expect(appService.channels.first['role'], 'none');
      expect(emailService.cachedChannels.first.role, 'backup');
    });

    test('改不存在的通道返回 false（不静默）', () async {
      expect(await updateChannelRole('webhook', 'nope', 'backup'), isFalse);
      expect(await updateChannelRole('email', 'nope', 'backup'), isFalse);
      expect(
        await updateChannelRole('unknown_family', 'wh-1', 'backup'),
        isFalse,
      );
      expect(
        webhookService.channels.first['role'],
        isNot('backup'),
        reason: '失败的那次不得顺手改掉别的通道',
      );
    });
  });
}

/// 顶层常量：EmailChannel 是 @immutable，构造参数必须是常量字面量
/// （写成函数内局部 `const map = {...}` 不是常量上下文，会掉进
/// prefer_const_literals_to_create_immutables —— 2026-09-25 实测）。（T11）
const Map<String, dynamic> _emailMap = {
  'id': 'e1',
  'name': '邮箱',
  'enabled': true,
  'smtpHost': 'smtp.example.com',
  'smtpPort': 465,
  'username': 'u@example.com',
  'fromEmail': 'u@example.com',
  'toEmail': 't@example.com',
  'role': 'backup',
};

class _AppStore implements AppChannelStore {
  List<Map<String, dynamic>> rows = [];
  @override
  Future<List<Map<String, dynamic>>> getAppChannels() async => rows;
  @override
  Future<void> saveAppChannels(List<Map<String, dynamic>> c) async =>
      rows = List.of(c);
}

/// 邮件也必须注伪存储：`EmailService()` 默认走 DatabaseHelper（SQLCipher），
/// 在测试里第一个调用就是 getDatabasesPath ⇒ MissingPluginException。
class _EmailStore implements EmailChannelStore {
  List<Map<String, dynamic>> rows = [];
  @override
  Future<List<Map<String, dynamic>>> getEmailChannels() async => rows;
  @override
  Future<void> saveEmailChannels(List<Map<String, dynamic>> c) async =>
      rows = c.map(Map<String, dynamic>.from).toList();
}

class _HookStore implements WebhookChannelStore {
  List<Map<String, dynamic>> rows = [];
  @override
  Future<List<Map<String, dynamic>>> getWebhookChannels() async => rows;
  @override
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> c) async =>
      rows = c.map(Map<String, dynamic>.from).toList();
}
