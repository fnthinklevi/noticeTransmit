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
/// 这一页管"对面能**读**这台什么"。**每一项一枚开关、默认全关、逐条单独开**
/// （与短信监听那一族同一条纪律；`?? false`，见 `fnthink_read_settings.dart`）。
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
///
/// ## 一条一开：每一行自己的读写/权限/文案都在[行描述]里，流程只有一套
/// 行与行之间**不共享**状态（一枚开关打开不代表另一枚的权限也给了；两枚权限是两次申请）。
/// 但"翻开关 → 申请 → 复核 → 落盘"这条流程只有这一份实现 —— 各写一遍等于两处会各自漂移。
class FnthinkReadCapsPage extends StatefulWidget {
  const FnthinkReadCapsPage({
    super.key,
    this.loadCalls,
    this.saveCalls,
    this.requestCallsPermission,
    this.isCallsGranted,
    this.loadLocation,
    this.saveLocation,
    this.requestLocationPermission,
    this.isLocationGranted,
  });

  /// 读写口与权限申请口（测试注入；默认走生产那两份）。
  /// ⚠ 与其余几页同一条纪律：不注入时就是生产那份，页面不自己另写一套判据。
  final Future<bool> Function()? loadCalls;
  final Future<void> Function(bool enabled)? saveCalls;
  final Future<void> Function()? requestCallsPermission;
  final Future<bool> Function()? isCallsGranted;

  final Future<bool> Function()? loadLocation;
  final Future<void> Function(bool enabled)? saveLocation;
  final Future<void> Function()? requestLocationPermission;
  final Future<bool> Function()? isLocationGranted;

  @override
  State<FnthinkReadCapsPage> createState() => _FnthinkReadCapsPageState();
}

/// 一行的全部可注入口（读写 + 权限申请/查询 + 文案）。
///
/// ⚠ [id] 只用来拼 key（`fnthink-read-<id>-switch` / `-denied`）与在 resumed 那一路
/// 认回"刚才弹的是哪一行"—— 不参与任何业务判据。
class _ReadCapRowSpec {
  const _ReadCapRowSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.deniedText,
    required this.icon,
    required this.iconColor,
    required this.load,
    required this.save,
    required this.requestPermission,
    required this.isGranted,
  });

  final String id;
  final String title;
  final String subtitle;

  /// 被拒/没给成时那一句（给了就清掉）。
  final String deniedText;
  final IconData icon;
  final Color iconColor;
  final Future<bool> Function() load;
  final Future<void> Function(bool enabled) save;
  final Future<void> Function() requestPermission;
  final Future<bool> Function() isGranted;
}

/// 一行的运行态。`value == null` = 还没读出来（第一帧画**关** —— 默认关是这条纪律的基数，
/// 画成空会让"翻开关"的判据分成两条路）。
class _ReadCapRowState {
  bool? value;
  String? note;
}

class _FnthinkReadCapsPageState extends State<FnthinkReadCapsPage>
    with WidgetsBindingObserver {
  final Map<String, _ReadCapRowState> _rows = {};

  /// 系统权限框正开着的那一行（等用户答复）。resumed 那一路用它决定要不要复核、复核谁。
  String? _awaitingId;

  /// 行描述（在 build 里按 l10n 建一次）。resumed 那一路也要用它，所以缓存住。
  List<_ReadCapRowSpec>? _specs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (state != AppLifecycleState.resumed) return;
    final id = _awaitingId;
    if (id == null) return;
    final spec = _specs?.where((s) => s.id == id).firstOrNull;
    if (spec != null) unawaited(_reconcile(spec));
  }

  _ReadCapRowState _rowOf(_ReadCapRowSpec spec) =>
      _rows.putIfAbsent(spec.id, _ReadCapRowState.new);

  Future<void> _reload(_ReadCapRowSpec spec) async {
    try {
      final value = await spec.load();
      if (mounted) setState(() => _rowOf(spec).value = value);
    } catch (_) {
      if (mounted) setState(() => _rowOf(spec).value = false);
    }
  }

  Future<void> _toggle(_ReadCapRowSpec spec, bool value) async {
    final st = _rowOf(spec);
    if (!value) {
      // 关：**立即生效**，不碰权限框 —— 关掉是持有者随时该能做的一件事。
      await spec.save(false);
      if (mounted) {
        setState(() {
          st.value = false;
          st.note = null;
          if (_awaitingId == spec.id) _awaitingId = null;
        });
      }
      return;
    }
    // 已经有权限（上一次会话给的）⇒ 不重复弹框，直接落开。
    final already = await spec.isGranted();
    if (!already) {
      await spec.requestPermission();
      final now = await spec.isGranted();
      if (!now) {
        // 系统框还开着（答复在 resumed 那一路收）。先不落开 —— 给了才落。
        if (mounted) {
          setState(() {
            st.value = false;
            st.note = null;
            _awaitingId = spec.id;
          });
        }
        return;
      }
    }
    await spec.save(true);
    if (mounted) {
      setState(() {
        st.value = true;
        st.note = null;
        if (_awaitingId == spec.id) _awaitingId = null;
      });
    }
  }

  Future<void> _reconcile(_ReadCapRowSpec spec) async {
    final granted = await spec.isGranted();
    if (!mounted) return;
    final st = _rowOf(spec);
    if (granted) {
      await spec.save(true);
      if (!mounted) return;
      setState(() {
        st.value = true;
        st.note = null;
        _awaitingId = null;
      });
    } else {
      setState(() {
        _awaitingId = null;
        st.note = spec.deniedText;
      });
    }
  }

  Future<bool> _callsGranted() async {
    if (widget.isCallsGranted != null) return widget.isCallsGranted!();
    return GetIt.instance<PermissionService>().isCallLogPermissionGranted();
  }

  Future<void> _requestCallsPermission() async {
    if (widget.requestCallsPermission != null) {
      return widget.requestCallsPermission!();
    }
    await GetIt.instance<PermissionService>().requestCallLogPermission();
  }

  Future<bool> _locationGranted() async {
    if (widget.isLocationGranted != null) return widget.isLocationGranted!();
    return GetIt.instance<PermissionService>().isLocationPermissionGranted();
  }

  Future<void> _requestLocationPermission() async {
    if (widget.requestLocationPermission != null) {
      return widget.requestLocationPermission!();
    }
    await GetIt.instance<PermissionService>().requestLocationPermission();
  }

  List<_ReadCapRowSpec> _buildSpecs(AppLocalizations l10n) {
    return [
      _ReadCapRowSpec(
        id: 'calls',
        title: l10n.fnthinkReadCallsTitle,
        subtitle: l10n.fnthinkReadCallsSubtitle,
        deniedText: l10n.fnthinkReadCallsDenied,
        icon: Icons.phone_in_talk_outlined,
        iconColor: AppColors.blue,
        load: widget.loadCalls ?? fnthinkReadCallsEnabled,
        save: widget.saveCalls ?? setFnthinkReadCallsEnabled,
        requestPermission: _requestCallsPermission,
        isGranted: _callsGranted,
      ),
      _ReadCapRowSpec(
        id: 'location',
        title: l10n.fnthinkReadLocationTitle,
        subtitle: l10n.fnthinkReadLocationSubtitle,
        deniedText: l10n.fnthinkReadLocationDenied,
        icon: Icons.location_on_outlined,
        iconColor: AppColors.orange,
        load: widget.loadLocation ?? fnthinkReadLocationEnabled,
        save: widget.saveLocation ?? setFnthinkReadLocationEnabled,
        requestPermission: _requestLocationPermission,
        isGranted: _locationGranted,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final specs = _specs ??= _buildSpecs(l10n);
    // 首次成帧：把每一行的读写口读一遍（每一行各读各的，不合成一个"全开/全关"）。
    for (final spec in specs) {
      if (!_rows.containsKey(spec.id)) {
        _rows[spec.id] = _ReadCapRowState();
        unawaited(_reload(spec));
      }
    }
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
              for (final spec in specs) ...[
                _row(spec),
                if (_rowOf(spec).note != null)
                  FnthinkNote(
                    keyName: 'fnthink-read-${spec.id}-denied',
                    text: _rowOf(spec).note!,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(_ReadCapRowSpec spec) {
    final st = _rowOf(spec);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: spec.iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(spec.icon, size: 22, color: spec.iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            key: ValueKey('fnthink-read-${spec.id}-switch'),
            value: st.value ?? false,
            activeTrackColor: AppColors.green,
            onChanged: st.value == null ? null : (v) => _toggle(spec, v),
          ),
        ],
      ),
    );
  }
}
