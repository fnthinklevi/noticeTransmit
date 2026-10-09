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
  const FnthinkL2Result.ok({this.payload}) : reason = null;
  const FnthinkL2Result.failed(this.reason) : payload = null;

  /// 对外回执词：成功走正常投递流程，失败走 [FnthinkL2Result.receipt]。
  final String? reason;

  /// 这一发产出、要**回传**给发起方的东西（T124 片B；`notifications:report` 那一类）。
  ///
  /// ⚠ 它不是"执行结果的可选说明"（那是 [reason]）：回传是**协议行为** ——
  /// 有 payload 的动作，把那条消息发出去是执行的一部分（发不出去这一步就没成），
  /// 而 [reason] 只进本机留痕。**谁发、发给谁由执行链决定**（runner 知道发起方），
  /// 执行器连"发起方是谁"都看不到 —— 所以 payload 只能从这一层带出来。
  final String? payload;

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

  /// 让这台响起（响铃＋震动＋高优先横幅一条，T124 片B 的 `alert:ring`；无参数）。
  ///
  /// ⚠ 它是**瞬时动作**：重投一次就会再响一次（与"翻开关"不同，重投不会留下错误状态，
  /// 那一次响是投递重试的可见代价）。产出为空（不是回传那一条）。
  Future<FnthinkL2Result> ringAlert();

  /// 在本机短信里按 [keyword] 搜，并把命中的那几条**回传**给发起方（T124 片B 的 `sms:search`）。
  ///
  /// 回 `(payload: 正文, reason: null)` = 这一步成了；`payload: null, reason: ...` = 没成
  /// （`sms-search-disabled` 开关关着 / `sms-search-refused` 没权限被拒 / `sms-search-failed` 读不出来）。
  /// ⚠ 与 [reportNotifications] 的一处不同值得留意：那一个的"没成"只有一种（读不出来），
  /// 这一个是三种，而**三种对用户的下一步动作不一样**（去开开关 / 去给权限 / 重试），
  /// 所以它带 reason 而不是一个 null。
  Future<({String? payload, String? reason})> searchSms(String keyword);

  /// 打开本机**登记过**的一条入口（T124 片B 的 `app:launch`）。
  ///
  /// [name] 是用户在本机给那条登记起的名称（对面的界面读不到本机的清单，所以按名字对）。
  /// 回 `ok: true` = 已经把它送到前台；`ok: false` 看 [reason]
  /// （`app-launch-unknown-name` 名称对不上 / `app-launch-refused` 系统拦了 / `app-launch-failed`）。
  /// ⚠ **名字对不上就是不做**（fail-closed）：猜一条最像的等于替用户开了一个他没点的东西。
  Future<({bool ok, String? reason})> launchApp(String name);

  /// 在本机通话记录里按 [keyword] 搜，并把命中的那几条**回传**给发起方
  /// （T124 片C 的 `calls:search`；与 [searchSms] 同一形状，门不同）。
  ///
  /// 回 `(payload: 正文, reason: null)` = 这一步成了；`payload: null, reason: ...` = 没成
  /// （`calls-search-disabled` 本机的开关关着 / `calls-search-refused` 没权限被拒 /
  /// `calls-search-failed` 读不出来）。⚠ 这一族**多一道本机开关**（默认关）：
  /// 权限是系统那一格，开关是「允不允许对面读这条数据」这一格 —— 两格都要过。
  Future<({String? payload, String? reason})> searchCalls(String keyword);

  /// 读本机**最近一次**定位并回传给发起方（T124 片C 的 `location:get`；无参数）。
  ///
  /// 回 `(payload: 正文, reason: null)` = 这一步成了；`payload: null, reason: ...` = 没成
  /// （`location-disabled` 本机开关关着 / `location-refused` 没权限被拒 /
  /// `location-unavailable` 有权限但没有任何「最近一次」可读 /
  /// `location-failed` 读不出来）。⚠ 与另两条同一纪律：开关关着连系统都不碰。
  Future<({String? payload, String? reason})> getLocation();

  /// 让这台**现在**拍一张照片（T124 片C-3 的 `camera:snap`；无参数）。
  ///
  /// 回 `(payload: 正文, reason: null)` = 这一步成了；`payload: null, reason: ...` = 没成
  /// （`camera-snap-disabled` 本机开关关着 / `camera-snap-refused` 没权限被拒 /
  /// `camera-snap-no-foreground` 这台没有可见界面（Android 11+ 的 while-in-use 规定）/
  /// `camera-snap-failed` 拍/存没成）。⚠ 画面**不回传**（那是图像传输＋收件端渲染，
  /// 另一个子系统）—— 这一发的产出是「拍到了、存在这台哪里」那段文字。
  Future<({String? payload, String? reason})> snapPhoto();

  /// 回传最近的 [count] 条通知原文（`notifications:report`，T124 片B）。
  ///
  /// 回**产出要回传的那段正文**；回 null = 这一步没做成（读库失败、这台没有可回传的东西）。
  /// ⚠ 它是唯一一个"有产出"的 L2 动作：产出由这一层**读出来**，而发去哪儿由执行链决定
  /// （这一层看不到发起方是谁 —— 见 [FnthinkL2Result.payload] 那一格）。
  Future<String?> reportNotifications(int count);
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
  'notifications:report': 'reportNotifications',
  'alert:ring': 'ringAlert',
  'sms:search': 'searchSms',
  'app:launch': 'launchApp',
  'calls:search': 'searchCalls',
  'location:get': 'getLocation',
  'camera:snap': 'snapPhoto',
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
    case 'alert:ring':
      return executor.ringAlert();
    case 'notifications:report':
      final badCount = reportArgumentProblem(
        contract,
        action.name,
        action.argument,
      );
      if (badCount != null) return FnthinkL2Result.failed(badCount);
      final count = int.parse(action.argument.trim());
      final payload = await executor.reportNotifications(count);
      if (payload == null || payload.isEmpty) {
        // 产不出正文 = 这一步没做成（读库失败那一支；"一条都没有"由产出自带一句明说，
        // 不是一个空串 —— 空串与"做成了但什么都没说"在读的人那边分不开）。
        return const FnthinkL2Result.failed('report-failed');
      }
      return FnthinkL2Result.ok(payload: payload);
    case 'sms:search':
      final badKeyword = reportArgumentProblem(
        contract,
        action.name,
        action.argument,
      );
      if (badKeyword != null) return FnthinkL2Result.failed(badKeyword);
      final found = await executor.searchSms(action.argument.trim());
      if (found.reason != null) return FnthinkL2Result.failed(found.reason!);
      final foundPayload = found.payload;
      if (foundPayload == null || foundPayload.isEmpty) {
        return const FnthinkL2Result.failed('sms-search-failed');
      }
      return FnthinkL2Result.ok(payload: foundPayload);
    case 'app:launch':
      final badName = reportArgumentProblem(
        contract,
        action.name,
        action.argument,
      );
      if (badName != null) return FnthinkL2Result.failed(badName);
      final launched = await executor.launchApp(action.argument.trim());
      return launched.ok
          ? const FnthinkL2Result.ok()
          : FnthinkL2Result.failed(launched.reason ?? 'app-launch-failed');
    case 'calls:search':
      // 与 sms:search 逐字同形：参数形状的唯一判据仍是 reportArgumentProblem。
      final badCallKeyword = reportArgumentProblem(
        contract,
        action.name,
        action.argument,
      );
      if (badCallKeyword != null) return FnthinkL2Result.failed(badCallKeyword);
      final foundCalls = await executor.searchCalls(action.argument.trim());
      if (foundCalls.reason != null) {
        return FnthinkL2Result.failed(foundCalls.reason!);
      }
      final callsPayload = foundCalls.payload;
      if (callsPayload == null || callsPayload.isEmpty) {
        return const FnthinkL2Result.failed('calls-search-failed');
      }
      return FnthinkL2Result.ok(payload: callsPayload);
    case 'location:get':
      // 无参数形态（契约 kind=none）：判据同源 —— 带了参数就是带了件没人认的东西。
      final badLocationArg = reportArgumentProblem(
        contract,
        action.name,
        action.argument,
      );
      if (badLocationArg != null) {
        return FnthinkL2Result.failed(badLocationArg);
      }
      final fix = await executor.getLocation();
      if (fix.reason != null) return FnthinkL2Result.failed(fix.reason!);
      final fixPayload = fix.payload;
      if (fixPayload == null || fixPayload.isEmpty) {
        return const FnthinkL2Result.failed('location-failed');
      }
      return FnthinkL2Result.ok(payload: fixPayload);
    case 'camera:snap':
      // 与 location:get 同形：无参数、产出挂在结果上、理由原样带上。
      final badSnapArg = reportArgumentProblem(
        contract,
        action.name,
        action.argument,
      );
      if (badSnapArg != null) return FnthinkL2Result.failed(badSnapArg);
      final snapped = await executor.snapPhoto();
      if (snapped.reason != null)
        return FnthinkL2Result.failed(snapped.reason!);
      final snapPayload = snapped.payload;
      if (snapPayload == null || snapPayload.isEmpty) {
        return const FnthinkL2Result.failed('camera-snap-failed');
      }
      return FnthinkL2Result.ok(payload: snapPayload);
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
/// 可被远程启停的那三族（`webhook` / `app` / `email`）—— **名单在这里，判据也在这里**。
///
/// 为什么是一枚可枚举的常量而不是只留一个 `isKnownChannelFamily`：发送侧那一格要把这三族
/// 画成可点的选项（T124 A 片：参数由界面生成，不让人手敲冒号串）。只留谓词的话，
/// 界面就得自己抄一份名单，而"抄的那份与判的那份不一致"正是这一族反复犯的病。
const List<String> kFnthinkRemoteChannelFamilies = ['webhook', 'app', 'email'];

bool isKnownChannelFamily(String family) =>
    kFnthinkRemoteChannelFamilies.contains(family);

/// 拼 `channel:toggle` 的参数（**发送侧唯一作者**）。
///
/// 形状与理由都在 [parseChannelTarget] 上面那段：三段齐全、第三段是**目标值**而不是"翻"。
/// 这里不校验 id（对面那台的通道号本机无从知道），但族与目标值只可能取自
/// [kFnthinkRemoteChannelFamilies] 与 `on`／`off` —— 拼出来的串必然能被对面拆开。
/// 往返性由用例钉（`parseChannelTarget(buildChannelArgument(…))` 必须还原出同一组值）。
String buildChannelArgument({
  required String family,
  required String id,
  required bool enabled,
}) => '$family:$id:${enabled ? 'on' : 'off'}';

/// 拼 L3 的 item（**发送侧唯一作者**）：带目标值的那一档才幂等。
///
/// `[want] == null` 回裸 key —— 那是老对端的形状，契约仍收（`l3.itemMayCarryTarget` 是
/// "可选"而不是"必填"），但**新界面不该产出它**：重投一次就翻两次、回到原状，
/// 而对面留痕两条都记 done。所以发送侧把目标值做成必选，这一层的 `null` 分支只服务测试。
String buildL3Item({required String key, bool? want}) {
  if (want == null) return key;
  return '$key/${want ? 'on' : 'off'}';
}

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

/// 「要几条」在不在契约闭区间里（收件判定那一格与发送侧界面**共用**这一条）。
///
/// 契约没声明这一项（缺 min/max）⇒ **一律不认**（fail-closed）：没有声明的回传
/// 等于一条没有上界的路，而它把本机的东西往外发。
bool reportCountInRange(FnthinkContract contract, String action, int count) {
  final min = contract.l2ReportMinItems(action);
  final max = contract.l2ReportMaxItems(action);
  if (min == null || max == null) return false;
  return count >= min && count <= max;
}

/// 回传动作的参数有没有问题（**按契约声明的 kind 分派**；回 null = 可以过）。
///
/// ⚠ **唯一的形状作者**：收件那一格（[rejectL2Argument]）与派发那一格都调它 ——
/// 两处各写一份的表现是"收的时候说没问题、动手时才发现动不了"。
/// 两种形态各一条判据，**不许合成一条"长度在 1..32 之间"**：
/// count 是数值区间，keyword 是字符长度与可见性（控制字符会让一句话在对面读起来断成两截）。
String? reportArgumentProblem(
  FnthinkContract contract,
  String action,
  String argument,
) {
  final kind = contract.l2ReportKind(action);
  if (kind == 'count') {
    final count = int.tryParse(argument.trim());
    if (count == null || !reportCountInRange(contract, action, count)) {
      return 'bad-report-count:${argument.trim()}';
    }
    return null;
  }
  if (kind == 'keyword') {
    final keyword = argument.trim();
    final min = contract.l2ReportMinChars(action);
    final max = contract.l2ReportMaxChars(action);
    // 契约没声明上下界 ⇒ 一律不认（fail-closed：没上界的串会被原样带出去）。
    if (min == null || max == null) return 'bad-keyword:${argument.trim()}';
    if (keyword.length < min || keyword.length > max) {
      return 'bad-keyword:${argument.trim()}';
    }
    for (final rune in keyword.runes) {
      if (rune < 0x20 || rune == 0x7F) return 'bad-keyword:${argument.trim()}';
    }
    return null;
  }
  if (kind == 'none') {
    // 无参数形态（T124 片C-2 的 `location:get`）：带了参数就是带了件**没人认**的东西 ——
    // fail-closed，不静默忽略（静默忽略等于把一段签过名的字节当没看见）。
    if (argument.trim().isNotEmpty) return 'unexpected-argument:$action';
    return null;
  }
  // 不在那张表里（或 kind 不认识）：**不认**（fail-closed）—— 这条判据只服务那张表里的动作，
  // 别的动作有自己的参数形状（见 [rejectL2Argument] 里按名分派的那两支）。
  return 'bad-argument-kind:$action';
}

/// 这条动作的参数能不能过（判定层那一格的前置判据，**按动作分派**）。
///
/// 回 null = 这个动作没有额外形状要求（认不认得由 `parseL2Item` 在更早那一格判）。
/// ⚠ 判据在**进延时窗口之前**跑：参数不成形就别让它占掉那 10 秒、再发一条 `executing`
/// 回执（对面会以为它在排队），最后才失败。每一种参数的形状判据各有唯一作者：
/// `channel:toggle` → [rejectChannelTarget]，契约那张表里的动作 → [reportArgumentProblem]。
///
/// ⚠ 只列"参数怎么读"分得最细的几种；两个都没有的动作（`listener:*` 等）回 null。
String? rejectL2Argument(FnthinkContract contract, FnthinkL2Action action) {
  if (action.name == 'channel:toggle') {
    return rejectChannelTarget(action.argument);
  }
  if (contract.l2ReportKind(action.name) != null) {
    return reportArgumentProblem(contract, action.name, action.argument);
  }
  return null;
}

/// 契约词表与设备侧映射是否同步。守卫用例调它，改契约时红的就是这一条。
bool l2ActionsCoveredByDevice(FnthinkContract contract) {
  final contractActions = contract.l2Actions.toSet();
  return contractActions.length == kFnthinkL2ActionVerbs.length &&
      contractActions.every(kFnthinkL2ActionVerbs.containsKey);
}
