import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_read_settings.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/help_note_button.dart';

/// 「可被远程读取的内容」这一页（T124 片C）。
///
/// ## 这一页答的是什么
/// 与「可被远程打开的入口」并列的一页：那一页管"对面能**打开**这台什么"，
/// 这一页管"对面能**读**这台什么"。每一项一枚开关，**默认全关**（与短信监听那一族
/// 同一条纪律；`?? false`，见 `fnthink_read_settings.dart`）。
///
/// ## 两道闸，缺一不可（这也是这一页存在的原因）
/// ① **系统权限**：这台设备"能不能读"（第一次打开时当场申请；被拒不算开）；
/// ② **本机开关**：持有者"允不允许对面读"（随时可关，关掉立即生效，不必去系统设置里找）。
/// 只有两格都过，那一条读动作才会执行（执行器先判开关、原生再审权限）。
///
/// ## 为什么开关不进备份
/// 见 `fnthink_read_settings.dart` 文件头：那是**本机对"谁可以读这台什么"的一次表态**，
/// 与远程执行凭据同一类 —— 恢复一份把它们打开的备份，等于别人替这台设备表了态。
///
/// ## 打开时的次序（用户能看见的那一半）
/// 翻到开 ⇒ **先弹系统权限框**；给了才落开。系统拒绝 ⇒ 开关回到关，并在下方说明为什么
/// （"再点一次重试，或去系统设置里打开"）—— 与权限页那枚精确闹钟同一条：
/// 没授权不许假装开着。
class FnthinkReadCapsPage extends StatefulWidget {
  const FnthinkReadCapsPage({
    super.key,
    this.loadCalls,
    this.saveCalls,
    this.requestPermission,
    this.isGranted,
  });

  /// 读写口与权限申请口（测试注入；默认走生产那两份）。
  /// ⚠ 与其余几页同一条纪律：不注入时就是生产那份，页面不自己另写一套判据。
  final Future<bool> Function()? loadCalls;
  final Future<void> Function(bool enabled)? saveCalls;
  final Future<void> Function()? requestPermission;
  final Future<bool> Function()? isGranted;

  @override
  State<FnthinkReadCapsPage> createState() => _FnthinkReadCapsPageState();
}

class _FnthinkReadCapsPageState extends State<FnthinkReadCapsPage>
    with WidgetsBindingObserver {
  /// `null` = 还没读出来（第一帧画的应当是"关"还是"空"—— 这里选**关**：
  /// 默认关是这条纪律的基数，画成空会让翻开关的判据分成两条路）。
  bool? _calls;

  /// 系统权限框正开着（等用户答复）。resumed 那一路用它决定要不要复核。
  bool _awaitingPermission = false;

  /// 权限没给成时那说明（给了就清掉）。
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 系统权限框关掉之后回到前台 —— 那一次答复到这里才收得到
    // （与权限页"从系统授权页返回后刷新"同一条路子）。
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      unawaited(_reconcileAfterPermission());
    }
  }

  Future<void> _reload() async {
    try {
      final value = await (widget.loadCalls ?? fnthinkReadCallsEnabled)();
      if (mounted) setState(() => _calls = value);
    } catch (_) {
      if (mounted) setState(() => _calls = false);
    }
  }

  Future<void> _save(bool enabled) async {
    await (widget.saveCalls ?? setFnthinkReadCallsEnabled)(enabled);
  }

  Future<void> _toggleCalls(bool value) async {
    if (!value) {
      // 关：**立即生效**，不碰权限框 —— 关掉是持有者随时该能做的一件事。
      await _save(false);
      if (mounted) {
        setState(() {
          _calls = false;
          _note = null;
          _awaitingPermission = false;
        });
      }
      return;
    }
    // 已经有权限（上一次会话给的）⇒ 不重复弹框，直接落开。
    final already = await _isGranted();
    if (!already) {
      await _requestPermission();
      final now = await _isGranted();
      if (!now) {
        // 系统框还开着（答复在 resumed 那一路收）。先不落开 —— 给了才落。
        if (mounted) {
          setState(() {
            _calls = false;
            _note = null;
            _awaitingPermission = true;
          });
        }
        return;
      }
    }
    await _save(true);
    if (mounted) {
      setState(() {
        _calls = true;
        _note = null;
        _awaitingPermission = false;
      });
    }
  }

  Future<void> _reconcileAfterPermission() async {
    final granted = await _isGranted();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (granted) {
      await _save(true);
      if (!mounted) return;
      setState(() {
        _calls = true;
        _note = null;
        _awaitingPermission = false;
      });
    } else {
      setState(() {
        _awaitingPermission = false;
        _note = l10n.fnthinkReadCallsDenied;
      });
    }
  }

  Future<bool> _isGranted() async {
    if (widget.isGranted != null) return widget.isGranted!();
    return GetIt.instance<PermissionService>().isCallLogPermissionGranted();
  }

  Future<void> _requestPermission() async {
    if (widget.requestPermission != null) return widget.requestPermission!();
    await GetIt.instance<PermissionService>().requestCallLogPermission();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(
          l10n.fnthinkReadPageTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FnthinkCard(
            title: l10n.fnthinkReadPageTitle,
            children: [
              HelpNoteRow(
                noteKey: 'fnthink-read-why',
                helpKey: 'fnthink-read-why-help',
                text: l10n.fnthinkReadWhy,
                helpTitle: l10n.fnthinkReadWhyTitle,
                helpBody: l10n.fnthinkReadWhyBody,
              ),
              _callsRow(l10n),
              if (_note != null)
                FnthinkNote(keyName: 'fnthink-read-calls-denied', text: _note!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _callsRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.phone_in_talk_outlined,
              size: 22,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.fnthinkReadCallsTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.fnthinkReadCallsSubtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            key: const ValueKey('fnthink-read-calls-switch'),
            value: _calls ?? false,
            activeTrackColor: AppColors.green,
            onChanged: _calls == null ? null : _toggleCalls,
          ),
        ],
      ),
    );
  }
}
