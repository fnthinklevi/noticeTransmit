import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import 'engine_rule_codec.dart';
import 'engine_rule_diff.dart';
import 'platform_channel.dart';

/// 通知引擎规则（电量族 / 温度族）的读写咽喉（T20）。
///
/// 存储分工 —— 一句话：**DB 是准的，prefs 是原生还在读的那份镜像**。
/// - `engine_rules` 表：唯一可信来源。备份恢复、界面显示、将来切主路径（T21）都读它；
/// - prefs 旧键 `flutter.<族>_rules`：**兼容镜像**。原生 `BatteryMonitor` 在 T21/T22
///   切过去之前仍然只读它（原生侧没有 SQLCipher 依赖，打不开加密库）；它同时是
///   "旧键只读回退"那一份回退 —— DB 打不开时规则至少还在；
/// - 原生方法 `setBatteryRules` / `setTemperatureRules`（T20 已删）以前会把**同一把键**
///   按自己那套默认值再写一遍，两处写同一个键迟早漂出一个"永远不触发"的规则。
///   现在镜像只有 Dart 这一个写入者，原生侧只读。
///
/// 写入顺序固定为 **DB → 镜像 → 通知原生重载**；T21 起在每次读写之后还做一次
/// **影子比对**（DB 那份规则 vs 镜像那份），不一致就记进 [EngineRuleDiffLog] ——
/// 只记账，不改行为、不改返回值（理由见该文件开头）。
class EngineRuleRepository {
  EngineRuleRepository({
    required this.family,
    required this.prefsKey,
    EngineRuleStore? store,
    MethodChannel? channel,
    EngineRuleDiffLog? diffLog,
  }) : _store = store ?? DatabaseHelper(),
       _channel = channel ?? AppChannels.notification,
       _diffs = diffLog ?? EngineRuleDiffLog();

  /// `battery` / `temperature`（[EngineRuleCodec.familyBattery] 等常量）
  final String family;

  /// 旧键名（不含 SharedPreferences 插件加的 `flutter.` 前缀）。
  /// ⚠ 必须与原生 `ConfigManager.KEY_BATTERY_RULES` / `KEY_TEMPERATURE_RULES` 的键名
  ///   逐字一致 —— 不一致时原生永远读到 `"[]"`：用户规则在界面上好好的，告警再也不来，
  ///   且没有任何报错。跨语言守卫见 `test/architecture/engine_rule_storage_test.dart`。
  final String prefsKey;

  final EngineRuleStore _store;
  final MethodChannel _channel;
  final EngineRuleDiffLog _diffs;

  /// 影子比对（T21）：**只记账**。不改返回值、不改写入顺序、不改任何判定 ——
  /// 它是探针，不是链路的一环，所以它自己出错也只打日志，绝不让规则读写跟着失败。
  Future<void> _shadowCheck(
    SharedPreferences prefs,
    List<Map<String, dynamic>> dbRows,
  ) async {
    try {
      final raw = prefs.getString(prefsKey);
      final diffs = compareEngineRuleSets(
        family: family,
        db: dbRows,
        mirrorRaw: raw,
        mirror: EngineRuleCodec.parseLegacyJson(raw, family),
        at: DateTime.now().millisecondsSinceEpoch,
      );
      if (diffs.isEmpty) return;
      await _diffs.record(diffs);
      // 同时走 debugPrint：T22 在设备上跑自检时，日志与环两份都能看。
      debugPrint(
        'EngineRuleRepository($family): 影子差异 ${diffs.length} 条 → $diffs',
      );
    } catch (e) {
      debugPrint('EngineRuleRepository($family): 影子比对失败（不影响规则读写）: $e');
    }
  }

  /// 读规则。[seed] 只在**这台设备从没配过该族规则**时用来播种默认值。
  ///
  /// 判据是"旧键不存在"而不是"表里没行"：用户把默认规则删空之后表也是空的，
  /// 按后者播种等于每次开机复活一遍刚删掉的规则。
  Future<List<Map<String, dynamic>>> load({
    List<Map<String, dynamic>> Function()? seed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = EngineRuleCodec.parseLegacyJson(
      prefs.getString(prefsKey),
      family,
    );

    List<Map<String, dynamic>>? rows;
    try {
      rows = await _store.getEngineRules(family);
    } catch (e) {
      // DB 打不开：旧键是唯一还能拿到用户规则的地方。**只读**，不写任何东西 ——
      // 此刻写库必然失败，写镜像又可能把"其实还没迁进库"的规则洗成空的。
      debugPrint('EngineRuleRepository($family): 读库失败，退回旧键: $e');
      return legacy ?? const [];
    }

    if (rows.isEmpty && legacy != null && legacy.isNotEmpty) {
      // 建表时那次一次性导入没跑成（旧明文库→加密库那条路径、或导入时 prefs 读失败）。
      // 这里补一次，等于把迁移重放；不补就是"升级后规则凭空消失"。
      // 残余风险：删掉最后一条规则时若镜像写失败，这里会把刚删的那条读回来 ——
      // 两害相权：复活一条规则可见、可再删；丢一族的规则无声无息。
      debugPrint('EngineRuleRepository($family): 旧键有规则而库里没有，补导入');
      // 先记账再补导入：这条"库是空的而原生还在按旧键推"正是 T22 要看见的事件。
      await _shadowCheck(prefs, rows);
      try {
        await save(legacy);
      } catch (e) {
        // 补导入失败也要把规则交给界面（save 内部已退化成"只写镜像"）；
        // 让 load 抛出等于用户打开设置页看到一片空白。
        debugPrint('EngineRuleRepository($family): 补导入未成功，按旧键显示: $e');
      }
      return legacy;
    }

    var current = rows;
    if (current.isEmpty && legacy == null && seed != null) {
      // 从没配过 = 走一次正常保存（入库 + 刷镜像 + 通知原生）。不通知的话，新装设备
      // 上那五条出厂电量规则要等到下一次配置变更广播才生效。
      current = EngineRuleCodec.normalizeAll(seed(), family);
      await save(current);
      return current;
    }

    await _shadowCheck(prefs, current);
    await _repairMirror(prefs, current);
    await _notifyNative();
    return current;
  }

  /// 整族保存：写库 → 写镜像 → 让原生重载；影子比对读的是**写完之后的镜像**
  /// （T21）—— 它抓的正是"以为写成了、其实没落/落成了别的形状"这类静默分叉。
  Future<void> save(List<Map<String, dynamic>> rules) async {
    final normalized = EngineRuleCodec.normalizeAll(rules, family);
    final prefs = await SharedPreferences.getInstance();
    try {
      await _store.saveEngineRules(family, normalized);
    } catch (e) {
      // 库写不进去时**仍然写镜像**：这台设备的 DB 已经不可信， prefs 是用户的编辑
      // 唯一的活路（重启后 load() 走回退分支照样读得回来）。
      debugPrint('EngineRuleRepository($family): 规则入库失败，退回只写镜像: $e');
      await _writeMirror(prefs, normalized);
      await _shadowCheck(prefs, normalized);
      await _notifyNative();
      rethrow;
    }
    await _writeMirror(prefs, normalized);
    await _shadowCheck(prefs, normalized);
    await _notifyNative();
  }

  /// 镜像与 DB 不一致时按 DB 修一次（一致时连磁盘都不碰）。
  Future<void> _repairMirror(
    SharedPreferences prefs,
    List<Map<String, dynamic>> rows,
  ) async {
    final wanted = EngineRuleCodec.toLegacyJson(rows);
    if (prefs.getString(prefsKey) == wanted) return;
    await prefs.setString(prefsKey, wanted);
  }

  Future<void> _writeMirror(
    SharedPreferences prefs,
    List<Map<String, dynamic>> rows,
  ) async {
    await prefs.setString(prefsKey, EngineRuleCodec.toLegacyJson(rows));
  }

  /// 让监听服务重跑一次 `loadConfig()`（原生侧唯一的规则刷新入口）。
  ///
  /// 以前这一步是搭在 `setBatteryRules` 那次镜像写上的 —— 镜像写删掉后，
  /// "配置变了"这个信号必须另有一处发，否则改完规则要等服务重启才生效
  /// （= 用户改了阈值，下一次电量跨界还是按旧值推）。
  /// 失败只是本轮没通知到，规则本身已经落库落镜像，下次启动会重新加载。
  Future<void> _notifyNative() async {
    try {
      await _channel.invokeMethod('refreshEngineRules');
    } catch (e) {
      debugPrint('EngineRuleRepository($family): 通知原生重载失败: $e');
    }
  }
}
