import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/services/webhook_service.dart';

import '../test_setup.dart';

/// 伪 Webhook 存储：纯 Dart 测试中 sqflite 平台通道不可用。
class _FakeWebhookStore implements WebhookChannelStore {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> getWebhookChannels() async => rows;

  @override
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels) async {
    rows = channels;
  }
}

/// 送达状态「通道快照时机」回归测试。
///
/// 背景：`addRecord` 在**每次**收到通知时为该记录固化一份通道列表快照
/// （`_getActiveChannels()` → `deliveryStatus`）：
///
///     record['channels'] = _getActiveChannels();
///     record['deliveryStatus'] = _buildInitialDeliveries(record['channels']);
///
/// 这份快照**一旦写入就再不会被补充**——后续送达回传只能更新快照里已存在的 key
/// （`updateDelivery` 找不到 key 时按 `FILTER` 兜底或直接忽略）。
///
/// 而 `_getActiveChannels()` 的数据来源是 GetIt 中**已加载**的
/// `WebhookService.channels` / `EmailService.cachedChannels`。启动期存在一个
/// 真实的时序窗口：`NotificationService.loadRecords()`（splash 内）不加载任何通道；
/// 两个通道配置分别要到 splash 的 webhook 步骤（早于 loadRecords）和
/// **MainPage._postInit**（晚于 MainPage 挂载）才载入。MainPage.initState 一挂载
/// 就注册 `onNotificationReceived` 处理器，此刻 webhook 已就绪、email 尚未就绪。
///
/// 本组测试把这个时序窗口固化为断言，并**修正一个曾有的错误判断**：
///
///   最初以为「快照缺通道 → 该通道的回传结果会丢失」。实测否定了这一判断——
///   `updateDelivery` 对非拦截类回传走的是 `updated[label] = {...}`（**赋值**），
///   即便快照里没有该 key 也会补上。所以真实缺陷面被收窄为：
///     **入库瞬间历史页少一个"发送中"占位，直到原生回传才补齐。**
///   回传丢失的风险只存在于按 `existing.keys` 整体改写的
///   FILTER / SMS / MERGE 三条路径，那些已由各自用例覆盖。
///
/// 因此本组用例既锁「当前行为」，也标注「修复后应改成什么」，
/// 避免后人凭错误前提去"修"一个不存在的 bug。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  group('送达状态通道快照 – 通道未加载时的缺口', () {
    late NotificationService service;
    late WebhookService webhookService;
    late EmailService emailService;

    setUp(() async {
      await GetIt.instance.reset();
      webhookService = WebhookService(store: _FakeWebhookStore());
      emailService = EmailService();
      GetIt.instance.registerSingleton<WebhookService>(webhookService);
      GetIt.instance.registerSingleton<EmailService>(emailService);
      service = NotificationService();
    });

    tearDown(() async {
      await GetIt.instance.reset();
    });

    Map<String, dynamic> record({String id = 'pkg:tag:1'}) => {
      'id': id,
      'title': '标题',
      'content': '内容',
      'packageName': 'com.example.app',
      'appName': '示例',
      'postTime': 1700000000000,
      'time': '2024-01-01 12:00:00',
    };

    EmailChannel enabledEmail() => const EmailChannel(
      id: 'e1',
      name: '主邮箱',
      enabled: true,
      smtpHost: 'smtp.example.com',
      smtpPort: 465,
      username: 'u@example.com',
      fromEmail: 'u@example.com',
      toEmail: 'to@example.com',
    );

    /// 预置一个已启用的 webhook 通道（对应启动期 splash 阶段已完成加载）。
    /// saveChannels 是异步的，必须 await，否则 addRecord 读到的仍是空列表。
    Future<void> seedWebhook() => webhookService.saveChannels([
      {
        'name': '企业微信',
        'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=t',
        'channelType': 'wechatWork',
        'type': 'wechatWork',
        'enabled': true,
      },
    ]);

    test('缺陷基线：email 通道未加载时入库 → deliveryStatus 不含邮件通道', () async {
      // 此时 webhook 已加载（splash 阶段在前）、email 尚未加载（MainPage._postInit 在后）
      await seedWebhook();
      // emailService.cachedChannels 保持初始空值——模拟真实启动时序
      expect(emailService.cachedChannels, isEmpty);

      service.addRecord(record());

      final status = service.records.first.deliveryStatus;
      expect(status.keys, contains('webhook:企业微信'));
      // 当前行为：邮件通道缺失。修复该时序后此处应改为 contains('邮件')
      expect(
        status.keys,
        isNot(contains('邮件')),
        reason:
            '若此断言失败，说明邮件通道已在入库前加载，该时序缺陷已被修复——'
            '请改写本用例并同步更新 notification_service.dart 的注释。',
      );
    });

    test('email 通道已加载时入库 → deliveryStatus 含邮件通道', () async {
      await seedWebhook();
      // 直接注入缓存，避免依赖数据库读取
      emailService.cachedChannels = [enabledEmail()];

      service.addRecord(record());

      final status = service.records.first.deliveryStatus;
      expect(status.keys, contains('webhook:企业微信'));
      expect(status.keys, contains('邮件'));
      expect(status['邮件']!['status'], 'pending');
    });

    test('快照固化：入库后再加载 email，既有记录不会被补上邮件通道', () async {
      await seedWebhook();
      service.addRecord(record());
      expect(service.records.first.deliveryStatus.keys, isNot(contains('邮件')));

      // 随后 MainPage._postInit 载入 email 通道
      emailService.cachedChannels = [enabledEmail()];

      // 既有记录的快照不会追溯补齐——邮件通道永远缺席这条记录
      expect(
        service.records.first.deliveryStatus.keys,
        isNot(contains('邮件')),
        reason: '通道快照在 addRecord 时固化，后续加载不回溯。',
      );

      // 但此后的新记录能拿到邮件通道
      service.addRecord(record(id: 'pkg:tag:2'));
      expect(service.records.first.deliveryStatus.keys, contains('邮件'));
    });

    test('邮件回传会补上缺失的通道 key（回传本身不丢）', () async {
      await seedWebhook();
      service.addRecord(record());
      expect(service.records.first.deliveryStatus.keys, isNot(contains('邮件')));

      // 原生端确实发出了邮件并回传结果
      await service.updateDelivery('pkg:tag:1', 'EMAIL', 'SUCCESS', '邮件发送成功');

      // 关键结论：非拦截类回传走 `updated[label] = {...}`，是**赋值而非合并**，
      // 因此即便入库时快照里没有「邮件」key，回传也会把它补上并落为 success。
      // 也就是说「快照缺通道」只影响**刚入库那一刻的展示**（少了"发送中"占位），
      // 不会导致回传结果丢失——回传丢失的风险仅存在于 FILTER/SMS/MERGE 这类
      // 按 existing.keys 整体改写的路径上（已由各自的用例覆盖）。
      final status = service.records.first.deliveryStatus;
      expect(status.keys, contains('邮件'));
      expect(status['邮件']!['status'], 'success');
      expect(status['邮件']!['message'], '邮件发送成功');
      // 其他通道不受影响，仍停留在 pending
      expect(status['webhook:企业微信']!['status'], 'pending');
    });

    test('快照缺通道只影响展示占位，不改写其他通道', () async {
      await seedWebhook();
      service.addRecord(record());

      // 入库瞬间：邮件通道未就绪 → 该记录少一个"发送中"占位。
      // 这是本组测试记录的**真实缺陷面**：用户在历史页看到的通道数少于实际启用数，
      // 直到原生回传才补齐。若后续修复（在 splash 阶段预加载 email 通道），
      // 本用例应改为断言 contains('邮件')。
      expect(service.records.first.deliveryStatus.keys, ['webhook:企业微信']);
    });
  });
}
