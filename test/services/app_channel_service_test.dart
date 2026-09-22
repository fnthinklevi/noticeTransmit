import '../support/source_guards.dart';
import 'dart:io';

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
      // 原生契约键（ConfigManager.getAppChannelConfigs 读 type / base_url），
      // 不是 UI 侧的 appType / baseUrl —— 发错键名会让原生解析出空 type，
      // 每条自建应用推送静默落到「未知应用通道类型」。
      expect(ch['type'], 'feishu_app');
      expect(ch['base_url'], 'https://open.feishu.cn');
      expect(ch['secret'], 'app-secret-x');
      expect(ch['enabled'], true);
      expect(ch['id'], 'app-feishu-1');
      expect(ch['name'], '飞书应用');
      expect(ch['message_format'], 'default');
      final config = ch['config'] as Map;
      expect(config['receive_id'], 'oc-x');
      expect(config['receive_id_type'], 'chat_id');
      // UI 键不得漏进跨端载荷（出现即说明映射被绕过、把 _channels 原样下发了）
      expect(ch.containsKey('appType'), isFalse);
      expect(ch.containsKey('baseUrl'), isFalse);
    });

    test('跨端契约：原生读取的每个键 Dart 载荷都必须提供（解析 ConfigManager.kt 实测）', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
      ).readAsStringSync();
      final start = kotlin.indexOf('fun getAppChannelConfigs(');
      expect(start, greaterThanOrEqualTo(0), reason: '原生读取函数改名了，需同步本用例');
      // 只取本函数体：到下一个 fun 声明为止，避免把别的读取键算进来
      final next = kotlin.indexOf('\n    fun ', start + 1);
      final block = stripComments(
        kotlin.substring(start, next < 0 ? kotlin.length : next),
      );
      final read = RegExp(
        r'opt(?:String|Boolean|Int|Long|Double|JSONObject|JSONArray)\(\s*"([A-Za-z_][A-Za-z0-9_]*)"',
      ).allMatches(block).map((m) => m.group(1)!).toSet();
      expect(read, isNotEmpty, reason: '未解析到任何读取键 —— 本用例已失效');

      final produced = AppChannelService.toNativePayload({
        'id': 'app-1',
        'name': 'n',
        'appType': 'wecom_app',
        'baseUrl': 'https://qyapi.weixin.qq.com',
        'secret': 's',
        'config': <String, dynamic>{},
        'message_format': 'default',
        'enabled': true,
      }).keys.toSet();

      // 原生对 base_url 保留了历史别名兜底（optString("base_url", optString("url", ""))）：
      // 别名键由原生兜底，Dart 只需提供主键名。
      const nativeFallbackAliases = <String>{'url'};
      final missing = read.difference(produced);

      expect(
        missing.difference(nativeFallbackAliases),
        isEmpty,
        reason:
            '原生读取但 Dart 载荷未提供的键 → 原生取到空值、推送静默失败：'
            '${missing.difference(nativeFallbackAliases)}',
      );
      // 反向自检：别名一旦从原生代码里消失，下面的豁免就该删掉（否则豁免变成死角）
      expect(
        read.intersection(nativeFallbackAliases),
        nativeFallbackAliases,
        reason: '原生已不再读这些别名键，请同步删除本用例的别名豁免',
      );
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
