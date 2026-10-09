import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import '../services/channel_display.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_l2_actions.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_remote_action_labels.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/help_note_button.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/primary_action_button.dart';

/// 「发一条」那两档收成一张页（T98 片④）。
///
/// ## 为什么是一张页而不是两件事
/// 这一路原来有**两个形状**：名单行与收件详情走一枚弹层（只有标题＋正文），远程执行那一格走
/// 一张 492 行的页（档位／动作／参数／凭据）。可它们是同一条出站路的两个档 —— 载荷不同，
/// 而签名、能力判定、去重、时间容差、回执、健康度**全共用协调者那一发**。分成两件的下场是：
/// 从名单进去的人根本不知道还有指令那一档，从远程页进去的人以为发一条也得填凭据。
///
/// ## 两档走的仍是既有那一发，不新开通路
/// 都不是第二条 HTTP 路：两档都经 [FnthinkReceiveCoordinator.sendNotice]（指令档是把
/// [RemoteCommandEnvelope] 编成 `text` 走）—— 那一发仍然被签名、仍被服务端按能力判、
/// 仍记送达健康度。多开一条通路的下场是"两条路的权限判定不一样"，而权限判定只有契约一份。
///
/// ## 界面不判协议
/// 这一页判的都只是**界面形状**：那一档在不在词表里、契约点名要参数的动作有没有参数、
/// 该档要不要凭据（直接读契约与 [levelNeedsAuth]）。真执行时对面那台还会再判一遍 ——
/// 本页的判只是"别让人填完才发现发不出去"。
class FnthinkSendPage extends StatefulWidget {
  const FnthinkSendPage({
    super.key,
    required this.deps,
    this.preselectedPeer,
    this.prefillTitle = '',
    this.prefillBody = '',
    this.initialTier = FnthinkSendTier.notice,
  });

  final FnthinkSendDeps deps;

  /// 从哪一行进来的那一台（名单行 / 收件详情的发送方）。null = 进来自己挑。
  ///
  /// 它只是**预选**：那一台仍在名单里被高亮、也仍可换 —— 这一页三个入口共用，
  /// 把对端锁死会让"从收件详情进来才发现想发给另一台"只能退出去重走一遍。
  final String? preselectedPeer;

  /// 「回复／重发」预填的那两格（重发＝原文；回复＝只给标题、正文留空 ⇒ 主操作是灰的）。
  final String prefillTitle;
  final String prefillBody;

  /// 远程执行那一格进来时停在指令档；其余入口停在纯文本档。
  final FnthinkSendTier initialTier;

  @override
  State<FnthinkSendPage> createState() => _FnthinkSendPageState();
}

/// 这一页要碰的三样（原来的 `RemoteSendDeps`，现在两档共用）。
class FnthinkSendDeps {
  const FnthinkSendDeps({
    required this.loadPeers,
    required this.send,
    required this.contractOf,
  });

  /// 名单**只**从读咽喉取（页面不自己排、也不自己读库）。
  final Future<List<FnthinkPeer>> Function() loadPeers;

  /// 那一发。两档同形，只是 `text` 里装的东西不同。
  final Future<FnthinkSendResult> Function({
    required String peer,
    required String title,
    required String text,
  })
  send;

  /// 契约（异步读）。只有指令档需要它 —— 但**进来就读**：档位那一排要当场说得出
  /// "指令档为什么进不去"，等人点下去才发现是另一回事。
  final Future<FnthinkContract> Function() contractOf;
}

/// 两档。枚举而不是布尔：加第三档（比如带附件的那一路）时这里要一起想清楚。
enum FnthinkSendTier { notice, command }

class _FnthinkSendPageState extends State<FnthinkSendPage> {
  FnthinkContract? _contract;
  String? _contractError;

  List<FnthinkPeer>? _peers;

  /// 选中那一台的**地址码**（不是整行记录）。
  ///
  /// 为什么不是 `FnthinkPeer`：三个入口里，收件详情那一路只知道地址（那一行的整条记录
  /// 是它自己从名单里查出来的），而发送那一发要的也只是地址 —— 公钥、档位由协调者按地址
  /// 去库里取。页面存整行记录的话，就得替名单那次读负责，读失败时连"发给谁"都一起丢了。
  late String? _peerAddress = widget.preselectedPeer;

  late FnthinkSendTier _tier = widget.initialTier;

  late final TextEditingController _title = TextEditingController(
    text: widget.prefillTitle,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.prefillBody,
  );

  String _level = '';
  String _item = '';
  final TextEditingController _argument = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _totp = TextEditingController();

  /// `channel:toggle` 那一条的另两段（T124 A 片：参数由界面生成，不让人手敲冒号串）。
  ///
  /// 族与目标值**只可能是选出来的**（族表在 `kFnthinkRemoteChannelFamilies`，
  /// 目标值是 `on`／`off` 两枚 chip）；只有对面那台的通道号还得自己填 ——
  /// 本机看不见那台的清单，那一格旁边就写着这件事。
  String? _channelFamily;
  bool? _channelWant;

  /// L3 那两个 `toggle` 项要设成的那一档（null = 没选）。
  ///
  /// ⚠ 发送侧**必填**：契约说 `itemMayCarryTarget` 是"可选"，那是为了老对端不必升级；
  /// 不带目标值的 item 落到对面就是"读当前再翻"，而投递是 at-least-once ⇒ 重投一次回到原状。
  /// 新界面不该产出一种自己知道不幂等的形状。
  bool? _l3Want;

  /// 挡住的那句（**发之前**）：画在页面最上面。
  String? _block;

  /// 那一发的结论（发之后）：画在提交那一格底下。两者分开是因为下一步动作不同 ——
  /// "去把参数填上"与"去对面那台看看为什么没接"不是同一件事。
  String? _note;
  bool _sent = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _argument.dispose();
    _key.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadPeers();
    final contract = await _loadContract();
    if (!mounted) return;
    setState(() {
      if (contract != null && contract.capabilityLevels.isNotEmpty) {
        // 默认那一档 = 词表里**最低**的那一档（不是写死 L1）：契约改了级别序，
        // 写死 L1 会让用户第一次进来就落在一个也许已经不存在的那一档上。
        _level = contract.capabilityLevels.first;
      }
      // 指令档没有契约就进不去 ⇒ 停在纯文本档，而不是画一张填不动的表单。
      if (_tier == FnthinkSendTier.command && contract == null) {
        _tier = FnthinkSendTier.notice;
      }
    });
  }

  Future<void> _loadPeers() async {
    try {
      final rows = await widget.deps.loadPeers();
      if (mounted) setState(() => _peers = rows);
    } catch (_) {
      // 读失败与"真的没有"是两句（`_peers == null` 才是读失败），不许糊成空名单。
      if (mounted) setState(() => _peers = null);
    }
  }

  Future<FnthinkContract?> _loadContract() async {
    try {
      final contract = await widget.deps.contractOf();
      if (mounted) setState(() => _contract = contract);
      return contract;
    } on FnthinkContractUnavailable catch (e) {
      if (mounted) setState(() => _contractError = e.reason);
      return null;
    } catch (e) {
      if (mounted) setState(() => _contractError = '$e');
      return null;
    }
  }

  /// 这一档**能发**的动作（词表从契约来，页面不写死任何一个动作名）。
  List<String> _actionsFor(FnthinkContract contract, String level) {
    if (level == 'L1') {
      // L1 无凭据、无逐条勾选：可做的与 L2 同源（执行时对面那台按自己的清单判）。
      return [...contract.l2Actions, ...contract.l3Settings.keys];
    }
    if (level == 'L2') return contract.l2Actions;
    return contract.l3Settings.keys.toList();
  }

  bool _needsArgument(FnthinkContract contract, String level) {
    if (level == 'L3') return false;
    return contract.l2ActionsRequiringArgument.contains(_item);
  }

  /// 这一项是 L3 里那两个 `toggle` 吗（要选"设成哪一档"）。
  ///
  /// 判据来自契约的 `mode`（`grant` 那四项只能"请用户去系统里开"，没有目标值这一说）。
  bool _needsL3Target(FnthinkContract contract) =>
      _level == 'L3' && (contract.l3Settings[_item]?.isToggle ?? false);

  bool _needsCredential(FnthinkContract contract) =>
      levelNeedsAuth(contract, _level);

  /// 交给对面的那两格：**界面选的东西在这里拼成协议形状**（唯一作者是
  /// [buildChannelArgument] 与 [buildL3Item]，本页不自己拼字符串）。
  String get _wireItem {
    if (!_needsL3Target(_contract!)) return _item;
    return buildL3Item(key: _item, want: _l3Want);
  }

  String get _wireArgument {
    if (!_needsArgument(_contract!, _level)) return '';
    return buildChannelArgument(
      family: _channelFamily ?? kFnthinkRemoteChannelFamilies.first,
      id: _argument.text.trim(),
      enabled: _channelWant ?? false,
    );
  }

  /// 发出之前那一发的本地校验。**回 null = 可以发**；回一句 = 为什么不发。
  String? _commandBlocked(FnthinkContract contract) {
    final l10n = AppLocalizations.of(context);
    if (_peerAddress == null) return l10n.fnthinkSendNeedsPeer;
    if (!contract.capabilityLevels.contains(_level)) {
      return l10n.remoteSendLevelUnknown(_level);
    }
    if (_item.isEmpty) return l10n.remoteSendAction;
    if (_needsArgument(contract, _level)) {
      if (_channelFamily == null) return l10n.remoteSendNeedsFamily;
      // 号空着沿用那一句旧话（"这一项要一个参数（目标通道标识）"）：它说的就是这件事。
      if (_argument.text.trim().isEmpty) return l10n.remoteSendNeedsArgument;
      if (_channelWant == null) return l10n.remoteSendNeedsWant;
    }
    if (_needsL3Target(contract) && _l3Want == null) {
      return l10n.remoteSendNeedsWant;
    }
    if (_needsCredential(contract) &&
        _key.text.trim().isEmpty &&
        _totp.text.trim().isEmpty) {
      return l10n.remoteSendNeedsCredential;
    }
    return null;
  }

  /// 纯文本那一档。
  ///
  /// 为什么**这里**还拦一次空正文（主操作本来就是灰的）：空正文发出去，那边只会收到一句空话，
  /// 而回执照样是"送达"—— 那正是"不静默丢、也不无谓留"那条不变量不想看到的形状。
  /// 这条判据从弹层那一版就在这儿，换了一张页而已：两处判同一件事，早晚有一处改了另一处没改。
  Future<void> _sendNotice() async {
    final peer = _peerAddress;
    if (peer == null || _busy) return;
    if (_body.text.trim().isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _block = null;
      _note = null;
      _sent = false;
    });
    final result = await widget.deps.send(
      peer: peer,
      title: _title.text,
      text: _body.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = result.status == FnthinkSendStatus.accepted;
      _note = fnthinkSendResultText(l10n, result);
    });
  }

  /// 远程指令那一档：载荷编成 [RemoteCommandEnvelope] 之后走**同一发**。
  Future<void> _sendCommand() async {
    final contract = _contract;
    if (contract == null || _busy) return;
    // ⚠ **先算"为什么发不出去"，再判有没有对端**：早退放在判据之前的话，
    //   "没选中对端"这一档就一个字都不说 —— 而用户刚按了那个按钮。
    final blocked = _commandBlocked(contract);
    if (blocked != null) {
      setState(() => _block = blocked);
      return;
    }
    final peer = _peerAddress;
    if (peer == null) return;
    final l10n = AppLocalizations.of(context);
    // 这一发会**带走刚填的凭据**，所以先过二次确认 —— 与 T06「删除一律二次确认」
    // 同一条纪律的另一面：不可撤的动作都要问一次。
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.remoteSendSubmit,
      message: l10n.remoteSendCancelNote,
      confirmText: l10n.remoteSendSubmit,
    );
    if (!ok || !mounted) return;
    final wire = RemoteCommandEnvelope.encode(
      level: _level,
      item: _wireItem,
      argument: _wireArgument,
      key: _key.text.trim(),
      totpCode: _totp.text.trim(),
    );
    setState(() {
      _busy = true;
      _block = null;
      _note = null;
      _sent = false;
    });
    final result = await widget.deps.send(
      peer: peer,
      // ⚠ 标题留空：指令没有标题/正文这个划分，而空标题在标题信封那边是"不套信封"
      //   （见 FnthinkTitleEnvelope 的注释）—— 套一个空标题会给收件端留一个
      //   「有信封而标题为空」的形状，而那与「这条本来没有标题」不可区分。
      title: '',
      text: wire,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = result.status == FnthinkSendStatus.accepted;
      _note = _sent
          ? l10n.remoteSendStartedNote
          : l10n.remoteSendFailed(result.reason ?? result.status.name);
      if (_sent) {
        // 发成之后**立刻清掉凭据输入框**：这一页不该留着别人的密钥等人回头再看。
        // （想再发一条就重新填 —— 这是有意的代价，不是顺手加的。）
        _key.clear();
        _totp.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.fnthinkPeerSend)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _tierCard(l10n),
          const SizedBox(height: 12),
          // ⚠ 挡住的那句在**最上面**（不是提交那一格底下）：ListView 是懒布局，提交键常常在
          //   视口之外 —— 用户按了它、什么也没发生，而"为什么"在屏幕外。那是这一页最不能
          //   出现的形状（"点了没反应"）。
          if (_block != null)
            FnthinkNote(keyName: 'fnthink-send-blocked', text: _block!),
          _peerCard(l10n),
          const SizedBox(height: 12),
          if (_tier == FnthinkSendTier.notice)
            _noticeCard(l10n)
          else if (_contract != null) ...[
            _levelCard(l10n),
            const SizedBox(height: 12),
            _actionCard(l10n),
            const SizedBox(height: 12),
            _commandSubmitCard(l10n),
          ],
        ],
      ),
    );
  }

  /// 档位那一排：两档是**同一条出发送的两副载荷**，所以并排给，而不是藏在两个入口里。
  Widget _tierCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.fnthinkSendTierLabel,
      children: [
        Row(
          children: [
            Expanded(
              child: FnthinkChoiceChip(
                keyName: 'fnthink-send-tier-notice',
                label: l10n.fnthinkSendTierNotice,
                selected: _tier == FnthinkSendTier.notice,
                onTap: () => _pickTier(FnthinkSendTier.notice),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              // 契约读不到时这一档灰掉并说原因（不是藏起来：藏起来用户以为这一页没这功能）。
              child: FnthinkChoiceChip(
                keyName: 'fnthink-send-tier-command',
                label: l10n.fnthinkSendTierCommand,
                selected: _tier == FnthinkSendTier.command,
                onTap: _contract == null
                    ? null
                    : () => _pickTier(FnthinkSendTier.command),
              ),
            ),
          ],
        ),
        FnthinkNote(
          keyName: 'fnthink-send-tier-note',
          text: l10n.fnthinkSendTierNote,
        ),
        if (_contractError != null)
          FnthinkNote(
            keyName: 'remote-send-contract-error',
            text: l10n.fnthinkContractUnavailable(_contractError!),
          ),
      ],
    );
  }

  void _pickTier(FnthinkSendTier tier) {
    if (_tier == tier) return;
    setState(() {
      _tier = tier;
      _block = null;
      _note = null;
      _sent = false;
    });
  }

  Widget _peerCard(AppLocalizations l10n) {
    final rows = _peers;
    return FnthinkCard(
      title: l10n.remoteSendPickPeer,
      children: [
        if (rows == null)
          FnthinkNote(
            keyName: 'remote-send-peers-unknown',
            text: l10n.remotePeersReadFailed,
          )
        else if (rows.isEmpty)
          // ⚠ 「还没有配对过任何设备」与「读不出来」是两句：名单空着不是"你可以随便填个地址"。
          FnthinkNote(
            keyName: 'remote-send-peers-empty',
            text: l10n.remoteHistoryEmpty,
          )
        else
          for (final peer in rows)
            Align(
              alignment: Alignment.centerLeft,
              // T108 片②：这一排原来是裸文字（选中只有一点点字重差），
              // 换成公共的选择件 ⇒ "选上没有"在屏上读得出来。key 一字节没动。
              child: FnthinkChoiceChip(
                keyName: 'remote-send-peer-${peer.peerAddress}',
                label: peer.peerAddress,
                selected: peer.peerAddress == _peerAddress,
                onTap: _busy
                    ? null
                    : () => setState(() => _peerAddress = peer.peerAddress),
              ),
            ),
      ],
    );
  }

  Widget _noticeCard(AppLocalizations l10n) {
    final empty = _body.text.trim().isEmpty;
    return FnthinkCard(
      title: l10n.fnthinkSendSheetTitle(_peerAddress ?? '—'),
      children: [
        CupertinoTextField(
          key: const ValueKey('fnthink-send-title'),
          controller: _title,
          placeholder: l10n.fnthinkSendTitleHint,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        CupertinoTextField(
          key: const ValueKey('fnthink-send-body'),
          controller: _body,
          placeholder: l10n.fnthinkSendBodyHint,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        // 这两句讲的是"这一路与端点那一路哪里不一样"，用户是在填内容时才需要知道它 ——
        // 发完之后再告诉他，他已经点过发送了。成段的那句（标题走正文信封）按 T100 的规矩
        // 收进右上角问号，界面上只留这一行短说。
        HelpNoteRow(
          noteKey: 'fnthink-send-boundary',
          helpKey: 'fnthink-send-envelope-help',
          text: l10n.fnthinkSendBoundary,
          helpTitle: l10n.fnthinkSendEnvelopeHelpTitle,
          helpBody: l10n.fnthinkSendEnvelopeNote,
        ),
        const SizedBox(height: 10),
        PrimaryActionButton(
          key: const ValueKey('fnthink-send-submit'),
          // 空正文时主操作**不藏、不换名、只置灰**，并把"为什么"写在键上（这一族的规矩）。
          label: empty ? l10n.fnthinkSendEmptyBody : l10n.fnthinkSendSubmit,
          subtitle: _peerAddress == null ? l10n.fnthinkSendNeedsPeer : null,
          onPressed: _busy || empty || _peerAddress == null
              ? null
              : _sendNotice,
        ),
        if (_note != null)
          FnthinkNote(keyName: 'fnthink-send-note', text: _note!),
      ],
    );
  }

  Widget _levelCard(AppLocalizations l10n) {
    final contract = _contract!;
    return FnthinkCard(
      title: l10n.remoteSendLevel,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final level in contract.capabilityLevels)
              FnthinkChoiceChip(
                keyName: 'remote-send-level-$level',
                label: level,
                selected: _level == level,
                // 换档时把那一档用不上的动作摘掉：留着上一个档的动作名，
                // 用户会发出一条对方那边压根没有的项。
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _level = level;
                        _item = '';
                      }),
              ),
          ],
        ),
        FnthinkNote(
          keyName: 'remote-send-level-desc',
          text: switch (_level) {
            'L2' => l10n.remoteSendLevelL2,
            'L3' => l10n.remoteSendLevelL3,
            _ => l10n.remoteSendLevelL1,
          },
        ),
      ],
    );
  }

  Widget _actionCard(AppLocalizations l10n) {
    final contract = _contract!;
    final actions = _actionsFor(contract, _level);
    final needsArgument = _item.isNotEmpty && _needsArgument(contract, _level);
    final needsL3Target = _item.isNotEmpty && _needsL3Target(contract);
    return FnthinkCard(
      title: l10n.remoteSendAction,
      children: [
        if (actions.isEmpty)
          FnthinkNote(keyName: 'remote-send-actions-empty', text: l10n.unknown)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in actions)
                FnthinkChoiceChip(
                  // key 里仍是契约那个动作名（闸门的路线认它），画出来的换成人话。
                  keyName: 'remote-send-action-$action',
                  label: fnthinkRemoteActionLabel(l10n, action),
                  selected: _item == action,
                  // 换一项时把上一项选的目标档摘掉：留着会拼出一条"用户没选过"的指令。
                  onTap: _busy
                      ? null
                      : () => setState(() {
                          _item = action;
                          _l3Want = null;
                          _channelWant = null;
                        }),
                ),
            ],
          ),
        if (needsArgument) ..._channelArgumentRows(l10n),
        if (needsL3Target) ...[
          const SizedBox(height: 10),
          _wantRow(
            l10n,
            value: _l3Want,
            onKey: 'remote-send-l3-want-on',
            offKey: 'remote-send-l3-want-off',
            onChanged: (v) => setState(() => _l3Want = v),
          ),
        ],
        const SizedBox(height: 8),
        // 凭据那两格**按契约说要不要**显示，不按档位写死（原来是"L1 不给、L2/L3 都给"）：
        // 契约若哪天说 L2 不必带凭据，画两格空输入框就是在暗示"这里要填点什么"。
        if (_needsCredential(contract)) ...[
          FnthinkNote(
            keyName: 'remote-send-key-label',
            text: l10n.remoteSendKeyRequired,
          ),
          CupertinoTextField(
            key: const ValueKey('remote-send-key'),
            controller: _key,
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 8),
          FnthinkNote(
            keyName: 'remote-send-totp-label',
            text: l10n.remoteSendTotpRequired,
          ),
          CupertinoTextField(
            key: const ValueKey('remote-send-totp'),
            controller: _totp,
            keyboardType: TextInputType.number,
            autocorrect: false,
          ),
        ],
      ],
    );
  }

  /// `channel:toggle` 那三段的选法：族（选）＋ 对面那台的通道号（填）＋ 目标档（选）。
  List<Widget> _channelArgumentRows(AppLocalizations l10n) {
    return [
      const SizedBox(height: 10),
      FnthinkNote(
        keyName: 'remote-send-family-label',
        text: l10n.remoteSendFamilyLabel,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final family in kFnthinkRemoteChannelFamilies)
            FnthinkChoiceChip(
              keyName: 'remote-send-family-$family',
              label: channelFamilyName(family),
              selected: (_channelFamily ?? _defaultFamily) == family,
              onTap: _busy
                  ? null
                  : () => setState(() => _channelFamily = family),
            ),
        ],
      ),
      const SizedBox(height: 10),
      FnthinkNote(
        keyName: 'remote-send-arg-label',
        text: l10n.remoteSendArgument,
      ),
      CupertinoTextField(
        key: const ValueKey('remote-send-argument'),
        controller: _argument,
        placeholder: l10n.remoteSendArgument,
        autocorrect: false,
      ),
      FnthinkNote(
        keyName: 'remote-send-channel-id-why',
        text: l10n.remoteSendChannelIdWhy,
      ),
      const SizedBox(height: 10),
      _wantRow(
        l10n,
        value: _channelWant,
        onKey: 'remote-send-want-on',
        offKey: 'remote-send-want-off',
        onChanged: (v) => setState(() => _channelWant = v),
      ),
    ];
  }

  /// 「设成开着／设成关掉」那一排。两枚而不是一枚"翻"：重投会翻两次（见 [buildL3Item]）。
  Widget _wantRow(
    AppLocalizations l10n, {
    required bool? value,
    required String onKey,
    required String offKey,
    required ValueChanged<bool> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FnthinkChoiceChip(
          keyName: onKey,
          label: l10n.remoteSendWantOn,
          selected: value == true,
          onTap: _busy ? null : () => onChanged(true),
        ),
        FnthinkChoiceChip(
          keyName: offKey,
          label: l10n.remoteSendWantOff,
          selected: value == false,
          onTap: _busy ? null : () => onChanged(false),
        ),
      ],
    );
  }

  String get _defaultFamily => kFnthinkRemoteChannelFamilies.first;

  Widget _commandSubmitCard(AppLocalizations l10n) {
    return FnthinkCard(
      title: l10n.remoteSendSubmit,
      children: [
        FnthinkNote(
          keyName: 'remote-send-cancel-note',
          text: l10n.remoteSendCancelNote,
        ),
        PrimaryActionButton(
          key: const ValueKey('remote-send-submit'),
          label: l10n.remoteSendSubmit,
          subtitle: _peerAddress == null ? l10n.fnthinkSendNeedsPeer : null,
          onPressed: _busy ? null : _sendCommand,
        ),
        // ⚠ 已发出/被拒那句留在这底下（"我刚做成了什么"离那个按钮近）；
        //   而"为什么发不出去"（还没填齐）在页面最上面 —— 两者位置不同是刻意的。
        if (_note != null)
          FnthinkNote(keyName: 'remote-send-note', text: _note!),
      ],
    );
  }
}

/// 这一档要不要凭据（**唯一出处**：契约 `auth.l2Requires` / `l3Requires`）。
bool levelNeedsAuth(FnthinkContract contract, String level) {
  if (level == 'L3') return contract.remoteExecutionL3RequiresAuth;
  if (level == 'L2') return contract.remoteExecutionL2RequiresAuth;
  return false;
}

/// 发送结论那一句的原话。**全仓唯一一处**：每一档状态说的都是"用户下一步做什么"，
/// 折叠成一句"发送失败"就是让他去点第二下。
String fnthinkSendResultText(AppLocalizations l10n, FnthinkSendResult result) {
  final base = switch (result.status) {
    FnthinkSendStatus.accepted => l10n.fnthinkSendSent(result.messageId ?? ''),
    FnthinkSendStatus.rejectedUnsigned => l10n.fnthinkSendRejectedUnsigned,
    FnthinkSendStatus.rejectedCapability => l10n.fnthinkSendRejectedCapability,
    FnthinkSendStatus.replayed => l10n.fnthinkSendReplayed,
    FnthinkSendStatus.needsCalibration => l10n.fnthinkSendNeedsCalibration,
    FnthinkSendStatus.rateLimited => l10n.fnthinkSendRateLimited(
      result.retryAfterSeconds ?? 0,
    ),
    FnthinkSendStatus.transportError => l10n.fnthinkSendTransportError,
    FnthinkSendStatus.signingUnavailable => l10n.fnthinkSendSigningUnavailable,
    FnthinkSendStatus.preconditionFailed => l10n.fnthinkSendPrecondition(
      result.reason ?? '',
    ),
    FnthinkSendStatus.badInput => l10n.fnthinkSendBadInput,
    FnthinkSendStatus.unparseable => l10n.fnthinkSendUnparseable,
  };
  // 挤位那句话只在真挤掉过东西时才出现。发送端是唯一能看见这件事的地方 ——
  // 服务端那边各条已写了 dropped 回执，但那要等下一次 poll 才看得见。
  if (result.status == FnthinkSendStatus.accepted &&
      result.evicted.isNotEmpty) {
    return '$base ${l10n.fnthinkSendEvicted(result.evicted.length)}';
  }
  return base;
}
