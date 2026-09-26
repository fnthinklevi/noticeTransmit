import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/engine_rule_codec.dart';
import 'package:notice_transmit/services/engine_rule_diff.dart';
import 'package:notice_transmit/services/temperature_service.dart';
import 'package:path/path.dart' show basename;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// roadmap T22：**覆盖升级自检**（旧版本预置规则 → 覆盖安装 → 逐项比对）。
///
/// 与闸门里那两个集成测试的区别：它跑之前，设备必须先被脚本造成"旧版本的样子"
/// （见 `tools/t22_overlay_upgrade.sh`）：先装 T20 之前构建的 debug 包并启动一次
/// （于是有了 v12 的库与加密钥），再用 `run-as` 灌进 v12 时代的 prefs 规则，
/// 最后 `adb install -r` 当前 debug 包 —— **同签名所以数据保留**，这才是覆盖安装。
///
/// ⚠ 不能进闸门默认清单：闸门起跑前会 `pm clear`，把刚灌好的旧形状数据清掉；
/// 而且它会改写设备上的库。它是一次性的升级验证，不是每次发版都要跑的回归。
///
/// 钉的是四条，每条都是"升级后用户会觉得设置被改了"的形状：
/// 1. 规则**逐条同序同值**搬进 `engine_rules`（顺序 = 引擎判定优先级）；
/// 2. 原生实际读的那份镜像与库一致（否则界面按 A 判、告警按 B 推）；
/// 3. 两个总开关不得被翻（升级改用户设置是硬禁）；
/// 4. 影子差异环为空（T21 的证据源；形状差异如 `100.0`、缺 `enabled`
///    会被归一化吃掉，所以"空"意味着搬家没有改变任何人的告警行为）。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'T22 覆盖升级：v12 时期的 prefs 规则搬进 v13 表，逐项一致',
    (tester) async {
      // 种子里的三条形状各自对应一种真实历史写法（v12 时代 Dart 直接 jsonEncode，
      // 原生镜像写又各自补默认值）：缺 enabled、Double 阈值、正常条目。
      // 用 equals 而不是 orderedEquals：Map 的 `==` 是同一性比较，逐条深比必须走 matcher。
      // ⚠ 先把镜像原文打出来。真跑时出过"缺 enabled 的那条搬进库成了 false"，那种红
      //   必须先分清是"种子在覆盖前被旧构建回写成显式 false"还是"缺省判据在真库路径上
      //   失效"—— 两者的修法完全不同（前者改脚本，后者是产品缺陷）。
      final prefs0 = await SharedPreferences.getInstance();
      debugPrint('T22 迁移前镜像原文 battery=${prefs0.getString('battery_rules')}');
      debugPrint('T22 迁移前镜像原文 temperature=${prefs0.getString('temperature_rules')}');
      expect(
        await DatabaseHelper().getEngineRules(EngineRuleCodec.familyBattery),
        equals([
          _r('low20', 'level_below', 20, true, '电量低于20%'),
          _r('charging', 'charging', 0, true, '开始充电'),
          _r('full', 'level_above', 100, false, '电量充满'),
        ]),
        reason: '电量族规则搬家后必须逐条同序同值（第 2 条缺 enabled，按缺省算启用）',
      );
      expect(
        await DatabaseHelper().getEngineRules(EngineRuleCodec.familyTemperature),
        equals([
          _r('t1', 'battery_temp_above', 45, true, '电池过热'),
          _r('t2', 'device_temp_above', 60, false, '设备过热'),
        ]),
        reason: '温度族同理；两族各从 0 编号，互不串位',
      );

      // 服务层读出来也必须是同一份（备份恢复、页面显示、引擎判定共用这一份结论）。
      final battery = BatteryService();
      await battery.loadSettings();
      expect(battery.rules, hasLength(3));
      expect(battery.notifyEnabled, isTrue, reason: '总开关被翻了 = 升级改了用户设置');
      final temperature = TemperatureService();
      await temperature.loadSettings();
      expect(temperature.notifyEnabled, isFalse, reason: '同上（温度族关着的要还关着）');

      // 原生读的那份 == 库里那份：两侧都是归一化后的形状，所以这条比"镜像存在"强得多。
      final prefs = await SharedPreferences.getInstance();
      final mirrorBattery = EngineRuleCodec.parseLegacyJson(
        prefs.getString('battery_rules'),
        EngineRuleCodec.familyBattery,
      );
      expect(
        mirrorBattery,
        equals(battery.rules),
        reason: '界面按库判、原生按镜像推 —— 两者不一致就是"改了没生效/没改却响了"',
      );

      final diffs = await EngineRuleDiffLog().read();
      if (diffs.isNotEmpty) {
        debugPrint('T22 影子差异：$diffs');
      }
      expect(diffs, isEmpty, reason: '覆盖升级搬完就有差异 = 搬家搬错了，看上面打印的明细');

      // ⚠ 这条才是"真的走了迁移"而不是"重建空库后被补导入救回来"的判据：
      // `_initDatabase` 打不开库时的兜底是把原文件改名成 `*.corrupt-<ts>` 再建空库，
      // 那种情况下规则也可能完好（T20 的补导入分支会从 prefs 救回来）—— 也就是说
      // 上面所有断言在全库重建的场景下**照样全绿**。留存的 .corrupt 文件戳穿它。
      // （脚本侧本来想用 inode 判，但 `flutter test` 收尾会把应用连数据一起卸载，
      //   跑完之后设备上已经没有了 —— 所以这条必须在进程内看。）
      final dir = Directory((await getDatabasesPath()));
      final names = dir.listSync().map((e) => basename(e.path)).toList();
      debugPrint('T22 databases/ 内容：$names');
      expect(
        names.where((n) => n.contains('.corrupt')),
        isEmpty,
        reason: '有 .corrupt 备份 ⇒ 旧库被打不开、内容是"重建后救回来"的，迁移没被验到',
      );
      expect(
        names,
        contains('notice_transmit_encrypted.db'),
        reason: '锚点：库不在，上一条断言就是空转',
      );
      final version = await DatabaseHelper().database;
      final stamped =
          (await version.rawQuery('PRAGMA user_version')).single.values.first;
      expect(
        stamped,
        DatabaseHelper.dbVersion,
        reason: '库没被贴上当前版本号 = 迁移链没跑完',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Map<String, dynamic> _r(
  String id,
  String type,
  int value,
  bool enabled,
  String title,
) => {
  'id': id,
  'type': type,
  'value': value,
  'enabled': enabled,
  'title': title,
  'content': '',
};
