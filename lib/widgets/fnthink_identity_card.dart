import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_credential_store.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_pairing_ack.dart';
import '../services/fnthink_pairing_lifecycle.dart';
import '../theme/app_colors.dart';
import 'fnthink_card.dart';
import 'fnthink_outcome.dart';
import 'primary_action_button.dart';

/// 身份卡的一次**现读**结果（T214）。
///
/// 两页（设置 / 配对）都挂同一张卡，但"这一台此刻是什么"的读法只有一处：
/// [loadFnthinkIdentitySnapshot]。卡自己不缓存来源，每次动作后重取一次。
typedef FnthinkIdentitySnapshot = ({
  String? addressCode,
  FnthinkArmedPairingCode? pairing,
  bool pairingConsumed,
  FnthinkDeviceIdentity? identity,
  String? credentialError,
});

/// 「本机身份」那一格：地址码 / 一次性配对口令 / 身份密钥（T214 抽出共享件）。
///
/// ⚠ 这张卡**不持有**任何真值：所有读数由宿主注入的 [load] 现取（不是打开页面那一刻
/// 冻住的快照 —— `permission_settings_page.dart` 那条既有纪律），动作也只是把"要做的事"
/// 交给宿主的 [onArm] / [onPublish] / [onRevoke] / [onResetAddress]。
/// 两页是独立路由、不同屏 ⇒ 不会同屏两份读数打架。
///
/// 动作档按页裁剪：配对页只给「挂出／重新生成」与「复制」——撤销口令与重置地址码是管理动作，
/// 留在设置页（destructive 一枚不在两处摆）。
class FnthinkIdentityCard extends StatefulWidget {
  const FnthinkIdentityCard({
    super.key,
    required this.load,
    required this.onArm,
    required this.onPublish,
    this.onRevoke,
    this.onResetAddress,
    this.note,
  });

  /// 现读一次本机身份。调用方传"去取一次"这件事，不是取好的那一份。
  final Future<FnthinkIdentitySnapshot> Function() load;

  /// 本机挂一枚新口令（并补齐地址码）。抛 [FnthinkCredentialCorrupted] 时卡上会显示原话。
  final Future<FnthinkArmedPairingCode?> Function() onArm;

  /// 把刚挂出的口令交给服务器；结论决定卡上那三态之一，也决定当场弹哪一句。
  final Future<({bool ok, String? reason})> Function(String code) onPublish;

  /// 撤销口令（只在设置页提供）。null = 这一页不给这一枚。
  final Future<void> Function()? onRevoke;

  /// 重置地址码（只在设置页提供；确认框由宿主那一侧负责）。
  final Future<void> Function()? onResetAddress;

  /// 卡片末尾追加的一句（配对页「对面要的就是这两样」）。null = 不加。
  final String? note;

  @override
  State<FnthinkIdentityCard> createState() => _FnthinkIdentityCardState();
}

class _FnthinkIdentityCardState extends State<FnthinkIdentityCard> {
  FnthinkIdentitySnapshot? _snapshot;
  bool _busy = false;

  /// 最近一次挂出后问服务器得到的结论，**连同它是哪一枚口令的结论**一起记：
  /// 只记 bool 的话，重新挂一枚时上一枚的"服务器已收到"会跟着新口令显示（那是第二份谎）。
  String? _ackedCode;
  bool? _acked;
  String? _publishNote;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final snapshot = await widget.load();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } on FnthinkCredentialCorrupted catch (e) {
      // 存量与契约对不上是**要人来处理**的状态：显示原话，不自动换一枚。
      if (!mounted) return;
      setState(() {
        _snapshot = (
          addressCode: _snapshot?.addressCode,
          pairing: _snapshot?.pairing,
          pairingConsumed: _snapshot?.pairingConsumed ?? false,
          identity: _snapshot?.identity,
          credentialError: e.reason,
        );
      });
    }
  }

  Future<void> _arm() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    FnthinkArmedPairingCode? armed;
    try {
      armed = await widget.onArm();
    } on FnthinkCredentialCorrupted catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshot = (
          addressCode: _snapshot?.addressCode,
          pairing: _snapshot?.pairing,
          pairingConsumed: _snapshot?.pairingConsumed ?? false,
          identity: _snapshot?.identity,
          credentialError: e.reason,
        );
        _busy = false;
      });
      return;
    }
    if (!mounted) return;
    if (armed == null) {
      setState(() => _busy = false);
      await _reload();
      return;
    }
    final result = await widget.onPublish(armed.code.value);
    if (!mounted) return;
    final acked = result.ok;
    final note = result.ok ? null : (result.reason ?? 'no-answer');
    setState(() {
      _ackedCode = armed!.code.value;
      _acked = acked;
      _publishNote = note;
      _busy = false;
    });
    // 本机那一份也要重取：地址码可能刚被补齐，倒计时的起点也换了。
    await _reload();
    if (!mounted) return;
    // T126 片2：这一发是"当场要看得见"最典型的一处 —— 口令没上到服务器时，对端扫码只会
    // 拿到"口令不存在"，而屏幕上写着"已挂出 5 分钟"。格子那三态留着，这里补一次弹层，
    // 句子与格子**同一个作者**（`fnthinkPairingAckText`）。
    await showFnthinkOutcome(
      context,
      ok: acked,
      detail: fnthinkPairingAckText(
        AppLocalizations.of(context),
        acked: acked,
        note: note,
      ),
    );
  }

  Future<void> _revoke() async {
    final revoke = widget.onRevoke;
    if (revoke == null || _busy || !mounted) return;
    setState(() => _busy = true);
    await revoke();
    if (!mounted) return;
    setState(() {
      _ackedCode = null;
      _acked = null;
      _publishNote = null;
      _busy = false;
    });
    await _reload();
  }

  Future<void> _resetAddress() async {
    final reset = widget.onResetAddress;
    if (reset == null || _busy || !mounted) return;
    setState(() => _busy = true);
    await reset();
    if (!mounted) return;
    setState(() => _busy = false);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = _snapshot;
    // 第一次读回来之前只画空壳：宁可少画一帧，也不拿"没生成地址码"这句凭空的话当读数。
    if (snapshot == null) return const SizedBox.shrink();
    final code = snapshot.addressCode;
    final pairing = snapshot.pairing;
    final lifecycle = pairing == null ? null : _lifecycle(pairing, snapshot);
    return FnthinkCard(
      title: l10n.fnthinkIdentitySection,
      children: [
        FnthinkRowLabel(
          label: l10n.fnthinkAddressCode,
          keyName: 'fnthink-address-code',
        ),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                code ?? l10n.fnthinkAddressCodeNone,
                key: const ValueKey('fnthink-address-code-value'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (code != null)
              FnthinkInlineAction(
                label: l10n.fnthinkCopy,
                tone: FnthinkActionTone.neutral,
                onPressed: () => fnthinkCopyNotice(context, code),
              ),
            if (widget.onResetAddress != null)
              FnthinkInlineAction(
                key: const ValueKey('fnthink-reset-code'),
                label: l10n.fnthinkResetCode,
                tone: FnthinkActionTone.destructive,
                onPressed: code == null || _busy ? null : _resetAddress,
              ),
          ],
        ),
        const SizedBox(height: 8),
        FnthinkRowLabel(
          label: l10n.fnthinkPairingCode,
          keyName: 'fnthink-pairing-code',
        ),
        if (pairing == null)
          Text(
            l10n.fnthinkPairingNone,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryLabel(context),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  pairing.code.value,
                  key: const ValueKey('fnthink-pairing-code-value'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              FnthinkInlineAction(
                label: l10n.fnthinkCopy,
                tone: FnthinkActionTone.neutral,
                onPressed: () => fnthinkCopyNotice(context, pairing.code.value),
              ),
            ],
          ),
        if (pairing != null && lifecycle != null) ...[
          // T171：只有还看起来有效时才报「已挂出 N 秒」；过期/用过/没上到服务器
          // 再报时长会让用户以为它还有效。
          if (lifecycle == FnthinkPairingLifecycle.active ||
              lifecycle == FnthinkPairingLifecycle.unknown)
            FnthinkNote(
              keyName: 'fnthink-pairing-age',
              text: l10n.fnthinkPairingHeld(_heldSeconds(l10n, pairing)),
            ),
          FnthinkNote(
            keyName: 'fnthink-pairing-lifecycle',
            text: _lifecycleText(l10n, lifecycle),
          ),
        ],
        if (pairing != null &&
            lifecycle != null &&
            lifecycle != FnthinkPairingLifecycle.active)
          Align(
            alignment: Alignment.centerLeft,
            child: FnthinkInlineAction(
              key: const ValueKey('fnthink-pairing-regenerate'),
              label: l10n.fnthinkPairingRegenerate,
              onPressed: _busy ? null : _arm,
            ),
          ),
        if (pairing != null)
          FnthinkNote(
            keyName:
                'fnthink-pairing-${fnthinkPairingAckKey(_ackedFor(pairing))}',
            text: fnthinkPairingAckText(
              l10n,
              acked: _ackedFor(pairing),
              note: _noteFor(pairing),
            ),
          ),
        if (pairing != null && widget.onRevoke != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FnthinkInlineAction(
              key: const ValueKey('fnthink-revoke-pairing'),
              label: l10n.fnthinkRevokePairing,
              tone: FnthinkActionTone.destructive,
              onPressed: _busy ? null : _revoke,
            ),
          ),
        PrimaryActionButton(
          key: const ValueKey('fnthink-arm-pairing'),
          label: l10n.fnthinkArmPairing,
          onPressed: _busy ? null : _arm,
        ),
        Text(
          l10n.fnthinkPairingExpireNote,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondaryLabel(context),
          ),
        ),
        if (widget.note != null)
          Text(
            widget.note!,
            key: const ValueKey('fnthink-pairing-peers-hint'),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        if (snapshot.credentialError != null)
          FnthinkNote(
            keyName: 'fnthink-credential-error',
            text: snapshot.credentialError!,
          ),
        // 身份密钥那一行：两页都是"本机是谁"的一部分。配对页拿不到身份读口时也照原样
        // 显示「未知」，不替它编一把。
        const SizedBox(height: 8),
        FnthinkRowLabel(
          label: l10n.fnthinkIdentityKey,
          keyName: 'fnthink-identity-key',
        ),
        Text(
          _identityText(l10n, snapshot.identity),
          key: const ValueKey('fnthink-identity-key-value'),
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: snapshot.identity == null
                ? AppColors.red
                : AppColors.primaryLabel(context),
          ),
        ),
      ],
    );
  }

  /// 这一枚口令的服务器结论：只认与**当前口令**同一枚的那一次挂出。
  bool? _ackedFor(FnthinkArmedPairingCode pairing) =>
      _ackedCode == pairing.code.value ? _acked : null;

  String? _noteFor(FnthinkArmedPairingCode pairing) =>
      _ackedCode == pairing.code.value ? _publishNote : null;

  FnthinkPairingLifecycle _lifecycle(
    FnthinkArmedPairingCode pairing,
    FnthinkIdentitySnapshot snapshot,
  ) => fnthinkPairingLifecycleOf(
    consumed: snapshot.pairingConsumed,
    looksExpired: pairing.looksExpired(
      DateTime.now().toUtc().millisecondsSinceEpoch,
    ),
    acked: _ackedFor(pairing),
  );

  String _lifecycleText(
    AppLocalizations l10n,
    FnthinkPairingLifecycle lifecycle,
  ) => switch (lifecycle) {
    FnthinkPairingLifecycle.active => l10n.fnthinkPairingLifecycleActive,
    FnthinkPairingLifecycle.consumed => l10n.fnthinkPairingLifecycleConsumed,
    FnthinkPairingLifecycle.expired => l10n.fnthinkPairingLifecycleExpired,
    FnthinkPairingLifecycle.notPublished =>
      l10n.fnthinkPairingLifecycleNotPublished,
    FnthinkPairingLifecycle.unknown => l10n.fnthinkPairingLifecycleUnknown,
  };
}

/// 一次现读：地址码 / 口令 / 口令的"用过"标记 / 身份密钥。
///
/// 两页读同一份 —— 判据（`fnthinkPairingLifecycleOf`、`FnthinkCredentialStore` 的解析）
/// 仍各在自己的作者里，这里只负责**把它们按同一个顺序取一遍**。
Future<FnthinkIdentitySnapshot> loadFnthinkIdentitySnapshot({
  required FnthinkCredentialStore credentials,
  required Future<FnthinkDeviceIdentity?> Function() identity,
}) async {
  String? addressCode;
  FnthinkArmedPairingCode? pairing;
  String? credentialError;
  try {
    addressCode = (await credentials.storedAddressCode())?.value;
    pairing = await credentials.currentPairingCode();
  } on FnthinkCredentialCorrupted catch (e) {
    credentialError = e.reason;
  }
  final consumed = pairing == null
      ? false
      : await FnthinkPairingLifecycleStore.isConsumed();
  return (
    addressCode: addressCode,
    pairing: pairing,
    pairingConsumed: consumed,
    identity: await identity(),
    credentialError: credentialError,
  );
}

/// 「挂了多久」。时间戳缺失/不是整数时显示「未知」而不是 0 秒 ——
/// 0 秒的字面意思是"刚挂上"，那是另一个结论。
String _heldSeconds(AppLocalizations l10n, FnthinkArmedPairingCode pairing) {
  final age = pairing.ageMs(DateTime.now().toUtc().millisecondsSinceEpoch);
  if (age == null) return l10n.unknown;
  return '${(age / 1000).floor()}s';
}

/// 身份密钥那一行：公钥只留前 8 位当"是不是同一把"的比对（整串用户读不了）。
String _identityText(AppLocalizations l10n, FnthinkDeviceIdentity? identity) {
  if (identity == null) return l10n.fnthinkKeystoreUnknown;
  final backed = identity.keystoreBacked
      ? l10n.fnthinkKeystoreOn
      : l10n.fnthinkKeystoreOff;
  final key = identity.publicKey;
  final short = key.length <= 8 ? key : '${key.substring(0, 8)}…';
  return '$short · $backed';
}
