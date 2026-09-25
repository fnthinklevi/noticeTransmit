import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';

import '../support/channel_descriptor_fixtures.dart';

/// `ChannelDescriptorService`：原生描述符 → Dart 只读视图。
///
/// 这个服务只有一份**不可逆**的关键行为：拉不到时保持未就绪。
/// 页面在它未就绪时按「不收窄」处理（见 webhook/app 设置页测试），
/// 所以这里锁的是缓存语义本身，而不是任何具体平台。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.fnthink.notice/notification');
  Object? Function(MethodCall call)? handler;
  final calls = <String>[];

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return handler?.call(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void answer(Object? Function(MethodCall) h) => handler = h;

  group('解析', () {
    test('导出快照能整份解析：15 条、族分布正确', () async {
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();
      expect(service.isReady, isTrue);
      expect(service.all, hasLength(15));
      expect(service.webhook, hasLength(12));
      expect(service.appChannels, hasLength(2));
      expect(service.email, isNotNull);
    });

    test('邮件族字段带提示与预置档位（T08-C：表单文本只发资源名）', () async {
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();
      final email = service.email!;

      expect(email.family, 'email');
      expect(email.iconKey, email.key, reason: '图标表按 iconKey 取，两者必须同值');
      expect(email.fields.map((f) => f.key), [
        'smtpHost',
        'smtpPort',
        'useSSL',
        'username',
        'password',
        'fromEmail',
        'toEmail',
        'subjectTemplate',
        'bodyTemplate',
      ]);
      expect(email.secretKeepsPrevious, isTrue);

      final port = email.fields.firstWhere((f) => f.key == 'smtpPort');
      expect(port.kind, 'number');
      expect(port.keyboardHint, 'number');
      expect(port.defaultValue, '465', reason: '默认端口只在原生一份');

      final ssl = email.fields.firstWhere((f) => f.key == 'useSSL');
      expect(ssl.isSwitch, isTrue);
      expect(ssl.keyboardHint, isNull, reason: '开关没有键盘');

      final pwd = email.fields.firstWhere((f) => f.key == 'password');
      expect(pwd.isSecret, isTrue);

      final body = email.fields.firstWhere((f) => f.key == 'bodyTemplate');
      expect(body.isMultiline, isTrue);
      expect(body.presets, hasLength(5));
      expect(
        body.presets.first.valueKey,
        isNull,
        reason: '「默认」档位的语义是清空自定义、交回运行时默认，不是空字符串巧合',
      );
      expect(
        email.fields.firstWhere((f) => f.key == 'subjectTemplate').presets,
        hasLength(6),
      );
      // 未登记的 kind 会静默降级成"另一个控件"，所以快照里出现的每个 kind 都要有渲染分支
      for (final f in email.fields) {
        expect(
          ChannelFieldSpec.knownKinds,
          contains(f.kind),
          reason: '${f.key} 的 kind=${f.kind} 没有渲染分支',
        );
      }
    });

    test('消息格式档位随同一份载荷到达（Dart 不再另存枚举）', () async {
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();
      expect(service.messageFormats, [
        'default',
        'text',
        'markdown',
        'json',
        'xml',
      ]);
    });

    test('能力位与字段解析成只读视图', () async {
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();

      final gotify = service.byKey('gotify')!;
      expect(gotify.usesSecretField, isTrue);
      expect(gotify.can('secretRequired'), isTrue);
      expect(gotify.supportsCustomTemplate, isFalse);
      expect(gotify.textLimitChars, isNull);

      final discord = service.byKey('discord')!;
      expect(discord.supportsCustomTemplate, isFalse);
      expect(discord.textLimitChars, 2000);
      expect(discord.usesSecretField, isFalse);

      final wecomApp = service.byKey('wecom_app')!;
      expect(wecomApp.family, 'app');
      expect(wecomApp.officialBase, 'https://qyapi.weixin.qq.com');
      expect(wecomApp.supportsMarkdown, isTrue);
      expect(wecomApp.fields.map((f) => f.key), [
        'corpid',
        'agentid',
        'touser',
      ]);
      final agentid = wecomApp.fields.firstWhere((f) => f.key == 'agentid');
      expect(agentid.isNumber, isTrue);
      expect(agentid.required, isTrue);
      expect(agentid.defaultValue, '0');
      expect(service.byKey('feishu_app')!.supportsMarkdown, isFalse);
    });

    test('未登记的 key 返回 null（调用方据此走兜底，不崩）', () async {
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();
      expect(service.byKey('matrix'), isNull);
    });
  });

  group('缓存与失败', () {
    test('原生返回空列表时保留旧缓存，不进入就绪态', () async {
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();
      final before = service.all;

      answer((call) => const <String, Object?>{'descriptors': <Object?>[]});
      await service.load(force: true);
      expect(service.all, same(before), reason: '空列表覆盖缓存 = 表单以为"这通道没字段"');
      expect(
        service.messageFormats,
        hasLength(5),
        reason: '描述符为空时档位也不得被清掉：清掉会让表单只剩当前值，看起来像"档位丢了"',
      );
    });

    test('载荷是旧形状（裸列表）时保留旧缓存', () async {
      // 两侧同包发布，认旧形状只会把协议错配藏起来 —— 这里锁的是"不藏"。
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();
      final before = service.all;

      answer((call) => exportedDescriptors());
      await service.load(force: true);
      expect(service.all, same(before));
    });

    test('未就绪时能力位查询不抛（服务只提供 null，收窄与否由页面决定）', () async {
      final service = ChannelDescriptorService();
      expect(service.isReady, isFalse);
      expect(service.all, isEmpty);
      expect(service.byKey('dingtalk'), isNull);
    });

    test('通道抛异常时保持未就绪（下一次 load 会重试）', () async {
      answer((call) => throw PlatformException(code: 'unavailable'));
      final service = ChannelDescriptorService();
      await service.load();
      expect(service.isReady, isFalse);

      answer(descriptorCallResponse);
      await service.load();
      expect(service.isReady, isTrue);
    });

    test('已就绪时重复 load 不再打原生；force 才重取', () async {
      answer(descriptorCallResponse);
      final service = ChannelDescriptorService();
      await service.load();
      await service.load();
      expect(calls.where((m) => m == 'getChannelDescriptors'), hasLength(1));

      await service.load(force: true);
      expect(calls.where((m) => m == 'getChannelDescriptors'), hasLength(2));
    });
  });
}
