import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/app_channel_service.dart';
import '../services/channel_config_codec.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_health_store.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/channel_form_renderer.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/channel_visuals.dart';
import '../widgets/ios_dialog_actions.dart';

/// 自建应用通道设置页（应用通道体系，管理完善度与 Webhook 通道对齐）。
///
/// 支持：企业微信自建应用（corpid/agentid/touser 定向）、飞书自建应用
/// （app_id/receive_id），每通道独立开关、测试发送、健康探测徽标、删除；
/// 保存后经 MethodChannel 同步原生（AppChannelSender 两阶段推送）。
class AppChannelSettingsPage extends StatefulWidget {
  /// 本页一次列出全部通道卡片并整表保存（delete+insert），没有"只编辑某一条"的
  /// 形态。此前这里有个 `initialIndex` 参数，调用方一路传进来但**从未被读取**，
  /// 于是从列表点第 2 条与点 FAB 打开的是同一个页面位置——参数已删。
  /// 若将来要做单通道编辑视图，必须同时改保存路径（只替换该行而不是整表重写），
  /// 否则保存会把其余通道删掉。
  const AppChannelSettingsPage({super.key});

  @override
  State<AppChannelSettingsPage> createState() => _AppChannelSettingsPageState();
}

class _AppChannelSettingsPageState extends State<AppChannelSettingsPage> {
  static const _channel = AppChannels.notification;

  late List<Map<String, dynamic>> _channels;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  String? _testingId;

  /// 健康度读写走单点（与 webhook 页同一份实现与同一套时效口径）
  late final ChannelHealthStore _health;

  /// 通道描述符（原生表）：扩展参数字段清单、必填校验、类型选择器全部由它驱动。
  late final ChannelDescriptorService _descriptors;

  /// 本页有接入引导的类型。**引导内容**只有企微/飞书两套（步骤文案按类型写在 l10n），
  /// 兜底成企微会把用户带去填错的凭据，所以入口只对这两类开放。
  static const _guidedTypes = {'wecom_app', 'feishu_app'};

  @override
  void initState() {
    super.initState();
    _descriptors = GetIt.instance<ChannelDescriptorService>();
    _health = GetIt.instance<ChannelHealthStore>();
    final service = GetIt.instance<AppChannelService>();
    _channels = List<Map<String, dynamic>>.from(service.channels);
    if (_channels.isEmpty) _addChannel('wecom_app');
    for (final c in _channels) {
      _bindControllers(c);
    }
    _loadHealth();
    // 描述符可能晚到（splash 那次没拉成功 / 原生未就绪）：到手后补建控制器并重建表单
    _descriptors.load().then((_) {
      if (!mounted) return;
      for (final c in _channels) {
        // initState 里自动新增的那一行拿不到基址时，这里补上（只补空值，不动用户填过的）
        if ((c['baseUrl']?.toString() ?? '').isEmpty) {
          final base = _descriptors
              .byKey(ChannelConfigCodec.nullableText(c['appType']) ?? '')
              ?.officialBase;
          if (base != null && base.isNotEmpty) {
            c['baseUrl'] = base;
            _controllers['${c['id']}.baseUrl']?.text = base;
          }
        }
        _bindControllers(c);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _bindControllers(Map<String, dynamic> c) {
    final id = ChannelConfigCodec.nullableText(c['id']) ?? '';
    // 基础字段控制器：渲染（名称/地址/密钥输入框）与保存（_channelPayload）
    // 都读取这三个控制器。缺失时输入框空白、且保存会把 baseUrl 清空、secret 置 null
    //（凭据丢失）——回归守卫见 app_channel_settings_page_test「保存不丢字段」。
    _controllers['$id.name'] ??= TextEditingController(
      text: c['name']?.toString() ?? '',
    );
    _controllers['$id.baseUrl'] ??= TextEditingController(
      text: c['baseUrl']?.toString() ?? '',
    );
    _controllers['$id.secret'] ??= TextEditingController(
      text: c['secret']?.toString() ?? '',
    );
    // 扩展参数：字段清单来自描述符，不再手抄 key（抄漏一个 = 该字段显示空白且保存写空）
    final descriptor = _descriptors.byKey(
      ChannelConfigCodec.nullableText(c['appType']) ?? '',
    );
    if (descriptor == null) return;
    ChannelFormRenderer.ensureControllers(
      descriptor,
      _controllers,
      keyPrefix: '$id.',
      existingConfig: _existingConfig(c),
    );
  }

  Map<String, dynamic> _existingConfig(Map<String, dynamic> c) {
    final raw = c['config'];
    if (raw is Map && raw.isNotEmpty) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  /// 换类型时清掉旧类型的字段文本（config 也整体重置，见调用点）
  void _clearFields(String appType, String id) {
    final descriptor = _descriptors.byKey(appType);
    if (descriptor == null) return;
    for (final f in descriptor.fields) {
      _controllers['$id.${f.key}']?.clear();
    }
  }

  /// 「新增」与「改类型」共用同一个选择弹层：列表来自描述符，
  /// 不再硬编码两个 ListTile（硬编码时新增一个应用通道只改原生表，界面上根本选不到）。
  Future<String?> _pickAppChannelType(String title) {
    return showChannelPickerSheet(
      context,
      descriptors: _descriptors.appChannels,
      title: title,
    );
  }

  void _addChannel(String appType) {
    final id = 'app_${DateTime.now().millisecondsSinceEpoch}';
    // 官方基址由描述符给出（私有化部署时用户改这一栏即可）
    final officialBase = _descriptors.byKey(appType)?.officialBase ?? '';
    _channels.add({
      'id': id,
      'name': '',
      'appType': appType,
      'baseUrl': officialBase,
      'secret': null,
      'config': <String, dynamic>{},
      'message_format': 'default',
      'enabled': true,
    });
    _bindControllers(_channels.last);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.appChannelTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addChannel,
            onPressed: () async {
              final picked = await _pickAppChannelType(l10n.selectChannelType);
              if (picked != null) _addChannel(picked);
            },
          ),
          // T04：两个动作分开。**仅测试**不落库（测的是表单当前值，保存前先验一次），
          // **测试并保存** = 先落库再逐条测；测试失败绝不回滚保存（配置是对的、
          // 只是这一刻连不上，回滚会把用户的有效编辑一起吞掉）。
          TextButton(
            onPressed: _saving || _testingId != null ? null : _testAll,
            child: Text(
              l10n.testOnly,
              style: TextStyle(
                fontSize: 16,
                color: _saving || _testingId != null
                    ? AppColors.tertiaryLabel(context)
                    : AppColors.secondaryLabel(context),
              ),
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _saveAll,
            child: Text(
              l10n.testAndSave,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.blue,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            l10n.appChannelPageDesc,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 8),
          // 接入引导入口（v1.59）：详细步骤见 _showSetupGuide
          InkWell(
            onTap: () => _showSetupGuide(context, 'wecom_app'),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.help_outline,
                    size: 14,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l10n.appChannelGuideEntry,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _channels.length; i++)
            _buildChannelCard(context, i, l10n),
        ],
      ),
    );
  }

  Widget _buildChannelCard(
    BuildContext context,
    int index,
    AppLocalizations l10n,
  ) {
    final c = _channels[index];
    final id = ChannelConfigCodec.nullableText(c['id']) ?? '';
    final appType =
        ChannelConfigCodec.nullableText(c['appType']) ?? 'wecom_app';
    final enabled = c['enabled'] == true;
    final health = _health.of('app', id);
    final descriptor = _descriptors.byKey(appType);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.separator(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('app-card-menu-$index'),
            onLongPress: () => _showCardActions(index),
            child: Row(
              children: [
                Text(
                  l10n.appChannelN(index + 1),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.blue,
                  ),
                ),
                // 按当前类型打开对应接入引导（v1.59）。只对**有引导内容**的类型给入口：
                // 引导文案只有企微/飞书两套，兜底成企微会把用户带去填错的凭据。
                if (_guidedTypes.contains(appType))
                  IconButton(
                    icon: const Icon(
                      Icons.help_outline,
                      size: 18,
                      color: AppColors.blue,
                    ),
                    tooltip: l10n.appChannelGuideOpen,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showSetupGuide(context, appType),
                  ),
                const Spacer(),
                CupertinoSwitch(
                  value: enabled,
                  activeTrackColor: AppColors.blue,
                  onChanged: (v) =>
                      setState(() => _channels[index]['enabled'] = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            controller: _controllers['$id.name'],
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: _decoration(context, l10n.appChannelNameLabel),
          ),
          const SizedBox(height: 10),
          _typeSelector(index, context),
          const SizedBox(height: 10),
          TextField(
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            controller: _controllers['$id.baseUrl'],
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: _decoration(context, l10n.appChannelBaseUrlHint),
          ),
          const SizedBox(height: 10),
          TextField(
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            controller: _controllers['$id.secret'],
            obscureText: true,
            style: TextStyle(color: AppColors.primaryLabel(context)),
            decoration: _decoration(
              context,
              channelSecretHintFor(l10n, channelVisual(appType)),
            ),
          ),
          // 扩展参数：字段清单 = 原生描述符（不再在此按类型手抄一份）
          if (descriptor != null)
            ChannelFormRenderer(
              descriptor: descriptor,
              controllers: _controllers,
              keyPrefix: '$id.',
            ),
          if (health != null) ...[
            const SizedBox(height: 10),
            ChannelHealthBadge(health: health),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_testingId == id)
                  ? null
                  : () => _testChannel(index, c),
              icon: (_testingId == id)
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 16),
              label: Text(
                (_testingId == id) ? l10n.testing : l10n.test,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.appChannelDeleteHint,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              // 与长按菜单共用同一条（那里也只有这一条路可走）：确认 + 释放控制器
              onPressed: () => _removeChannel(index),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(l10n.delete, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  /// T05 长按菜单（共用组件见 [CardActionSheet]）。
  ///
  /// ⚠ 这一族**没有「修改」**：卡片本身就是编辑表单（三个凭据框 + 扩展参数都在眼前），
  /// 长按再"跳到编辑态"是空动作。等 T07 拆成「列表页 → 单通道详情页」后补上。
  /// 复制走的是**当前表单值**（`_channelPayload`），所以"改了一半先复制一份"是安全的。
  Future<void> _showCardActions(int index) async {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final id = ChannelConfigCodec.nullableText(c['id']) ?? '';
    final name = (_controllers['$id.name']?.text ?? '').trim();
    final enabled = c['enabled'] == true;
    await CardActionSheet.show(
      context,
      title: name.isEmpty ? l10n.appChannelN(index + 1) : name,
      actions: [
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateChannel(index),
        ),
        CardAction(
          icon: enabled ? Icons.toggle_off : Icons.toggle_on,
          label: enabled ? l10n.turnOff : l10n.turnOn,
          iconColor: enabled ? AppColors.orange : AppColors.green,
          onTap: () => setState(() => _channels[index]['enabled'] = !enabled),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          onTap: () => _removeChannel(index),
        ),
      ],
    );
  }

  /// 删除一条通道 —— **卡片红叉与长按菜单共用这一条**（T06 的单一咽喉：确认写在
  /// 执行删除的函数里，而不是写在每个调用点，否则新增入口必然漏一条）。
  Future<void> _removeChannel(int index) async {
    final l10n = AppLocalizations.of(context);
    final c = _channels[index];
    final id = ChannelConfigCodec.nullableText(c['id']) ?? '';
    final name = (_controllers['$id.name']?.text ?? '').trim();
    final confirmed = await IosDialogActions.askConfirm(
      context,
      title: l10n.confirmDelete,
      message: l10n.deleteChannelConfirm(
        name.isEmpty ? l10n.appChannelN(index + 1) : name,
      ),
      confirmText: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    // 控制器按 `<id>.<字段>` 存在 map 里，只删 `_channels` 那一条会让它们整批留在
    // map 中（页面关闭前不会回收）。今天它们已经不可达（新通道拿新 id），但留着
    // 就是下一次"id 复用即串台"的现成弹药，所以删。
    _releaseControllers(id);
    setState(() => _channels.removeAt(index));
    await _health.remove('app', id);
  }

  /// 释放某条通道的全部控制器（名称/地址/密钥 + 描述符声明的扩展参数）。
  void _releaseControllers(String id) {
    if (id.isEmpty) return;
    final prefix = '$id.';
    for (final key
        in _controllers.keys
            .where((k) => k.startsWith(prefix))
            .toList(growable: false)) {
      _controllers.remove(key)?.dispose();
    }
  }

  /// 复制出一条同配置通道：**新 id** ⇒ 健康记录不跟着复制（刚复制的那条没测过，
  /// 顶着一枚绿勾比顶着空白更糟）。追加在末尾，不插在原行后面：`_channels` 的下标
  /// 被卡片构建与 `_testChannel(i, …)` 共用，中间插入会让进行中的测试对错通道。
  void _duplicateChannel(int index) {
    final l10n = AppLocalizations.of(context);
    final src = _channels[index];
    final payload = _channelPayload(index);
    final name = payload['name']?.toString().trim() ?? '';
    final id = 'app_${DateTime.now().millisecondsSinceEpoch}';
    _channels.add({
      ...src,
      // 表单当前值优先（改了一半就复制，复制到的应是眼前这份）；
      // enabled / message_format 也随 _channelPayload 一起带过来
      ...payload,
      'id': id,
      'name': name.isEmpty ? '' : l10n.copyOfName(name),
    });
    _bindControllers(_channels.last);
    setState(() {});
  }

  /// 接入步骤引导（v1.59）：按通道类型展示详细参数获取步骤 + 注意事项。
  /// iOS 底部弹层，与页面其他弹层风格一致。
  void _showSetupGuide(BuildContext context, String appType) {
    final l10n = AppLocalizations.of(context);
    final isWecom = appType != 'feishu_app';
    // 调用方只可能传这两个值（引导入口已按类型收窄）；写死默认值会让未知类型
    // 静默显示企微步骤，故此处显式断言而不是兜底。
    assert(_guidedTypes.contains(appType));
    final title = isWecom
        ? l10n.appChannelGuideTitleWecom
        : l10n.appChannelGuideTitleFeishu;
    final prep = isWecom
        ? l10n.appChannelGuidePrepWecom
        : l10n.appChannelGuidePrepFeishu;
    final steps = isWecom
        ? <(String, String)>[
            (l10n.appChannelGuideWecomS1, l10n.appChannelGuideWecomS1Desc),
            (l10n.appChannelGuideWecomS2, l10n.appChannelGuideWecomS2Desc),
            (l10n.appChannelGuideWecomS3, l10n.appChannelGuideWecomS3Desc),
            (l10n.appChannelGuideWecomS4, l10n.appChannelGuideWecomS4Desc),
            (l10n.appChannelGuideWecomS5, l10n.appChannelGuideWecomS5Desc),
            (l10n.appChannelGuideWecomS6, l10n.appChannelGuideWecomS6Desc),
          ]
        : <(String, String)>[
            (l10n.appChannelGuideFeishuS1, l10n.appChannelGuideFeishuS1Desc),
            (l10n.appChannelGuideFeishuS2, l10n.appChannelGuideFeishuS2Desc),
            (l10n.appChannelGuideFeishuS3, l10n.appChannelGuideFeishuS3Desc),
            (l10n.appChannelGuideFeishuS4, l10n.appChannelGuideFeishuS4Desc),
            (l10n.appChannelGuideFeishuS5, l10n.appChannelGuideFeishuS5Desc),
            (l10n.appChannelGuideFeishuS6, l10n.appChannelGuideFeishuS6Desc),
          ];
    final notes = <String>[
      l10n.appChannelGuideNote1,
      l10n.appChannelGuideNote2,
      l10n.appChannelGuideNote3,
      l10n.appChannelGuideNote4,
      l10n.appChannelGuideNote5,
    ];

    showModalBottomSheet(
      context: context,
      // 颜色/圆角放在 sheet 自己的 Material 上：涂在中间层 Container 会吞掉
      // 选项 ListTile 的水波纹（Flutter 调试断言，6.7 闸门同类问题）。
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.separator(sheetContext),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(sheetContext),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg(sheetContext),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          prep,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.primaryLabel(sheetContext),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var i = 0; i < steps.length; i++) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: AppColors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    steps[i].$1,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primaryLabel(
                                        sheetContext,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    steps[i].$2,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: AppColors.secondaryLabel(
                                        sheetContext,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (i != steps.length - 1) const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        height: 0.5,
                        color: AppColors.separator(sheetContext),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.appChannelGuideNoteTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryLabel(sheetContext),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final note in notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.secondaryLabel(sheetContext),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: AppColors.secondaryLabel(
                                      sheetContext,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: AppColors.separator(sheetContext)),
              // ⚠ 不用 ListTile：它要求最近的 Material 祖先绘制 ink，被带背景色的
              // Container 包裹时会触发 "ink splashes may be invisible" 调试断言
              InkWell(
                onTap: () => Navigator.pop(sheetContext),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      l10n.appChannelGuideClose,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 12,
        color: AppColors.tertiaryLabel(context),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.separator(context)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
      filled: true,
      fillColor: AppColors.inputBg(context),
    );
  }

  Widget _typeSelector(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final type =
        ChannelConfigCodec.nullableText(_channels[index]['appType']) ??
        'wecom_app';
    final descriptor = _descriptors.byKey(type);
    // 名称优先取描述符的 labelKey（原生表为准），取不到再退回 slug 表
    final label = descriptor == null
        ? channelDisplayNameFor(l10n, type)
        : channelNameOf(l10n, descriptor);
    final visual = channelVisual(type);
    return InkWell(
      onTap: () => _pickType(index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.inputBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.separator(context)),
        ),
        child: Row(
          children: [
            Icon(visual.icon, size: 16, color: visual.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.primaryLabel(context),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.tertiaryLabel(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 换类型：扩展参数与 config 一起重置。两套应用通道的凭据字段完全不同，
  /// 把 corpid 残留塞进飞书通道不会报错、却会让用户以为「配过了」——合并语义
  /// （[ChannelFormRenderer.collect] 保留未知键）在这里必须显式让位于重置。
  Future<void> _pickType(int index) async {
    final current =
        ChannelConfigCodec.nullableText(_channels[index]['appType']) ??
        'wecom_app';
    final picked = await _pickAppChannelType(
      AppLocalizations.of(context).selectChannelType,
    );
    if (picked == null || picked == current || !mounted) return;
    final id = _channels[index]['id'] as String;
    _clearFields(current, id);
    setState(() {
      _channels[index]['appType'] = picked;
      _channels[index]['config'] = <String, dynamic>{};
    });
    _bindControllers(_channels[index]);
    if (mounted) setState(() {});
  }

  // ── 测试 / 保存 ──────────────────────────────────────────────────────

  /// 扩展参数收集：字段清单与默认值都由描述符决定。
  /// 描述符未就绪时**原样回传已存 config** —— 重建会把 corpid/app_id 写空（凭据丢失）。
  /// 校验提示里用字段自己的显示名，而不是 `corpid` 这种存储键
  String _fieldLabel(ChannelDescriptor descriptor, String fieldKey) {
    final f = descriptor.fields.where((e) => e.key == fieldKey).firstOrNull;
    return f == null
        ? fieldKey
        : channelLabelFor(AppLocalizations.of(context), f.labelKey);
  }

  Map<String, dynamic> _configOf(Map<String, dynamic> c) {
    final existing = _existingConfig(c);
    final descriptor = _descriptors.byKey(
      ChannelConfigCodec.nullableText(c['appType']) ?? '',
    );
    if (descriptor == null) return existing;
    return ChannelFormRenderer.collect(
      descriptor,
      _controllers,
      existing,
      keyPrefix: '${c['id']}.',
    );
  }

  Map<String, dynamic> _channelPayload(int index, {bool forTest = false}) {
    final c = _channels[index];
    final id = ChannelConfigCodec.nullableText(c['id']) ?? '';
    return {
      'appType': c['appType'],
      // name 必须进载荷：它此前只在 _saveAll 里做非空校验、从不回填 ⇒ 合并
      // `{..._channels[i], ...payload}` 时用的仍是 _addChannel 写下的 ''（新建）
      // 或加载时的旧名（改名），列表页/首页标签因此看不到名字。
      'name':
          _controllers['$id.name']?.text.trim() ??
          (c['name']?.toString() ?? ''),
      // 控制器缺失时保留原值（防空值覆盖导致 baseUrl/secret 丢失）
      'baseUrl':
          _controllers['$id.baseUrl']?.text.trim() ??
          (c['baseUrl']?.toString() ?? ''),
      'secret': _controllers['$id.secret']?.text.trim() ?? c['secret'],
      'config': _configOf(c),
      if (!forTest) 'message_format': c['message_format'] ?? 'default',
      if (!forTest) 'enabled': c['enabled'] == true,
    };
  }

  /// 「仅测试」：不落库，把每条**启用**通道按当前表单值依次测一遍。
  ///
  /// 读的是控制器里的值（`_channelPayload(forTest: true)`），所以"先验再存"是安全的：
  /// 测坏了也不会把已保存的配置改掉。结果逐条写进健康单点 ⇒ 异常能冒到首页。
  Future<void> _testAll() async {
    for (var i = 0; i < _channels.length; i++) {
      if (_channels[i]['enabled'] != true) continue;
      await _testChannel(i, _channels[i]);
      if (!mounted) return;
    }
  }

  Future<void> _testChannel(int index, Map<String, dynamic> c) async {
    final l10n = AppLocalizations.of(context);
    final id = ChannelConfigCodec.nullableText(c['id']) ?? '';
    setState(() => _testingId = id);
    final watch = Stopwatch()..start();
    try {
      final result = await _channel.invokeMethod('testAppChannel', {
        ..._channelPayload(index, forTest: true),
        'appType': c['appType'],
      });
      final success = result['success'] as bool? ?? false;
      final message = result['message'] as String? ?? '';
      await _recordHealth(
        id,
        reachable: success,
        latencyMs: watch.elapsedMilliseconds,
      );
      _showToast(
        '${success ? l10n.test : l10n.testFailedMsg(message)} $message',
        success,
      );
    } catch (e) {
      await _recordHealth(
        id,
        reachable: false,
        latencyMs: watch.elapsedMilliseconds,
      );
      _showToast('${l10n.appChannelTestFailed}$e', false);
    } finally {
      if (mounted) setState(() => _testingId = null);
    }
  }

  /// 记一次「测试」的结果到健康单点。
  ///
  /// ⚠️ 这里**不做进入页面时的自动探测**（与 webhook 的 6h 后台刷新不同）：
  /// `testAppChannel` 会真的向企业微信/飞书发一条测试消息，自动探测等于每 6 小时
  /// 骚扰用户一次。要做自动健康度，得先加只换 access_token 的非侵入探测
  /// （roadmap 第 3.1 步 / 本步 6e）。
  Future<void> _recordHealth(
    String id, {
    required bool reachable,
    required int latencyMs,
  }) => _health.record('app', id, reachable: reachable, latencyMs: latencyMs);

  Future<void> _saveAll() async {
    final l10n = AppLocalizations.of(context);
    // ── 表单校验：启用通道的必填字段不能为空（name 从控制器读，_channelPayload 不含 name）──
    for (var i = 0; i < _channels.length; i++) {
      final c = _channels[i];
      if (c['enabled'] != true) continue;
      final id = ChannelConfigCodec.nullableText(c['id']) ?? '';
      final name = _controllers['$id.name']?.text.trim() ?? '';
      final payload = _channelPayload(i);
      final baseUrl = payload['baseUrl']?.toString() ?? '';
      if (name.isEmpty) {
        _showToast(l10n.appChannelErrNameRequired, false);
        return;
      }
      if (baseUrl.isEmpty) {
        _showToast(l10n.appChannelErrBaseUrlRequired, false);
        return;
      }
      // 扩展参数必填项：以前这里**不校验**，靠原生 require() 抛错，用户只看到一句"保存失败"
      final descriptor = _descriptors.byKey(
        ChannelConfigCodec.nullableText(c['appType']) ?? '',
      );
      if (descriptor == null) continue;
      final missing = ChannelFormRenderer.missingRequired(
        descriptor,
        _controllers,
        keyPrefix: '$id.',
      );
      if (missing.isNotEmpty) {
        _showToast(
          l10n.appChannelErrFieldsRequired(
            missing.map((k) => _fieldLabel(descriptor, k)).join(', '),
          ),
          false,
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final service = GetIt.instance<AppChannelService>();
      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < _channels.length; i++) {
        payload.add({..._channels[i], ..._channelPayload(i)});
      }
      await service.saveChannels(payload);
      if (!mounted) return;
      _showToast(l10n.appChannelSaveOk, true);
      // ── 保存成功后自动发起连接测试（fire-and-forget，不阻塞保存反馈）──
      for (var i = 0; i < _channels.length; i++) {
        final c = _channels[i];
        if (c['enabled'] != true) continue;
        _testChannel(i, c);
      }
    } catch (e) {
      _showToast('${l10n.appChannelSaveFailed}$e', false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadHealth() async {
    await _health.load();
    if (mounted) setState(() {});
  }

  void _showToast(String message, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: ok ? AppColors.green : AppColors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
