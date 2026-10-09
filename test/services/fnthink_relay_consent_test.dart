import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

/// T119：撤销「通知内容经服务器中转」那一发。
///
/// 三件事各自一条判据（不合成一个计数，合成本仓已证过必出假绿）：
///  ① **只清那一枚键** —— 撤销的是许可，不是数据：开关、名单、端点、通道配置、历史一律留着。
///  ② **两处入口指向同一个实现**（`confirmAndRevokeRelayConsent`）—— 各写一遍就会有一处清了键
///     而另一处还显示"已同意"；且入口那一侧**不许跳过二次确认**直接调服务层的撤销。
///  ③ **清那枚键的作者全仓只有一个** —— 形状守卫，不抄路径名单。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = projectRoot();
  final contract = FnthinkContract.readFile();
  final settings = FnthinkSettings(contract: contract);

  String page(String relative) => stripComments(
    File('$root${Platform.pathSeparator}$relative').readAsStringSync(),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('撤销只清那一枚键', () {
    test('同意 → 撤销：同意那枚没了，接收开关一条不动', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.${FnthinkSettings.keyReceiveEnabled}': true,
      });
      await settings.grantRelayConsent();
      expect(await settings.hasRelayConsent(), isTrue);

      await settings.revokeRelayConsent();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(FnthinkSettings.keyConsentVersion),
        isFalse,
        reason: '那枚键还在 ⇒ 撤销没生效，而界面会自己说"已撤销"',
      );
      expect(
        await settings.hasRelayConsent(),
        isFalse,
        reason: '清完还判成同意过 ⇒ 协调者会照常中转内容，而用户以为许可已收回',
      );
      expect(
        await settings.receiveEnabled,
        isTrue,
        reason:
            '撤销的是"允许中转"，不是把这些设置一并抹掉 —— '
            '那样用户下次不敢点这个按钮（名单/端点/通道/历史同一条纪律）',
      );
    });

    test('撤销之后重新同意：记回的仍是契约当前那一档', () async {
      await settings.grantRelayConsent();
      await settings.revokeRelayConsent();
      await settings.grantRelayConsent();
      expect(
        await settings.grantedConsentVersion(),
        settings.requiredConsentVersion,
        reason: '撤销若记成"降到旧版本"，重新同意就永远补不回当前档',
      );
    });
  });

  group('两处入口共用一个实现（形状守卫）', () {
    test('接收页与设置页都走同一个确认+撤销，都不自己摸那枚键', () {
      for (final relative in const [
        'lib/pages/fnthink_receive_page.dart',
        'lib/pages/fnthink_settings_page.dart',
      ]) {
        final code = page(relative);
        expect(
          code,
          contains('confirmAndRevokeRelayConsent('),
          reason:
              '$relative 不走那一个实现 ⇒ 两处撤销各清各的，'
              '"设置页撤了而接收页还显示已同意"就是迟早的事',
        );
        expect(
          code,
          isNot(contains(FnthinkSettings.keyConsentVersion)),
          reason: '$relative 自己碰那枚键 ⇒ 服务层唯一作者被绕过',
        );
        expect(
          code,
          isNot(contains('.revokeRelayConsent(')),
          reason: '$relative 跳过二次确认直接清键 ⇒ 同意要显式点、撤销也必须要点第二下',
        );
      }
    });

    test('清那枚键的作者全仓只有服务层一处', () {
      final writers = <String>[];
      for (final f
          in Directory('$root/lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (stripComments(
          f.readAsStringSync(),
        ).contains('remove(keyConsentVersion)')) {
          writers.add(
            f.path
                .substring(root.length + 1)
                .replaceAll('\\', '/')
                .replaceFirst('lib/', 'lib/'),
          );
        }
      }
      expect(writers, [
        'lib/services/fnthink_settings.dart',
      ], reason: '又多一处清同意 ⇒ "两处入口同一实现"从形状上已经断了');
    });
  });
}
