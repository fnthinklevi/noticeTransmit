import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/native_channel_invalidator.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late List<String> events;

  setUp(() {
    events = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          events.add('secure:${call.method}');
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('阻断位每次读盘，不吃 isolate 的旧快照', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(await isChannelMirrorInvalidationPending(), isFalse);

    await prefs.setBool(kChannelMirrorInvalidationPendingKey, true);

    expect(await isChannelMirrorInvalidationPending(), isTrue);

    await prefs.setBool(kChannelMirrorInvalidationPendingKey, false);

    expect(await isChannelMirrorInvalidationPending(), isFalse);
  });

  test('先原生阻断，再删旧副本，最后完成失效并撤闸', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          events.add('native:${call.arguments['phase']}');
          return true;
        });

    await invalidateNativeChannelMirrors();

    expect(events, ['native:begin', 'secure:delete', 'native:finish']);
  });

  test('开始阻断未确认时不删旧副本也不进入完成阶段', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          events.add('native:${call.arguments['phase']}');
          return false;
        });

    await expectLater(invalidateNativeChannelMirrors(), throwsStateError);
    expect(events, ['native:begin']);
  });

  test('Dart 旧副本删除失败后不再调用完成阶段', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          events.add('native:${call.arguments['phase']}');
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          throw PlatformException(code: 'secure-delete-failed');
        });

    await expectLater(
      invalidateNativeChannelMirrors(),
      throwsA(isA<PlatformException>()),
    );
    expect(events, ['native:begin']);
  });

  test('完成阶段异常原样上抛，由数据库恢复路径中止重建', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          events.add('native:${call.arguments['phase']}');
          if (call.arguments['phase'] == 'finish') {
            throw PlatformException(code: 'invalidation-failed');
          }
          return true;
        });

    await expectLater(
      invalidateNativeChannelMirrors(),
      throwsA(isA<PlatformException>()),
    );
    expect(events, ['native:begin', 'secure:delete', 'native:finish']);
  });
}
