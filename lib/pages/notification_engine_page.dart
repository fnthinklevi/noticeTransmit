import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../services/battery_service.dart';
import '../services/device_state_service.dart';
import '../services/fnthink_remote_gate.dart';
import '../services/temperature_service.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/help_note_button.dart';
import 'battery_page.dart';
import 'device_state_page.dart';
import 'fnthink_peers_page.dart';
import 'fnthink_channel_list_page.dart';
import 'fnthink_channel_settings_page.dart';
import 'fnthink_receive_page.dart';
import 'fnthink_remote_page.dart';
import 'temperature_page.dart';

/// 「通知引擎」tab 的骨架页（T15）。
///
/// 这一格管的是**设备侧触发**的告警：电量、温度。与「更多 → 规则约束」不是一回事 ——
/// 那边判"这条已到达的通知要不要转"，这边判"设备自己到了某个状态要不要提醒"。
/// 二分口径来自 roadmap §3，把两件事放进同一个列表会让人以为规则约束也能配温度阈值。
///
/// ⚠ **T94 起这一页多了一块「幻念推送」**，而且它与上面那三格**不是一类东西**：
/// 上面三格是"什么时候主动提醒"（阈值/迟滞/冷却），这一块是"往哪儿发"
/// （渠道、设备绑定、发起推送、接收设置、远程执行）。维护者明确要求两块区域分开：
/// 「更多 → 幻念推送」那一处只做这台设备的渠道信息（服务地址·身份·端点·边界），
/// 而"我和谁有关系、往哪儿发"归这里。⚠ 混在一处时用户改完一件事分不清自己刚动的是哪一个，
/// 而这两个决定的代价完全不同（换地址码要重新配对，撤销一台只影响那一台）。
///
/// 入口只放**今天真的能用**的两个：
/// - 设备状态（T17 快照 + T18 详情页）还没建，不放占位行 —— 点了没反应的行比没有这行更糟；
/// - 「幻念收件」跳转同理，等 T42/T59 落地再加（本 tab 只放跳转，配置入口按 T42 归「更多」）。
///
/// 两条入口的目标页都**订阅各自的服务**（T16 立的先例），所以本页不往下传回调：
/// 传了就会有第三份"父页接线"，而父页 rebuild 根本到不了被 push 出去的子页。
class NotificationEnginePage extends StatefulWidget {
  const NotificationEnginePage({
    super.key,
    this.peersDeps,
    this.receiveDeps,
    this.remoteDeps,
    this.remoteGateOf,
    this.channelProbe,
  });

  /// 「设备配对」那一行的依赖（T94）。
  ///
  /// 缺省走 `FnthinkPeersDeps.fromLocator()`；测试里传一份替身。
  /// 为什么这一页要单独开一个参数而不是拿 GetIt：这一页的判据是「入口能不能点不动」，
  /// 而被点开的那一页是跟 GetIt 拿的（没注册就异常）——那样的用例必须先注册三个单例，
  /// 而那三个单例与这一页的判据无关，白白让测试变成装配点的清单。
  final FnthinkPeersDeps? peersDeps;

  /// 「接收与远程执行」那一行要推的那张页的依赖（T94 片2）。
  /// 缺省同样走 `fromLocator()`；测试里传替身。
  final FnthinkReceiveDeps? receiveDeps;

  /// 「远程控制」那一行（T97 片C）：既是它要推的那张页的依赖，也是**前置三选一**的读口。
  ///
  /// ⚠ 与上面两个参数不同，这一个**同时决定 hub 那一行灰不灰** —— 前置的判定要在这一页上
  /// 现算；缺省（null：测试或未接线）时那一行按「还不知道」画（不禁用、中性副标题），
  /// 见 `_readRemoteGate`。
  final FnthinkRemoteDeps? remoteDeps;

  /// 只读前置那一下（widget 测试专用：造一整套 `FnthinkRemoteDeps` 要先有契约与协调者，
  /// 而那两件与本页的判据无关）。缺省 null ⇒ 这一页保持「还不知道」。
  final Future<FnthinkRemoteGate?> Function()? remoteGateOf;

  /// 「通道」那一行推的列表页里，详情页那枚「测试这条通道」要的两件（#271）。
  ///
  /// ⚠ 这里**不写 `?? fromLocator()`**：`FnthinkRemoteDeps` 那条能那么写是因为它在
  ///   「点进去」那一刻才求值，而这一份是 `page:` 参数，**在 build 里就要求值** ——
  ///   于是每个 pump 这一页的用例都得先注册 GetIt 单例（而它与本页判据无关），
  ///   本文件那十条用例实测就是这么红的。缺省 null ⇒ 从这条路进去没有那一枚。
  final FnthinkChannelProbeDeps? channelProbe;

  @override
  State<NotificationEnginePage> createState() => _NotificationEnginePageState();
}

class _NotificationEnginePageState extends State<NotificationEnginePage> {
  final BatteryService _battery = GetIt.instance<BatteryService>();
  final TemperatureService _temperature = GetIt.instance<TemperatureService>();
  final DeviceStateService _deviceState = GetIt.instance<DeviceStateService>();

  /// 远程控制那一行的前置（T97 片C）。null = 还不知道（契约没读到 / 这一页没装配依赖）。
  FnthinkRemoteGate? _remoteGate;

  @override
  void initState() {
    super.initState();
    _battery.addListener(_onServiceChanged);
    _temperature.addListener(_onServiceChanged);
    _deviceState.addListener(_onServiceChanged);
    unawaited(_readRemoteGate());
  }

  /// 读前置三选一。**读不到就保持 null（还不知道）**，绝不按「全都没开」画成灰的 ——
  /// 那会把「还没读到契约」说成「你不能用」。
  Future<void> _readRemoteGate() async {
    final read = widget.remoteGateOf;
    if (read == null) return;
    final gate = await read();
    if (!mounted) return;
    setState(() => _remoteGate = gate);
  }

  /// 进「远程控制」。回来再读一次前置 —— 开关就在那一页里（凭据与窗口），
  /// 用户在那边打开之后回到 hub，这一行必须立刻不再是灰的。
  Future<void> _openRemotePage() async {
    final deps = widget.remoteDeps ?? FnthinkRemoteDeps.fromLocator();
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => FnthinkRemotePage(deps: deps)),
    );
    if (!mounted) return;
    await _readRemoteGate();
  }

  @override
  void dispose() {
    // 三个服务都是 GetIt 里的长生命周期单例：只摘监听，不 dispose
    _battery.removeListener(_onServiceChanged);
    _temperature.removeListener(_onServiceChanged);
    _deviceState.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  /// 副标题 = 启用中的规则数；开关关了就把「已暂停」带上 ——
  /// 规则还在但一条都不会推，只报数字会让人以为"配了就会响"。
  String _summary(
    AppLocalizations l10n,
    List<Map<String, dynamic>> rules,
    bool paused,
  ) {
    final count = rules.where((r) => r['enabled'] == true).length;
    final base = count == 0 ? l10n.ruleEmpty : l10n.ruleCount(count);
    return paused ? '$base · ${l10n.pushPausedByUser}' : base;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationEngineTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          HelpNoteRow(
            noteKey: 'engine-page-desc',
            helpKey: 'engine-page-help',
            text: l10n.notificationEngineShort,
            // 标题另起一个键：`notificationEngineTitle` 已经是这一页的 AppBar 标题，
            // 拿它当弹窗标题只会重复一遍页面名，什么也没多说。
            helpTitle: l10n.notificationEngineScopeTitle,
            helpBody: l10n.notificationEngineDesc,
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.separator(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _entry(
                  key: const ValueKey('engine-battery'),
                  icon: Icons.battery_std,
                  iconColor: AppColors.green,
                  title: l10n.engineBatteryEntry,
                  subtitle: _summary(
                    l10n,
                    _battery.rules,
                    !_battery.notifyEnabled,
                  ),
                  page: const BatteryPage(),
                ),
                _divider(),
                _entry(
                  key: const ValueKey('engine-temperature'),
                  icon: Icons.thermostat,
                  iconColor: AppColors.red,
                  title: l10n.engineTemperatureEntry,
                  subtitle: _summary(
                    l10n,
                    _temperature.rules,
                    !_temperature.notifyEnabled,
                  ),
                  page: const TemperaturePage(),
                ),
                _divider(),
                // T24：亮度与网络（同一族 device_state，引擎按 type 路由）
                _entry(
                  key: const ValueKey('engine-device-state'),
                  icon: Icons.brightness_medium,
                  iconColor: AppColors.orange,
                  title: l10n.deviceStateEntry,
                  subtitle: _summary(
                    l10n,
                    _deviceState.rules,
                    !_deviceState.notifyEnabled,
                  ),
                  page: const DeviceStatePage(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _constraintCard(l10n),
          const SizedBox(height: 12),
          _fnthinkHubCard(l10n),
        ],
      ),
    );
  }

  /// T94：这一块收「往哪儿发」 —— 渠道、设备绑定、发起推送、接收设置、远程执行。
  ///
  /// 这一块现在有四行（设备配对／接收设置／幻念通道／远程执行）—— T94 片2/片3 都已落。
  /// **不摆占位行** —— 这一页上面那三格为什么只有三个，理由就是「点了没反应的行比没有这行更糟」，
  /// 同一页里摆三行占位会把那条理由自己拆了。
  Widget _fnthinkHubCard(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.separator(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.fnthinkHubTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.fnthinkHubDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          _entry(
            key: const ValueKey('engine-fnthink-peers'),
            icon: Icons.devices_other,
            iconColor: AppColors.blue,
            title: l10n.fnthinkPeersTitle,
            subtitle: l10n.fnthinkHubPeersDesc,
            page: FnthinkPeersPage(deps: widget.peersDeps),
          ),
          _divider(),
          _entry(
            key: const ValueKey('engine-fnthink-receive'),
            icon: Icons.move_to_inbox,
            iconColor: AppColors.orange,
            title: l10n.fnthinkReceive,
            subtitle: l10n.fnthinkHubReceiveDesc,
            page: FnthinkReceivePage(deps: widget.receiveDeps),
          ),
          _divider(),
          _entry(
            key: const ValueKey('engine-fnthink-channels'),
            icon: Icons.send_rounded,
            iconColor: AppColors.purple,
            title: l10n.fnthinkChannelTitle,
            subtitle: l10n.fnthinkHubChannelsDesc,
            // `probe`（#271）从这里也要给到：这一格是「幻念推送 → 通道」的第二个入口，
            // 两个入口进的是同一页，只给一个装、另一个不装的话，用户从哪进决定了他有没有那一枚。
            page: FnthinkChannelListPage(probe: widget.channelProbe),
          ),
          _divider(),
          // 第四行：远程控制（T97 片C）。它与上面三行的**画法不同** —— 那一行会灰，
          // 灰的原因写在副标题里（缺接收 / 缺同意 / 缺自己的开关）。
          // ⚠ 判定不在这段代码里：`FnthinkRemoteGate` 一个纯函数，两个读者共用一份。
          FnthinkEntryRow(
            key: const ValueKey('engine-fnthink-remote'),
            icon: Icons.settings_remote,
            iconColor: AppColors.teal,
            title: l10n.fnthinkRemoteTitle,
            subtitle: _remoteSubtitle(l10n),
            onTap:
                (_remoteGate == null || _remoteGate == FnthinkRemoteGate.ready)
                ? _openRemotePage
                : null,
          ),
        ],
      ),
    );
  }

  /// T23：设备态告警要不要也过一遍关键词约束。
  ///
  /// 放在这一页而不是电量页/温度页各一枚：它一次作用于**两族**，两处开关迟早会出现
  /// 一个开一个关，而"设备态告警受不受约束"不可能同时有两个答案。
  /// 描述文案里明写了"应用黑白名单不适用"—— 这类告警是本机自己产生的，
  /// 让它受"只转发这些应用"管辖只会得到"配了白名单之后电量告警永远不来"。
  Widget _constraintCard(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.separator(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.engineConstraintEntry,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 2),
                HelpNoteRow(
                  noteKey: 'engine-constraint-desc',
                  helpKey: 'engine-constraint-help',
                  text: l10n.engineConstraintShort,
                  helpTitle: l10n.engineConstraintTitle,
                  // 「应用黑白名单不适用」与「被拦下的告警会写进历史并标注原因」两句
                  // 都在弹窗里 —— 前者是这一格最容易被误解的地方。
                  helpBody: l10n.engineConstraintDesc,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            key: const ValueKey('engine-device-constraint'),
            value: _battery.deviceAlertsRespectConstraints,
            onChanged: (v) => _battery.saveDeviceAlertsRespectConstraints(v),
          ),
        ],
      ),
    );
  }

  /// 「进一页那一行」走 §1 定稿的形状①，装配点在 `widgets/fnthink_card.dart`。
  ///
  /// 为什么改成调公共件：hub 这三行与接收页远程执行那三行是**同一件事**（进一页），
  /// 而 T100 片2 之前各搭一份 —— 一份自己搭行壳 + Material 路由、一份是裸的蓝字按钮，
  /// 于是「同页对齐」没有可对齐的东西，点法与转场也各走各的。
  /// ⚠ 与「更多」页那种 InkWell 行不是一件东西：那一族是另一张页的账（T05 已定不抽）。
  Widget _entry({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return FnthinkEntryRow(
      key: key,
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      // 转场走 Cupertino：这本「Material 路由站点」台账只许变薄，而 hub 这三行
      // 就是它在**这个文件里的全部**（换完这一格从账上删掉，不是留 0）。
      onTap: () => Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => page)),
    );
  }

  /// 远程控制那一行的副标题：**缺哪一条就说哪一条**（四条文案一一对应 `FnthinkRemoteGate`）。
  ///
  /// `null`（还不知道）走中性那句 —— 与 `.ready` 同一句，因为"还没读到契约"不许被画成"缺东西"。
  String _remoteSubtitle(AppLocalizations l10n) {
    switch (_remoteGate) {
      case FnthinkRemoteGate.receiveOff:
        return l10n.fnthinkRemoteNeedsReceive;
      case FnthinkRemoteGate.notConsented:
        return l10n.fnthinkRemoteNeedsConsent;
      case FnthinkRemoteGate.switchOff:
        return l10n.fnthinkRemoteNeedsSwitch;
      case FnthinkRemoteGate.ready:
      case null:
        return l10n.remoteExecShort;
    }
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }
}
