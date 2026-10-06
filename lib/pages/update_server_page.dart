import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/channel_health_store.dart';
import '../services/update_server_regions.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/help_note_button.dart';

/// 「更新服务器」选择页（T95 片3）。
///
/// 这一页回答三个问题：现在走哪一台、为什么走它、这台今天能不能用。
///
/// ## 两档恒常摆出来，探不通也不藏
/// 与幻念推送那两台同一口径（T76 定的）：候选就是这两台，探不通就在界面上说"没回话"，
/// 而不是把它从列表里拿掉 —— 拿掉的那一刻用户就没有回去的路，而那一台能不能用是
/// **部署侧**的事，不是客户端该替它做的判断。
///
/// ## 自动档在这里才比较
/// [pickAutoRegion] 需要两台**都**被测过。所以"进这一页各探一次"不只是把徽标画出来，
/// 它同时是自动档唯一一次拿到比较材料的机会（首启那一发另说）。手动档则一个字节都不
/// 自动改（`UpdateServerSettings` 的类注释）。
///
/// ## 每台那一行还报出"这台说最新版是几"
/// 两台的 `version.json` 是各自部署的两份数据文件，会漂。漂的时候"我在这台看不到新版本"
/// 是真话而不是 bug，界面上只有这一格能把它说出来。
class UpdateServerPage extends StatefulWidget {
  const UpdateServerPage({super.key, this.probe, this.health});

  /// 探一台。默认真走 `UpdateService`（它顺手把结论记进健康度单点）。
  /// ⚠ 测试必须换掉它：这一页的结论是拿去替用户换档的，让用例连真网络就是在赌运气。
  final Future<UpdateServerProbe> Function(UpdateServerRegion region)? probe;

  final ChannelHealthStore? health;

  @override
  State<UpdateServerPage> createState() => _UpdateServerPageState();
}

class _UpdateServerPageState extends State<UpdateServerPage> {
  UpdateServerSettings? _settings;
  Map<UpdateServerRegion, UpdateServerProbe>? _probes;
  bool _busy = false;

  /// 健康度单点（测试注入，生产走容器）。做成 getter 而不是字段：
  /// 记账与读徽标必须走同一个口，字段化会允许"探测写到 A、界面读的是 B"。
  ChannelHealthStore get _healthStore =>
      widget.health ?? GetIt.instance<ChannelHealthStore>();

  /// 这一页自己读不回来的那件事（偏好读炸、探测炸）。与"读不到值"分开写：
  /// 空列表和错误列表是两句话。
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    await _loadSettings();
    await _probeAll();
  }

  Future<void> _loadSettings() async {
    try {
      await _healthStore.load();
      final settings = await UpdateServerSettings.load();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// 两台各探一次；自动档据此重挑。
  Future<void> _probeAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    final results = <UpdateServerRegion, UpdateServerProbe>{};
    try {
      // 只在没被注入时才向容器要那一个：探测能被替身接住的页面，不该因为
      // "顺手取了一下 UpdateService"而要求测试把整个装配摆好。
      final probe = widget.probe ?? GetIt.instance<UpdateService>().probeRegion;
      await Future.wait(
        UpdateServerRegion.ordered.map((region) async {
          results[region] = await probe(region);
        }),
      );
      var settings = await UpdateServerSettings.load();
      // 记账落在**这里**（两台一起探完、一起写），而不是服务里那一发：
      // 页面是聚合点，注入替身的用例走的也是同一条写入路 —— 换掉探测不换掉记账，
      // 否则测试绿的是假世界（徽标那条永远空，而生产靠另一条路填）。
      final store = _healthStore;
      for (final result in results.values) {
        await store.record(
          kUpdateHealthFamily,
          result.region.name,
          reachable: result.reachable,
          latencyMs: result.latencyMs,
          httpCode: result.httpCode,
        );
      }
      // 只有停在自动档时才让实测决定用哪台；手动档那一次探测只更新徽标与那一行的数字。
      if (settings.isAuto) {
        final picked = pickAutoRegion(results);
        if (picked != null && picked != settings.autoRegion) {
          await settings.recordAutoProbe(picked);
        }
      }
      settings = await UpdateServerSettings.load();
      if (!mounted) return;
      setState(() {
        _probes = results;
        _settings = settings;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _setAuto() async {
    final settings = await UpdateServerSettings.load();
    await settings.setAuto();
    final reloaded = await UpdateServerSettings.load();
    if (!mounted) return;
    setState(() => _settings = reloaded);
  }

  Future<void> _pin(UpdateServerRegion region) async {
    final settings = await UpdateServerSettings.load();
    await settings.setManual(region);
    final reloaded = await UpdateServerSettings.load();
    if (!mounted) return;
    setState(() => _settings = reloaded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.updateServerTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          HelpNoteRow(
            noteKey: 'update-server-desc',
            helpKey: 'update-server-desc-help',
            text: l10n.updateServerShort,
            helpTitle: l10n.updateServerHelpTitle,
            helpBody: l10n.updateServerHelpBody,
          ),
          if (_error != null)
            Padding(
              key: const ValueKey('update-server-error'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _sectionHeader(l10n.updateServerModeSection, context),
          _modeTile(
            keyName: 'update-server-mode-auto',
            title: l10n.updateServerModeAuto,
            selected: _settings?.isAuto ?? true,
            onTap: _busy ? null : _setAuto,
          ),
          _modeTile(
            keyName: 'update-server-mode-manual',
            title: l10n.updateServerModeManual,
            selected: !(_settings?.isAuto ?? true),
            onTap: _busy ? null : () => _pin(_currentOrFallback()),
          ),
          const SizedBox(height: 16),
          _sectionHeader(l10n.updateServerListSection, context),
          for (final region in UpdateServerRegion.ordered)
            _regionTile(l10n, region),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                key: const ValueKey('update-server-reprobe'),
                onPressed: _busy ? null : _probeAll,
                child: Text(
                  _busy ? l10n.updateServerProbing : l10n.updateServerProbeNow,
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CupertinoActivityIndicator(radius: 7),
                ),
            ],
          ),
          if (_settings?.autoUnprobed ?? false)
            _note(
              keyName: 'update-server-auto-unprobed',
              text: l10n.updateServerAutoUnprobed,
            ),
          if (_allUnreachable)
            _note(
              keyName: 'update-server-both-down',
              text: l10n.updateServerBothDown,
            ),
        ],
      ),
    );
  }

  /// 「手动」那一下点下去时钉住谁：当前生效的那一台（用户看到的就是它）。
  UpdateServerRegion _currentOrFallback() =>
      _settings?.region ?? UpdateServerRegion.defaultRegion;

  /// 两台都被探过、且一台都没通 —— 这时候那句"暂时用默认那一台"必须说出来。
  bool get _allUnreachable {
    final probes = _probes;
    if (probes == null || probes.isEmpty) return false;
    return probes.values.every((p) => !p.reachable);
  }

  Widget _sectionHeader(String text, BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.secondaryLabel(context),
      ),
    ),
  );

  Widget _modeTile({
    required String keyName,
    required String title,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return CupertinoButton(
      key: ValueKey(keyName),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
          if (selected)
            Icon(
              Icons.check,
              size: 18,
              color: AppColors.blue,
              key: ValueKey('$keyName-check'),
            ),
        ],
      ),
    );
  }

  Widget _regionTile(AppLocalizations l10n, UpdateServerRegion region) {
    final probes = _probes;
    final probe = probes == null ? null : probes[region];
    final inUse = _settings != null && _settings!.region == region;
    final title = region == UpdateServerRegion.mainland
        ? l10n.updateRegionMainland
        : l10n.updateRegionInternational;
    return Padding(
      key: ValueKey('update-server-row-${region.name}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        minimumSize: Size.zero,
        // 自动档下这一行也可点：点它就等于"我要钉住这台"（切手动）。
        // 反过来说不行的时候，界面必须解释为什么不行 —— 这里选择让它一直可行。
        onPressed: _busy ? null : () => _pin(region),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (inUse)
                  Text(
                    l10n.updateServerInUse,
                    key: ValueKey('update-server-inuse-${region.name}'),
                    style: const TextStyle(fontSize: 12, color: AppColors.blue),
                  ),
              ],
            ),
            Text(
              region.apiHost,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            Text(
              _statusLine(l10n, probe),
              key: ValueKey('update-server-status-${region.name}'),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            ChannelHealthBadge(
              health: _healthStore.of(kUpdateHealthFamily, region.name),
            ),
          ],
        ),
      ),
    );
  }

  /// 一行里"这台今天怎么样"那句话。
  ///
  /// ⚠ 四档分开说：没探过／没回话／回了非 200／通了。第三档带着状态码 —— 被 CDN 拦
  ///   与这台宕机对用户是同一个后果、两个不同的下一步，数字是唯一的线索。
  String _statusLine(AppLocalizations l10n, UpdateServerProbe? probe) {
    if (probe == null) return l10n.updateServerUnprobed;
    if (!probe.reachable) {
      final code = probe.httpCode;
      return code == null
          ? l10n.updateServerNoAnswer
          : l10n.updateServerHttpStatus(code);
    }
    final version = probe.latestVersion;
    final build = probe.latestBuild;
    final cdn = probe.downloadHost;
    // 回了 200 却既没版本号也没下载地址：这句话说"它答了但我读不出东西"，
    // **不许**退成"还没探过" —— 那会把一次成功的往返说成没有发生过。
    if (version == null && cdn == null) return l10n.updateServerAnswerEmpty;
    final parts = <String>[
      if (version != null)
        l10n.updateServerLatestLine(version, build?.toString() ?? '?'),
      if (cdn != null) l10n.updateServerCdnLine(cdn),
    ];
    return parts.join(' · ');
  }

  Widget _note({required String keyName, required String text}) => Padding(
    key: ValueKey(keyName),
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: AppColors.secondaryLabel(context)),
    ),
  );
}
