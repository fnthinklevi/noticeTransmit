import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_rule.dart';

import '../support/source_guards.dart';

/// T186 片1 第②刀的形状守卫：设备态两型条件（`charging_state`／`network_type`）。
///
/// 这一族**没有编译期依赖**跨语言：Dart 的条件串、原生 `RuleEngine` 的 `when` 分支、
/// `NotificationInfo` 的字段名、fixture 里 `notification` 的键名 —— 全是字符串。
/// 任意一端改名，另一端照旧编译通过、测试照旧"看起来对"，然后真机上两端各自转发不同的东西。
/// 所以这里把四件事钉在同一份现读源码上：
///  ① 值域词表两端**逐名**一致（不是数量一致）；
///  ② `RuleEngineTest.info()` 接住了 fixture 里那两枚键 —— 漏一枚就是原生永远读到空串、
///     Dart 读得到，而双端跑的是同一份 fixture（最难发现的假保护）；
///  ③ 求值口径同形，且取数那一处不跨通道；
///  ④ 设备态读数不进持久化副本，但通知链路的构造点真的喂了它。
void main() {
  String read(String rel) => File('${projectRoot()}/$rel').readAsStringSync();

  /// 取 `start` 到 `end` 之间的片段。**两端都验存在**，且末点必须晚于入口 ——
  /// 抽取式守卫最怕的是"尺量到半截签名"或"末点找不到就把整文件当体"（本仓撞过）。
  String slice(String src, String start, String end, String label) {
    final i = src.indexOf(start);
    expect(i, greaterThan(-1), reason: '$label 的入口没了 ⇒ 本条在测空气');
    final j = src.indexOf(end, i);
    expect(j, greaterThan(i), reason: '$label 的末点没找到 ⇒ 尺不可信，不拿整文件充数');
    return src.substring(i, j);
  }

  List<String> tokens(String text, RegExp re, String label) {
    final found = re.allMatches(text).map((m) => m.group(1)!).toList();
    expect(found, isNotEmpty, reason: '$label 一枚都没抽到 ⇒ 抽取正则漂了');
    return found;
  }

  final dartRule = stripComments(read('lib/models/notification_rule.dart'));
  final dartFilter = stripComments(read('lib/services/filter_service.dart'));
  final dartTrace = stripComments(read('lib/services/rule_trace.dart'));
  final dartTester = stripComments(read('lib/pages/rule_tester_page.dart'));
  final kotlinEngine = stripComments(
    read('android/app/src/main/kotlin/com/fnthink/notice/RuleEngine.kt'),
  );
  final kotlinSnapshot = stripComments(
    read('android/app/src/main/kotlin/com/fnthink/notice/DeviceSnapshot.kt'),
  );
  final kotlinService = stripComments(
    read(
      'android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt',
    ),
  );
  final kotlinProcessor = stripComments(
    read(
      'android/app/src/main/kotlin/com/fnthink/notice/NotificationProcessor.kt',
    ),
  );
  final kotlinTest = stripComments(
    read('android/app/src/test/java/com/fnthink/notice/RuleEngineTest.kt'),
  );
  final zhArb = read('lib/l10n/arb/app_zh.arb');
  final enArb = read('lib/l10n/arb/app_en.arb');

  test('① 充电状态值域：Dart 那份清单 == 原生 chargingStateOf 产出的那几档', () {
    final dartList = tokens(
      slice(
        dartRule,
        'const List<String> chargingStateValues',
        '];',
        'Dart chargingStateValues',
      ),
      RegExp("'([a-z_]+)'"),
      'Dart chargingStateValues',
    );
    final nativeList = tokens(
      slice(
        kotlinSnapshot,
        'fun chargingStateOf(status: Int)',
        '\n    }',
        '原生 chargingStateOf',
      ),
      RegExp(r'-> "([a-z_]+)"'),
      '原生 chargingStateOf',
    );
    expect(dartList.toSet(), nativeList.toSet(), reason: '对称差集为空才算一致');
    expect(dartList.length, dartList.toSet().length, reason: 'Dart 侧不许有重复档');
    // 换算只许在原生那一处：Dart 出现系统状态常量就是第二份换算
    expect(
      dartRule.contains('BATTERY_STATUS'),
      isFalse,
      reason: 'Dart 侧出现 BATTERY_STATUS ⇒ 有人在这里重推"是不是在充"',
    );
  });

  test('① 网络值域：Dart 那份清单 == 原生 networkTypeOf 产出的六枚原值', () {
    final dartList = tokens(
      slice(
        dartRule,
        'const List<String> networkTypeValues',
        '];',
        'Dart networkTypeValues',
      ),
      RegExp("'([a-z_]+)'"),
      'Dart networkTypeValues',
    );
    final nativeList = tokens(
      slice(
        kotlinSnapshot,
        'fun networkTypeOf(',
        '\n    }',
        '原生 networkTypeOf',
      ),
      RegExp(r'return "([a-z_]+)"'),
      '原生 networkTypeOf',
    );
    expect(dartList.toSet(), nativeList.toSet());
    expect(
      dartList.length,
      6,
      reason: '这一型刻意采用**六枚原值**：造三档要新定 vpn/ethernet/other 的归属，没人拍过',
    );
  });

  test('② 黄金用例的构造点必须接住两枚设备态键', () {
    final info = slice(
      kotlinTest,
      'private fun info(n: JSONObject)',
      '\n    )',
      'RuleEngineTest.info()',
    );
    expect(info, contains('n.optString("chargingState")'));
    expect(info, contains('n.optString("networkType")'));
    // fixture 里确实用到这两枚键，否则上面两条是在测空气
    final fixture = read('test/fixtures/rule_engine_golden.json');
    expect(fixture, contains('"chargingState"'));
    expect(fixture, contains('"networkType"'));
  });

  test('③ 求值口径同形，且取数那一处不跨通道', () {
    expect(
      kotlinEngine,
      contains(
        '"charging_state" -> info.chargingState.equals(value, ignoreCase = true)',
      ),
    );
    expect(
      kotlinEngine,
      contains(
        '"network_type" -> info.networkType.equals(value, ignoreCase = true)',
      ),
    );
    expect(
      dartFilter,
      contains("_deviceStateOf(notification, 'chargingState')"),
    );
    expect(dartFilter, contains("_deviceStateOf(notification, 'networkType')"));
    final readBody = slice(
      dartFilter,
      'static String _deviceStateOf(',
      '\n  }',
      '_deviceStateOf',
    );
    expect(
      readBody.contains('invokeMethod'),
      isFalse,
      reason: '求值路径里出现通道调用 ⇒ 同步纯函数变成每次求值都跨进程',
    );
  });

  test('③ 追踪链与测试器都把读数带到求值（不是只在页面上显示）', () {
    expect(dartTrace, contains("'chargingState': chargingState"));
    expect(dartTrace, contains("'networkType': networkType"));
    expect(dartTrace, contains('String chargingState ='));
    expect(dartTrace, contains('String networkType ='));
    expect(dartTester, contains('chargingState: _chargingState'));
    expect(dartTester, contains('networkType: _networkType'));
  });

  test('④ 设备态读数不进持久化副本（陈旧读数比"读不到"更容易骗人）', () {
    final header = slice(
      kotlinService,
      'data class NotificationInfo(',
      '\n) {',
      'NotificationInfo 字段表',
    );
    expect(header, contains('val chargingState: String = ""'));
    expect(header, contains('val networkType: String = ""'));
    final toJson = slice(
      kotlinService,
      'fun toJson(): org.json.JSONObject',
      '\n    }',
      'toJson',
    );
    final fromJson = slice(
      kotlinService,
      'fun fromJson(',
      '\n        )',
      'fromJson',
    );
    expect(toJson.contains('chargingState'), isFalse);
    expect(toJson.contains('networkType'), isFalse);
    expect(fromJson.contains('chargingState'), isFalse);
    expect(fromJson.contains('networkType'), isFalse);
  });

  test('⑤ 通知链路的构造点真的喂这两枚，且各自包在 try 里', () {
    final built = slice(
      kotlinProcessor,
      'return NotificationInfo(',
      '\n        )',
      'processNotification 的构造点',
    );
    expect(built, contains('chargingState = try {'));
    expect(built, contains('networkType = try {'));
    expect(
      kotlinProcessor.contains('DeviceSnapshot.readChargingState(context)'),
      isTrue,
    );
    expect(
      kotlinProcessor.contains('DeviceSnapshot.readNetworkType(context)'),
      isTrue,
    );
    // 换算口只有一处：读充电状态的那条路必须走 chargingStateOf，不许自己比常量
    final readState = slice(
      kotlinSnapshot,
      'fun readChargingState(',
      '\n    }',
      'readChargingState',
    );
    expect(readState, contains('chargingStateOf('));
    expect(
      readState.contains('BATTERY_STATUS_CHARGING'),
      isFalse,
      reason: '又一份换算',
    );
  });

  test('⑥ 界面那两句话由词表现取：ARB 里不许再抄一份值域', () {
    for (final arb in [zhArb, enArb]) {
      for (final key in [
        'condChargingState',
        'condNetworkType',
        'hintAllowedValues',
        'testerDeviceStateLine',
        'testerDeviceStateUnavailable',
      ]) {
        expect(arb.contains('"$key"'), isTrue, reason: 'ARB 缺 $key');
      }
      final hint = RegExp('"hintAllowedValues": "([^"]*)"')
          .firstMatch(arb)!
          .group(1)!;
      expect(
        hint,
        contains('{values}'),
        reason: 'hint 必须吃占位符：把 charging/full 写进 ARB 就是第二份值域作者',
      );
      for (final token in [...chargingStateValues, ...networkTypeValues]) {
        expect(hint.contains(token), isFalse, reason: 'ARB 的 hint 里出现了 $token');
      }
    }
  });

  test('⑦ 状态翻转真的进了规则引擎：三条事件源都接到同一个求值入口', () {
    // 求值体必须真的是「翻转 → 规则引擎」：只接了事件、不调 decideDeviceState，
    // 等于配了 charging_state 的规则永远不会响，而界面上一切正常。
    final evaluate = slice(
      kotlinService,
      'private fun runDeviceRuleEvaluation(',
      '\n    }',
      'runDeviceRuleEvaluation',
    );
    expect(
      evaluate,
      contains('RuleEngine.decideDeviceState('),
      reason: '状态触发路径没接规则引擎',
    );
    expect(
      evaluate,
      contains('RuleEngine.isDeviceStateFlip('),
      reason: '没有翻转判据 ⇒ 每次电量/网络回调都推一条',
    );
    // 电池广播是充电翻转唯一可靠的来源（电量/温度告警那套 hasRules 与规则引擎无关）
    final battery = slice(
      kotlinService,
      'private fun startBatteryMonitoring()',
      'private fun scheduleBatteryAlarm()',
      'startBatteryMonitoring',
    );
    expect(
      battery,
      contains('evaluateDeviceStateRules()'),
      reason: '电池广播没接状态规则 ⇒ 充电/拔线这条路径永远不触发',
    );
    final changed = slice(
      kotlinService,
      'private fun onDeviceStateChanged()',
      '\n    }',
      'onDeviceStateChanged',
    );
    expect(
      changed,
      contains('evaluateDeviceStateRules()'),
      reason: '网络/亮度事件源没接状态规则',
    );
    // 配置变更后重新立基准：否则新增规则时会把"此刻在充电"当成一次刚发生的翻转
    final load = slice(
      kotlinService,
      'private fun loadConfig()',
      '\n    }',
      'loadConfig',
    );
    expect(
      load,
      contains('primeDeviceStateRuleBaseline()'),
      reason: '新增规则后不立基准 ⇒ 下一次任意事件凭空推一条',
    );
  });
}
