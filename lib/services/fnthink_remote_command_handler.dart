import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';

import '../models/fnthink_inbox_message.dart';
import 'fnthink_l2_actions.dart';
import 'fnthink_remote_execution.dart';
import 'fnthink_remote_settings.dart';
import 'fnthink_sender_grant.dart';
import 'remote_credential_store.dart';

/// 收到一条收件时判"这是不是一条远程指令"，并把**该不该执行**判完（片3c）。
///
/// ## 这一层只回答两件事，**不执行任何东西**
///  ① 这一条是不是远程指令（`RemoteCommandEnvelope` 拆得出来）；
///  ② 如果是：开关开着没有、来源渠道对不对、凭据对不对、item 在不在那一档的词表里。
/// 执行（MethodChannel）、延时窗口、撤销、两段回执都在**调用方**那一层 —— 这一层不碰它们，
/// 那样第二个读者就长出来了。
///
/// ## 开关关着 ⇒ 回「拒」（维护者 2026-10-12 裁定 1，推翻下面这句旧设计）
/// **原句（留着）**：「开关关着时它必须回 `RemoteCommandNotEnabled` —— 照常显示：那是一条用户
/// 看得见的消息。回"拒"的话指令会被吃掉而不显示、也不执行、还不留痕，而用户唯一看到的现象是
/// "对方说发了，我这儿什么也没有"。」
/// 这句的**前提今天不成立**：拒的那一档现在既留痕（进远程执行历史，终态 `failed` + 理由
/// `switch-off`）又回执（对面那台看得见被拒）。两头都有读数 ⇒ 「吃掉而不显示」不再成立，
/// 而把一次动作显示成一条消息，正是维护者报的那个故障形状。
/// 所以这一档从此**并进 [RemoteCommandRejected]**，不保留独立类型：留痕与「该不该发回执」
/// 的判据本来就在 `source` 上（本机那一路没有对面 ⇒ 契约 `localTriggerReceipt=none` 不回），
/// 再开一个类型就是让那条判据有两个读者。
///
/// ## item 的判据**分档**（与 T50/T51 同一纪律，不共用一张表）
/// - L2 → `parseL2Item`；L3 → `parseL3Item`（**只判"认不认得"**）；
/// - L1 → `L2 动作 ∪ L3 设置` 那张并集：L1 无凭据、无逐条勾选（契约
///   `itemRequiredFromLevel = L2`），但**能做的事**与 L2 同源，对面那台按自己的清单再判一次。
///   把它做成"只能 L1 自己那张表"等于凭空发明一份协议里没有的 L1 词表。
///
/// ## ⚠ 「这一条是 L3、动的是哪一项」只在这台设备上被读过（T128 片2）
/// 一条远程指令在线上是**一条 L1 通知**（发送侧只有 `sendNotice(peer,title,text)` 那个口，
/// 被签的六个字段里没有 `item`）⇒ 服务端的能力判据对它**根本不响**。
/// 所以这一层的第五道判据（[rejectBySenderGrant]：发送方在本机名单里那一行的**档位天花板**
/// 与**逐条清单**）不是纵深防御，而是这一族**唯一一道**；少了它，"只允许 A 读定位、
/// 不允许 B 读定位"在本仓没有一行代码能表达，而配对到 L1 的那台发 L2 指令连凭据都不必带
/// （契约 `auth.l2Requires = false`）。
///
/// ⚠ **L3 的"逐次确认"不在这里判**：`parseL3Item(confirmedThisTime: …)` 要的是**本机**那一次
/// 用户动作，不许拿载荷里自称的标志替它（T30 那条红线）。而这一层的调用点在后台轮次里 ——
/// 那时没有"本机这一次"可拿。所以这里只判"认不认得 + 有没有前置授权"，
/// `confirmedThisTime` 交给执行那一层（它知道窗口是怎么走完的）。
class RemoteCommandRecognizer {
  RemoteCommandRecognizer({
    required this.contract,
    required this.settings,
    required this.credentials,
    required this.grantForSender,
  });

  final FnthinkContract contract;
  final FnthinkRemoteSettings settings;
  final RemoteCredentialStore credentials;

  /// 发送方地址码 → **本机名单里那一行**（`fnthink_peers`，T128 片2）。
  ///
  /// ⚠ 必填、不给默认值，理由与 `RemoteCommandWiring.notifier` 同一族：这一格漏接时
  ///   **没有任何症状** —— 通知照常弹、指令照常执行，只是"谁都能执行"。
  ///   写成一个可空的隐式依赖，等于让唯一那道权限判据静默失效；要断就在编译期断。
  ///
  /// ⚠ 读口必须是 `FnthinkPeerService.grantFor`：那张表的读只有一个咽喉，
  ///   这里再 `loadFnthinkPeers()` 一遍就是第二个读法（页面与服务层从此各读各的）。
  final Future<FnthinkGrant> Function(String peerAddress) grantForSender;

  /// 这一条收件是不是远程指令。**只认幻念推送那一条渠道** —— L1 的白名单应用那一路
  /// 是**本机**触发的、根本不经过收件表，它走 [RemoteCommandWiring.onLocalContent]
  /// （本文件那一条 `source:` 形参就是为它留的）。
  Future<RemoteCommandParse> parse(FnthinkInboxMessage message) async {
    final command = RemoteCommandEnvelope.decode(message.body);
    if (command == null) return const RemoteCommandNotACommand();
    return judge(
      command: command,
      sender: message.sender,
      // 名单读不出来（库坏了、契约没装载）⇒ **让这一发抛出去**，不在这里咽成缺省档：
      // 抛出后收货循环那一格按"不是指令"处理（照常显示、不执行、不留痕），
      // 而咽成缺省档会把"读不到"与"这一台确实没被勾过"混成同一件事。
      grant: await grantForSender(message.sender),
    );
  }

  /// 判定一条**已经拆出来**的指令（白名单那一路复用这一份，不重写判定）。
  Future<RemoteCommandParse> judge({
    required RemoteCommand command,
    required String sender,
    required FnthinkGrant grant,
    String source = 'fnthink',
  }) async {
    // ⚠ 这一份是**名字**的集合，不是整串的集合：L3 的词表与"先有授权才谈得上翻"那两格
    //   问的都是"哪一项设置"，而清单里从片4 起存的是 `<名>/<参数>`。两边直接比会永远差一段
    //   —— 勾了 `monitoring/on` 却回一句 `missing-grant:monitoring`，而屏幕上写着"已授权"。
    //   整串那一维由第四道判据（`rejectBySenderGrant`）负责，它比的正是整串。
    final grantedKeys = {
      for (final item in grant.items) contract.grantItemBase(item),
    };
    // ① 开关：关着 ⇒ **拒**（留痕 + 回执，理由 `switch-off`），不再"当不是指令显示掉"。
    //   维护者 2026-10-12 裁定 1；旧理由与它为什么不成立写在类注释里，留着。
    if (!await settings.enabled) {
      return RemoteCommandRejected(command, sender, 'switch-off', source);
    }
    // ② 来源渠道（契约 remoteExecution.sources；"判不许有的渠道"与 L2/L3 无关）。
    final sources = contract.remoteExecutionSourcesFor(command.level);
    if (!sources.contains(source)) {
      return RemoteCommandRejected(
        command,
        sender,
        'source-not-allowed:${command.level}',
        source,
      );
    }
    // ③ 凭据（L2 可选 / L3 必填，契约 auth）。
    final auth = await checkRemoteExecutionAuth(
      contract,
      level: command.level,
      key: command.key,
      totpCode: command.totpCode,
      probe: remoteCredentialProbe(credentials),
    );
    if (auth is RemoteExecutionAuthRejected) {
      return RemoteCommandRejected(
        command,
        sender,
        'auth:${auth.reason}',
        source,
      );
    }
    // ④ 发送方在本机名单里那一行：档位天花板 + 逐条清单（T128 片2）。
    //   排在凭据**之后**：先证明"你是谁"，再谈"你被允许到哪"——与服务端
    //   `decideCapability`（身份过了才判能力）同一顺序，两处的理由串才对得上。
    final byGrant = rejectBySenderGrant(
      contract,
      level: command.level,
      item: command.item,
      grant: grant,
    );
    if (byGrant != null) {
      return RemoteCommandRejected(
        command,
        sender,
        // `level:…` / `unknown-ceiling:…` 是**这一条自己**的理由（与 `item:` 不同族：
        // 它答的是"这一档你够不够"，不是"这一项你勾没勾"），而 `not-granted:` 是清单那一半。
        byGrant.startsWith('not-granted:') ? 'item:$byGrant' : byGrant,
        source,
      );
    }
    // ⑤ item 在不在那一档的词表里。
    final bad = _rejectItem(command, grantedKeys: grantedKeys);
    if (bad != null) {
      return RemoteCommandRejected(command, sender, 'item:$bad', source);
    }
    return RemoteCommandAccepted(
      command: command,
      sender: sender,
      source: source,
      credential: (auth as RemoteExecutionAuthOk).presented,
      grantedKeys: grantedKeys,
    );
  }

  /// 回 null = 认得；回一句 = 拒的理由。
  ///
  /// ⚠ 判据**分两段**：先按档判"这个词认不认得"，再判"参数成不成形"。
  /// 参数那一段放在 switch **之后**是因为 L1 也能做 L2 的事（`itemRequiredFromLevel`
  /// 使 L1 的 item 就是 L2∪L3 那张并集表）—— 只写进 `case 'L2'` 的话，
  /// L1 那条路会绕过形状判据直接放行。而 switch 里每一档若都 return，
  /// 后面那段就成了死代码，所以三档各归一个小函数、由这一段统一收口。
  String? _rejectItem(
    RemoteCommand command, {
    required Set<String> grantedKeys,
  }) {
    final word = switch (command.level) {
      'L3' => _rejectL3Item(command, grantedKeys: grantedKeys),
      'L2' => _rejectL2Item(command.item),
      _ => _rejectL1Item(command.item),
    };
    if (word != null) return word;
    // ⚠⚠ 动作名与参数**都**从 `parseL2Item` 的结果取，不要直接碰 `command.item`：
    //   后者是**带斜杠段**的整串（`channel:toggle/webhook:acme:off`），
    //   拿它比 `'channel:toggle'` 恒不相等 ⇒ 这一格形同没写，每一条都放行。
    //   （本条判据第一版就是这么错的：症状是「参数拼错了也照样执行」。）
    //   而信封里那个 `argument` 字段是**另一处**参数，读它同样是错的。
    final parsed = parseL2Item(contract, command.item);
    if (parsed is! FnthinkL2Ok) return null;
    // 参数形状那一段按动作分派（T124 片B 起不止 channel:toggle 一种参数形状）：
    // 唯一的作者在 `fnthink_l2_actions.dart`，这里只转发。
    return rejectL2Argument(contract, parsed.action);
  }

  String? _rejectL3Item(
    RemoteCommand command, {
    required Set<String> grantedKeys,
  }) {
    // ⚠ **这里只判"认不认得"与"前置授权有没有"两件** ——
    //   `confirm-required`（契约 confirmEveryTime）是**延期**判据：它答的是
    //   "本机那一次用户动作有没有发生"，而这件事只有执行那一层知道（延时窗口
    //   走完之后才有）。把它算成"拒"的话**每一条 L3 指令都会在这一层被拒**，
    //   而 `parseL3Item(confirmedThisTime: false)` 正是那个会必然返回它的一侧
    //   —— 这就是这一条第一版的写法（实测 6 条红全在这里）。
    // ⚠ 查的是**名字**那一段（片4 起 item 是整串 `monitoring/on`）：拿整串去查那张键控表
    //   会得到 `unknown-setting:monitoring/on`，而发送页本来就发整串 —— 这一格在片4 之前
    //   只是没被人走到（同意屏给不出带目标值的勾），不是它一直是对的。
    final key = contract.grantItemBase(command.item);
    final setting = contract.l3Settings[key];
    if (setting == null) return 'unknown-setting:$key';
    // ⚠⚠ 片4 之后这一格与第四道（`rejectBySenderGrant`）**读的是同一份东西**：
    //   `grantedKeys` 就是名单那一行的 items（按名字取），而 L3 要过第四道就得整串在档，
    //   在档则名字必在 ⇒ 这一条对**对端那一路已经判不出任何新的东西**（旧用例
    //   「缺前置授权 ⇒ missing-grant」今天红的位置已经挪到 `not-granted`）。
    //   它留着是因为 `requiresExistingGrantFrom` 的原意是「这台**自己**先开着这一项，
    //   对面才谈得上翻」—— 那一维今天没有读口（读的是对端清单，不是本机状态）。
    //   拆成读本机还是删掉，是一条安全取舍，登记在 roadmap，不由这一片代拍。
    if (contract.l3SettingsRequiringExistingGrant.contains(key) &&
        !grantedKeys.contains(key)) {
      return 'missing-grant:$key';
    }
    return null;
  }

  String? _rejectL2Item(String item) {
    final parsed = parseL2Item(contract, item);
    return parsed is FnthinkL2Rejected ? parsed.reason : null;
  }

  String? _rejectL1Item(String item) {
    if (parseL2Item(contract, item) is FnthinkL2Ok) return null;
    // ⚠ 同上（`_rejectL3Item` 那条）：这里问的是"这个词在不在 L3 那张表上"，
    //   而 L1 的 item 也可以是带目标值的整串 ⇒ 先切回名字再查，只查词表，
    //   不走 parseL3Item（那会把 confirm-required 一起带出来）。
    if (contract.l3Settings.containsKey(contract.grantItemBase(item))) {
      return null;
    }
    return 'unknown-action:$item';
  }
}

/// 一条收件被判成什么（**三档必须分开**：不是指令 / 被拒 / 放行）。
///
/// ⚠ 这里曾经有第四档 `RemoteCommandNotEnabled`（开关关着 ⇒ 照常按通知显示、不留痕、不回执）。
/// 2026-10-12 裁定 1 把它并进了 [RemoteCommandRejected]（理由 `switch-off`）——
/// 留着那个类型就是留着第二条"该不该回执"的判据，而那一判只认 `source`。
sealed class RemoteCommandParse {
  const RemoteCommandParse();
}

/// 不是一条远程指令（收件表里绝大多数行都是这一类）。
class RemoteCommandNotACommand extends RemoteCommandParse {
  const RemoteCommandNotACommand();
}

/// 是指令，被拒（**开关关着** / 凭据不对 / 来源渠道不对 / item 不认得）—— 执行不发生，
/// 但**要留痕并给对面回一条拒的回执**（对方在等一个答复）。
class RemoteCommandRejected extends RemoteCommandParse {
  const RemoteCommandRejected(
    this.command,
    this.sender,
    this.reason,
    this.source,
  );

  final RemoteCommand command;
  final String sender;

  /// `switch-off` ｜`auth:<reason>` ｜`source-not-allowed:<level>` ｜`item:<reason>`。
  final String reason;

  /// 这一条是从哪来的（契约 `remoteExecution.sources` 的那两项之一）。
  ///
  /// ⚠ 它不是多余的：留痕与「该不该发回执」这两件事**都要按来源判** ——
  /// 本机白名单触发的那一路没有远端发送方，不许给它发回执
  /// （契约 `localTriggerReceipt`）。少了这一格，接线处只能拿 `sender` 当来源，
  /// 而那一路上 sender 恰恰是有值的（本机那条通知的来源）⇒ 会朝一个不存在的地址发回执。
  final String source;
}

/// 是指令且放行（**还没有执行** —— 延时窗口与执行都在调用方那一层）。
class RemoteCommandAccepted extends RemoteCommandParse {
  const RemoteCommandAccepted({
    required this.command,
    required this.sender,
    required this.source,
    required this.credential,
    required this.grantedKeys,
  });

  final RemoteCommand command;
  final String sender;

  /// `fnthink` 或 `localNotificationWhitelist`（契约 remoteExecution.sources 的那两项）。
  final String source;

  /// 带了哪一种凭据（`key` / `totp` / 空串）。
  final String credential;

  /// 本机**已逐条勾选**的 L3 设置键（执行那一层要拿它判 `requiresExistingGrantFrom`）。
  final Set<String> grantedKeys;
}
