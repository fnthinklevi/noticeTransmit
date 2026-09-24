import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/webhook_service.dart';

/// Webhook 多通道保存链路 + Flutter↔Kotlin 前后端契约测试。
///
/// SQLCipher 加密库依赖原生 MethodChannel，无法在纯 Dart 测试中真实打开，
/// 因此通过 [WebhookChannelStore] 注入伪存储，覆盖完整保存链路：
///   UI 通道列表 → DB 行归一化（saveChannels）→ 原生同步 payload（_syncToNative）
/// 并验证与 Kotlin 端 MainActivity.setWebhookChannels / setWebhookUrls 的契约：
///   - setWebhookChannels: channels 数组携带 url/secret/channelType/enabled 等键
///   - setWebhookUrls: 仅包含 enabled == true 的 URL（后台服务只推送启用通道）
class FakeChannelStorage implements WebhookChannelStore {
  List<Map<String, dynamic>> rows = [];
  final List<List<Map<String, dynamic>>> savedBatches = [];

  @override
  Future<List<Map<String, dynamic>>> getWebhookChannels() async => rows;

  @override
  Future<void> saveWebhookChannels(List<Map<String, dynamic>> channels) async {
    savedBatches.add(List.of(channels));
    rows = List.of(channels);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WebhookService service;
  late FakeChannelStorage storage;
  late List<MethodCall> channelCalls;

  setUp(() {
    storage = FakeChannelStorage();
    channelCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          channelCalls.add(call);
          return true;
        });
    service = WebhookService(store: storage);
  });

  group('saveChannels 保存链路', () {
    test('多通道保存：DB 行归一化 + 原生同步 payload 契约', () async {
      await service.saveChannels([
        {
          'id': 'c1',
          'name': '企微',
          'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a',
          'channelType': 'wechat_work',
          'enabled': true,
          'secret': 'sec-123',
          'message_format': 'default',
          'message_template': null,
        },
        {
          'id': 'c2',
          'name': 'TG',
          'url': 'https://api.telegram.org/botTOKEN/sendMessage?chat_id=-100',
          'channelType': 'telegram',
          'enabled': true,
          'secret': null,
        },
        {
          'id': 'c3',
          'name': '关闭的通用',
          'url': 'https://example.com/hook',
          'type': 'generic',
          'enabled': false,
          'secret': null,
        },
      ]);

      // ---- DB 行契约（channelType → channel_type、secret/模板过滤）----
      final rows = storage.savedBatches.single;
      expect(rows.length, 3);
      expect(rows[0]['channel_type'], 'wechat_work');
      expect(rows[1]['channel_type'], 'telegram');
      // 未传 channelType 时回退 type 字段
      expect(rows[2]['channel_type'], 'generic');
      // secret："null" 字符串与 null 均不应写入明文占位
      expect(rows[2]['secret'], isNull);
      expect(rows[1]['secret'], isNull);
      // message_format 缺省为 default
      expect(rows[2]['message_format'], 'default');

      // ---- 前后端契约：setWebhookChannels 全量通道 ----
      final setChannels = channelCalls.firstWhere(
        (c) => c.method == 'setWebhookChannels',
      );
      final channels = (setChannels.arguments as Map)['channels'] as List;
      expect(channels.length, 3);
      final first = channels[0] as Map;
      expect(
        first['url'],
        'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a',
      );
      expect(first['channelType'], 'wechat_work');
      expect(first['secret'], 'sec-123');
      expect(first['enabled'], true);
      // 通道 map 应携带 Kotlin 端读取所需的所有键
      expect(
        first.keys,
        containsAll(['url', 'secret', 'channelType', 'enabled']),
      );

      // ---- 前后端契约：setWebhookUrls 仅启用 URL ----
      final setUrls = channelCalls.firstWhere(
        (c) => c.method == 'setWebhookUrls',
      );
      final urls = (setUrls.arguments as Map)['urls'] as List;
      expect(urls.length, 2);
      expect(urls, [
        'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a',
        'https://api.telegram.org/botTOKEN/sendMessage?chat_id=-100',
      ]);
      // c3 已禁用，不得出现在启用 URL 列表
      expect(urls, isNot(contains('https://example.com/hook')));
    });
  });

  group('loadChannels 往返', () {
    test('DB 行 → camelCase UI 结构，历史 "null" 脏数据被过滤', () async {
      storage.rows = [
        {
          'id': 'c1',
          'name': '企微',
          'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a',
          'channel_type': 'wechat_work',
          'enabled': 1,
          'secret': 'null', // 历史脏数据
          'message_format': 'default',
          'message_template': 'null',
        },
      ];

      await service.loadChannels();

      final c = service.channels.single;
      expect(c['channelType'], 'wechat_work');
      expect(c['type'], 'wechat_work');
      expect(c['enabled'], true);
      expect(c['secret'], isNull);
      expect(c['message_template'], isNull);
      expect(
        c['url'],
        'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a',
      );

      // 加载后同样触发原生同步
      expect(channelCalls.map((c) => c.method), contains('setWebhookChannels'));
    });
  });

  group('extra_config 已退出链路（roadmap D4 / ㊷；DB 列保留不动）', () {
    test('保存：UI 里带 extra_config 也不得写进 DB 行或原生载荷', () async {
      await service.saveChannels([
        {
          'id': 'wecom1',
          'name': '企微自建应用',
          'url': 'https://qyapi.weixin.qq.com',
          'channelType': 'wecom_app',
          // 真实页面发的就是 webhookFromDb 的形状：两个键都在（`type` 是原生首选键）
          'type': 'wecom_app',
          'enabled': true,
          'secret': 'corpsecret-demo',
          'extra_config': {
            'corpid': 'corp-demo',
            'agentid': 1000002,
            'touser': '@all',
          },
        },
      ]);

      // 写入端已断：DB 行不再含该列键（列留在 schema 里，值为默认 NULL）。
      // wecom_app 的 corpid/agentid/touser 自 v10 起只走 app_channels.config。
      final row = storage.savedBatches.single.single;
      expect(row.containsKey('extra_config'), isFalse);

      final syncCall = channelCalls.singleWhere(
        (c) => c.method == 'setWebhookChannels',
      );
      final channels = (syncCall.arguments as Map)['channels'] as List;
      final nativeChannel = channels.single as Map;
      expect(nativeChannel.containsKey('extra_config'), isFalse);
      // 其余契约键不得被连带丢掉（否则就是"删死代码顺手改契约"）：
      // 原生首选 `type`（optString("type", optString("channel_type", …))），UI 别名 `channelType` 同发
      expect(nativeChannel['url'], 'https://qyapi.weixin.qq.com');
      expect(nativeChannel['type'], 'wecom_app');
      expect(nativeChannel['channelType'], 'wecom_app');
      expect(nativeChannel['secret'], 'corpsecret-demo');
    });

    test('加载：DB 行里的历史 JSON 值被忽略，且不得抛错', () async {
      storage.rows = [
        {
          'id': 'wecom1',
          'name': '企微自建应用',
          'url': 'https://qyapi.weixin.qq.com',
          'channel_type': 'wecom_app',
          'enabled': 1,
          'secret': 'corpsecret-demo',
          'message_format': 'default',
          'message_template': null,
          'extra_config':
              '{"corpid":"corp-demo","agentid":1000002,"touser":"@all"}',
        },
      ];

      await service.loadChannels();

      final channel = service.channels.single;
      expect(channel.containsKey('extra_config'), isFalse);
      // 老库里存量的 9 类行仍要正常读出（删的是链路，不是数据可读性）
      expect(channel['channelType'], 'wecom_app');
      expect(channel['secret'], 'corpsecret-demo');
    });

    test('读回再保存：老行的 extra_config 值在下一次保存后归为 NULL（预期清理）', () async {
      storage.rows = [
        {
          'id': 'tg1',
          'name': 'TG',
          'url': 'https://api.telegram.org/botT/sendMessage',
          'channel_type': 'telegram',
          'enabled': 1,
          'secret': null,
          'message_format': 'default',
          'extra_config': '{"legacy":true}',
        },
      ];
      await service.loadChannels();
      await service.saveChannels(service.channels);
      final row = storage.savedBatches.last.single;
      expect(row.containsKey('extra_config'), isFalse);
      expect(row['url'], 'https://api.telegram.org/botT/sendMessage');
      expect(row['channel_type'], 'telegram');
    });
  });

  group('保存后内存列表的形状（㊹：备份恢复不得把 DB 形状留在内存）', () {
    test('调用方传来的形状被归一化后才留在 _channels', () async {
      // 备份恢复走的就是 saveChannels，而文件里的形状不受我们控制：
      // enabled 可能是 0/1、类型可能只有 channel_type、secret 可能是字符串 "null"。
      // 旧实现 `_channels = channels` 原样保留输入 → 设置页按 UI 形状硬转 → 页面打死。
      await service.saveChannels([
        {
          'id': 'wh_1',
          'name': '钉钉',
          'url': 'https://oapi.dingtalk.com/robot/send?access_token=x',
          'channel_type': 'dingtalk',
          'enabled': 1,
          'secret': 'null',
        },
      ]);

      final ch = service.channels.single;
      expect(ch['enabled'], isA<bool>(), reason: '页面用 flag() 读，但内存里就该是 bool');
      expect(ch['enabled'], isTrue);
      expect(ch['channelType'], 'dingtalk');
      expect(ch['type'], 'dingtalk', reason: '送达回传/通知服务按 type 取');
      expect(ch['secret'], isNull, reason: '"null" 字符串必须在归一化时被洗掉，否则被当成已配置密钥');
      expect(ch['message_format'], 'default');
    });

    test('恢复备份再打开页面所依赖的形状与 loadChannels 一致', () async {
      final rows = [
        {
          'id': 'wh_9',
          'name': 'ntfy',
          'url': 'http://192.168.1.9:8888/topic',
          'channelType': 'ntfy',
          'enabled': true,
          'secret': null,
          'message_format': 'default',
        },
      ];
      await service.saveChannels(rows);
      final afterSave = List<Map<String, dynamic>>.from(service.channels);

      storage.rows = List.of(storage.rows);
      await service.loadChannels();
      final afterLoad = service.channels;

      expect(afterSave.single.keys, isNotEmpty);
      for (var i = 0; i < afterLoad.length; i++) {
        expect(
          afterSave[i].keys.toSet(),
          equals(afterLoad[i].keys.toSet()),
          reason: 'saveChannels 与 loadChannels 必须交出同一套键，否则页面按来源不同表现不一致',
        );
      }
    });
  });
}
