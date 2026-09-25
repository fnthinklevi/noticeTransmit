import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../models/webhook_channel.dart';
import '../services/channel_config_codec.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_url_policy.dart';
import '../services/channel_health_store.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/card_action_sheet.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/channel_visuals.dart';

// R3 拆分：通道卡片构建巨型方法迁出（extension 共享 State 私有成员）
part 'webhook_settings_item.dart';

class WebhookSettingsPage extends StatefulWidget {
  final List<Map<String, dynamic>> webhookChannels;

  const WebhookSettingsPage({super.key, required this.webhookChannels});

  @override
  State<WebhookSettingsPage> createState() => _WebhookSettingsPageState();
}

class _WebhookSettingsPageState extends State<WebhookSettingsPage> {
  static const _channel = AppChannels.notification;

  /// 通道描述符（原生表）：secret/模板显隐、类型候选列表与名称都按它渲染
  late final ChannelDescriptorService _descriptors;
  late List<TextEditingController> _webhookControllers;
  late List<TextEditingController> _nameControllers;
  late List<TextEditingController> _secretControllers;
  late List<TextEditingController> _templateControllers;
  late List<bool> _webhookEnabled;
  late List<bool> _secretVisible;
  late List<WebhookMessageFormat> _messageFormats;
  // 渠道类型：'auto' 表示自动识别（按 URL host 探测），否则为用户手动指定的类型值
  late List<String> _channelTypes;
  // 各行的既有通道 id，与上面所有列表**并行同下标**。删除行时必须同步 removeAt：
  // widget.webhookChannels 是 final 输入、不会随删除收缩，按其下标取 id 会让
  // 删掉第 1 条后其余各行继承错位的 id（保存走 delete+insert，健康缓存/送达归属全错）。
  late List<String?> _channelIds;
  bool _isTesting = false;

  /// 通道健康：读写、键格式与 6h 时效全在 [ChannelHealthStore]（第 6 步单点），
  /// 页面只负责渲染与「进页刷新过期条目」。此前这里自己读 prefs、自己写 prefs、
  /// 自己判时效，应用通道页又写一份 —— 三族通道的徽标因此行为各不相同。
  late final ChannelHealthStore _health;
  bool _probing = false;
  String? _testResult;
  bool? _testSuccess;
  bool? _testSigned;
  int? _testIndex;
  bool _isSaving = false;

  /// 当前行的**有效类型 slug**：手动指定优先，'auto' 时按 URL host 探测。
  ///
  /// 以前这里返回 Dart 枚举，于是「Dart 有没有登记这个平台」会决定界面能不能显示它。
  /// 第 5 步起一律用 slug（与原生描述符的 `key`、送达键 `chan:<slug>` 同一口径），
  /// 原生新增通道时 Dart 不再需要跟着加枚举臂。
  String _effectiveSlug(int index) {
    final manual = _channelTypes[index];
    if (manual.isNotEmpty && manual != 'auto') return manual;
    return WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    ).value;
  }

  /// 该行的描述符（原生表）；描述符未拉到时 null，调用方按"不收窄"处理。
  ChannelDescriptor? _descriptorFor(int index) =>
      _descriptors.byKey(_effectiveSlug(index));

  /// 渠道类型图标与品牌色
  ChannelVisual _typeVisual(String slug) => channelVisual(slug);

  /// 渠道类型本地化名称：描述符的 labelKey 优先，Dart slug 表兜底，最后原样显示 slug
  String _channelTypeLabel(BuildContext context, String slug) {
    final l10n = AppLocalizations.of(context);
    final descriptor = _descriptors.byKey(slug);
    return descriptor == null
        ? channelDisplayNameFor(l10n, slug)
        : channelNameOf(l10n, descriptor);
  }

  /// 消息格式本地化名称（品牌/格式名无需翻译）
  String _messageFormatLabel(BuildContext context, WebhookMessageFormat fmt) {
    final l10n = AppLocalizations.of(context);
    switch (fmt) {
      case WebhookMessageFormat.defaultFormat:
        return l10n.msgFormatDefault;
      case WebhookMessageFormat.text:
        return l10n.msgFormatText;
      case WebhookMessageFormat.markdown:
        return 'Markdown';
      case WebhookMessageFormat.json:
        return 'JSON';
      case WebhookMessageFormat.xml:
        return 'XML';
    }
  }

  /// 渠道类型选择器：iOS 风格输入框样式 + 弹窗选择（替代 Material DropdownButton）
  Widget _buildChannelTypeSelector(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manual = _channelTypes[index];
    final isAuto = manual.isEmpty || manual == 'auto';
    final detectedSlug = WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    ).value;
    final currentSlug = isAuto ? detectedSlug : manual;
    final display = isAuto
        ? (detectedSlug == 'generic'
              ? l10n.channelTypeAuto
              : l10n.channelTypeAutoWith(
                  _channelTypeLabel(context, detectedSlug),
                ))
        : _channelTypeLabel(context, currentSlug);
    final visual = _typeVisual(currentSlug);

    return InkWell(
      onTap: () => _showChannelTypePicker(index, context),
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
                display,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
                ),
                overflow: TextOverflow.ellipsis,
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

  /// 类型下拉的候选项：**描述符列表**（原生表为准）。
  /// 描述符没拉到时退回 Dart 枚举（12 个），保证离线也能改类型。
  List<String> _typeSlugs() {
    final descriptors = _descriptors.webhook;
    if (descriptors.isNotEmpty) {
      return descriptors.map((d) => d.key).toList(growable: false);
    }
    return WebhookChannelType.values
        .map((t) => t.value)
        .toList(growable: false);
  }

  /// 渠道类型选择弹窗（与主题/语言选择同款 iOS 风格）
  void _showChannelTypePicker(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detectedSlug = WebhookChannel.detectTypeFromUrl(
      _webhookControllers[index].text,
    ).value;
    final current = _channelTypes[index];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          l10n.selectChannelType,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                _buildTypeOption(
                  context,
                  icon: Icons.auto_awesome,
                  color: AppColors.blue,
                  label: detectedSlug == 'generic'
                      ? l10n.channelTypeAuto
                      : l10n.channelTypeAutoWith(
                          _channelTypeLabel(context, detectedSlug),
                        ),
                  selected: current.isEmpty || current == 'auto',
                  onTap: () {
                    setState(() => _channelTypes[index] = 'auto');
                    Navigator.pop(dialogContext);
                  },
                ),
                ..._typeSlugs().map((slug) {
                  final visual = _typeVisual(slug);
                  return _buildTypeOption(
                    context,
                    icon: visual.icon,
                    color: visual.color,
                    label: _channelTypeLabel(context, slug),
                    selected: current == slug,
                    onTap: () {
                      setState(() => _channelTypes[index] = slug);
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildTypeOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(fontSize: 15, color: AppColors.primaryLabel(context)),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: AppColors.blue)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  void initState() {
    super.initState();
    _descriptors = GetIt.instance<ChannelDescriptorService>();
    _health = GetIt.instance<ChannelHealthStore>();
    // ⚠ 这里**不得用硬转型**：通道列表可能来自备份文件（形状不可信 ——
    // `enabled` 可能是 0/1、值可能是数字、键可能是 snake_case），一个 `as bool?`
    // 就能让整个页面在 initState 抛异常，表现为"恢复备份后打不开 webhook 设置页"。
    // 归一化统一走 ChannelConfigCodec（与 loadChannels 同一套读法）。
    _webhookControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: ChannelConfigCodec.nullableText(c['url']) ?? '',
          ),
        )
        .toList();
    _nameControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: ChannelConfigCodec.nullableText(c['name']) ?? '',
          ),
        )
        .toList();
    _secretControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: ChannelConfigCodec.nullableText(c['secret']) ?? '',
          ),
        )
        .toList();
    _templateControllers = widget.webhookChannels
        .map(
          (c) => TextEditingController(
            text: ChannelConfigCodec.nullableText(c['message_template']) ?? '',
          ),
        )
        .toList();
    _webhookEnabled = widget.webhookChannels
        .map(
          (c) => c.containsKey('enabled')
              ? ChannelConfigCodec.flag(c['enabled'])
              : true,
        )
        .toList();
    _secretVisible = widget.webhookChannels.map((c) => false).toList();
    _messageFormats = widget.webhookChannels
        .map(
          (c) => WebhookMessageFormat.fromValue(
            ChannelConfigCodec.nullableText(c['message_format']) ??
                ChannelConfigCodec.nullableText(c['messageFormat']),
          ),
        )
        .toList();
    // 已有通道保留原类型；空值的新通道默认自动识别
    _channelTypes = widget.webhookChannels.map((c) {
      final t =
          ChannelConfigCodec.nullableText(c['channelType']) ??
          ChannelConfigCodec.nullableText(c['type']) ??
          ChannelConfigCodec.nullableText(c['channel_type']) ??
          'auto';
      return t.isEmpty ? 'auto' : t;
    }).toList();
    _channelIds = widget.webhookChannels
        .map((c) => ChannelConfigCodec.nullableText(c['id']))
        .toList();
    if (_webhookControllers.isEmpty) {
      _webhookControllers.add(TextEditingController());
      _nameControllers.add(TextEditingController());
      _secretControllers.add(TextEditingController());
      _templateControllers.add(TextEditingController());
      _webhookEnabled.add(true);
      _secretVisible.add(false);
      _messageFormats.add(WebhookMessageFormat.defaultFormat);
      _channelTypes.add('auto');
      _channelIds.add(null);
    }
    // 进入设置页即读取缓存健康状态；启用的通道超 6 小时未探测则后台刷新
    _loadHealthAndProbe();
    // splash 那次没拉成功时兜底重取：到手后重建，否则显隐判断会一直停在"按显示处理"
    _descriptors.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// 进页：确保健康单点已装载（splash 装过就是 no-op），再刷新过期条目
  Future<void> _loadHealthAndProbe() async {
    await _health.load();
    if (!mounted) return;
    setState(() {});
    _probeStaleChannels();
  }

  /// 启用通道超过 [ChannelHealthStore.staleness] 未探测 → 后台逐个探测并写回单点
  Future<void> _probeStaleChannels() async {
    if (_probing) return;
    final now = DateTime.now();
    final stale = widget.webhookChannels.where((c) {
      if (c['enabled'] != true) return false;
      final id = c['id']?.toString() ?? '';
      if (id.isEmpty) return false;
      return ChannelHealthStore.needsProbe(_health.of('webhook', id), now: now);
    }).toList();
    if (stale.isEmpty) return;
    _probing = true;
    for (final c in stale) {
      final id = c['id']?.toString() ?? '';
      final url = c['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final watch = Stopwatch()..start();
      try {
        final r = await _channel.invokeMethod('probeChannelHealth', {
          'url': url,
        });
        await _health.record(
          'webhook',
          id,
          reachable: r['reachable'] as bool? ?? false,
          latencyMs:
              (r['latencyMs'] as num?)?.toInt() ?? watch.elapsedMilliseconds,
          httpCode: (r['httpCode'] as num?)?.toInt(),
        );
        if (mounted) setState(() {});
      } catch (_) {
        // 探测本身失败不写「不可达」：那会把徽标钉成红，比"这次没探到"更误导
      }
    }
    _probing = false;
  }

  void _addWebhookField() {
    setState(() {
      _webhookControllers.add(TextEditingController());
      _nameControllers.add(TextEditingController());
      _secretControllers.add(TextEditingController());
      _templateControllers.add(TextEditingController());
      _webhookEnabled.add(true);
      _secretVisible.add(false);
      _messageFormats.add(WebhookMessageFormat.defaultFormat);
      _channelTypes.add('auto');
      _channelIds.add(null);
    });
  }

  void _removeWebhookField(int index) {
    setState(() {
      _webhookControllers[index].dispose();
      _nameControllers[index].dispose();
      _secretControllers[index].dispose();
      _templateControllers[index].dispose();
      _webhookControllers.removeAt(index);
      _nameControllers.removeAt(index);
      _secretControllers.removeAt(index);
      _templateControllers.removeAt(index);
      _webhookEnabled.removeAt(index);
      _secretVisible.removeAt(index);
      _messageFormats.removeAt(index);
      _channelTypes.removeAt(index);
      _channelIds.removeAt(index);
      if (_webhookControllers.isEmpty) {
        _webhookControllers.add(TextEditingController());
        _nameControllers.add(TextEditingController());
        _secretControllers.add(TextEditingController());
        _templateControllers.add(TextEditingController());
        _webhookEnabled.add(true);
        _secretVisible.add(false);
        _messageFormats.add(WebhookMessageFormat.defaultFormat);
        _channelTypes.add('auto');
        _channelIds.add(null);
      }
    });
  }

  /// T05 长按菜单（共用组件见 [CardActionSheet]）。
  ///
  /// ⚠ 这一族**没有「修改」**：本页是全量平铺编辑器，该行的三个输入框就在眼前，
  /// 长按后再"跳到编辑态"是空动作。等 T07 拆成「列表页 → 单通道详情页」之后，
  /// 「修改」在 webhook 上才成为真动作（届时这一条要补上，别当成漏做）。
  Future<void> _showRowActions(int index) async {
    final l10n = AppLocalizations.of(context);
    final name = _nameControllers[index].text.trim();
    final enabled = _webhookEnabled[index];
    await CardActionSheet.show(
      context,
      title: name.isEmpty ? l10n.channelN(index + 1) : name,
      actions: [
        CardAction(
          icon: Icons.copy,
          label: l10n.duplicate,
          onTap: () => _duplicateWebhookRow(index),
        ),
        CardAction(
          icon: enabled ? Icons.toggle_off : Icons.toggle_on,
          label: enabled ? l10n.turnOff : l10n.turnOn,
          iconColor: enabled ? AppColors.orange : AppColors.green,
          onTap: () => _toggleWebhookEnabled(index),
        ),
        CardAction(
          icon: Icons.delete_outline,
          label: l10n.delete,
          danger: true,
          // 只剩一行时不许删（与卡片上删除按钮的显隐条件同一口径）⇒ 置灰而不是藏起来
          onTap: _webhookControllers.length > 1
              ? () => _removeWebhookField(index)
              : null,
        ),
      ],
    );
  }

  /// 复制出一行同配置的新通道。**新行不带 id**（`_channelIds.add(null)`）⇒ 健康记录
  /// 不会跟着复制：刚复制出来的那条本来就没测过，顶着一枚绿勾比顶着空白更糟。
  /// 追加在末尾而不是紧贴原行：本页所有行状态都是**并行列表按下标**寻址
  /// （`_testIndex` 等），中间插入会让它们集体错位（这个页面的老缺陷类别）。
  void _duplicateWebhookRow(int index) {
    final l10n = AppLocalizations.of(context);
    final name = _nameControllers[index].text.trim();
    setState(() {
      _webhookControllers.add(
        TextEditingController(text: _webhookControllers[index].text),
      );
      _nameControllers.add(
        TextEditingController(text: name.isEmpty ? '' : l10n.copyOfName(name)),
      );
      _secretControllers.add(
        TextEditingController(text: _secretControllers[index].text),
      );
      _templateControllers.add(
        TextEditingController(text: _templateControllers[index].text),
      );
      _webhookEnabled.add(_webhookEnabled[index]);
      _secretVisible.add(false);
      _messageFormats.add(_messageFormats[index]);
      _channelTypes.add(_channelTypes[index]);
      _channelIds.add(null);
    });
  }

  void _toggleWebhookEnabled(int index) {
    setState(() {
      _webhookEnabled[index] = !_webhookEnabled[index];
    });
  }

  void _toggleSecretVisible(int index) {
    setState(() {
      _secretVisible[index] = !_secretVisible[index];
    });
  }

  /// 校验不通过：收起"保存中"状态、点名问题、停在页面上让用户改。
  ///
  /// 三条必填/合法性检查共用它，避免每处再抄一遍"翻回按钮状态 + 弹条 + return"
  /// （以前各抄一份，结果有一处忘了复位按钮 ⇒ 按钮永久禁用）。
  void _saveBlocked(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    setState(() => _isSaving = false);
  }

  Future<void> _saveAndBack() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isSaving = true;
    });
    // 保存前一次性校验（T03）：必填缺失/非法一律**点名到哪一行、缺什么**并阻止保存。
    // 为什么必须挡在保存前，而不是"让它存进去、发的时候再说"：
    //  - 空 URL 的行会在落库后被原生 filter 掉（`WebhookSender.updateChannelConfigs`），
    //    而本页保存时也只收 `url.isNotEmpty` 的行 ⇒ 用户在这一行敲过的名字与密钥
    //    会**静默消失**，表现为"我明明填了，怎么又空了"；
    //  - `secretRequired` 的平台缺密钥时签名算不出来，服务端直接拒收（钉钉 31000），
    //    用户看到的是"配好了却永远收不到"。
    // 判据不在本页另立：URL 规则用 `ChannelUrlPolicy`（与原生、备份恢复同一份），
    // "必须要密钥"读描述符能力位 `secretRequired`（原生表派生）。描述符没拉到就跳过
    // （拿不到元数据时不许凭猜测拦人保存）。
    for (int i = 0; i < _webhookControllers.length; i++) {
      final url = _webhookControllers[i].text.trim();
      if (url.isEmpty) {
        final typedSomething =
            _nameControllers[i].text.trim().isNotEmpty ||
            _secretControllers[i].text.trim().isNotEmpty ||
            _templateControllers[i].text.trim().isNotEmpty;
        // 整行空白 = 加了行又放弃，按原行为丢掉，不算错误
        if (typedSomething) {
          _saveBlocked(l10n.webhookUrlMissing(i + 1));
          return;
        }
        continue;
      }
      if (!ChannelUrlPolicy.isHttpUrl(url)) {
        _saveBlocked(l10n.webhookUrlInvalid(i + 1));
        return;
      }
      final descriptor = _descriptorFor(i);
      if (descriptor != null &&
          descriptor.requiresSecret &&
          _secretControllers[i].text.trim().isEmpty) {
        _saveBlocked(l10n.webhookSecretMissing(i + 1));
        return;
      }
    }
    final channels = <Map<String, dynamic>>[];
    for (int i = 0; i < _webhookControllers.length; i++) {
      final url = _webhookControllers[i].text.trim();
      final name = _nameControllers[i].text.trim();
      final secret = _secretControllers[i].text.trim();
      if (url.isNotEmpty) {
        // 保留已有通道 id（webhook_channels.id 是 PRIMARY KEY，缺失会被 replace 覆盖）
        // 取并行列表 _channelIds —— 不能按 i 读 widget.webhookChannels：那是 final
        // 输入、不随删除收缩，删过一行后其余行会继承错位的 id（保存走 delete+insert，
        // 健康缓存 channel_health_<id> 与送达归属会整体串台）。
        final existingId = i < _channelIds.length ? _channelIds[i] : null;
        // 渠道类型：手动指定优先（自建 Telegram/Bark 代理等场景），'auto' 才按 URL host 探测
        final manualType = _channelTypes[i];
        final channelType = (manualType == 'auto' || manualType.isEmpty)
            ? WebhookChannel.detectTypeFromUrl(url).value
            : manualType;
        final template = _templateControllers[i].text.trim();
        channels.add({
          'id': (existingId != null && existingId.isNotEmpty)
              ? existingId
              : 'wh_${DateTime.now().millisecondsSinceEpoch}_$i',
          'url': url,
          'name': name,
          'channelType': channelType,
          'enabled': _webhookEnabled[i],
          if (secret.isNotEmpty) 'secret': secret,
          'message_format': _messageFormats[i].value,
          if (template.isNotEmpty) 'message_template': template,
        });
      }
    }
    if (!mounted) return;
    Navigator.pop(context, channels);
  }

  Future<bool> _testWebhook(int index) async {
    final l10n = AppLocalizations.of(context);
    final url = _webhookControllers[index].text.trim();
    final secret = _secretControllers[index].text.trim();
    if (url.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testResult = l10n.webhookUrlRequired;
        _testIndex = index;
      });
      return false;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
      _testSigned = null;
      _testIndex = index;
    });

    try {
      final watch = Stopwatch()..start();
      // 传递 secret 让原生端做签名验证，返回真实送达结果（含状态/HTTP码/签名标识）
      final result = await _channel.invokeMethod('testWebhook', {
        'url': url,
        if (secret.isNotEmpty) 'secret': secret,
        // 把用户在通道上选过的类型一起传过去：只给 URL 时，自建 Gotify / 私有 ntfy
        // 会被原生按 host 降级成通用 webhook 判定，测试按钮的结论与真实推送不一致。
        'channelType': _channelTypes[index],
      });
      final success = result['success'] as bool? ?? false;
      final message = result['message'] as String? ?? l10n.unknownError;
      final signed = result['signed'] as bool? ?? false;

      if (!mounted) return false;
      // T04：手动测试的结果落健康单点，否则"测出失败"只活在这一屏 ——
      // 首页与通道状态页永远显示 unknown，配置异常冒不上去。
      // 新增行还没有稳定 id（保存前 `id` 为空）⇒ 不记：没有归属的记账比不记更糟
      // （会把下一条复用该位置的通道的徽标钉错）。
      final testedId = index < _channelIds.length ? _channelIds[index] : null;
      if (testedId != null && testedId.isNotEmpty) {
        await _health.record(
          'webhook',
          testedId,
          reachable: success,
          latencyMs: watch.elapsedMilliseconds,
        );
        if (!mounted) return false;
      }
      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testResult = message;
        _testSigned = signed;
      });
      return success;
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testSigned = false;
        _testResult = l10n.testFailedMsg(e.toString());
      });
      return false;
    }
  }

  /// T04「仅测试」：把每一行按**当前表单值**依次测一遍，不落库、不退出页面。
  ///
  /// 为什么单独要有这个动作：本页是全量平铺编辑器，「保存」= 校验 + 落库 + pop，
  /// 以前唯一的测试入口在每张卡片里，逐条手点；用户想"整页先验一遍再决定存不存"
  /// 只能一边点一边担心自己是不是已经把半成品存进去了。
  /// 测出来的失败会写健康单点 ⇒ 即使不保存，异常也能冒到首页（T04 的冒泡链路）。
  /// 这里**不**在保存后自动测：webhook 的一次测试就是往真实机器人发一条消息，
  /// 每次保存都轰炸一遍不是用户要的（自建应用页是 token 校验，量级不同）。
  Future<void> _testAll() async {
    final l10n = AppLocalizations.of(context);
    var tested = 0;
    for (var i = 0; i < _webhookControllers.length; i++) {
      if (_webhookControllers[i].text.trim().isEmpty) continue;
      tested++;
      await _testWebhook(i);
      if (!mounted) return;
    }
    if (tested == 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.webhookUrlRequired),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  /// 当前通道是否显示 secret 输入框。
  ///
  /// 判据来自描述符的 `secretUsed` 能力位（= 原生签名表 + 传输事实派生：
  /// 有签名方案 / secret 走 Bearer 头 / secret 作为 URL token）。此前这里是本页
  /// 自带的一份「排除 6 个平台」黑名单 —— 原生加一个签名方案时这边不会跟着变，
  /// 表现就是"能签名却没地方填密钥"。
  /// 描述符没拉到时**按显示处理**：宁可多给一个入口，也不能让凭据没地方填。
  bool _supportsSigning(int index) =>
      _descriptorFor(index)?.usesSecretField ?? true;

  /// 「消息格式 / 自定义模板」对该通道是否生效（不生效时不给入口）。
  /// Server酱 / PushPlus 有实发正文覆写，ntfy / gotify / slack / discord 没有平台
  /// 模板包装 —— 用户选了格式也不会进正文，以前照样给一整排选择器。
  bool _supportsCustomTemplate(int index) =>
      _descriptorFor(index)?.supportsCustomTemplate ?? true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.webhookSettingsTitle),
        actions: [
          // T04：「仅测试」在左、保存类动作在右，三页同一形状（自建应用页同）。
          TextButton(
            onPressed: _isSaving || _isTesting ? null : _testAll,
            child: Text(
              l10n.testOnly,
              style: TextStyle(
                fontSize: 16,
                color: _isSaving || _isTesting
                    ? AppColors.tertiaryLabel(context)
                    : AppColors.secondaryLabel(context),
              ),
            ),
          ),
          TextButton(
            onPressed: _isSaving ? null : _saveAndBack,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.save,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader(l10n.channelList, context),
          _buildGroup([
            ...List.generate(_webhookControllers.length, (index) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                  _buildChannelItem(index, context),
                ],
              );
            }),
          ], context),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _addWebhookField,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.addChannel,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.notes, context),
          _buildGroup([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DescRow(text: l10n.webhookDesc1, context: context),
                  const SizedBox(height: 8),
                  _DescRow(text: l10n.webhookDesc2, context: context),
                  const SizedBox(height: 8),
                  _DescRow(text: l10n.webhookDesc3, context: context),
                ],
              ),
            ),
          ], context),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.secondaryLabel(context),
        ),
      ),
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

  /// URL 识别提示区。
  /// 尊重手动指定的通道类型（自建 ntfy/Gotify 服务器 host 不可枚举，
  /// 纯 URL 探测会把手动选择的类型误显示为「通用 Webhook」，误导用户）；
  /// 仅当处于「自动识别」模式时才按 URL host 探测。
  Widget _buildWebhookTypeHint(int index, String urlStr, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = urlStr.trim();
    if (url.isEmpty) {
      // 未填 URL：没有类型可识别，用中性样式（不冒充某个平台的名字和颜色）
      return _typeHintChip(
        context,
        name: l10n.urlEmpty,
        desc: l10n.urlPlaceholder,
        icon: Icons.link_off,
        color: const Color(0xFF8E8E93),
      );
    }
    final visual = _typeVisual(_effectiveSlug(index));
    return _typeHintChip(
      context,
      name: channelHintNameFor(l10n, visual),
      desc: channelDescFor(l10n, visual),
      icon: visual.icon,
      color: visual.color,
    );
  }

  /// 「URL 识别」提示卡片：图标 + 平台名 + 一句说明。
  Widget _typeHintChip(
    BuildContext context, {
    required String name,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _webhookControllers) {
      controller.dispose();
    }
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    for (final controller in _secretControllers) {
      controller.dispose();
    }
    for (final controller in _templateControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _DescRow extends StatelessWidget {
  final String text;
  final BuildContext context;
  const _DescRow({required this.text, required this.context});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.tertiaryLabel(this.context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.secondaryLabel(this.context),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
