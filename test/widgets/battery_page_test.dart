import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/pages/battery_page.dart';

import '../support/source_guards.dart';

/// 电量页顶部读数的色调档位（1.5.76 实拍三页时发现的不一致，维护者点头后修）。
///
/// 病灶：`currentLevel` 读不到时是 `-1`，而旧判据只有三档（`>=50` 绿 / `>=20` 橙 / 否则红）
/// ⇒ `-1` 掉进红色档，顶部大字写着「未知」、图标与数字却是"电量已低于阈值"的红。
/// 那是把"没有数"报成"出事了"，比不显示更坏。
void main() {
  group('batteryToneOf 档位', () {
    test('读不到（-1）走 unknown，不许落进任何一档颜色', () {
      expect(batteryToneOf(-1), BatteryTone.unknown);
      // 比 -1 更小的异常值同样不许被当成"极低电量"
      expect(batteryToneOf(-100), BatteryTone.unknown);
    });

    test('边界前后一格分明（20 / 50 是含端点的）', () {
      expect(batteryToneOf(0), BatteryTone.critical);
      expect(batteryToneOf(19), BatteryTone.critical);
      expect(batteryToneOf(20), BatteryTone.warn);
      expect(batteryToneOf(49), BatteryTone.warn);
      expect(batteryToneOf(50), BatteryTone.good);
      expect(batteryToneOf(100), BatteryTone.good);
    });
  });

  group('页面确实按档位上色（不是只改了函数没接线）', () {
    final src = stripComments(
      File('${projectRoot()}/lib/pages/battery_page.dart').readAsStringSync(),
    );

    test('色调只从 batteryToneOf 来，页里不再留第二份三档判据', () {
      expect(src, contains('batteryToneOf(_service.currentLevel)'));
      expect(
        src,
        isNot(contains('_service.currentLevel >= 50')),
        reason: '阈值判据留在 build 里 = 改档位时只改到一处，另一处继续骗人',
      );
    });

    test('unknown 档给中性色，不给红/绿/橙', () {
      final line = src
          .split('\n')
          .firstWhere((l) => l.contains('BatteryTone.unknown =>'));
      expect(line, contains('AppColors.tertiaryLabel(context)'));
      expect(
        line,
        isNot(anyOf(contains('AppColors.red'), contains('AppColors.green'))),
      );
    });

    // 片13：那一发系统请求原来写在弹层按钮的回调里（pop 完立刻 invokeMethod），
    // 现在必须等 `askConfirm` 返回答案之后由调用点发 —— 与 #103、片11 同一条道理：
    // 「点没点中那颗钮」与「用户到底选了哪颗」是两件事，后者才是发请求的条件。
    test('去设置那一发在 await 之后，不在弹层回调里', () {
      expect(
        src,
        contains('IosDialogActions.askConfirm('),
        reason: '外壳没走装配点 ⇒ 形状又要各页一份',
      );
      expect(
        src.indexOf('askConfirm(') <
            src.indexOf("invokeMethod('requestBatteryOptimization')"),
        isTrue,
        reason: '那一发跑到 askConfirm 之前 ⇒ 框一弹出来就把用户送去设置了',
      );
      // 「拿到答案之后按答案早退」这一条由 `delete_confirmation_contract_test` 的咽喉清单钉
      // （那里断的是同一个标识符被否定过），这里不重复写第二份判据。
      expect(
        src,
        isNot(contains('onConfirm:')),
        reason: '又把动作塞回弹层回调 ⇒ 点「暂不」与点「去设置」在这条链上又分不开了',
      );
    });
  });
}
