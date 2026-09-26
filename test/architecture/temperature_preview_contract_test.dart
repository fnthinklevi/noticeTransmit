import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/temperature_preview.dart';

import '../support/source_guards.dart';

/// T25：温度试跑的跨端契约。
///
/// 这一批改的是一句老话的兑现：**判据只有一份**。求值在原生 `NotificationEngine`，
/// Dart 只负责读数递过去、把结果翻译成人话。所以这里钉的都是"两边怎么悄悄脱钩"：
/// 原生新增一个 `Silence` 原因、Dart 标签表没跟上 ⇒ 界面不崩，只是把 `NOT_CROSSING`
/// 这种原始枚举名直接甩给用户看；ARB 少一条 ⇒ 生成物编译期就会红，但**加错语言**不会。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  /// 原生 `Silence` 枚举的全部值（剥注释后扫，注释里提到的枚举名不算）。
  List<String> nativeSilences() {
    final engine = stripComments(
      read(
        'android/app/src/main/kotlin/com/fnthink/notice/NotificationEngine.kt',
      ),
    );
    final start = engine.indexOf('enum class Silence {');
    expect(
      start,
      greaterThan(0),
      reason: 'Silence 枚举不见了/改名 ⇒ 本判据要重新指向（不许静默空转）',
    );
    final body = engine.substring(start, engine.indexOf('}', start));
    final names = RegExp(
      r'^\s*([A-Z][A-Z0-9_]+)',
      multiLine: true,
    ).allMatches(body).map((m) => m.group(1)!).toList();
    expect(
      names.length,
      greaterThanOrEqualTo(7),
      reason: '只数到 ${names.length} 个枚举值 ⇒ 解析正则已失效，下面的覆盖判据是空的',
    );
    return names;
  }

  group('标签表与原生枚举同源', () {
    test('每个 Silence 值（含 FIRE）在页面里都有标签分支', () {
      final page = stripComments(read('lib/pages/temperature_page.dart'));
      for (final name in [...nativeSilences(), 'FIRE']) {
        expect(
          page,
          contains("'$name'"),
          reason:
              '原生有 $name 这个结论，而 Dart 的 _outcomeLabel 没登记 ⇒ '
              '用户会在弹层里看到原始枚举名（"为什么没响"恰恰是这个问题要回答的）',
        );
      }
    });

    test('标签分支引用的 l10n 键，中英两份 ARB 都得有值', () {
      final page = stripComments(read('lib/pages/temperature_page.dart'));
      final labels = RegExp(
        r"'(?:[A-Z][A-Z0-9_]+|FIRE)'\s*=>\s*l10n\.(\w+)",
      ).allMatches(page).map((m) => m.group(1)!).toList();
      expect(
        labels.length,
        greaterThanOrEqualTo(8),
        reason: '没数到标签键 ⇒ 正则已失效（这条会变成空守卫）',
      );
      for (final locale in const ['zh', 'en']) {
        final arb =
            jsonDecode(read('lib/l10n/arb/app_$locale.arb'))
                as Map<String, dynamic>;
        for (final key in labels) {
          expect(
            arb[key],
            isA<String>(),
            reason: '$locale 缺 $key：另一种语言的会退回键名或空串（gen-l10n 不报错）',
          );
        }
      }
      // 反向锚点：这些标签确实有中文值，不是空串占位。
      final zh =
          jsonDecode(read('lib/l10n/arb/app_zh.arb')) as Map<String, dynamic>;
      for (final key in labels) {
        expect((zh[key]! as String).trim(), isNotEmpty, reason: '$key 中文值是空的');
      }
    });
  });

  group('交给原生的形状仍是那一份', () {
    test('previewTest 走 EngineRuleCodec 编码，不手抄规则形状', () {
      final svc = stripComments(read('lib/services/temperature_service.dart'));
      final body = blockAfter(svc, 'Future<TemperaturePreview?> previewTest(');
      expect(
        body,
        contains('EngineRuleCodec.normalizeAll'),
        reason:
            '规则形状的单点就是 EngineRuleCodec（T20）；这里自己拼 Map 就等于开出第二份，'
            '以后 codec 改字段，镜像与试跑看到的规则会不是同一批',
      );
      expect(
        body,
        contains("'rulesJson'"),
        reason: '必须按原生那侧的入参名递（改名不会编译报错，只会静默收空规则）',
      );
    });

    test('原生那侧确实接住了这个方法（两侧都要有，中间没有编译期联系）', () {
      final handler = stripComments(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/channels/DeviceChannelHandler.kt',
        ),
      );
      expect(handler, contains('"previewTemperatureRule" ->'));
      expect(
        stripComments(
          read(
            'android/app/src/main/kotlin/com/fnthink/notice/BatteryMonitor.kt',
          ),
        ),
        contains('NotificationEngine.previewTemperature('),
      );
    });
  });

  group('模型宽容解析（形状来自平台通道，不受我们控制）', () {
    test('整数落成字符串/浮点、steps 形状不对、键缺失都不许抛', () {
      final p = TemperaturePreview.fromMap(const {
        'ok': true,
        'temps': {'battery_temp_above': 45}, // Int 而不是 Double
        'steps': [
          {'phase': 'baseline', 'outcome': 'BASELINE'},
          {'phase': 'below'}, // 少 outcome
          'not a map', // 形状完全不对
        ],
        'ruleCount': '2',
        'fired': false,
        'threshold': 40.0,
        'silence': 'NOT_TRIGGERED',
      });
      expect(p.ok, isTrue);
      expect(p.temps['battery_temp_above'], 45.0);
      expect(p.steps, hasLength(1), reason: '缺 outcome 的那步不该被塞进列表显示成空白');
      expect(p.ruleCount, 2, reason: '数字串也要认（同 T23-B 的口径）');
      expect(p.threshold, 40);
      expect(p.fired, isFalse);
      expect(p.failed, isFalse);
    });

    test('缺 ok 键按“没测成”处理，绝不按“不会触发”处理', () {
      final p = TemperaturePreview.fromMap(const {'fired': false});
      expect(p.ok, isFalse);
      expect(p.failed, isTrue);
      // 反向锚点：不是"fired 缺省=false"这种顺带成立。
      expect(TemperaturePreview.fromMap(const {'ok': true}).failed, isFalse);
    });

    test('通道回 null 与"不会触发"是两件事', () {
      final silent = TemperaturePreview.fromMap(const {
        'ok': true,
        'fired': false,
        'silence': 'NOT_CROSSING',
      });
      expect(silent.failed, isFalse);
      expect(silent.silence, 'NOT_CROSSING');
    });
  });
}
