import 'dart:io';

import '../support/source_guards.dart';
import 'package:flutter_test/flutter_test.dart';

/// T20：引擎规则存储的跨语言接线守卫。
///
/// 这一族的键名与"谁写谁读"全是字符串契约，改错一端不会有任何编译期报错，
/// 表现都是**静默的**：
/// - Dart 的 prefsKey 与原生 `ConfigManager.KEY_*_RULES` 不一致 ⇒ 原生永远读到 `"[]"`，
///   用户界面上规则好好的，告警再也不来；
/// - 原生侧若又长回一处镜像写（`setBatteryRules` 那类），同一把键就有两个写入者、
///   两套默认值，漂出来的那条规则要么永不触发要么乱触发；
/// - Dart 侧若绕过 [EngineRuleRepository] 自己写 prefs ⇒ 写库与写镜像脱钩，
///   备份恢复/切主路径（T21）时读到的就是两份不同答案。
///
/// ⚠ 全部断言都在测试体里惰性读文件、并且先验"锚点解析到了东西"：解析器失效时
/// 这些判据会恒真（base.md（75）的教训）。
void main() {
  final root = projectRoot();
  String dart(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());
  String kotlin(String rel) => stripComments(
    File(
      '$root/android/app/src/main/kotlin/com/fnthink/notice/$rel',
    ).readAsStringSync(),
  );

  /// Dart 侧所有 lib 源码（注释已剥离）。
  Map<String, String> dartLibSources() {
    final out = <String, String>{};
    for (final entity in Directory('$root/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      out[path] = stripComments(entity.readAsStringSync());
    }
    expect(out.length, greaterThan(60), reason: '扫到的 Dart 文件太少，守卫已失效');
    return out;
  }

  group('镜像只有一个写入者（T20 撤掉的原生那一份不许长回来）', () {
    test('Dart 不再调用 setBatteryRules / setTemperatureRules', () {
      final hit = dartLibSources().entries
          .where(
            (e) =>
                e.value.contains('setBatteryRules') ||
                e.value.contains('setTemperatureRules'),
          )
          .map((e) => e.key.split('/').last)
          .toList();
      expect(
        hit,
        isEmpty,
        reason: '规则镜像已由 Dart 直接写 prefs，再经通道让原生重抄一遍就是两处写同一把键',
      );
    });

    test('原生侧那两枚方法与分支都已删除，改由 refreshEngineRules 只发重载信号', () {
      final main = kotlin('MainActivity.kt');
      final handler = kotlin('channels/ConfigChannelHandler.kt');
      expect(
        RegExp(r'fun setBatteryRules\(').hasMatch(main),
        isFalse,
        reason: '原生镜像写回来了 = 两处写同一把键、两套默认值',
      );
      expect(
        RegExp(r'fun setTemperatureRules\(').hasMatch(main),
        isFalse,
        reason: '同上（温度族）',
      );
      expect(handler, isNot(contains('"setBatteryRules"')));
      expect(handler, isNot(contains('"setTemperatureRules"')));
      expect(
        handler,
        contains('"refreshEngineRules"'),
        reason: '没有这枚方法，改完规则要等监听服务重启才生效',
      );
      expect(
        handler,
        contains('notifyServiceConfigChanged'),
        reason: 'refreshEngineRules 的实质就是这一声重载广播',
      );
    });

    test('原生不再写 flutter.battery_rules / flutter.temperature_rules', () {
      for (final file in ['MainActivity.kt', 'ConfigManager.kt']) {
        final src = kotlin(file);
        for (final key in ['battery_rules', 'temperature_rules']) {
          expect(
            RegExp('putString\\(\\s*"(flutter\\.)?$key"').hasMatch(src),
            isFalse,
            reason: '$file 又成了 $key 的第二个写入者',
          );
        }
      }
    });
  });

  group('跨语言键名契约', () {
    /// 原生读的 prefs 键（去掉 SharedPreferences 插件加的 `flutter.` 前缀）。
    Set<String> kotlinRuleKeys() {
      final src = kotlin('ConfigManager.kt');
      final keys = <String>{};
      for (final name in ['KEY_BATTERY_RULES', 'KEY_TEMPERATURE_RULES']) {
        final m = RegExp('$name\\s*=\\s*"flutter\\.([a-z_]+)"').firstMatch(src);
        expect(m, isNotNull, reason: '原生常量 $name 被改名或删除，守卫已失效');
        keys.add(m!.group(1)!);
      }
      expect(keys.length, 2, reason: '两族键名解析重复，本用例已失效');
      return keys;
    }

    /// Dart 侧传给 [EngineRuleRepository] 的 prefsKey。
    Set<String> dartRuleKeys() {
      final keys = <String>{};
      for (final file in [
        'lib/services/battery_service.dart',
        'lib/services/temperature_service.dart',
      ]) {
        final src = dart(file);
        final m = RegExp(r"prefsKey:\s*'([a-z_]+)'").firstMatch(src);
        expect(m, isNotNull, reason: '$file 里没有 prefsKey 常量，本用例已失效');
        keys.add(m!.group(1)!);
      }
      return keys;
    }

    test('Dart 写的镜像键名 == 原生读的键名（逐字）', () {
      expect(
        dartRuleKeys(),
        kotlinRuleKeys(),
        reason:
            '两端键名不一致 → 原生永远读到 "[]"：用户规则在界面上好好的，'
            '告警再也不来，且没有任何报错',
      );
    });

    test('两族各自的键不共享，且都带族前缀', () {
      expect(dartRuleKeys(), {'battery_rules', 'temperature_rules'});
    });
  });

  group('形状归一只有一个地方', () {
    test('规则镜像的 JSON 编码只在 EngineRuleCodec 里', () {
      final encoders = dartLibSources().entries
          .where((e) => e.value.contains('toLegacyJson'))
          .map((e) => e.key.split('/').last)
          .toList();
      expect(
        encoders,
        contains('engine_rule_codec.dart'),
        reason: '编解码函数被改名或搬家 —— 本用例已失效',
      );
      expect(
        encoders.where((p) => p != 'engine_rule_codec.dart'),
        ['engine_rule_repository.dart'],
        reason: '多一处调用 toLegacyJson = 又多一处形状定义点',
      );
    });

    test('两个服务都不再自己拼规则 JSON（一律走仓储）', () {
      for (final file in [
        'lib/services/battery_service.dart',
        'lib/services/temperature_service.dart',
      ]) {
        final src = dart(file);
        expect(
          src,
          contains('EngineRuleRepository'),
          reason: '$file 绕过了仓储咽喉 —— 落库/镜像/重载三件事就分家了',
        );
        expect(
          RegExp(r"setString\(\s*'(battery|temperature)_rules'").hasMatch(src),
          isFalse,
          reason: '$file 自己写镜像 = 与库里内容脱钩',
        );
      }
    });

    test('原生读取侧仍按那五个键取值（Dart 少写一个键就落到原生默认值）', () {
      // 这条与 Kotlin 侧 EngineRuleMirrorContractTest 是一对：那边从 Dart 源码取
      // uiKeys 与本文件比对，这边钉住 Dart 侧的定义处只有一份。
      final codec = dart('lib/services/engine_rule_codec.dart');
      final keys = RegExp(
        r"uiKeys\s*=\s*\[([^\]]*)\]",
      ).firstMatch(codec)?.group(1);
      expect(keys, isNotNull, reason: '未解析到 uiKeys，本用例已失效');
      final listed = RegExp(
        r"'([a-z_]+)'",
      ).allMatches(keys!).map((m) => m.group(1)!).toSet();
      expect(listed, {
        'id',
        'type',
        'value',
        'enabled',
        'title',
        'content',
      }, reason: '镜像键集合变了必须同时改 BatteryMonitor.parseBatteryRules 与原生测试');
    });
  });
}
