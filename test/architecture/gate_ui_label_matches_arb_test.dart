import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 闸门里写死的**界面文案**必须与 ARB 里的那一个键**同源**。
///
/// ## 这一族是怎么来的
/// 2026-10-03 的 `2befab9` 把更多页那个入口改名「设备状态」→「设备状态快照」
/// （ARB 键 `deviceStatusEntry`，两边同时改，所以**编译期与 widget 测试都发现不了**），
/// 而 `release_walkthrough_test.dart` 里**两处**写死的字面量没跟着改。
/// 后果是闸门 3/4 的 5.14 当场红在「更多页里找不到入口『设备状态』」——
/// 而**闸门自己的措辞把真相说反了**（读起来像页面改坏了，真相是定位是旧的）。
/// 这一族直到跑模拟器才现形：App 全量测试里没有一条会去点那个入口。
///
/// ## 为什么守卫要读 ARB 而不是 import l10n
/// 判据得在**没有 pump 出 widget** 的环境里也能问出"现在叫什么"，
/// 所以直接读 `app_zh.arb`。⚠ 两侧**必须**读同一份文件：闸门运行时按当前 locale 取值，
/// 守卫钉中文那份（闸门里写的也是中文）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = projectRoot();

  String arpValue(String key) {
    final raw =
        jsonDecode(File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync())
            as Map<String, dynamic>;
    final v = raw[key];
    expect(v, isA<String>(), reason: 'ARB 里没有字符串键 $key');
    return v as String;
  }

  test('闸门里那两处「设备状态」定位与 ARB 同源（2befab9 漏了它们两处）', () {
    final label = arpValue('deviceStatusEntry');
    expect(label, '设备状态快照', reason: '本条判据要改：入口改名了（连同下面两处一起改）');

    final gate = File(
      '$root/integration_test/release_walkthrough_test.dart',
    ).readAsStringSync();
    // ⚠ 断的是「**恰好两处**，且都等于现值」，不是「文件里有这个词」——
    //   后者被注释与别处的复述喂成恒绿。计数与取值同时钉。
    final needle = "_openMoreRow(tester, '$label')";
    expect(
      RegExp(RegExp.escape(needle)).allMatches(gate).length,
      1,
      reason: '5.14 点那个入口的那一句不见了或改写了：闸门与页面从此对不上',
    );
    final recordNeedle = "(r) => r.title == '$label'";
    expect(
      RegExp(RegExp.escape(recordNeedle)).allMatches(gate).length,
      1,
      reason:
          '5.14 里「那条通知的 title」那一处不见了或改写了。'
          '⚠ 这两处曾是一起漏的：只补入口定位的话，5.14 会往后跑一段再红在同一节上，'
          '而那一节的标题写着"设备状态"—— 读起来像另一件事，其实是同一处漏改',
    );
    // 反向：闸门里**不许**再留着旧标签的裸字面量（那一处就是它开始腐坏的样子）。
    expect(
      gate,
      isNot(contains("_openMoreRow(tester, '设备状态')")),
      reason: '旧标签没被完全换掉：精确匹配下它是找不到的，红在"找不到入口"',
    );

    // ⚠⚠ 元守卫那三处**也要一起换** —— 这一条才是本文件存在的理由：
    //   第一次只改闸门那两处时，App 全量立刻又红在 `release_gate_emulator_test`
    //   的两条上（"更多页入口「设备状态」不再被点击 ⇒ 覆盖面缩水"）。
    //   那一族断的是**闸门自身有没有被静默削弱**，它靠字面量认入口名 ——
    //   所以改 UI 文案会连带改掉它的主语。三处一起钉，下次改名只红这一条。
    final meta = File(
      '$root/test/architecture/release_gate_emulator_test.dart',
    ).readAsStringSync();
    for (final needle in [
      "'$label',",
      "_openMoreRow\\\\(tester, '$label'\\\\)",
      "r.title == '$label'",
    ]) {
      expect(
        meta,
        contains(needle),
        reason:
            '元守卫那一族没跟上（缺 "$needle"）。⚠ 它断的是「闸门有没有被静默削弱」，'
            '认入口靠字面量 ⇒ UI 改名时不改它，闸门会以"覆盖面缩水"的名义喊，'
            '而真相是它自己过期了',
      );
    }
    expect(meta, isNot(contains("'设备状态',")), reason: '元守卫里还留着旧标签的裸字面量');
  });
}
