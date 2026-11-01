import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/secure_storage_service.dart';

/// T222：安全存储的**有界失败**。
///
/// 现场是 AndroidKeyStore 的主密钥解不开 prefs（`SecurityException: Could not decrypt key`），
/// 插件那一发**可能永远不回答** —— 过去它一路冒到启动链，界面就停在「初始化完成」。
/// 这一组钉住两条：失败必须变成有类型的 [SecureStorageUnavailable]，且每次调用都有上界。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // 全局测试配置（`test/flutter_test_config.dart`）默认关掉上界；这一组要钉的正是
  // 「不回答就超时」，所以单独打开。
  setUp(() => SecureStorageService.boundedOps = true);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    SecureStorageService.boundedOps = false;
  });

  test('插件抛 SecurityException 时读失败变成 SecureStorageUnavailable', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'SecurityException',
        message: 'Could not decrypt key. decryption failed',
      );
    });

    await expectLater(
      SecureStorageService().read('db_encryption_key'),
      throwsA(
        isA<SecureStorageUnavailable>().having(
          (e) => e.reason,
          'reason',
          contains('read:db_encryption_key'),
        ),
      ),
    );
  });

  test('读成功时原样返回 null —— "没有值"不许被说成失败', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    expect(await SecureStorageService().read('db_encryption_key'), isNull);
  });

  test('插件不回答时 5 秒有界超时，而不是一直挂着', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) => Completer<Object?>().future,
    );

    await expectLater(
      SecureStorageService()
          .read('db_encryption_key')
          .timeout(const Duration(seconds: 8)),
      throwsA(isA<SecureStorageUnavailable>()),
    );
  }, timeout: const Timeout(Duration(seconds: 15)));
}
