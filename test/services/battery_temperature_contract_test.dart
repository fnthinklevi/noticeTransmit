import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/temperature_service.dart';

import '../support/engine_rule_store_fake.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

/// 温度规则类型双端契约（v1.59 引入，v1.62 修成**真**比对）。
///
/// 本文件原版本名为「与 Kotlin TEMP_RULE_TYPES 一致」，实际是拿一个测试内部的
/// `const dartTypes` 和自己比（`hasLength(3)` + 后缀循环），不读任何 Kotlin 文件
/// —— 原生改名后两端仍然全绿，而温度规则会静默不再触发。现改为解析原生源码比对。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          return true; // setBatterySetting / refreshEngineRules 同步成功
        });
  });

  /// 从 Kotlin 源码里取 `val <name> = setOf(...)` 的字符串字面量集合。
  /// T19 起两个集合都住在 `NotificationEngine.kt`（判据的单点），不再是 BatteryMonitor。
  /// ⚠ 两侧都要剥注释：一句"TEMP_RULE_TYPES = setOf(...) 已改名"的注释，
  ///   或页面里一行提到某类型字面量的注释，都能让判据为真而代码其实什么都没做。
  Set<String> kotlinRuleTypes(String name) {
    final src = stripComments(
      File(
        'android/app/src/main/kotlin/com/fnthink/notice/NotificationEngine.kt',
      ).readAsStringSync(),
    );
    final start = src.indexOf('$name = setOf(');
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: '原生 $name 定义被改名/删除/挪走（T19 后判据只在 NotificationEngine 一处）',
    );
    final end = src.indexOf(')', start);
    final block = RegExp(
      r'"([a-z_]+)"',
    ).allMatches(src.substring(start, end)).map((m) => m.group(1)!).toSet();
    expect(block, isNotEmpty, reason: '未解析到任何类型字面量，本用例已失效');
    return block;
  }

  Set<String> kotlinTempRuleTypes() => kotlinRuleTypes('TEMP_RULE_TYPES');

  group('温度规则类型 – 双端契约', () {
    test('Dart tempRuleTypes 与 Kotlin TEMP_RULE_TYPES 逐字一致', () {
      expect(
        TemperatureService.tempRuleTypes,
        kotlinTempRuleTypes(),
        reason:
            '两端类型字面量不一致 → 原生 when/contains 静默失配，'
            '用户配的温度规则永远不触发且无任何报错',
      );
    });

    /// T19 的引擎接缝：界面能配的每个类型，引擎都必须认识。
    /// 不钉这条的话，T24 加亮度/网络时很容易先让 Dart 能配、原生后认识 ——
    /// 表现是"规则保存成功、永不触发"（引擎对未知类型一律不触发）。
    test('电量页能配的类型 == 原生 BATTERY_RULE_TYPES（引擎不认识的类型不得出现在界面）', () {
      final chips = stripComments(
        File('lib/pages/battery_page.dart').readAsStringSync(),
      );
      final dartTypes = RegExp(
        r"_buildTypeChip\(\s*'([a-z_]+)'",
      ).allMatches(chips).map((m) => m.group(1)!).toSet();
      expect(dartTypes, isNotEmpty, reason: '没解析到任何类型芯片 ⇒ 页面写法变了，本条已失效');
      expect(
        dartTypes,
        kotlinRuleTypes('BATTERY_RULE_TYPES'),
        reason: '界面能配的电量类型与引擎认识的集合分叉',
      );
    });

    test('三个维度齐备且命名符合 _temp_above 约定', () {
      expect(TemperatureService.tempRuleTypes, <String>{
        'battery_temp_above',
        'device_temp_above',
        'screen_temp_above',
      });
      for (final t in TemperatureService.tempRuleTypes) {
        expect(t.endsWith('_temp_above'), isTrue, reason: '类型 $t 命名不符契约');
      }
    });

    test('两个规则编辑页都仍在呈现这些类型（新增维度不得只加一处）', () {
      for (final page in [
        'lib/pages/battery_page.dart',
        'lib/pages/temperature_page.dart',
      ]) {
        final src = stripComments(File(page).readAsStringSync());
        for (final t in TemperatureService.tempRuleTypes) {
          expect(src.contains("'$t'"), isTrue, reason: '$page 缺少类型 $t 的入口');
        }
      }
    });
  });

  group('规则透传保真', () {
    test('温度服务：addRule 后类型与阈值原样保留', () async {
      final service = TemperatureService(store: MemoryRuleStore());
      await service.loadSettings();
      await service.addRule({
        'id': 'temp-s-1',
        'type': 'device_temp_above',
        'value': 42,
        'enabled': true,
        'title': '设备温度过高',
        'content': '',
      });
      final saved = service.rules.firstWhere((r) => r['id'] == 'temp-s-1');
      expect(saved['type'], 'device_temp_above');
      expect(saved['value'], 42);
    });

    test('电量服务：温度类型规则经 addRule/save 后透传保真', () async {
      final service = BatteryService(store: MemoryRuleStore());
      await service.loadSettings();
      final before = service.rules.length;
      await service.addRule({
        'id': 'temp-1',
        'type': 'battery_temp_above',
        'value': 45,
        'enabled': true,
        'title': '电池温度过高',
        'content': '',
      });
      final added = service.rules.firstWhere((r) => r['id'] == 'temp-1');
      expect(added['type'], 'battery_temp_above');
      expect(added['value'], 45);
      expect(service.rules.length, before + 1);
    });
  });
}
