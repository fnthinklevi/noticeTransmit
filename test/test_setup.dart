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
