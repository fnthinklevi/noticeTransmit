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

  /// 翻某一条通道的启用状态（[target] 指明哪一条、要设成哪一档）。
  ///
  /// ⚠ 参数**不是**一个裸 id：见 [parseChannelTarget] 顶上那段（族 / id / 目标值三段）。
  /// 这一层收一个已经拆好的 [RemoteChannelTarget] 而不是字符串，是为了让
  /// 「参数成不成形」这个判据只发生在**一个地方**（收件判定那一格）——
  /// 执行层再拆一次的话，两处对同一个字符串的理解可能不同，
  /// 而表现是"收的时候说参数没问题、动手的时候才发现动不了"。
  Future<FnthinkL2Result> toggleChannel(RemoteChannelTarget target);

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
      // ⚠ 拆不出 [RemoteChannelTarget] 就是「参数不成形」—— 收件那一格应当已经拒过，
      //   走到这里说明那两处对同一个字符串的理解不一致（收件那格漏了，或参数被换过）。
      //   记成 `failed` 而不是抛：那正是"这份代码与判据脱节了"，要让留痕看得见。
      final target = parseChannelTarget(action.argument);
      if (target == null) {
        return FnthinkL2Result.failed(
          'bad-channel-argument:${action.argument}',
        );
      }
      return executor.toggleChannel(target);
    case 'device_state:push':
      return executor.pushDeviceState();
    default:
      // 走到这里说明 [parseL2Item] 与本函数对同一张表的读法不一致 ——
      // 两者都在同一份契约上，却给出了不同的答案。
      return FnthinkL2Result.failed('unmapped-action:${action.name}');
  }
}

/// `channel:toggle` 的参数解析（远程执行 片3c-2）。
///
/// ## 参数形状：`<family>:<id>:<on|off>`
///
/// ⚠ **三段都必填，缺一段就拒**。这不是格式洁癖，是重投的直接后果：
/// 契约 `delivery` 的投递语义是 at-least-once（ack 没送到 ⇒ 服务端重投），
/// 而"翻"（toggle）**不可重现** —— 翻一次开、翻两次回原状。
/// 对面看到的现象是"我下了两次指令，通道回到了原来的样子"，
/// 而本机留痕里两条都记成 done，没有任何异常可查。
/// 所以这一项**只允许"设成某一档"**：`…:off` 重投多少次都是关着的。
///
/// ⚠ **第三段是目标值，不是"翻"** —— 与 `listener:start` / `listener:stop` 的关系：
/// 那两个是**两个动作词**（天然幂等），这一个只有一个词（`channel:toggle`），
/// 所以目标值只能由参数带。契约 `l2.actions` 仍是四个词、不许加 `channel:enable`：
/// 加词会让两端的动作词表与 `kFnthinkL2ActionVerbs` 那张对照表一起变，
/// 而收益只是少写三个字符。
///
/// ⚠ **family 段必填**（不能只给 id）：三族的 id **允许重复**
/// （健康缓存按 `family:id` 存就是这个前提），
/// 所以"按 id 在三族里找第一个"是不确定的 —— 同一条指令两次执行可能命中不同族。
/// `family` 的合法值就是本机**可远程启停的那三族**，与 [updateChannelRole] / [updateChannelEnabled]
/// 的 switch 分支同源。⚠ 显示用的族表（`channel_display.dart` 的 `_familyNames`）现在**多一族**
/// （幻念，T104 片③ 起出现在首页与通道状态页）：要开放远程启停得同时给两条 switch 加分支，
/// 那是扩大"对面能动我这台的范围"，不是一次显示改动顺带做的事。
///
/// ⚠ **拆不出来就回 null，不猜**：这一层在**进延时窗口之前**跑（判定层那一格），
/// 而"猜一个族"等于凭空替这条指令选一个要动的东西。
RemoteChannelTarget? parseChannelTarget(String? argument) {
  if (argument == null || argument.isEmpty) return null;
  final parts = argument.split(':');
  // ⚠ 用 `length != 3` 而不是 `parts.length < 3`：多一段也要拒 ——
  //   `<family>:<id>:<on|off>:<多余>` 静默取前三段的话，对面拼错一个字符就变成另一条指令。
  if (parts.length != 3) return null;
  final (family, id, wanted) = (parts[0], parts[1], parts[2]);
  if (family.isEmpty || id.isEmpty) return null;
  // ⚠ 只认这两个词，不做 `startsWith('o')` 之类的宽容归一：
  //   宽容会把拼错的参数变成一次真实的启停，而重投会把它再启停一次。
  final bool? enabled = switch (wanted) {
    'on' => true,
    'off' => false,
    _ => null,
  };
  if (enabled == null) return null;
  if (!isKnownChannelFamily(family)) return null;
  return RemoteChannelTarget(family: family, id: id, enabled: enabled);
}

/// 这里**只管远程启停**这一档的三族（`webhook` / `app` / `email`）。
///
/// ⚠ **这里列的是"可写的族"里的第三份**：另两份在 [updateChannelRole] 与
/// [updateChannelEnabled] 的 switch 分支。加一族要三处一起改；只改这份的表现是
/// 「这一族能配能显示，就是远程启停不认识它，界面上还没有提示」。
/// ⚠ 显示那一张表（`channel_display.dart` 的 `_familyNames`）比这里多一族（幻念）：
/// 那是 T104 片③ 的**显示**改动。⚠ **别把这一档与"主备"混着读** —— 主备那一档从 T113 起
/// 四族都能改（幻念走只改角色的 `FnthinkChannelService.setRole`，不重验目标），
/// 而这一族的**启停**仍只有那三族：幻念的启停只有 `save()` 一条路，会连带重验目标，
/// 形状与"设一个布尔"不是一件事。要在这里加一个词，先决定的是那条形状，不是这里。
bool isKnownChannelFamily(String family) =>
    family == 'webhook' || family == 'app' || family == 'email';

/// 拆出来的那条通道 + 它该被设成哪一档。
class RemoteChannelTarget {
  const RemoteChannelTarget({
    required this.family,
    required this.id,
    required this.enabled,
  });

  final String family;
  final String id;

  /// 目标值（不是"翻"）：见 [parseChannelTarget] 顶上那段。
  final bool enabled;

  @override
  String toString() => 'RemoteChannelTarget($family/$id ⇒ $enabled)';
}

/// 这条指令的参数能不能走 `channel:toggle`（判定层那一格的前置判据）。
///
/// ⚠ 判据在**进延时窗口之前**跑：参数不成形就别让它占掉那 10 秒、再发一条
/// `executing` 回执（对面会以为它在排队），最后才失败。
/// ⚠ 这不是「参数非空」那条的重复：`parseL2Item` 只判非空，
/// 而**三段齐全**是本机这一层的形状要求（协议里没有约定参数长什么样）。
String? rejectChannelTarget(String? argument) {
  if (parseChannelTarget(argument) == null) {
    return 'bad-channel-argument:${argument ?? ''}';
  }
  return null;
}

/// 契约词表与设备侧映射是否同步。守卫用例调它，改契约时红的就是这一条。
bool l2ActionsCoveredByDevice(FnthinkContract contract) {
  final contractActions = contract.l2Actions.toSet();
  return contractActions.length == kFnthinkL2ActionVerbs.length &&
      contractActions.every(kFnthinkL2ActionVerbs.containsKey);
}
