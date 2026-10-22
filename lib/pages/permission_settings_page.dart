import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_l3_grants.dart';
import '../services/permission_service.dart';
import '../services/vendor_family.dart';
import '../theme/app_colors.dart';
import '../widgets/app_info_note_box.dart';
import '../widgets/pull_to_refresh_list.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_dialog_actions.dart';

class PermissionSettingsPage extends StatefulWidget {
  // T140 ㉔①：这一页曾经还有六枚 bool 构造参数（通知监听／通知权限／电池优化／
  // 短信／电话／应用列表）。它们**一次都没被读过** —— 页面上每一格的读数都是
  // 「去取一次」（`_permissionService` 现读那一支 getter），而传进来的那六枚
  // 只是打开页面那一刻的旧快照。假注入的死码，删掉；那一族的状态仍由同一个作者现读。

  /// 契约 `capabilities.l3.settings` 那几项在这一台设备上的读数（T52）。
  ///
  /// ⚠ **这一份仍然由调用方提供，页面不自己去读**：读法与判态都只有一处
  ///   （`collectL3GrantRows`），页面里再读一遍就会出现「两处读数各自漂移」——
  ///   而那正是本仓修过的「权限页恒显已授予」的形状。构造参数是**必填**的：
  ///   少传一项编译就不过，而不是那一格悄悄不渲染。
  /// ⚠ 但传进来的是**「去取一次」这件事**（一个函数），不是已经取好的那一份：
  ///   这一格里每一项说的都是「此刻这台的授权」，而用户点进行去系统里改完回来，
  ///   那一份就过期了。旧写法注入的是算好的 `List` —— 页面在**被打开那一刻**冻结，
  ///   于是回前台时同一页上「精确闹钟」出现两行：B1 那一格跟着新读数改口，
  ///   这一格还停在旧的（表现是「我刚开的权限它还说没开」，而用户只能退出重进）。
  ///   页面现在只决定**什么时候再取一次**（进页面、回前台、下拉刷新），不决定怎么判。
  final Future<List<FnthinkL3GrantRow>> Function() loadL3GrantRows;
  final String manufacturer;
  final Future<void> Function() onRefresh;

  /// 从系统页回来时让排程按新授权重排一次（T140）。null = 这一页没有那条链路
  /// （widget 用例直接构造时就不需要）；真机上由主页面接到收货协调者。
  final Future<void> Function()? onAuthorizationChanged;
  final VoidCallback onRequestNotificationListenerPermission;
  final VoidCallback onRequestPostNotificationPermission;
  final VoidCallback onRequestBatteryOptimization;
  final VoidCallback onRequestXiaomiAutoStart;
  final VoidCallback onRequestMeizuBackground;
  final VoidCallback onRequestHuaweiLaunch;
  final VoidCallback onRequestOppoBackground;
  final VoidCallback onRequestVivoBackground;
  final VoidCallback onRequestSmsPermission;
  final VoidCallback onRequestPhonePermission;
  final VoidCallback onRequestAppListPermission;

  const PermissionSettingsPage({
    super.key,
    required this.loadL3GrantRows,
    required this.manufacturer,
    required this.onRefresh,
    this.onAuthorizationChanged,
    required this.onRequestNotificationListenerPermission,
    required this.onRequestPostNotificationPermission,
    required this.onRequestBatteryOptimization,
    required this.onRequestXiaomiAutoStart,
    required this.onRequestMeizuBackground,
    required this.onRequestHuaweiLaunch,
    required this.onRequestOppoBackground,
    required this.onRequestVivoBackground,
    required this.onRequestSmsPermission,
    required this.onRequestPhonePermission,
    required this.onRequestAppListPermission,
  });

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage>
    with WidgetsBindingObserver {
  final PermissionService _permissionService =
      GetIt.instance<PermissionService>();

  /// B1 精确闹钟：这一行**只画系统授权**（T140 走 (c) 之后这一族只剩一枚真值）。
  bool _exactAlarmGranted = false;

  /// L3 那一格**这一次**读回来的那几行（空 = 还没读回来，见 `_buildL3Group`）。
  ///
  /// ⚠ 它是 state 而不是直接画 `widget.` 那一份，为的就是「回前台要重算」这件事能真的发生：
  ///   构造参数是打开页面那一刻的快照，画它就等于把「此刻这台的授权」冻在进页那一刻。
  List<FnthinkL3GrantRow> _l3GrantRows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadExactAlarmState();
    _loadL3GrantRows();
  }

  /// 再取一次 L3 读数。**取法与判态都不在这里**（那是 `collectL3GrantRows` 那一处作者），
  /// 这里只决定"什么时候再问一遍"：进页面、从系统设置回来、下拉刷新。
  Future<void> _loadL3GrantRows() async {
    final rows = await widget.loadL3GrantRows();
    if (!mounted) return;
    setState(() => _l3GrantRows = rows);
  }

  /// 下拉刷新：外层那一次（刷新六项布尔读数与循环状态）之后，把这一格也重取一遍。
  /// ⚠ 两件事**必须同一刻做完**再让刷新圈收下：只刷外层的后果是"页面说它刷新过了，
  ///   而 L3 那几行还是进页那一刻的读数"——那一句"已刷新"就是假的。
  Future<void> _refreshBoth() async {
    await widget.onRefresh();
    await _loadExactAlarmState();
    await _loadL3GrantRows();
  }

  /// 再取一次精确闹钟的**系统授权**。
  ///
  /// ⚠ 这里读的与原生排闹钟时读的是同一枚（`canScheduleExactAlarms` ⇒ 原生 `ExactAlarmPolicy`），
  /// 页面上不再有第二份"要不要用精确闹钟"的偏好 —— 那一枚开关正是 T140 走 (c) 删掉的东西。
  Future<void> _loadExactAlarmState() async {
    final granted = await _permissionService.canScheduleExactAlarms();
    if (!mounted) return;
    setState(() => _exactAlarmGranted = granted);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _permissionService.checkAllPermissions();
      // 从系统授权页返回后刷新精确闹钟那一行（现在它画的就是一枚真值：系统授权）
      await _loadExactAlarmState();
      // ⚠ L3 那一格必须跟着重取：它说的是"此刻这台设备的授权"，而用户正是去系统里
      //   改完才回来的。不重取的表现不是崩，是**那一行把用户刚做完的事抹掉** ——
      //   已经授权了，行上还写着"还没给这台设备授权"，用户只能退出重进来确认。
      await _loadL3GrantRows();
      // T140：系统授权页可能改的就是精确闹钟这一枚。读回新值还不够 ——
      // 已经排出去的那颗闹钟仍按旧精度走，要在回前台这一刻按新授权重排一次。
      try {
        await widget.onAuthorizationChanged?.call();
      } catch (e) {
        debugPrint('[permission] 授权变更后的重排失败：$e');
      }
      if (mounted) setState(() {});
    }
  }

  bool get _notificationListenerGranted =>
      _permissionService.notificationListenerGranted;
  bool get _postNotificationGranted =>
      _permissionService.postNotificationGranted;
  bool get _batteryOptimizationIgnored =>
      _permissionService.batteryOptimizationIgnored;
  bool get _smsPermissionGranted => _permissionService.smsGranted;
  bool get _phonePermissionGranted => _permissionService.phoneGranted;
  bool get _appListPermissionGranted => _permissionService.appListGranted;
  // 厂商分流只认 `vendor_family.dart` 那一张表（T140 (b) ②）。
  //
  // 这一页以前自己写了六行 `contains`，而 L3 那一发与小组件引导页各写了一份**不同**的：
  // 同一台红米／荣耀／iQOO 在这里"能跳"，在 L3 的审计里"什么都没做" —— 一屏两句话的另一种形状。
  // ⚠ 这一族的**状态**仍然读不到（六厂商都不给公开读数），所以这里判的只是"该给哪一家的入口"，
  //   那一行的读数仍旧走 `l3StateUnreadable` 那一句，不许在这里画成"已开启"。
  FnthinkVendorFamily get _vendorFamily =>
      fnthinkVendorFamilyOf(widget.manufacturer);

  bool get _isXiaomi => _vendorFamily == FnthinkVendorFamily.xiaomi;

  bool get _isMeizu => _vendorFamily == FnthinkVendorFamily.meizu;

  bool get _isHuawei => _vendorFamily == FnthinkVendorFamily.huawei;

  bool get _isOppo => _vendorFamily == FnthinkVendorFamily.oppo;

  bool get _isVivo => _vendorFamily == FnthinkVendorFamily.vivo;

  bool get _isSamsung => _vendorFamily == FnthinkVendorFamily.samsung;

  bool get _isStockAndroid => _vendorFamily == FnthinkVendorFamily.stock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.permSettingsTitle)),
      body: PullToRefreshList(
        onRefresh: _refreshBoth,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader(
            l10n.essentialPerms,
            keyName: 'permission-section-essential-perms',
          ),
          _buildGroup([
            _buildPermissionTile(
              icon: Icons.notifications_active,
              title: l10n.notifAccessPerm,
              subtitle: _notificationListenerGranted
                  ? l10n.enabled
                  : l10n.disabled,
              isOn: _notificationListenerGranted,
              onTap: _notificationListenerGranted
                  ? null
                  : widget.onRequestNotificationListenerPermission,
              context: context,
            ),
            _buildDivider(context),
            _buildPermissionTile(
              icon: Icons.notification_add,
              title: l10n.allowNotifications,
              subtitle: _postNotificationGranted ? l10n.enabled : l10n.disabled,
              isOn: _postNotificationGranted,
              onTap: _postNotificationGranted
                  ? null
                  : widget.onRequestPostNotificationPermission,
              context: context,
            ),
            _buildDivider(context),
            _buildPermissionTile(
              icon: Icons.battery_full,
              title: l10n.ignoreBatteryOpt,
              subtitle: _batteryOptimizationIgnored
                  ? l10n.enabled
                  : l10n.disabled,
              isOn: _batteryOptimizationIgnored,
              onTap: _batteryOptimizationIgnored
                  ? null
                  : widget.onRequestBatteryOptimization,
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          if (_isXiaomi ||
              _isMeizu ||
              _isHuawei ||
              _isOppo ||
              _isVivo ||
              _isSamsung ||
              _isStockAndroid) ...[
            _buildSectionHeader(
              l10n.keepAliveGuideTitle,
              keyName: 'permission-section-keep-alive-guide',
            ),
            _buildKeepAliveGuideCard(context),
            const SizedBox(height: 24),
            _buildSectionHeader(
              l10n.vendorBgSettings,
              keyName: 'permission-section-vendor-bg-settings',
            ),
            _buildGroup([
              if (_isXiaomi)
                _buildPermissionTile(
                  icon: Icons.rocket_launch,
                  title: l10n.xiaomiAutoStart,
                  subtitle: l10n.clickToSettings,
                  isOn: false,
                  onTap: () => _guideThenJump(
                    title: l10n.autostartGuideTitle,
                    message: l10n.autostartGuideMsg,
                    jump: widget.onRequestXiaomiAutoStart,
                  ),
                  isWarning: true,
                  context: context,
                ),
              if (_isMeizu)
                _buildPermissionTile(
                  icon: Icons.rocket_launch,
                  title: l10n.meizuBgRun,
                  subtitle: l10n.clickToSettings,
                  isOn: false,
                  onTap: () => _guideThenJump(
                    title: l10n.autostartGuideTitle,
                    message: l10n.autostartGuideMsg,
                    jump: widget.onRequestMeizuBackground,
                  ),
                  isWarning: true,
                  context: context,
                ),
              if (_isHuawei)
                _buildPermissionTile(
                  icon: Icons.rocket_launch,
                  title: l10n.huaweiProtected,
                  subtitle: l10n.clickToSettings,
                  isOn: false,
                  onTap: () => _guideThenJump(
                    title: l10n.autostartGuideTitle,
                    message: l10n.autostartGuideMsg,
                    jump: widget.onRequestHuaweiLaunch,
                  ),
                  isWarning: true,
                  context: context,
                ),
              if (_isOppo)
                _buildPermissionTile(
                  icon: Icons.rocket_launch,
                  title: l10n.oppoAutoStart,
                  subtitle: l10n.clickToSettings,
                  isOn: false,
                  onTap: () => _guideThenJump(
                    title: l10n.autostartGuideTitle,
                    message: l10n.autostartGuideMsg,
                    jump: widget.onRequestOppoBackground,
                  ),
                  isWarning: true,
                  context: context,
                ),
              if (_isVivo)
                _buildPermissionTile(
                  icon: Icons.rocket_launch,
                  title: l10n.vivoBgStart,
                  subtitle: l10n.clickToSettings,
                  isOn: false,
                  onTap: () => _guideThenJump(
                    title: l10n.autostartGuideTitle,
                    message: l10n.autostartGuideMsg,
                    jump: widget.onRequestVivoBackground,
                  ),
                  isWarning: true,
                  context: context,
                ),
              if (_isSamsung)
                _buildPermissionTile(
                  icon: Icons.info_outline,
                  title: l10n.samsungSettings,
                  subtitle: l10n.samsungSmartManagerDesc,
                  isOn: false,
                  onTap: null,
                  isWarning: true,
                  context: context,
                ),
              if (_isStockAndroid)
                _buildPermissionTile(
                  icon: Icons.info_outline,
                  title: l10n.nativeAndroid,
                  subtitle: l10n.nativeBatteryOptDesc,
                  isOn: false,
                  onTap: null,
                  isWarning: true,
                  context: context,
                ),
            ], context),
            const SizedBox(height: 24),
          ],
          _buildSectionHeader(
            l10n.optionalPerms,
            keyName: 'permission-section-optional-perms',
          ),
          _buildGroup([
            _buildExactAlarmTile(context),
            _buildDivider(context),
            _buildPermissionTile(
              icon: Icons.message,
              title: l10n.smsPerm,
              subtitle: _smsPermissionGranted ? l10n.enabled : l10n.disabled,
              isOn: _smsPermissionGranted,
              onTap: _smsPermissionGranted
                  ? null
                  : widget.onRequestSmsPermission,
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
              child: Text(
                l10n.smsPermDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            _buildDivider(context),
            _buildPermissionTile(
              icon: Icons.call,
              title: l10n.phonePerm,
              subtitle: _phonePermissionGranted ? l10n.enabled : l10n.disabled,
              isOn: _phonePermissionGranted,
              onTap: _phonePermissionGranted
                  ? null
                  : widget.onRequestPhonePermission,
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
              child: Text(
                l10n.phonePermDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            _buildDivider(context),
            _buildPermissionTile(
              icon: Icons.apps,
              title: l10n.appListPerm,
              // 三态而不是开关：`unknown` 表示"这个系统压根不给明确读数"。
              // 显示成「已开启」是本次修复的原始缺陷（权限页恒显已授予），
              // 显示成「已关闭」会误导用户去系统里找一个并不存在的开关。
              subtitle: switch (_permissionService.appListPermission) {
                AppListPermission.granted => l10n.enabled,
                AppListPermission.denied => l10n.disabled,
                AppListPermission.unknown => l10n.appListPermUnknown,
              },
              isOn: _appListPermissionGranted,
              // T153 片4（维护者 2026-10-15 拍板 Q2=a）：点下去**先弹引导，再说去跳**。
              // ⚠ 这一格与 1.5.76 反馈 #3 去掉的那一层不是同一层：那次去掉的是
              //   「进筛选页就自动弹」，这次是"用户主动点了这一行" —— 他正要跳走，
              //   此刻最需要知道的正是"系统里它叫什么、去哪找、开完回来"。
              //   而这一格从前只有一个「应用列表权限」的标题，跳过去之后用户
              //   面对一页密密麻麻的权限项，不知道开哪一项（维护者原话：
              //   "不要只是跳转到应用设置页"）。
              onTap: _appListPermissionGranted
                  ? null
                  : () => _guideThenJump(
                      title: l10n.appListPermGuideTitle,
                      message: l10n.appListPermGuideMsg,
                      jump: widget.onRequestAppListPermission,
                    ),
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
              child: Text(
                l10n.appListPermExtra,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader(
            l10n.l3SettingsSectionTitle,
            keyName: 'permission-section-l3-settings',
          ),
          _buildL3Group(context),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AppInfoNoteBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.l3SettingsSectionDesc,
                    style: TextStyle(
                      color: AppColors.secondaryLabel(context),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.appListPermDesc,
                    style: TextStyle(
                      color: AppColors.secondaryLabel(context),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// L3 那一格：**六行按契约次序全列**，没给的置灰并说一句，不折叠、不隐藏。
  ///
  /// ⚠ 这里**不读任何系统状态**：那一几行由 `loadL3GrantRows` 交回来（组装只有一处作者，
  /// 见 `main_page_actions._l3GrantRows`）。这一层负责的是**什么时候再问一遍**，
  /// 不是"怎么判" —— 在这儿再问一次系统就会出现两处读数（本仓为这个栽过一次）。
  Widget _buildL3Group(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 空 = **还没读回来**（第一帧），不是"这台一项都不用给"：那种情况下画一张空的分组卡，
    // 用户读到的是"这里没有东西要管"，而真相是"我们还没问过"。所以第一帧什么都不画。
    if (_l3GrantRows.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (final (i, row) in _l3GrantRows.indexed) {
      if (i > 0) children.add(_buildDivider(context));
      children.add(
        _buildPermissionTile(
          icon: _l3Icon(row.key),
          title: _l3ItemTitle(l10n, row.key),
          // 状态那句 + 调用方补的那一条说明（说明只在没给的时候非空，见读模型）
          subtitle: row.note.isEmpty
              ? _l3StateText(l10n, row)
              : '${_l3StateText(l10n, row)} · ${row.note}',
          isOn: row.granted,
          dimmed: !row.granted,
          // 已授予 ⇒ 不再给"重复申请"留口子；这台没有这一项 / 开关住在别处 ⇒ 不放会动的按钮
          onTap: row.granted || row.thisDeviceLacksIt ? null : _l3Jump(row.key),
          context: context,
        ),
      );
    }
    // 这把 key 是给"那张空卡到底画没画"留的观察点：没有它，用例只能断"行在不在"，
    // 而"一行都不画"与"画了一张什么都没有的卡"在两行文本的断言下长得一模一样。
    return KeyedSubtree(
      key: const ValueKey('perm-l3-group-card'),
      child: _buildGroup(children, context),
    );
  }

  /// 契约里的设置项 key → 这一格叫什么。
  ///
  /// ⚠ 契约加了一项而这里没接 ⇒ **把 key 原样显示**，而不是让那一行消失：
  /// 少一行是静默的，多一个看得见的生词不是。
  /// ⚠ **这一张表与 `fnthink_remote_action_labels` 是两张，不许合**（T146 片6 现读）：
  ///   同一枚 `monitoring` 在那边叫「开／关**对面的**通知转发总开关」——答的是"这条指令会对对面做什么"；
  ///   在这一页只许叫「通知转发监听」——答的是"**这台**有没有这项授权"。
  ///   合表的后果是让权限页替用户说一句他沒做的事（"去开对面的开关"出现在"这台给了没有"那一行上）。
  ///   钉这一维的守卫是 `test/architecture/fnthink_l3_item_words_scope_test.dart`（串台与覆盖各一条）。
  String _l3ItemTitle(AppLocalizations l10n, String key) => switch (key) {
    'notification' => l10n.notifAccessPerm,
    'exact_alarm' => l10n.exactAlarmTitle,
    'battery_optimization' => l10n.ignoreBatteryOpt,
    'autostart' => l10n.l3ItemAutostart,
    'monitoring' => l10n.l3ItemMonitoring,
    'collect_inbox' => l10n.l3ItemCollectInbox,
    _ => key,
  };

  /// 四种状态四句话。⚠ **穷尽由编译器把关**：读模型加第五态而这里没接，编译就红。
  String _l3StateText(AppLocalizations l10n, FnthinkL3GrantRow row) =>
      switch (row.state) {
        FnthinkL3GrantState.granted => l10n.enabled,
        FnthinkL3GrantState.missing => l10n.l3StateMissing,
        FnthinkL3GrantState.unreadable => l10n.l3StateUnreadable,
        FnthinkL3GrantState.unsupported => l10n.l3StateUnsupported,
      };

  IconData _l3Icon(String key) => switch (key) {
    'notification' => Icons.notifications_active,
    'exact_alarm' => Icons.alarm,
    'battery_optimization' => Icons.battery_full,
    'autostart' => Icons.rocket_launch,
    'monitoring' => Icons.radar,
    'collect_inbox' => Icons.inbox,
    _ => Icons.settings,
  };

  /// 点这一行去哪儿：只有「跳系统页请用户自己点」这一种，且**每一项的落点不同**。
  ///
  /// ⚠ 返回 null 的两种情况都刻意不放按钮 —— 「点了没反应」是这片要防的形状，
  /// 而 monitoring / collect_inbox 的开关在「幻念推送」页那一格（说明行已经写在那一行上）。
  VoidCallback? _l3Jump(String key) => switch (key) {
    'notification' => widget.onRequestNotificationListenerPermission,
    'battery_optimization' => widget.onRequestBatteryOptimization,
    'exact_alarm' => () => _permissionService.requestExactAlarmPermission(),
    'autostart' => _vendorJump(),
    _ => null,
  };

  /// B1 精确闹钟那一行：**状态 + 一键跳**，右侧那枚写偏好的开关已删（T140 走 (c)）。
  ///
  /// 为什么这一行必须换形状：以前它右侧是一枚写进 Flutter 偏好的开关（默认关），副标题报的
  /// 却是系统授权 —— 开关关掉时「已授权」与「到点晚几分钟」同时成立，两句各自都不算假、
  /// 合起来是一句假话（而契约对常态收取承诺的是 5–60 秒）。
  /// 现在画出去的布尔与原生排闹钟时读的是**同一枚**（原生同一个表达式，见 `ExactAlarmPolicy`）。
  ///
  /// ⚠ 与下面 L3 那一格里同名的一行**不是重复**（T146 片6 那条纪律：主语不同不许合表）：
  ///   这一行答的是"本机的延迟/定时推送准不准点"，那一行答的是"对端能不能请求这一项"。
  Widget _buildExactAlarmTile(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _buildPermissionTile(
      icon: Icons.alarm,
      title: l10n.exactAlarmTitle,
      subtitle:
          '${_exactAlarmGranted ? l10n.exactAlarmGranted : l10n.exactAlarmNeedGrant}'
          ' · ${l10n.exactAlarmDesc}',
      isOn: _exactAlarmGranted,
      // 已授权 ⇒ 不给"重复申请"留口子（与 L3 那几行同一条规矩）
      onTap: _exactAlarmGranted
          ? null
          : () => _permissionService.requestExactAlarmPermission(),
      isWarning: true,
      context: context,
    );
  }

  /// B2 后台保活引导卡片（dontkillmyapp 4 步）
  Widget _buildKeepAliveGuideCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vendorJump = _vendorJump();
    final steps = [
      (l10n.keepAliveStep1, widget.onRequestBatteryOptimization),
      (l10n.keepAliveStep2, vendorJump),
      (l10n.keepAliveStep3, vendorJump),
      (l10n.keepAliveStep4, widget.onRequestNotificationListenerPermission),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.keepAliveGuideDesc,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          for (var i = 0; i < steps.length; i++) ...[
            InkWell(
              onTap: steps[i].$2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.blue.withValues(alpha: 0.12),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        steps[i].$1,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primaryLabel(context),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.tertiaryLabel(context),
                    ),
                  ],
                ),
              ),
            ),
            if (i < steps.length - 1) _buildDivider(context),
          ],
        ],
      ),
    );
  }

  /// 当前厂商后台设置跳转（自启动/任务锁定共用同一入口）
  VoidCallback? _vendorJump() {
    if (_isXiaomi) return widget.onRequestXiaomiAutoStart;
    if (_isMeizu) return widget.onRequestMeizuBackground;
    if (_isHuawei) return widget.onRequestHuaweiLaunch;
    if (_isOppo) return widget.onRequestOppoBackground;
    if (_isVivo) return widget.onRequestVivoBackground;
    return null;
  }

  /// 跳系统页之前**先把话说清楚**（T153 片4，维护者 2026-10-15 拍板 Q2=a）。
  ///
  /// 这一族动作全都有一个共同的坑：点下去屏幕直接切走，用户站在一页陌生的系统设置里
  /// 不知道自己要找什么。所以每次跳之前先说清三件事 —— **系统里它叫什么、去哪一页、
  /// 开完回来**（第三件尤其重要：不说它，用户不敢确定自己开对了没有）。
  ///
  /// ⚠ 与 1.5.76 反馈 #3 不冲突，两个语境不同：那一次去掉的是「**进页面就自动弹**一层」
  ///   （用户正在做事，被无来由的弹层打断）；这一层是「**用户刚点了这一行**」时的说明 ——
  ///   他正要跳走，此刻的说明是他要的那一件。判据也一样：前者拦路，后者铺路。
  ///
  /// ⚠ 拒绝的那条路**什么都不做**（不跳、不记状态）：这一格本来就没被授予，
  ///   用户点"取消"的意思就是"现在别跳"。
  Future<void> _guideThenJump({
    required String title,
    required String message,
    required VoidCallback jump,
  }) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final allowed = await IosDialogActions.showPermissionGuide(
      context,
      icon: Icons.settings,
      title: title,
      message: message,
      rejectText: l10n.cancel,
      // 「允许」在这一族里是"去开启"：它不是一次授权（应用内根本授不了），
      // 而是一次**跳转约定**。文案照实说，用户才知道按下去会发生什么。
      allowText: l10n.clickToSettings,
    );
    if (allowed) jump();
  }

  /// 组标题走公共件 `FnthinkRowLabel`（T146 片4）：这张页只交出**它在自己版面里的留白**（12px 起），
  /// 画法（13/w600/次要字色）与另外三张清单页同源 —— 以前这里是与另一页**逐字相同**的一把抄本，
  /// 两把之间只差一个字号重量（w500 对 w600）：同一件事在两处各漂各的，正是 T146 要治的那一半。
  /// ⚠ 旧的 `BuildContext context` 形参一并去掉：公共件自己解上下文，留着就是死参数。
  Widget _buildSectionHeader(String title, {required String keyName}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: FnthinkRowLabel(keyName: keyName, label: title),
    );
  }

  Widget _buildGroup(List<Widget> children, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isOn,
    required VoidCallback? onTap,
    required BuildContext context,
    bool isWarning = false,
    bool dimmed = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isOn
                    ? AppColors.green
                    : isWarning
                    ? const Color(0xFFFF9500)
                    : AppColors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: dimmed
                          ? AppColors.tertiaryLabel(context)
                          : AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.tertiaryLabel(context),
              ),
          ],
        ),
      ),
    );
  }
}
