import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 测试用数据库初始化。
///
/// 纯 Dart 单元测试没有 Android 平台通道，直接访问 sqflite 会抛出
/// MissingPluginException。将全局 [databaseFactory] 替换为 FFI 后端，
/// 使数据库读写走 sqflite_common_ffi 实现。
void initTestDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// 碰**服务层写路径**的测试必须先接住原生通道，两种坏法都见过：
/// - 普通 `test()`：`invokeMethod` 抛 `MissingPluginException` —— 服务里没包 try 的那条
///   （如 `EmailService.saveChannels`）直接把用例打红；
/// - `testWidgets`：那个 `await` **永远不返回** ⇒ 整批用例 `did not complete`
///   （base.md（53）（54）两次都是它；`WebhookService._syncToNative` 还会先走
///   flutter_secure_storage 那**另一个**通道）。
///
/// 默认全部回 `null`；需要特定返回值（描述符、探测结果）时用 [onCall] 覆盖。
void stubNativeChannels({Future<Object?> Function(MethodCall call)? onCall}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in const [
    'com.fnthink.notice/notification',
    'plugins.it_nomads.com/flutter_secure_storage',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(name),
          onCall ?? (call) async => null,
        );
  }
}

/// 摘掉桩（在 tearDown 里调用，避免桩渗到同一 isolate 的下一个文件）。
void clearNativeChannelStubs() {
  for (final name in const [
    'com.fnthink.notice/notification',
    'plugins.it_nomads.com/flutter_secure_storage',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), null);
  }
}
