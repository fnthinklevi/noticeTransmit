import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import '../models/fnthink_channel.dart';
import '../services/fnthink_channel_service.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_pair_items.dart';
import '../services/fnthink_pair_link.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_remote_action_labels.dart';
import '../theme/app_colors.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/fnthink_outcome.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/fnthink_pair_dialog.dart';
import 'fnthink_consent_gate.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_input_dialog.dart';
import 'fnthink_send_page.dart';

/// 这一页要碰的三样依赖。
///
/// 与 `FnthinkSettingsDeps` 分开而不是复用它：那一包还带 presence 与健康度读口，
/// 而设备绑定这一页一个都用不到（留着就是"这一页其实能读那些、只是没读"，
/// 而那种多余的能力正是将来被人顺手用上的那一半）。
class FnthinkPeersDeps {
  FnthinkPeersDeps({
    required this.contracts,
    required this.coordinator,
    required this.loadPeers,
    FnthinkChannelStore? channels,
  }) : _injectedChannels = channels;

  factory FnthinkPeersDeps.fromLocator() => FnthinkPeersDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
    // 名单只从读咽喉取。退回 `DatabaseHelper().loadFnthinkPeers` 的话，页面就会自己长出一份
    // 排序/时间口径，而 `history_page` 那批守卫已经证明过这种分叉是怎么开始的。
    loadPeers: GetIt.instance<FnthinkPeerService>().list,
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
  final Future<List<FnthinkPeer>> Function() loadPeers;
  FnthinkChannelStore? _injectedChannels;

  /// 勾选写嗅喂（T94）＋ 代建通道（T98 片③）。类型是**接口**：这一页今天要读通道、
  /// 按目标找一条、没有就建一条 —— 三件事都得能在测试里被替身钉住。
  ///
  /// ⚠ 缺省是 DI 里那**一个** `FnthinkChannelService`（T104 片②），不 new 第二份 ——
  ///   这一页代建的那条通道要立刻出现在首页那张「当前推送通道」清单里，而清单读的是它的缓存。
  /// ⚠ 但**第一次用到时才解析**：构造这一包的地方比用得到这一格的地方多（设置页的 harness
  ///   每次都构造它），在构造函数里摸 GetIt 会让"这一格从没被碰过"那条路也崩在注册表上。
  FnthinkChannelStore get channels =>
      _injectedChannels ??= GetIt.instance<FnthinkChannelService>();
}

/// 设备绑定（T94 片1）—— 「我和谁有关系」这一页。
///
/// 它从幻念推送页里独立出来，是因为维护者把幻念推送分成两块：**推送引擎**那侧收
/// 渠道设置·设备绑定·发起推送·接收设置·远程执行，**更多页**那处只留这台设备的渠道信息。
/// 绑定是"两台设备之间"的关系，不是"这台设备自己"的属性，所以它归推送引擎那侧 ——
/// 而"两处都能进"这一条要求它必须是一张**独立页**：否则第二处入口只能指向第一处的某一格，
/// 那不是两个入口，是一个入口被指了两次。
class FnthinkPeersPage extends StatefulWidget {
  const FnthinkPeersPage({super.key, this.deps, this.pairLink});

  /// 刚被点开的那条配对链接（#176 片4）。null = 这一页不是从链接进来的。
  ///
  /// ⚠ 它带着那枚一次性口令，所以**只活在这一次导航的参数里**：页面不把它写进 prefs、
  /// 不写进名单表、不拼进日志，处理过一次就再不放回（`_pairLinkHandled`）。
  /// 为什么不在这里自己判格式：判据（载荷名单、`v`、口令形状、档位词表）在包层那份契约
  /// 读口里，页面再判一遍就是第二个作者。
  final FnthinkPairLinkOutcome? pairLink;

  final FnthinkPeersDeps? deps;

  @override
  State<FnthinkPeersPage> createState() => _FnthinkPeersPageState();
}

class _FnthinkPeersPageState extends State<FnthinkPeersPage> {
  late final FnthinkPeersDeps _deps;
  late final FnthinkReceiveCoordinator _coordinator;

  FnthinkContract? _contract;

  /// 契约不可用的原话。非空时整页只显示这一条 —— 弹层里的档位名单要从契约读，
  /// 拿不到契约还让人去配对，等于把一次签出去的请求写进一个说不清含义的地方。
  String? _contractError;

  List<FnthinkPeer>? _peers;

  /// 名单读失败的原话。与 `null`（还没读）分开：那一句是"读不到"，不能画成"一个都没有"。
  String? _peersError;

  /// 最近一次答复配对请求的结论（null = 这一页还没答过）。
  ({FnthinkPairRequest request, bool approve, FnthinkPairAnswer answer})?
  _pairAnswer;

  /// 最近一次撤销的结论（null = 这一页还没撤过）。
  ({FnthinkPeer peer, FnthinkPeerRevoke revoke})? _peerRevoke;

  /// 最近一次「配对另一台设备」的结论（null = 这一页还没提交过）。
  FnthinkPairResult? _pairSubmit;

  bool _busy = false;

  /// 勾选写不上时的原话（null = 没发生过错）。
  String? _forwardError;

  /// 勾上之后代建通道那一句（T98 片③）：建了还是本来就有 —— 两句不同，不是「成功/失败」。
  String? _forwardChannelNote;

  /// 批准那一屏上那一枚「同意时也把它设为往外发的目标」（T98 片②）。
  ///
  /// ⚠ 它只管**本机这两段**（那一列勾上 ＋ 一条目标=它的通道）。反过来的那一半 ——
  ///   对面那台允许这台推过去 —— 由那一台自己点同意（契约 `pairing.relationshipStoredOn`
  ///   把关系记在**被投那台**的记录上），这一屏替它点不了，所以结论里必须单独说一句。
  bool _alsoOutbound = false;

  /// 上一次的批准**真的把这两段办掉了**（结论行据此决定要不要说那句"还缺那一半"）。
  /// 每次答复开头清零：留着它，下一次没勾的批准也会跟着说"已经能往它发了"这句假话。
  bool _outboundDone = false;

  /// 那条被点开的链接**这一页已经处理过了**。口令是 singleUse 的：
  /// 重放一次不是"再试一次"，而是"把同一枚口令往被人再看一眼的方向推"，所以一次进入只处理一次。
  bool _pairLinkHandled = false;

  /// 链接判不过（前缀对但载荷不成形 / 契约读不到）。⚠ 这与"没有链接"是两件事：
  /// 后者什么都不该说，前者必须说一句 —— 用户确实点了一条链接，"点了没反应"就是这次任务要修的缺陷形状。
  /// 这里只留一个布尔：那句文案是**同一句**（不分辨哪一种不对），原因留在 outcome 里不进界面。
  bool _pairLinkRejected = false;

  /// 逐条勾选那张表的候选集（T134 片3，派生自契约，见 `pairItemCandidates`）。
  List<String> _pairItems = const <String>[];

  /// 契约的取值域与本机的两张词表**不一致**（派生出的项落在取值域外）。
  /// 这时候那张表一幅都不画，但要说一句"这一屏逐条给不了"——
  /// 静默退化成"只能给档位"，用户会以为自己已经勾过了。
  bool _pairItemsBroken = false;

  /// **这一条请求**上勾了哪些项。按 requestId 分键：一屏可以同时挂着几条，
  /// 共用一个 Set 会把"我给 B 勾的那两项"跟着落到 C 那条的答复上 —— 而答复是按条签出去的。
  final Map<String, Set<String>> _pairChecked = {};

  @override
  void initState() {
    super.initState();
    _deps = widget.deps ?? FnthinkPeersDeps.fromLocator();
    _coordinator = _deps.coordinator;
    // 链接里带来的那份预填必须**等 `_load` 之后**再处理：弹层的档位来自 `_contract`，
    // 而 `_contract` 是 `_load` 里异步读到的。早一步开弹层，档位那一排就无处可取（当场抛），
    // 表现是"点开了链接，页面闪一下就没了"。
    unawaited(_load().then((_) => _consumePairLink()));
  }

  Future<void> _load() async {
    final FnthinkContract contract;
    try {
      contract = await _deps.contracts.load();
    } on FnthinkContractUnavailable catch (e) {
      if (mounted) setState(() => _contractError = e.reason);
      return;
    }
    if (!mounted) return;
    // 候选集在契约到手这一刻算一次，界面不自己算：派生这件事有两个写法的时候，
    // "只从契约读名单"那条守卫会跟着一个写法红，另一个写法照样上线。
    _derivePairItems(contract);
    setState(() => _contract = contract);
    // 进这一页先看一眼本机那一份配对账（T116）。为什么不等下一轮 poll：这一页正是用户
    // "去看看有没有回音"的那一屏，慢一轮的表现是"他打开的是空的，而结论其实早就落了"。
    await _coordinator.reloadPairLedger();
    await _loadPeers();
  }

  /// 派生失败（契约取值域与两张词表不一致）时**不画那张表**并记下原因，而不是让这一页
  /// 在 build 里抛：抛出来的表现是整页白屏，而"逐条给不了、只能给档位"是可以说清的。
  void _derivePairItems(FnthinkContract contract) {
    try {
      _pairItems = pairItemCandidates(contract);
      _pairItemsBroken = false;
    } on StateError {
      _pairItems = const <String>[];
      _pairItemsBroken = true;
    }
  }

  /// 勾上 / 取消勾选「这一台可以当幻念通道的目标」（T94）。
  ///
  /// 取消不连带删通道：那一下要断掉的只是「新通道不能选它」，已建好的那一条留着
  /// 并让它在发送时报出「目标未勾选」—— 比偷偷把用户的配置删掉好。
  Future<void> _setForward(FnthinkPeer peer, bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _deps.channels.setForward(peer.peerAddress, value);
      // T98 片③：勾上就**代建**一条目标=这台的通道（已有就不动）。三段链 —— 对方授权／
      // 本机的这一勾／一条目标=它的通道 —— 缺一段就不发，而缺的是哪一段界面上看不出来。
      // ⚠ 只在**勾上**那一支做：取消勾选不连带删通道（服务层那条判据写着为什么）。
      if (value) await _ensureChannelFor(peer);
      await _loadPeers();
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      // 写不上就在界面上说一句原话。**不 debugPrint**：这一页的守卫明写「不许打印」
      // （一次性口令不许有第二份去处，而本站日志脱敏 T89 还没配）。
      // 开关是从库里读的，不抬回就等于说屏幕上那个开关是假的。
      if (mounted) {
        setState(() {
          _busy = false;
          _forwardError = '$e';
        });
      }
    }
  }

  /// 保证「目标=这台」的通道存在（T98 片③）。**已有就不动**：用户可能自己改过它的名字
  /// 或主备角色，代建的第二条只会在通道列表里多出一行长得一样的行。
  Future<void> _ensureChannelFor(FnthinkPeer peer) async {
    final channels = await _deps.channels.list();
    final exists = channels.any(
      (c) =>
          c.targetKind == FnthinkChannelTarget.device &&
          c.target == peer.peerAddress,
    );
    if (!exists) {
      await _deps.channels.create(
        id: '${DateTime.now().millisecondsSinceEpoch}-ff',
        name: peer.peerAddress,
        target: peer.peerAddress,
        targetKind: FnthinkChannelTarget.device,
      );
    }
    if (mounted) {
      setState(() => _forwardChannelNote = exists ? 'kept' : 'made');
    }
  }

  Future<void> _loadPeers() async {
    List<FnthinkPeer>? rows;
    String? error;
    try {
      rows = await _deps.loadPeers();
    } catch (e) {
      error = '$e';
      rows = null;
    }
    if (!mounted) return;
    setState(() {
      _peers = rows;
      _peersError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _contractError;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fnthinkPeersTitle)),
      backgroundColor: AppColors.bgColor(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (error != null)
            FnthinkNote(keyName: 'fnthink-peers-contract-error', text: error)
          else ...[
            _buildPairRequests(l10n),
            _buildSentRequests(l10n),
            _buildPairHistory(l10n),
            _buildPeersCard(l10n),
          ],
        ],
      ),
    );
  }

  /// 待确认的配对请求那一格。
  ///
  /// 列表**跟着协调者那份账走**（`pairRequestsListenable`）：用户挂出口令之后是盯着屏幕等对面来配的，
  /// 后台每轮带回来的东西要自己上界面。页面不重新 poll（那会长出第二个"这一轮有没有货"的读法），
  /// 也不自己定定时器去翻（那种"什么时候该看"的口径一漏，表现就是列表看着看着不再更新）。
  /// 空列表**不画这一格** —— 一张永远空的表等于让界面猜；但答过一条之后要留着：那一条已经
  /// 是发生过的事，抹掉它等于让界面说"没发生过"。
  Widget _buildPairRequests(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: _coordinator.pairRequestsListenable,
      builder: (context, _) {
        final requests = _coordinator.pendingPairRequests;
        final answer = _pairAnswer;
        if (requests.isEmpty && answer == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FnthinkCard(
            title: l10n.fnthinkPairRequests,
            children: [
              for (final request in requests)
                ..._pairRequestRows(l10n, request),
              if (answer != null)
                FnthinkNote(
                  keyName: 'fnthink-pair-answer',
                  text: _pairAnswerText(l10n, answer),
                ),
              // 代办了本机这两段 ⇒ 必须跟着说清**还缺哪一段**（这一段不在这屏的能力里：
              // 关系存在被投那台的记录上，那台的同意只能那台点）。不说，用户读到的就是
              // "点一次两边都通了"这句假话 —— 而那正是这次任务要修的形状。
              if (answer != null &&
                  answer.approve &&
                  answer.answer.ok &&
                  _outboundDone)
                FnthinkNote(
                  keyName: 'fnthink-pair-one-way',
                  text: l10n.fnthinkPairApprovedOneWay,
                ),
            ],
          ),
        );
      },
    );
  }

  /// 「我发起过的配对请求」那一格（T110 第二面）。
  ///
  /// 这一格答的是维护者那句「我怎么看对方进度？」：上面那一格是"别人等我答"，这里是"我等别人答"。
  /// ⚠ T116 起它读的是**本机那一份账**（`pairLedgerListenable`），不再只读 poll 带回来的内存账：
  ///   那一条要求服务端有 `sentPairRequests` 这条读口（T110 格1 那一片），部署在它之前的服务器
  ///   永远不回这一项 ⇒ 用户发完刷新、屏幕上那一格根本不存在，读起来成了"我没发出去"。
  ///   发起那一刻本机就落了账，所以这一格**不问服务器是新是旧**。
  /// 与待答复那格的三条纪律同源：列表走协调者那份账、页面不自己 poll、空列表**不画这一格**。
  ///
  /// ⚠ 空列表不画，也**不许**画成"没有被拒绝过"：空有三种来路（没发起过／这一台还没读动那份账／
  ///   装了本片之前压根没落过账），而那三种都不是"没有发生过"——一句都不说，比说一句假的诚实。
  /// ⚠ 这一行**没有任何可点的按钮**：本机对这一条能做的事一件都没有（同意只能由对面那台点，
  ///   契约 `pairing.relationshipStoredOn` 把关系记在被投那台的记录上）。摆一枚"重试"会让用户
  ///   以为重扫一次码能替对面点头。
  Widget _buildSentRequests(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: _coordinator.pairLedgerListenable,
      builder: (context, _) {
        final rows = _coordinator.outgoingPairRequests;
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FnthinkCard(
            title: l10n.fnthinkPairRequestsSent,
            children: [
              for (final row in rows)
                FnthinkNote(
                  keyName: 'fnthink-pair-sent-${row.requestId}',
                  text: l10n.fnthinkPairSentLine(
                    row.peerAddress,
                    row.level.isEmpty ? '—' : row.level,
                    _pairStateWord(l10n, row.status),
                    // 「多久之前」问的是**这一档状态是什么时候成的**：还在等的说它等了多久，
                    // 已答复/已过期的说结论是几时落的。取不到结论时刻（pending 那一条服务端
                    // 还没写过状态变更）才退到发起那一刻 —— 退的是同一件事的更早出处，不是猜。
                    fnthinkAgoLabel(
                          l10n,
                          row.changedAt > 0 ? row.changedAt : row.createdAt,
                        ) ??
                        '—',
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: FnthinkInlineAction(
                  key: const ValueKey('fnthink-pair-refresh'),
                  label: l10n.fnthinkPairRefresh,
                  // T129 片2：这一格讲的是"我在等谁答"，而它原来只能等下一轮 poll 才更新
                  // （提频那一半在片1 已接）。挂在**这一格**而不是页面顶部：问的就是这几行。
                  onPressed: _busy ? null : _refreshPairing,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 手动问一次服务器"对面答了没有"（T129 片2）。
  ///
  /// ⚠ 走协调者那**一个** `receiveOnce()`：页面不自己发 poll、也不自己判"这一轮算不算成功"。
  /// 三件事分开说（与收件页那三句同源）：收取没开（`null`）、这一轮被跳过、跑完了而对面
  /// 还没答 —— 把后两件说成一件，用户就会再点一次，而对第二遍服务端只回一句同形的话。
  Future<void> _refreshPairing() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final report = await _coordinator.receiveOnce();
    if (!mounted) return;
    // 问完重读一次本机那两份账（发起面与历史共用一份），否则弹层说"跑完了"而格子还是旧的。
    await _loadPeers();
    if (!mounted) return;
    setState(() => _busy = false);
    final ran = report != null && !report.skipped;
    await showFnthinkOutcome(
      context,
      ok: ran,
      detail: report == null
          ? l10n.fnthinkReceiveDisabled
          : report.skipped
          ? l10n.fnthinkReceiveSkipped
          : l10n.fnthinkPairRefreshQuiet,
    );
  }

  /// 「配对历史」那一格（T116：维护者 2026-10-09 要的三面之三）。
  ///
  /// 一行是「{谁发起的} · {对端} · {档位} · {结论} · {结论几时落的}」。**两个主语合在一张表里**，
  /// 不拆两张：这一格答的是"这台设备上配对这件事发生过什么"，按主语拆开会把「我拒绝过的那条」
  /// 与「我等到的那个结论」排成两段互不相干的历史，而用户要的是翻一遍就知道结果。
  /// ⚠ 空列表**不画**，也不说"没有历史"（理由与上面那格同一条）。
  Widget _buildPairHistory(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: _coordinator.pairLedgerListenable,
      builder: (context, _) {
        final rows = _coordinator.pairRequestHistory;
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FnthinkCard(
            title: l10n.fnthinkPairHistoryTitle,
            children: [
              for (final row in rows)
                FnthinkNote(
                  keyName: 'fnthink-pair-history-${row.requestId}',
                  text: l10n.fnthinkPairHistoryLine(
                    row.outgoing
                        ? l10n.fnthinkPairHistoryOutgoing
                        : l10n.fnthinkPairHistoryIncoming,
                    row.peerAddress,
                    row.level.isEmpty ? '—' : row.level,
                    _pairStateWord(l10n, row.status),
                    fnthinkAgoLabel(l10n, row.changedAt) ?? '—',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 那一档状态说哪句话。**词与档的对应不在这里**（在内核那份状态映射里，词表来自契约），
  /// 这里只做措辞 —— 所以契约把 `approved` 改名的那一天，这一句会跟着换，而不是继续说"已同意"。
  String _pairStateWord(AppLocalizations l10n, String status) {
    switch (fnthinkPairRequestStateOf(_contract!, status)) {
      case FnthinkPairRequestState.pending:
        return l10n.fnthinkPairStatePending;
      case FnthinkPairRequestState.approved:
        return l10n.fnthinkPairStateApproved;
      case FnthinkPairRequestState.denied:
        return l10n.fnthinkPairStateDenied;
      case FnthinkPairRequestState.expired:
        return l10n.fnthinkPairStateExpired;
      case FnthinkPairRequestState.unknown:
        // 词表外的值：把原话摊出来。画成"失败"会让人去重扫一次码，而那一发会消耗新口令。
        return l10n.fnthinkPairStateUnknown(status);
    }
  }

  List<Widget> _pairRequestRows(
    AppLocalizations l10n,
    FnthinkPairRequest request,
  ) {
    // 这一档是不是本机够得着的：`grantableLevel` 回 null 就是词表里没有那个词。
    // 词表里没有 ⇒ **同意不许点**（协调者那一发也不会发出去，但把按钮灰掉比让用户点下去
    // 再读一句 `unknown-level:xxx` 诚实），拒绝仍然可以 —— 划掉一条看不懂的请求不需要档位。
    final grantable = _contract?.grantableLevel(request.level);
    final capped = grantable != null && grantable != request.level;
    return [
      FnthinkNote(
        keyName: 'fnthink-pair-request-${request.requestId}',
        text: l10n.fnthinkPairRequestLine(
          request.requester,
          request.level,
          // 「多久之前」只有这一份口径（与通道健康度那句共用同一把尺，见 `fnthinkAgoBucket`）；
          // 服务端没带创建时刻就写 '—'，不拿"此刻"凑一条看起来刚刚请求过的。
          fnthinkAgoLabel(l10n, request.createdAt) ?? '—',
        ),
      ),
      if (capped)
        FnthinkNote(
          keyName: 'fnthink-pair-will-grant-${request.requestId}',
          text: l10n.fnthinkPairWillGrant(grantable),
        ),
      if (grantable == null)
        FnthinkNote(
          keyName: 'fnthink-pair-unknown-level-${request.requestId}',
          text: l10n.fnthinkPairUnknownLevel(request.level),
        ),
      ..._pairItemRows(l10n, request, grantable),
      Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FnthinkInlineAction(
              key: ValueKey('fnthink-pair-approve-${request.requestId}'),
              label: l10n.fnthinkPairApprove,
              onPressed: grantable == null || _busy
                  ? null
                  : () => _answer(request, true),
            ),
            FnthinkInlineAction(
              key: ValueKey('fnthink-pair-deny-${request.requestId}'),
              label: l10n.fnthinkPairDeny,
              tone: FnthinkActionTone.destructive,
              onPressed: _busy ? null : () => _answer(request, false),
            ),
          ],
        ),
      ),
      // T98 片②：把"批准完之后还要再去下面把那一列勾上、再去通道页建一条"这三下并成一下。
      // 名字说的是它真正做的事 —— 不是"一次配对即双向"（那一条今天做不到：关系存在被投那台）。
      Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.fnthinkPairApproveOutbound,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            CupertinoSwitch(
              key: const ValueKey('fnthink-pair-approve-outbound'),
              value: _alsoOutbound,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _alsoOutbound = v),
            ),
          ],
        ),
      ),
      FnthinkNote(
        keyName: 'fnthink-pair-approve-outbound-desc',
        text: l10n.fnthinkPairApproveOutboundDesc,
      ),
    ];
  }

  /// 逐条勾选那一小段（T134 片3）。
  ///
  /// 候选集来自 `pairItemCandidates`（契约那两张表做减法），**这一屏不自己写名单** ——
  /// 名单抄进界面的下场是"契约加了一项而这里没加"，而那一格的缺席长得和"用户没兴趣"一模一样。
  ///
  /// 三种"一幅都不画"：这一档用不上逐条清单（L1，见 `pairItemsApplyAtLevel`）、
  /// 派生不出候选、档位词本机不认识（上面那条 `unknown-level` 已经在说了）。
  /// 前两种**不补一句"没有可勾选项"**：那几种来路在界面上会读成同一句话，而其中有的
  /// 是"这一档不需要"、有的是"契约读歪了"，把它们塌成一句就等于替后者撒谎。
  List<Widget> _pairItemRows(
    AppLocalizations l10n,
    FnthinkPairRequest request,
    String? grantable,
  ) {
    if (_pairItemsBroken) {
      return [
        FnthinkNote(
          keyName: 'fnthink-pair-items-broken-${request.requestId}',
          text: l10n.fnthinkPairItemsBroken,
        ),
      ];
    }
    final contract = _contract;
    if (contract == null ||
        grantable == null ||
        !pairItemsApplyAtLevel(contract, grantable)) {
      return const <Widget>[];
    }
    final checked = _pairChecked[request.requestId] ?? const <String>{};
    return [
      FnthinkNote(
        keyName: 'fnthink-pair-items-title-${request.requestId}',
        text: l10n.fnthinkPairItemsTitle,
      ),
      for (final item in _pairItems)
        Row(
          children: [
            Expanded(
              child: Text(
                // 那一行**说什么**只有 `kFnthinkRemoteActionLabels` 一个作者（发送页也用它）；
                // 这里不另拼"允许 xxx"那种前缀，前缀是这句话的第二个来源。
                fnthinkRemoteActionLabel(l10n, item),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            Checkbox(
              key: ValueKey('fnthink-pair-item-${request.requestId}-$item'),
              value: checked.contains(item),
              // `_busy` 期间锁：答复已经在飞，这时改勾选改的是**已经签出去的那一份**之外的东西，
              // 屏幕上会留下一张与刚发出去的答案不一致的表。
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      final next = Set<String>.of(checked);
                      if (v == true) {
                        next.add(item);
                      } else {
                        next.remove(item);
                      }
                      _pairChecked[request.requestId] = next;
                    }),
            ),
          ],
        ),
      FnthinkNote(
        keyName: 'fnthink-pair-items-note-${request.requestId}',
        text: l10n.fnthinkPairItemsNote,
      ),
    ];
  }

  /// 名单那一格：每一行是一台对端，能发一条、能撤销。
  Widget _buildPeersCard(AppLocalizations l10n) {
    final rows = _peers;
    final revokeEntry = _peerRevoke;
    return FnthinkCard(
      title: l10n.fnthinkPeersTitle,
      children: [
        if (rows == null)
          FnthinkNote(
            keyName: 'fnthink-peers-error',
            text: l10n.fnthinkPeersError(_peersError ?? ''),
          )
        else if (rows.isEmpty)
          FnthinkNote(
            keyName: 'fnthink-peers-empty',
            text: l10n.fnthinkPeersEmpty,
          )
        else
          for (final peer in rows) ...[
            FnthinkNote(
              keyName: 'fnthink-peer-${peer.peerAddress}',
              text: l10n.fnthinkPeerLine(
                // T128 片1：这一行"是谁"那一段的唯一作者（地址码仍在前，别名在括号里 ——
                // 能被核对的那个东西不能被一个本机编的名字替掉）。
                peer.whoLabel,
                peer.level,
                fnthinkFormatTime(peer.grantedAt),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FnthinkInlineAction(
                key: ValueKey('fnthink-peer-revoke-${peer.peerAddress}'),
                label: l10n.fnthinkPeerRevoke,
                tone: FnthinkActionTone.destructive,
                // 撤销那一发要能连点两下都不出事（服务端幂等），但 `_busy` 仍然拦：
                // 拦的不是"撤两次"，是"两次删行撞在一起"——那种时候界面显示的是哪一次？
                onPressed: _busy ? null : () => _revoke(peer),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FnthinkInlineAction(
                key: ValueKey('fnthink-peer-rename-${peer.peerAddress}'),
                label: l10n.fnthinkPeerRename,
                // T128 片1：别名挂在**这一行**，且刻意不是破坏性色调 —— 它不碰授权、
                // 不碰服务端，改的只是这一行在屏幕上叫什么。地址码不能被它替掉（见 whoLabel）。
                onPressed: _busy ? null : () => _renamePeer(peer),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FnthinkInlineAction(
                key: ValueKey('fnthink-peer-send-${peer.peerAddress}'),
                label: l10n.fnthinkPeerSend,
                // 「发一条」挂在**这一行**上而不是页面顶部一个通用按钮：收件人只能是本机
                // 同意过的那几台（名单就是候选全集），让人先在行里选中那台再填内容，
                // 比在弹层里再挑一次少一处可能填错的地址（填错了服务端只会回一句同形的 403）。
                onPressed: _busy ? null : () => _sendTo(peer),
              ),
            ),
            // T94：「这台能不能当幻念通道的目标」是**另一件事**（方向相反：配对是对方能往
            // 这台推，勾选是这台可以往它那边发），所以它挂在**这一行**而不是通道那一格里 ——
            // 放通道那里的话，用户得先知道目标是谁才能回头去名单里开这个权限。
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.fnthinkPeerForwardToggle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ),
                CupertinoSwitch(
                  key: ValueKey('fnthink-peer-forward-${peer.peerAddress}'),
                  value: peer.forwards,
                  onChanged: _busy ? null : (v) => _setForward(peer, v),
                ),
              ],
            ),
            if (_forwardError != null)
              FnthinkNote(
                keyName: 'fnthink-peer-forward-error',
                text: _forwardError!,
              ),
            if (_forwardChannelNote != null)
              FnthinkNote(
                keyName: 'fnthink-peer-forward-channel',
                text: _forwardChannelNote == 'made'
                    ? l10n.fnthinkPeerForwardChannelMade
                    : l10n.fnthinkPeerForwardChannelKept,
              ),
            FnthinkNote(
              keyName: 'fnthink-peer-forward-hint',
              text: l10n.fnthinkPeerForwardHint,
            ),
          ],
        if (revokeEntry != null)
          FnthinkNote(
            keyName: 'fnthink-peer-revoke-note',
            text: _peerRevokeText(l10n, revokeEntry),
          ),
        // 点开的那条链接判不过 ⇒ 必须说一句（用户确实点了一下，"没反应"就是这次要修的缺陷形状）。
        // 只给一句、不分辨原因：分辨"哪种不对"对着抄来的链接就是枚举器。
        if (_pairLinkRejected)
          FnthinkNote(
            keyName: 'fnthink-pair-link-rejected',
            text: l10n.fnthinkPairLinkRejected,
          ),
        // 「配对另一台设备」挂在名单这一格里，而不是身份那一格（本机是自己）或页面顶部
        // 一个通用按钮：这一格讲的正是"我和谁有关系"，而这一发要做的就是把一行新的关系挂进去。
        PrimaryActionButton(
          key: const ValueKey('fnthink-pair-peer'),
          label: l10n.fnthinkPairPeer,
          onPressed: _busy ? null : _pairWithPeer,
        ),
        // 提交之后本机这一格不会立刻多出什么：同意由对面那台点，那一行要等下一轮收取才回来。
        // 少了这句，"发过去了"会被读成"已经配上了"，而用户接下来做的动作（发一条试试）当场必失败。
        FnthinkNote(
          keyName: 'fnthink-pair-peer-pending',
          text: l10n.fnthinkPairPeerPendingNote,
        ),
        if (_pairSubmit != null)
          FnthinkNote(
            keyName: 'fnthink-pair-peer-note',
            text: fnthinkPairSubmitText(l10n, _pairSubmit!),
          ),
        const SizedBox(height: 8),
        FnthinkNote(
          keyName: 'fnthink-peers-boundary',
          text: l10n.fnthinkPeersBoundary,
        ),
      ],
    );
  }

  /// 答复一条待确认的配对请求。**同意那一下一定过二次确认** —— 契约把这一步定为
  /// `confirmRequired=true / autoApprove=false`，它存在的意义就是有人看过并点过一次。
  ///
  /// 页面交给协调者的**只有一个布尔**：答复词与档位都由协调者从契约取。弹层上写的那一档是
  /// 契约算出来的（`grantableLevel`），不是对方请求的那一档 —— 让用户在他以为的档位上按下同意，
  /// 而实际授出去的是另一档，那一下点得就没有意义。
  ///
  /// ⚠ 参数写成位置式是给 T06 那条守卫留一个不带 `{` 的签名锚点：`blockAfter` 会停在
  ///    命名参数表那个花括号上，取到的是参数表而不是函数体（这条在收件守卫上砸过一次）。
  Future<void> _answer(FnthinkPairRequest request, bool approve) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final willGrant = _contract?.grantableLevel(request.level) ?? request.level;
    if (approve) {
      // T118 同意门：批准配对＝把这一台记到**那台中转机**的关系列上 ⇒ 内容此后会经服务器走。
      // ⚠ 只拦"同意"那一支：拒绝是**把关系挡在门外**，拦它等于让一个还没同意的人既不能同意、
      //    也不能拒绝 —— 那条请求会一直挂在待处理里（而它没有一个"过期"的本地判据）。
      //    文案用通用那一句：那一格的按钮就叫「同意」，拿它当动作名会读成"同意这件事还要同意"。
      if (!await requireFnthinkRelayConsent(context)) {
        return;
      }
      if (!mounted) return;
      final ok = await IosDialogActions.askConfirm(
        context,
        title: l10n.fnthinkPairAskTitle,
        message: l10n.fnthinkPairAskMsg(request.requester, willGrant),
        // 确认键不复用列表里那句"同意"：弹层内外两句一模一样，用户分不清自己点的是哪一个，
        // 而 `find.text` 会一次抓到两个。
        confirmText: l10n.confirm,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    _outboundDone = false;
    final answer = await _coordinator.confirmPairing(
      request: request,
      approve: approve,
      // 勾选表上勾了什么就交什么（顺序由界面上的那张表给，去重与排序由服务层/服务端负责）。
      // 拒绝那一支**不**带清单 —— 协调者会把它收成空，这里传的是"用户在这一条上勾过的东西"，
      // 不是"我打算授出去的清单"（两件事两个名字，见 confirmPairing 里那段）。
      items: (_pairChecked[request.requestId] ?? const <String>[]).toList(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pairAnswer = (request: request, approve: approve, answer: answer);
      // 这一条已经有结论了：那份勾选留在表里，下一次同 id 的请求（不可能有）或
      // 页面上另一条请求都会读到它。答复落定就擦掉。
      _pairChecked.remove(request.requestId);
    });
    // 名单是这一发的**后果**：不重读一次，用户点完同意，下面那格还是旧的（而它的存在意义
    // 正是"我同意过谁"）。重读走的是同一个读咽喉，不是页面自己数一遍。
    await _loadPeers();
    // T98 片②：勾了就把**本机这两段**当场办掉。为什么放在 `_loadPeers()` 之后：那两段要的
    // 是"名单里已经有这一台"，而这一台正是刚才那一发写进去的 —— 早一步做就是在一行还不存在
    // 的记录上写勾选。
    if (approve && answer.ok && _alsoOutbound) {
      FnthinkPeer? row;
      for (final p in _peers ?? const <FnthinkPeer>[]) {
        if (p.peerAddress == request.requester) row = p;
      }
      // 名单里没有那一行 ⇒ 一段都不代办，也不再补一句"没建成"：上面 `fnthink-pair-answer`
      // 那句说的就是为什么（写不进去／档位不认／换过钥），补第二句是替那句撒第二次谎。
      if (row != null) {
        await _setForward(row, true);
        // 写失败时 `_setForward` 已经把原话放进 `_forwardError`，那句"这边已经能往它发了"
        // 就跟着不许出现。
        _outboundDone = _forwardError == null;
      }
    }
    if (!mounted) return;
    setState(() {});
    // T126：答完那一下要**当场**看得见。下面那格的小字是"事后翻回来还在"的地方，两处同一句
    // 原话（都走 [_pairAnswerText]），这里不另拼措辞 —— 另拼就是第二个词表。
    final entry = _pairAnswer;
    if (entry != null) {
      await showFnthinkOutcome(
        context,
        ok: entry.answer.ok,
        detail: _pairAnswerText(l10n, entry),
      );
    }
  }

  /// 最近一次答复的结论。⚠ 档位那一格用的是**服务端回的** `grantedLevel`，不是用户点的那一档：
  /// 封顶（`pairConfirm.levelCeilingFrom`）在服务端那侧也判一次，本机以为给到了而对面记低了
  /// 是完全可能的，而名单以后就是按这一列显示"我给过谁哪一档"的。
  String _pairAnswerText(
    AppLocalizations l10n,
    ({FnthinkPairRequest request, bool approve, FnthinkPairAnswer answer})
    entry,
  ) {
    final answer = entry.answer;
    if (!answer.ok) return l10n.fnthinkPairFailed(answer.reason ?? 'no-answer');
    final peer = entry.request.requester;
    if (!entry.approve) return l10n.fnthinkPairDenied(peer);
    final skipped = answer.skipped;
    if (skipped == FnthinkPeerSkip.grantedLevelUnusable) {
      return l10n.fnthinkPairNoGrantedLevel;
    }
    if (skipped == FnthinkPeerSkip.storeUnavailable) {
      return l10n.fnthinkPeerStoreUnavailable;
    }
    if (skipped == FnthinkPeerSkip.writeFailed) {
      return l10n.fnthinkPeerWriteFailed;
    }
    if (answer.wrote == FnthinkPeerWrite.keySwapped) {
      return l10n.fnthinkPairKeySwapped(peer);
    }
    final granted = answer.result.grantedLevel;
    if (granted == null) return l10n.fnthinkPairNoGrantedLevel;
    return l10n.fnthinkPairApproved(peer, granted);
  }

  /// 划掉名单里的一台（T31 B 片那一发的入口）。
  ///
  /// ⚠ 参数写成位置式，与 [_answer] 同一条理由：T06 那条守卫的锚点要不带 `{` 的签名
  ///    （`blockAfter` 会停在命名参数表那个花括号上，取到的是参数表而不是函数体）。
  /// ⚠ 页面**只交一个 bool 之外的东西都没有**：撤谁、先后怎么做、`revoked:false` 算不算成，
  ///    全在协调者那一处。页面自己先删行再发请求的话，"授权还在而来源消失"那一种就长在界面里了。
  Future<void> _revoke(FnthinkPeer peer) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkRevokeAskTitle,
      message: l10n.fnthinkRevokeAskMsg(peer.peerAddress),
      // 弹层里的确认键不写"撤销"：那与列表里那个按钮同词，`find.text` 一次抓到两个，
      // 而用户也分不清自己点的是"要撤"还是"只是打开了弹层"。
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final revoke = await _coordinator.revokePeer(peer);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _peerRevoke = (peer: peer, revoke: revoke);
    });
    // 撤成了那一行就不该再显示；没撤成也要重读一次，因为界面那句结论说的是"此刻名单什么样"。
    // 重读走同一个读咽喉，不是页面自己数一遍（那会长出第二个排序/时间口径）。
    await _loadPeers();
  }

  /// 给这一行起（或抹）一个本机名字（T128 片1）。
  ///
  /// 三件事必须分开说：**改了**、**抹了**、**这一行已经不在了**。
  /// 把第三件说成前两件，用户会带着一张其实没有那台的名单去核对对面；
  /// 而把"抹了"说成"改成了「」"是更常见的假绿 —— 空串也是一种有效的新名字吗？不是，
  /// 那是"这台没有别名"，行里就只剩地址码。
  Future<void> _renamePeer(FnthinkPeer peer) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final typed = await showIosInputDialog(
      context,
      title: l10n.fnthinkPeerRenameTitle,
      initialText: peer.alias,
      // 取消回 null（一个字都不改）；确认回字符串，可能是空串（那就是"抹掉名字"）。
    );
    if (typed == null || !mounted) return;
    setState(() => _busy = true);
    final alias = FnthinkPeer.normalizeAlias(typed);
    final ok = await GetIt.instance<FnthinkPeerService>().rename(
      peer.peerAddress,
      alias,
    );
    if (!mounted) return;
    await _loadPeers();
    if (!mounted) return;
    setState(() => _busy = false);
    await showFnthinkOutcome(
      context,
      ok: ok,
      detail: !ok
          ? l10n.fnthinkPeerRenameGone
          : alias.isEmpty
          ? l10n.fnthinkPeerRenameCleared
          : l10n.fnthinkPeerRenameSaved(alias),
    );
  }

  /// 撤销那一发的结论。⚠ `revoked:false` 走的是**成功**那一路：撤销是幂等的
  /// （契约 `clientEvents.pairRevoke._why`），把它显示成失败会让人再点一次，而那一行一直在。
  String _peerRevokeText(
    AppLocalizations l10n,
    ({FnthinkPeer peer, FnthinkPeerRevoke revoke}) entry,
  ) {
    final revoke = entry.revoke;
    if (!revoke.ok) {
      return l10n.fnthinkRevokeFailed(revoke.reason ?? 'no-revoke');
    }
    final skipped = revoke.skipped;
    if (skipped == FnthinkPeerRemoveSkip.storeUnavailable) {
      return l10n.fnthinkRevokeStoreUnavailable;
    }
    if (skipped == FnthinkPeerRemoveSkip.removeFailed) {
      return l10n.fnthinkRevokeRowRemains;
    }
    final peer = entry.peer.peerAddress;
    if (revoke.result.revoked != true) {
      return l10n.fnthinkRevokeAlreadyGone(peer);
    }
    return l10n.fnthinkRevoked(peer);
  }

  /// 发一条给名单里那一台（T98 片④：从弹层换成一张页）。
  ///
  /// 这一格**只负责把那一台带过去**（`preselectedPeer`），填什么、发不发、结论怎么说都在
  /// [FnthinkSendPage] 上 —— 与远程执行那一格同一个形状，两条路不再有"一边是弹层一边是页"的分裂。
  ///
  /// 两件事按本仓既有纪律摆：
  ///  - **取消 ⇒ 一个字节都不发**：这一发是 push，退出这一页（不点发送）就是取消，
  ///    本页不留任何"发过一半"的状态。
  ///  - **页面不判协议**：授权、配对、去重、时间容差都在内核与服务端判过并反证过。
  Future<void> _sendTo(FnthinkPeer peer) async {
    if (_busy) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => FnthinkSendPage(
          preselectedPeer: peer.peerAddress,
          deps: FnthinkSendDeps(
            loadPeers: _deps.loadPeers,
            send:
                ({
                  required String peer,
                  required String title,
                  required String text,
                }) => _coordinator.sendNotice(
                  peer: peer,
                  title: title,
                  text: text,
                ),
            contractOf: () async => _deps.contracts.load(),
          ),
        ),
      ),
    );
    // 回来时重读名单：那一台的名字/档位/是否还在，可能已经被对面那台的改动带变了
    // （撤销、重新同意）。不重读的话，这一页会留着进来时那一份。
    if (!mounted) return;
    await _loadPeers();
  }

  /// 「配对另一台设备」那一格（#176 片3，B 侧那发 `pair` 的唯一入口）。
  ///
  /// 三件事按本仓既有纪律摆：
  ///  - **取消 ⇒ 一个字节都不发**：弹层返回 null 就早退。这一发带走的是对端刚挂出的**一次性**口令，
  ///    把半填的表单发出去等于替用户用掉那枚口令（那边下一次挂出来的才是新的一枚）。
  ///  - **页面不判协议**：档位名单、target 能不能等于本机、成功要哪三样都在契约/内核/协调者判过，
  ///    这里只把结论翻成一句人话（唯一作者 [fnthinkPairSubmitText]）。页面自己 min(L?) 一遍的话，
  ///    封顶换档时界面还在说旧的 —— 那正是 `pairRequestableLevels` 存在的理由。
  ///  - **口令不进页面状态**：它只在这次调用里存在，`_pairSubmit` 记的是结论。
  ///
  /// 与「发一条」不同，这一发**不要求接收开关开着**（配对是接收的前置），那条判据在协调者的
  /// `requireEnabled: false` 上，不在这里 —— 页面若自己加一个"先打开关"的判断，就会把
  /// 唯一那条"关着也能配对"的路径堵回去，而界面上看不出来。
  Future<void> _pairWithPeer({FnthinkPairingRequest? prefill}) async {
    if (_busy) return;
    final contract = _contract;
    if (contract == null) return;
    // T118 同意门：发起配对会把地址码与关系记在**那台中转机**上 ⇒ 先过门。
    // ⚠ 门在填表弹层**之前**：让用户先把地址码与那串一次性口令敲完、再被告知"先去同意"，
    //    等于白敲一遍（而口令是现读现用的东西）。
    if (!await requireFnthinkRelayConsent(
      context,
      action: AppLocalizations.of(context).fnthinkPairPeer,
    )) {
      return;
    }
    if (!mounted) return;
    final input = await showFnthinkPairDialog(
      context: context,
      contract: contract,
      prefill: prefill,
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    final result = await _coordinator.pairWithDevice(
      targetAddressCode: input.target,
      pairingCode: input.code,
      level: input.level,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pairSubmit = result;
    });
    // T126：发起那一发的结论同样要当场看得见。⚠ 这句**不重读名单**（下面那条理由留着），
    // 但弹层要说清"这一发做成了、接下来等对面点"，否则"发过去了"会被读成"已经配上了"。
    await showFnthinkOutcome(
      context,
      ok: result.ok,
      detail: fnthinkPairSubmitText(AppLocalizations.of(context), result),
    );
    // 提交成不成都不重读名单：这一发**不会**让本机名单多出任何东西（要等对方点同意，
    // 而那一下由后台那一轮带回来）。在这里 `_loadPeers()` 的话，界面就会把"还没人同意"
    // 显示成刚刷新过的样子，像是这一发已经结了。
  }

  /// 处理"点开的那条配对链接"带进来的那一份（#176 片4）。
  ///
  /// 三条都在这里，理由各不相同：
  ///  - **一次进入只处理一次**（`_pairLinkHandled`）：口令是 singleUse 的，重放不是"再试一次"，
  ///    而是把同一枚口令往"被人再看一眼"的方向推；`didUpdateWidget` 因此**不**重放。
  ///  - **判不过要说一句**（`_pairLinkRejected`），且只说同一句：用户确实点了一条链接，
  ///    "点了没反应"正是这片要修的那个缺陷的形状；而分辨"是前缀不对还是口令形状不对"，
  ///    对着一台自己的设备没有风险、对着一份抄来的链接就是枚举器 —— 所以原因不进界面。
  ///  - **契约没就位就不开弹层**：档位那一排从 `_contract` 读（`pairRequestableLevels`），
  ///    没契约的弹层只能摆一个猜出来的档位，而那一发是要签出去的。
  Future<void> _consumePairLink() async {
    final link = widget.pairLink;
    if (link == null || _pairLinkHandled) return;
    _pairLinkHandled = true;
    final contract = _contract;
    if (!mounted) return;
    if (!link.accepted || link.request == null || contract == null) {
      setState(() => _pairLinkRejected = true);
      return;
    }
    await _pairWithPeer(prefill: link.request);
  }
}
