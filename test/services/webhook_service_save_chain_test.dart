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
      final setChannels = channelCalls
          .firstWhere((c) => c.method == 'setWebhookChannels');
      final channels = (setChannels.arguments as Map)['channels'] as List;
      expect(channels.length, 3);
      final first = channels[0] as Map;
      expect(first['url'], 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a');
      expect(first['channelType'], 'wechat_work');
      expect(first['secret'], 'sec-123');
      expect(first['enabled'], true);
      // 通道 map 应携带 Kotlin 端读取所需的所有键
      expect(first.keys, containsAll(['url', 'secret', 'channelType', 'enabled']));

      // ---- 前后端契约：setWebhookUrls 仅启用 URL ----
      final setUrls = channelCalls.firstWhere((c) => c.method == 'setWebhookUrls');
      final urls = (setUrls.arguments as Map)['urls'] as List;
      expect(urls.length, 2);
      expect(
        urls,
        [
          'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a',
          'https://api.telegram.org/botTOKEN/sendMessage?chat_id=-100',
        ],
      );
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
      expect(c['url'], 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=a');

      // 加载后同样触发原生同步
      expect(channelCalls.map((c) => c.method), contains('setWebhookChannels'));
    });
  });
}
