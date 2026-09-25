import 'package:notice_transmit/database/database_helper.dart';

/// 内存版引擎规则存储（T20）。
///
/// 为什么要有：`BatteryService` / `TemperatureService` 从 T20 起读写 `engine_rules` 表。
/// 页测试要钉的是"服务变了 → 界面跟上"，不该顺带依赖 sqflite ffi；不注伪的话它们会走
/// [EngineRuleRepository] 的"库打不开 → 只读回退"分支，看着绿，其实测的是降级路径。
///
/// SQL 层的行为（整族替换、position 顺序、类型落库）在
/// `test/database/engine_rules_schema_test.dart` 里用**真库**验，这里一律不重复。
class MemoryRuleStore implements EngineRuleStore {
  final Map<String, List<Map<String, dynamic>>> rows = {};

  /// 各族被写过几次（钉"保存确实落到存储"，而不只是内存列表换了个引用）。
  final List<String> saveLog = [];

  @override
  Future<List<Map<String, dynamic>>> getEngineRules(String family) async =>
      (rows[family] ?? const []).map(Map<String, dynamic>.from).toList();

  @override
  Future<void> saveEngineRules(
    String family,
    List<Map<String, dynamic>> rules,
  ) async {
    saveLog.add(family);
    rows[family] = rules.map(Map<String, dynamic>.from).toList();
  }
}
