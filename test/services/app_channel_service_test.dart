import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';

/// 自建应用通道服务契约测试（fake AppChannelStore 注入，不出网）。
///
/// 覆盖：load/save 归一化（DB 行 ↔ UI Map 双向）、原生同步 payload 契约
/// （setAppChannels 携带完整通道含 secret/config/config Map 保真）、
/// 加密 store 与明文镜像分离。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppChannelService service;
  late FakeAppChannelStore storage;
  late List<MethodCall> channelCalls;

  setUp(() {
    storage = FakeAppChannelStore();
    channelCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          channelCalls.add(call);
          return true;
        });
    service = AppChannelService(store: storage);
  });

  group('AppChannelService – loadChannels（DB 行 → UI Map）', () {
    test('config JSON 字符串解码为 Map；字段映射完整', () async {
      storage.rows = [
        {
          'id': 'app-1',
          'name': '企微应用',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': 'corpsecret-demo',
          'config': '{"corpid":"corp-x","agentid":1000002,"touser":"@all"}',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();

      expect(service.channels.length, 1);
      final c = service.channels.single;
      expect(c['id'], 'app-1');
      expect(c['appType'], 'wecom_app');
      expect(c['baseUrl'], 'https://qyapi.weixin.qq.com');
      expect(c['secret'], 'corpsecret-demo');
      expect(c['enabled'], true);
      final config = c['config'] as Map;
      expect(config['corpid'], 'corp-x');
      expect(config['agentid'], 1000002);
      expect(config['touser'], '@all');
    });

    test('config 畸形 JSON 解码失败时回退空 Map（不崩溃）', () async {
      storage.rows = [
        {
          'id': 'app-bad',
          'name': '坏数据',
          'app_type': 'wecom_app',
          'base_url': 'https://qyapi.weixin.qq.com',
          'secret': null,
          'config': '{broken json',
          'message_format': 'default',
          'enabled': 1,
        },
      ];
      await service.loadChannels();
      final c = service.channels.single;
      expect(c['config'], isA<Map>());
      expect((c['config'] as Map).isEmpty, isTrue);
    });

    test('空配置（无 app_channels 行）加载为空列表', () async {
      storage.rows = [];
      await service.loadChannels();
      expect(service.channels, isEmpty);
    });
  });

  group('AppChannelService – saveChannels（归一化 + 原生同步）', () {
    test('UI Map → DB 行归一化（appType/baseUrl/config Map 保真）', () async {
      await service.saveChannels([
        {
          'id': 'app-wecom-1',
          'name': '企微自建应用',
          'appType': 'wecom_app',
          'baseUrl': 'https://qyapi.weixin.qq.com',
          'secret': 'corpsecret-x',
          'config': {'corpid': 'corp-x', 'agentid': 1000002, 'touser': '@all'},
          'message_format': 'default',
          'enabled': true,
        },
      ]);

      final rows = storage.savedBatches.single;
      expect(rows.length, 1);
      final row = rows.single;
      expect(row['appType'], 'wecom_app');
      expect(row['baseUrl'], 'https://qyapi.weixin.qq.com');
      expect(row['secret'], 'corpsecret-x');
      // DB 层负责 JSON 序列化（saveAppChannels 内做 encode）——
      // 但 service.saveChannels 传入的是 Map（由 DatabaseHelper 行构建器编码），
      // fake store 透传 service 层的原始 Map。此处验证结构正确即可。
      expect(row['config'], isA<Map>());
      expect((row['config'] as Map)['corpid'], 'corp-x');
      expect(row['enabled'], true);
    });

    test('原生同步 payload 契约：setAppChannels 携带完整通道（含 secret/config）', () async {
      await service.saveChannels([
        {
          'id': 'app-feishu-1',
          'name': '飞书应用',
          'appType': 'feishu_app',
          'baseUrl': 'https://open.feishu.cn',
          'secret': 'app-secret-x',
          'config': {
            'app_id': 'cli-x',
            'receive_id_type': 'chat_id',
            'receive_id': 'oc-x',
          },
          'message_format': 'default',
          'enabled': true,
        },
      ]);

      final syncCall = channelCalls.singleWhere(
        (c) => c.method == 'setAppChannels',
      );
      final channels = (syncCall.arguments as Map)['channels'] as List;
      final ch = channels.single as Map;
      expect(ch['appType'], 'feishu_app');
      expect(ch['baseUrl'], 'https://open.feishu.cn');
      expect(ch['secret'], 'app-secret-x');
      final config = ch['config'] as Map;
      expect(config['receive_id'], 'oc-x');
      expect(config['receive_id_type'], 'chat_id');
    });

    test('空通道保存：原生同步 payload 为空数组', () async {
      await service.saveChannels([]);
      final syncCall = channelCalls.singleWhere(
        (c) => c.method == 'setAppChannels',
      );
      expect((syncCall.arguments as Map)['channels'], isEmpty);
    });

    test('保存后 channels 内存列表与传入一致（回读用）', () async {
      final input = [
        {
          'id': 'app-1',
          'name': '测试',
          'appType': 'wecom_app',
          'baseUrl': 'https://qyapi.weixin.qq.com',
          'secret': null,
          'config': {'corpid': 'corp'},
          'message_format': 'default',
          'enabled': true,
        },
      ];
      await service.saveChannels(input);
      expect(service.channels.single['id'], 'app-1');
      expect(service.channels.single['enabled'], true);
    });
  });
}

/// 伪自建应用通道存储（注入 AppChannelService，不出网）
class FakeAppChannelStore implements AppChannelStore {
  List<Map<String, dynamic>> rows = [];
  final List<List<Map<String, dynamic>>> savedBatches = [];

  @override
  Future<List<Map<String, dynamic>>> getAppChannels() async => rows;

  @override
  Future<void> saveAppChannels(List<Map<String, dynamic>> channels) async {
    savedBatches.add(List.of(channels));
    rows = List.of(channels);
  }
}
