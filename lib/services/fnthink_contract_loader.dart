import 'package:flutter/services.dart' show rootBundle;
import 'package:fnthink_push/fnthink_push.dart';

/// 随包的协议契约在 asset bundle 里的键。
///
/// ⚠ 这个串必须与 `pubspec.yaml` 的 `assets:` 里那一行**逐字相同** —— 少了那行，表现是设备上
/// "Unable to load asset"，而桌面测试永远看不到（测试里要么直接读仓库文件，要么注入假读数）。
/// 由 `test/services/fnthink_contract_loader_test.dart` 钉住。
const String fnthinkContractAssetKey = 'protocol/fnthink-v1.json';

/// 契约不可用：读不到 / 不是合法 JSON / 这一包解释不了 / 这张表自己不自洽。
///
/// 这是**唯一**允许从这一层抛出的失败。调用方（收货、发送、配对）拿不到契约就必须整体停手，
/// 不许"先用一半能读到的数"下去 —— 那等于两端各算一份事实，而分歧静默生效。
class FnthinkContractUnavailable implements Exception {
  const FnthinkContractUnavailable(this.reason);

  final String reason;

  @override
  String toString() => '幻念推送的协议契约不可用：$reason';
}

/// 从随包资源里读那份契约（App 侧唯一的契约入口）。
///
/// 为什么不让 `FnthinkContract.readFile()` 直接上机：它按"从 cwd 逐级向上找
/// `protocol/fnthink-v1.json`"定位，那是**仓库**的形状；Android 上应用沙箱里没有仓库根，
/// 那条路径会以"读不到文件"收场（而它的错误长得像部署问题，不像代码问题）。
class FnthinkContractLoader {
  FnthinkContractLoader({Future<String> Function(String key)? readAsset})
    : _read = readAsset ?? rootBundle.loadString;

  final Future<String> Function(String) _read;

  FnthinkContract? _cached;

  /// 已读到的那份（没读过就是 null）。页面在初始化时想知道"契约到底可用不可用"而不触发一次 IO。
  FnthinkContract? get cached => _cached;

  /// [refresh] = 强制重读（换机恢复、或运维改过包内契约的自检路径）。
  Future<FnthinkContract> load({bool refresh = false}) async {
    final cached = _cached;
    if (cached != null && !refresh) return cached;

    final String source;
    try {
      source = await _read(fnthinkContractAssetKey);
    } catch (e) {
      throw FnthinkContractUnavailable(
        '随包资源里没有 $fnthinkContractAssetKey（检查 pubspec.yaml 的 assets 那一行）：$e',
      );
    }

    final FnthinkContract contract;
    try {
      contract = FnthinkContract.parse(source);
    } on FormatException catch (e) {
      throw FnthinkContractUnavailable('契约不是合法 JSON：${e.message}');
    } catch (e) {
      // 顶层是数组/字符串这类"合法 JSON 但不是那张表"：parse 里的类型转换会抛，
      // 一律收成同一种失败 —— 调用方只需要知道"契约不可用"，不需要按异常种类分支。
      throw FnthinkContractUnavailable('契约的顶层形状不对（要一个 JSON 对象）：$e');
    }

    // 这道闸与下面的 validate **今天是重叠的**（validate 的第一条就是 `unsupportedReason() == null`），
    // 所以把这里摘掉不会让任何用例变红 —— 摘掉之后失败仍然发生，只是原因变成笼统的"表不自洽"。
    // 留着它有两层用处：① 报出来的是"本包只实现到 v1"这种可操作的句子，而不是抄了一整条 validate 结果；
    // ② 协议真升 v2 时，这一行是明确要动的地方，而"藏在 validate 里的那条"不是。
    // ⚠ 它可观察的那一半在测试里：用例断的是 reason **只**含版本那句、不含"不自洽"。
    final unsupported = contract.unsupportedReason();
    if (unsupported != null) throw FnthinkContractUnavailable(unsupported);

    final problems = contract.validate();
    if (problems.isNotEmpty) {
      // 只点名第一条：整表贴进日志会把这份表里所有数字都抄进日志（而日志会离开这台机）。
      throw FnthinkContractUnavailable(
        '契约表不自洽（${problems.length} 条），第一条：${problems.first}',
      );
    }
    _cached = contract;
    return contract;
  }

  void clear() => _cached = null;
}
