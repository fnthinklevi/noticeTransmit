import 'package:fnthink_push/fnthink_push.dart';

/// L2 应用动作的**设备侧枚举映射**（T50）。
///
/// 与 `server/lib/fnthink/l2actions.js` 是同一套动作的**两份实现**，动作词表的唯一出处是
/// 契约 `capabilities.l2.actions`。两端各写一份映射是刻意的 —— 它们各自调用本地的能力
/// （Dart 侧调 MethodChannel / ChannelHealthStore，Node 侧调自己的执行器），
/// **但"哪几个动作算数"必须同源**：一份名单存在两处时两处各自都对，
/// 而对面新加一个动作只有自己认得，表现是服务端把它收进队列、设备端在 apply 段
/// 判成 unknown-action，两头日志互相看不懂。
///
/// 所以这一层只做三件事，且全是纯函数：
///  ① 把 `item` 拆成（动作, 参数）；
///  ② 认不出的动作一律拒（契约 `capabilities.l2.unknownAction: reject`），
///     **不静默跳过** —— 跳过等于让对端用一个编出来的动作名试探这台设备的边界；
///  ③ 那些契约点名要参数的动作，参数缺了就是缺（不回退到"第一条"，
///     那是一条静默的越权）。
///
/// 执行本身（真正去启停监听、翻开关、推一次设备状态）**不在这里**：
/// 那是 [FnthinkL2Executor] 那一层的事，那里才碰 MethodChannel 与 DB。
class FnthinkL2Action {
  const FnthinkL2Action(this.name, this.argument);

  /// 契约词表里的那一个（如 `channel:toggle`）。
  final String name;

  /// 参数（`channel:toggle` 才有；其余为空串）。**不是"目标 id"的别名** ——
  /// 它就是载荷里签过名的那个参数，调用方不许自己拼。
  final String argument;

  @override
  String toString() => argument.isEmpty ? name : '$name($argument)';

  // ⚠ 这三个是**必需**的，不是可选的：测试里写 `expect(parseL2Item(...), const FnthinkL2Ok(...))`
  // 走的是 `==`。没有它，两侧 `toString()` 逐字相同而 `expect` 仍判不等 ——
  // 表现是"期望与实际打印一模一样却红"，读起来像断言写错了。
  @override
  bool operator ==(Object other) =>
      other is FnthinkL2Action &&
      other.name == name &&
      other.argument == argument;

  @override
  int get hashCode => Object.hash(name, argument);
}

/// 一个 L2 动作的解析结果。`reason` 只进日志与留痕，不改变对外形状。
sealed class FnthinkL2Parse {
  const FnthinkL2Parse();
}

class FnthinkL2Ok extends FnthinkL2Parse {
  const FnthinkL2Ok(this.action);

  final FnthinkL2Action action;

  @override
  String toString() => 'FnthinkL2Ok($action)';

  @override
  bool operator ==(Object other) =>
      other is FnthinkL2Ok && other.action == action;

  @override
  int get hashCode => action.hashCode;
}

class FnthinkL2Rejected extends FnthinkL2Parse {
  const FnthinkL2Rejected(this.reason);

  final String reason;

  @override
  String toString() => 'FnthinkL2Rejected($reason)';

  @override
  bool operator ==(Object other) =>
      other is FnthinkL2Rejected && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// 把载荷里那个 `item` 读成动作。纯函数：只读契约，不碰系统。
///
/// [item] 的形状是 `<family>:<verb>`（契约 `capabilities.l2.itemFormat`），
/// 契约点名要参数的动作写成 `<family>:<verb>/<参数>`。
///
/// 四种拒的理由各不相同，**不许合并**：合并之后界面只能说"这条不行"，
/// 而用户看到的是一个点了没反应的按钮 —— 与"没有权限"读起来一模一样，
/// 正是 T27/T28 那条「预授权失败只有一句话」在 L2 上的复刻。
FnthinkL2Parse parseL2Item(
  FnthinkContract contract,
  String? item, {
  String Function(String name)? onUnknown,
}) {
  if (item == null || item.isEmpty) {
    return const FnthinkL2Rejected('missing-item');
  }
  final head = item.split('/');
  final name = head.first;
  if (!contract.l2Actions.contains(name)) {
    return FnthinkL2Rejected(onUnknown?.call(name) ?? 'unknown-action:$name');
  }
  final argument = head.length > 1 ? head.sublist(1).join('/') : '';
  // 契约点名要参数而没给：拒。**不取第一条** —— 那等于替用户猜一个目标，
  // 而这条消息的签名者从未说过他要动哪一条。
  if (contract.l2ActionsRequiringArgument.contains(name) && argument.isEmpty) {
    return FnthinkL2Rejected('missing-argument:$name');
  }
  return FnthinkL2Ok(FnthinkL2Action(name, argument));
}

/// 执行一个 L2 动作的结果。
///
/// [reason] 与 [FnthinkL2Rejected.reason] 是**两件事**：前者是"设备上做这一步失败了"
/// （通道不存在、系统拒绝、没装那款应用），后者是"这条消息根本不该被执行"。
/// 对外都只回契约那一个回执词（`capabilities.l2.actionReceipt`）——
/// 身份已证明，不许把两种失败压成同形的一句话；但**本地细节不许写进对外形状**，
/// 那些要进留痕（T53）。
class FnthinkL2Result {
  const FnthinkL2Result.ok() : reason = null;
  const FnthinkL2Result.failed(this.reason);

  /// 对外回执词：成功走正常投递流程，失败走 [FnthinkL2Result.receipt]。
  final String? reason;

  bool get ok => reason == null;

  /// 这一次执行对外应当回哪一个回执词。
  String receipt(FnthinkContract contract) =>
      ok ? 'delivered' : contract.l2ActionReceipt;
}

/// 设备侧执行 L2 动作的那一层（真正碰系统的那一半）。
///
/// 拆成接口是为了让 [parseL2Item] 与执行分开可测：**解析是纯函数，一行系统调用都没有**，
/// 而执行要 MethodChannel 与 DB，两者混在一个类里就会连"这个词认不认得"都测不了。
abstract class FnthinkL2Executor {
  /// 启停整个通知监听服务（无参数）。
  Future<FnthinkL2Result> setListener({required bool enabled});

  /// 翻某一��通道的开关（参数是通道标识）。
  Future<FnthinkL2Result> toggleChannel(String channelId);

  /// 立刻推一次设备状态（无参数）。
  Future<FnthinkL2Result> pushDeviceState();
}

/// 契约词表里那四个动作，与 [FnthinkL2Executor] 的三个方法一一对应。
///
/// **这张对照表是守卫的对象**：契约加了一个动作而这里没加 ⇒ [FnthinkL2Dispatch] 判红；
/// 反过来这里加了而契约没有 ⇒ 同样判红。两边各长一个而没人发现的表现是
/// 「对端能发一个这台设备做不了的动作」，而设备端把它记成执行失败（failed_action）
/// 而不是"不认得" —— 后者会让人以为是自己没配好。
const Map<String, String> kFnthinkL2ActionVerbs = {
  'listener:start': 'setListener',
  'listener:stop': 'setListener',
  'channel:toggle': 'toggleChannel',
  'device_state:push': 'pushDeviceState',
};

/// 把一个已解析的动作派到执行器上。纯转发，但**这里是唯一一处** action 名 → 方法的映射。
///
/// 返回值分三种：执行成功、执行失败、以及**这个执行器不会做这个动作**
/// （[FnthinkL2Executor] 的实现与 [kFnthinkL2ActionVerbs] 不同步时）。
/// 最后一种必须与"做失败了"分开：它不是这台设备的问题，是这份代码与契约脱节了。
Future<FnthinkL2Result> dispatchL2Action(
  FnthinkContract contract,
  FnthinkL2Executor executor,
  FnthinkL2Action action,
) async {
  switch (action.name) {
    case 'listener:start':
      return executor.setListener(enabled: true);
    case 'listener:stop':
      return executor.setListener(enabled: false);
    case 'channel:toggle':
      return executor.toggleChannel(action.argument);
    case 'device_state:push':
      return executor.pushDeviceState();
    default:
      // 走到这里说明 [parseL2Item] 与本函数对同一张表的读法不一致 ——
      // 两者都在同一份契约上，却给出了不同的答案。
      return FnthinkL2Result.failed('unmapped-action:${action.name}');
  }
}

/// 契约词表与设备侧映射是否同步。守卫用例调它，改契约时红的就是这一条。
bool l2ActionsCoveredByDevice(FnthinkContract contract) {
  final contractActions = contract.l2Actions.toSet();
  return contractActions.length == kFnthinkL2ActionVerbs.length &&
      contractActions.every(kFnthinkL2ActionVerbs.containsKey);
}
