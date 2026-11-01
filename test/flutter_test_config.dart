import 'dart:async';

import 'package:notice_transmit/services/secure_storage_service.dart';

/// 全局测试配置（Flutter 在每个测试 isolate 启动时调用一次）。
///
/// T222 给安全存储每一发都加了 5 秒上界。widget 测试里那一发平台通道的 await
/// 本来就不会返回（见 `test_setup.dart` 的注释），上界到点之前用例已经结束 ⇒
/// 树销毁时留下 pending Timer。这里统一关掉上界；**只有**
/// `test/services/secure_storage_service_test.dart` 单独打开它，因为那一组要钉的
/// 正是"不回答就超时"。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SecureStorageService.boundedOps = false;
  await testMain();
}
