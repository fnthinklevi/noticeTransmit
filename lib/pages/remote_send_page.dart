import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../l10n/app_localizations.dart';
import '../models/fnthink_peer.dart';
import '../services/fnthink_contract_loader.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_dialog_actions.dart';

/// 「远程指令发送」页（片3b-2，维护者 2026-10-03 要求：幻念推送页内的远程指令发送页）。
///
/// ## 发送那一发走的是既有链路
/// 它**不是**新开一条 HTTP 通路，而是复用 `FnthinkReceiveCoordinator.sendNotice`：
/// 载荷（`level` / `item` / `argument` / 凭据）编成 [RemoteCommandEnvelope] 之后当 `text` 走 ——
/// 那一发仍然被签名、仍然被服务端按能力判、仍然记送达健康度。多开一条通路的下场是
/// "两条路的权限判定不一样"，而权限判定只有契约一份。
///
/// ## 界面不判协议，只把结论念出来
/// 这一页判三件事，全是**界面形状**而不是协议：
///  ① 那一档在不在词表里（不在就不给发）；
///  ② 契约点名要参数的动作有没有参数；
///  ③ 该档要不要凭据（L3 要、L2 不要）—— 三条都直接读契约与已有的 `parseL2Item`。
/// 真执行时对面那台会再判一遍；本页的判只是"别让用户填完才发现发不出去"。
class RemoteSendPage extends StatefulWidget {
  const RemoteSendPage({super.key, required this.deps});

  final RemoteSendDeps deps;

  @override
  State<RemoteSendPage> createState() => _RemoteSendPageState();
}

class RemoteSendDeps {
  const RemoteSendDeps({
    required this.loadPeers,
    required this.send,
    required this.contractOf,
  });

  /// 名单**只**从读咽喉取（与幻念推送页同一条纪律：页面不自己排也不自己读库）。
  final Future<List<FnthinkPeer>> Function() loadPeers;

  /// 那一发。签名与 `sendNotice` 同形，只是把载荷换成了编好的指令。
  final Future<FnthinkSendResult> Function({
    required String peer,
    required String title,
    required String text,
  })
  send;

  /// 契约（**异步**读：契约读不到时整页只显示一句，不给填）。
  final Future<FnthinkContract> Function() contractOf;
}

class _RemoteSendPageState extends State<RemoteSendPage> {
  FnthinkContract? _contract;
  String? _contractError;

  List<FnthinkPeer>? _peers;
  FnthinkPeer? _peer;

  String _level = 'L1';
  String _item = '';
  final TextEditingController _argument = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _totp = TextEditingController();

  /// 发出去那一发的结论。**留在页面上**而不是弹个 toast：用户回头再看一次才能确认
  /// "发出去了"与"发不出去"（两者的下一步动作完全不同）。
  String? _note;
  bool _sent = false;
  bool _busy = false;

  /// 拖动中的延时（只有拖动过程用，松手才落）。null = 没在拖。
  // 本页不管延时：那是**接收端**的设置，发送端看不见也不该改 —— 所以这里没有它。

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _argument.dispose();
    _key.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final FnthinkContract contract;
    try {
      contract = await widget.deps.contractOf();
    } on FnthinkContractUnavailable catch (e) {
      if (mounted) setState(() => _contractError = e.reason);
      return;
    }
    if (!mounted) return;
    setState(() {
      _contract = contract;
      // 默认那一档 = 词表里**最低**的一档（不是写死 L1）：契约改了级别序，
      // 写死 L1 会让用户第一次进来就落在一个也许已经不存在的那一档上。
      _level = contract.capabilityLevels.isEmpty
          ? ''
          : contract.capabilityLevels.first;
      // 那一档能做的动作：契约的 L2 动作表 ∪ L3 设置表。
      // ⚠ **只看这一档允许什么，不看用户给了对方几档** —— 后者要按逐条勾选判，
      //   而本页没有那份清单（它在对面那台的库里）。所以界面上写"能不能做由对方那台判"。
      _item = '';
    });
    await _loadPeers();
  }

  Future<void> _loadPeers() async {
    List<FnthinkPeer>? rows;
    try {
      rows = await widget.deps.loadPeers();
    } catch (_) {
      rows = null;
    }
    if (!mounted) return;
    setState(() => _peers = rows);
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

  bool _needsCredential(FnthinkContract contract) =>
      levelNeedsAuth(contract, _level);

  /// 发出之前那一发本地校验。**回 null = 可以发**；回一句 = 为什么不发。
  String? _blocked(FnthinkContract contract) {
    if (_peers?.isEmpty ?? true) {
      return AppLocalizations.of(context).remoteHistoryEmpty;
    }
    if (_peer == null) {
      return AppLocalizations.of(context).remoteSendPickPeer;
    }
    if (!_contract!.capabilityLevels.contains(_level)) {
      return AppLocalizations.of(context).remoteSendLevelUnknown(_level);
    }
    if (_item.isEmpty) {
      return AppLocalizations.of(context).remoteSendAction;
    }
    if (_needsArgument(contract, _level) && _argument.text.trim().isEmpty) {
      return AppLocalizations.of(context).remoteSendNeedsArgument;
    }
    if (_needsCredential(contract) &&
        _key.text.trim().isEmpty &&
        _totp.text.trim().isEmpty) {
      return AppLocalizations.of(context).remoteSendNeedsCredential;
    }
    return null;
  }

  Future<void> _send() async {
    final contract = _contract;
    if (contract == null || _busy) return;
    // ⚠ **先算"为什么发不出去"，再判有没有对端**：早退放在判据之前的话，
    //   "没选中对端"这一档就一个字都不说 —— 而用户刚按了那个按钮。
    //   这是本页最容易长成的形状：点一下没反应，而界面上没有任何解释。
    final blocked = _blocked(contract);
    if (blocked != null) {
      setState(() => _note = blocked);
      return;
    }
    final peer = _peer;
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
      item: _item,
      argument: _argument.text.trim(),
      key: _key.text.trim(),
      totpCode: _totp.text.trim(),
    );
    setState(() => _busy = true);
    final result = await widget.deps.send(
      peer: peer.peerAddress,
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
        // （用户想再发一条就重新填 —— 这是有意的代价，不是顺手加的。）
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
      appBar: AppBar(
        title: Text(
          l10n.remoteSendTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_contractError != null)
            _Note(
              keyName: 'remote-send-contract-error',
              text: l10n.fnthinkContractUnavailable(_contractError!),
            )
          else if (_contract == null)
            const SizedBox(height: 40)
          else ...[
            // ⚠ **挡住的那句放在最上面**（不是提交那一格底下）：ListView 是懒布局，
            //   提交键常常在视口之外，用户按了它、什么也没发生，而"为什么"在屏幕外 ——
            //   那是这一页最不能出现的形状（"点了没反应"）。
            if (_note != null && !_sent)
              _Note(keyName: 'remote-send-blocked', text: _note!),
            _buildPeerCard(l10n),
            const SizedBox(height: 12),
            _buildLevelCard(l10n),
            const SizedBox(height: 12),
            _buildActionCard(l10n),
            const SizedBox(height: 12),
            _buildSubmitCard(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildPeerCard(AppLocalizations l10n) {
    final rows = _peers;
    return _Card(
      title: l10n.remoteSendPickPeer,
      children: [
        if (rows == null)
          _Note(keyName: 'remote-send-peers-unknown', text: l10n.unknown)
        else if (rows.isEmpty)
          // ⚠ 「还没有配对过任何设备」与「读不出来」必须是两句：这里能发的对象
          //   就是名单，名单空着不是"你可以随便填个地址"。
          _Note(
            keyName: 'remote-send-peers-empty',
            text: l10n.remoteHistoryEmpty,
          )
        else
          for (final peer in rows)
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                key: ValueKey('remote-send-peer-${peer.peerAddress}'),
                onPressed: _busy ? null : () => setState(() => _peer = peer),
                child: Text(peer.peerAddress),
              ),
            ),
        if (_peer != null)
          _Note(
            keyName: 'remote-send-peer-picked',
            text: '${l10n.remoteSendPickPeer}：${_peer!.peerAddress}',
          ),
      ],
    );
  }

  Widget _buildLevelCard(AppLocalizations l10n) {
    final contract = _contract!;
    return _Card(
      title: l10n.remoteSendLevel,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final level in contract.capabilityLevels)
              CupertinoButton(
                key: ValueKey('remote-send-level-$level'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _level = level;
                        // 换档时把那一档用不上的动作摘掉：留着上一个档的动作名
                        // 会让用户发出一条对方那边压根没有的项。
                        _item = '';
                      }),
                child: Text(level),
              ),
          ],
        ),
        _Note(
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

  Widget _buildActionCard(AppLocalizations l10n) {
    final contract = _contract!;
    final actions = _actionsFor(contract, _level);
    return _Card(
      title: l10n.remoteSendAction,
      children: [
        if (actions.isEmpty)
          _Note(keyName: 'remote-send-actions-empty', text: l10n.unknown)
        else
          Wrap(
            spacing: 8,
            children: [
              for (final action in actions)
                CupertinoButton(
                  key: ValueKey('remote-send-action-$action'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _item = action),
                  child: Text(action),
                ),
            ],
          ),
        if (_item.isNotEmpty && _needsArgument(contract, _level)) ...[
          _Note(
            keyName: 'remote-send-arg-label',
            text: l10n.remoteSendArgument,
          ),
          CupertinoTextField(
            key: const ValueKey('remote-send-argument'),
            controller: _argument,
            placeholder: l10n.remoteSendArgument,
            autocorrect: false,
          ),
        ],
        const SizedBox(height: 8),
        // 凭据两格按该档**要不要**显示：L1 一格都不给（它永远不需要凭据，
        // 给一个永远空的输入框等于在暗示"这里要填点什么"）。
        if (_level != 'L1') ...[
          _Note(
            keyName: 'remote-send-key-label',
            text: _needsCredential(contract)
                ? l10n.remoteSendKeyRequired
                : l10n.remoteSendKeyOptional,
          ),
          CupertinoTextField(
            key: const ValueKey('remote-send-key'),
            controller: _key,
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 8),
          _Note(
            keyName: 'remote-send-totp-label',
            text: _needsCredential(contract)
                ? l10n.remoteSendTotpRequired
                : l10n.remoteSendTotpOptional,
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

  Widget _buildSubmitCard(AppLocalizations l10n) {
    return _Card(
      title: l10n.remoteSendSubmit,
      children: [
        _Note(
          keyName: 'remote-send-cancel-note',
          text: l10n.remoteSendCancelNote,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton.filled(
            key: const ValueKey('remote-send-submit'),
            onPressed: _busy ? null : _send,
            child: Text(l10n.remoteSendSubmit),
          ),
        ),
        // ⚠ 已发出/已发出的那句**留在提交那一格底下**（"我刚做成了什么"离那个按钮近）；
        //   而"为什么发不出去"放页面最上面（见 build 里的那一条）—— 两者的位置不同是刻意的。
        if (_note != null)
          _Note(
            keyName: 'remote-send-note',
            text: _sent ? l10n.remoteSendStartedNote : _note!,
          ),
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

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.keyName, required this.text});

  final String keyName;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        key: ValueKey(keyName),
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }
}
