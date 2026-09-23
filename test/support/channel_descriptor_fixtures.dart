import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';
import 'package:notice_transmit/services/channel_health_store.dart';

import 'source_guards.dart';

/// 原生 `getChannelDescriptors` 的**导出快照**（widget 测试的 fixture）。
///
/// ⚠ 这份文件不是手写的，由 JVM 测试 `ChannelDescriptorExportTest` 从
/// `ChannelRegistry` / `AppChannelRegistry` 直接生成：
/// 删掉文件 → 跑一次该测试 → 重新生成。
/// 手抄一份「测试用描述符」的后果是 widget 测试对着假表跑绿 ——
/// 原生改了字段或能力位，Dart 测试看不见。
const String kDescriptorFixtureRelPath =
    'android/app/src/test/resources/channel_descriptors.json';

List<Map<Object?, Object?>>? _cached;

List<Map<Object?, Object?>> exportedDescriptors() {
  final cached = _cached;
  if (cached != null) return cached;
  final file = File('${projectRoot()}/$kDescriptorFixtureRelPath');
  if (!file.existsSync()) {
    throw StateError(
      '缺少 ${file.path}：跑 ./gradlew :app:testDebugUnitTest '
      '--tests "*ChannelDescriptorExportTest*" 生成'
      '（它是 Dart 表单测试唯一的描述符来源）',
    );
  }
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return _cached = (decoded['descriptors'] as List<Object?>)
      .cast<Map<Object?, Object?>>();
}

/// `getChannelDescriptors` 的 mock 答复（形状与 MethodChannel 真实回传一致）。
/// 用法：在测试自己的 handler 里 `if (call.method == 'getChannelDescriptors') return descriptorCallResponse(call);`
Object? descriptorCallResponse(MethodCall call) => exportedDescriptors();

/// 注册「通道设置页」依赖的两个服务（widget 测试用；重复注册时覆盖）。
///
/// 两个都要：页面 initState 里各取一次，缺任何一个都是**建页即抛**，
/// 表现为 `Found 0 widgets with type "...SettingsPage"`（不是断言失败，容易被误读成路由问题）。
void registerChannelPageServices({GetIt? getIt}) {
  final locator = getIt ?? GetIt.instance;
  locator.allowReassignment = true;
  if (locator.isRegistered<ChannelDescriptorService>()) {
    locator.unregister<ChannelDescriptorService>();
  }
  if (locator.isRegistered<ChannelHealthStore>()) {
    locator.unregister<ChannelHealthStore>();
  }
  locator.registerLazySingleton<ChannelDescriptorService>(
    ChannelDescriptorService.new,
  );
  locator.registerLazySingleton<ChannelHealthStore>(ChannelHealthStore.new);
}
