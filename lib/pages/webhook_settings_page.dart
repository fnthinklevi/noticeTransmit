import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../models/webhook_channel.dart';
import '../services/channel_config_codec.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_health_store.dart';
import '../services/channel_url_policy.dart';
import '../services/platform_channel.dart';
import '../services/template_variables.dart';
import '../services/webhook_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/channel_visuals.dart';

// R3 拆分：通道卡片构建巨型方法迁出（extension 共享 State 私有成员）
part 'webhook_settings_item.dart';

/// Webhook **单通道详情页**（T07-B：「列表页 → 单通道详情页」）。
///
/// * [channelId] 非空 ⇒ 编辑那条已存在的通道；为空 ⇒ 新增一条。
/// * 「有哪些通道」归 [WebhookChannelListPage] 管：启停 / 复制 / 删除都在那一页。
///
/// 保存走 `WebhookService.saveChannel`（按 id 就地替换、没有则追加），**不再整表重写**：
/// 以前这里是"九条并行列表按下标拼出整表 + pop 给调用方整表 delete+insert"，
/// 所以"只想改这一条"根本没有安全路径（别的通道会被这份快照覆盖），
/// 删一行还得九处同步收缩，漏一处就是"行串台"。
class WebhookSettingsPage extends StatefulWidget {
  const WebhookSettingsPage({super.key, this.channelId});

  final String? channelId;

  @override
  State<WebhookSettingsPage> createState() => _WebhookSettingsPageState();
}

class _WebhookSettingsPageState extends State<WebhookSettingsPage> {
  static const _channel = AppChannels.notification;

  /// 通道描述符（原生表）：secret/模板显隐、类型候选列表与名称都按它渲染
  late final ChannelDescriptorService _descriptors;
  late final ChannelHealthStore _health;
  late final WebhookService _service;

  // ── 单通道形态：一行一套字段，标量而不是列表 ──
  /// 已落库的通道 id；null = 还没保存过的新通道（保存时当场发号）
  String? _channelId;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  final TextEditingController _templateController = TextEditingController();
  bool _enabled = true;
  bool _secretVisible = false;

  /// 消息格式档位（token 字符串，名单来自原生；见 `_formatOptions`）。
  /// 用字符串而不是 Dart 枚举：枚举曾把不认识的存量值静默回退成 'default'。
  String _messageFormat = 'default';
  // 'auto' = 按 URL host 探测，否则为用户手动指定的类型（自建代理等场景）
  String _channelType = 'auto';

  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;
  bool? _testSuccess;
  bool? _testSigned;

  @override
  void initState() {
    super.initState();
    _descriptors = GetIt.instance<ChannelDescriptorService>();
    _health = GetIt.instance<ChannelHealthStore>();
    _service = GetIt.instance<WebhookService>();
    final wanted = widget.channelId ?? '';
    // ⚠ 只把库里的值**读进本页的标量字段**，不就地改服务里的那条：
    // 未点保存就返回时，列表页按库里的内容重刷，用户不该看到"改了又弹回去"。
    // 形状一律走 ChannelConfigCodec 读 —— 通道列表可能来自备份文件（形状不可信：
    // `enabled` 是 0/1、值可能是数字、键可能是 snake_case），一个 `as bool?` 就能打死页面。
    if (wanted.isNotEmpty) {
      final rows = _service.channels
          .where(
            (c) => (ChannelConfigCodec.nullableText(c['id']) ?? '') == wanted,
          )
          .toList();
      if (rows.isNotEmpty) _loadFrom(rows.first);
    }
    _health.load().then((_) {
      if (mounted) setState(() {});
    });
    // splash 那次没拉成功时兜底重取：到手后重建，否则显隐判断会一直停在"按显示处理"
    _descriptors.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _loadFrom(Map<String, dynamic> c) {
    _channelId = ChannelConfigCodec.nullableText(c['id']);
    _urlController.text = ChannelConfigCodec.nullableText(c['url']) ?? '';
    _nameController.text = ChannelConfigCodec.nullableText(c['name']) ?? '';
    _secretController.text = ChannelConfigCodec.nullableText(c['secret']) ?? '';
    _templateController.text =
        ChannelConfigCodec.nullableText(c['message_template']) ?? '';
    _enabled = c.containsKey('enabled')
        ? ChannelConfigCodec.flag(c['enabled'])
        : true;
    // 原样收下存着的档位 token：未知值也必须能显示出来，否则"看一眼设置页"就把
    // 用户的格式改掉了（旧的 WebhookMessageFormat.fromValue 就会静默回退 default）。
    _messageFormat =
        ChannelConfigCodec.nullableText(c['message_format']) ??
        ChannelConfigCodec.nullableText(c['messageFormat']) ??
        'default';
    final type =
        ChannelConfigCodec.nullableText(c['channelType']) ??
        ChannelConfigCodec.nullableText(c['type']) ??
        ChannelConfigCodec.nullableText(c['channel_type']) ??
        'auto';
    _channelType = type.isEmpty ? 'auto' : type;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _secretController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  /// 本行的**有效类型 slug**：手动指定优先，'auto' 时按 URL host 探测。
  ///
  /// 用 slug 而不是 Dart 枚举（第 5 步起）：「Dart 有没有登记这个平台」不该决定
  /// 界面能不能显示它 —— 原生新增通道时 Dart 不再需要跟着加枚举臂。
  String get _effectiveSlug {
    if (_channelType.isNotEmpty && _channelType != 'auto') return _channelType;
    return WebhookChannel.detectTypeFromUrl(_urlController.text).value;
  }

  /// 本行的描述符（原生表）；描述符未拉到时 null，调用方按"不收窄"处理。
  ChannelDescriptor? get _descriptor => _descriptors.byKey(_effectiveSlug);

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

  /// 详情页标题：有名字用名字，没有名字就说清"这是新增一条"。
  /// （"通道 1"那种序号是给整表平铺页用的，单通道形态下它既不是名字也不是状态。）
  String _title(AppLocalizations l10n) {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) return name;
    return _channelId == null
        ? l10n.webhookChannelNewTitle
        : l10n.channelUntitled;
  }

  /// 本条通道的健康记录：按 **id** 取（新增未保存时 null ⇒ 徽标不画）。
  ChannelHealth? get _healthInfo {
    final id = _channelId;
    if (id == null || id.isEmpty) return null;
    return _health.of('webhook', id);
  }

  /// 校验不通过：收起"保存中"状态、点名问题、停在页面上让用户改。
  ///
  /// 三条必填/合法性检查共用它，避免每处再抄一遍"翻回按钮状态 + 弹条 + return"
  /// （以前各抄一份，结果有一处忘了复位按钮 ⇒ 按钮永久禁用）。
  void _saveBlocked(String message) {
    if (!mounted) return;
    _showToast(message, false);
    setState(() => _isSaving = false);
  }

  void _showToast(String message, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: ok ? AppColors.green : AppColors.red,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// 本条通道的载荷 —— **只描述这一条**，写库交给 `WebhookService.saveChannel` 合并。
  ///
  /// 只带本页**看得见**的字段：能力位收掉的字段（不给签名平台填密钥、不给无模板
  /// 平台选格式）不进载荷，服务层的合并语义会保留库里的原值。反过来，看得见的字段
  /// 一律显式发值（含 null）：用户清空了密钥就是清空了，不能因为"载荷没这个键"
  /// 而被上一条的 secret 顶回去。
  Map<String, dynamic> _channelPayload() {
    final url = _urlController.text.trim();
    final manual = _channelType;
    return <String, dynamic>{
      'id': _channelId,
      'url': url,
      'name': _nameController.text.trim(),
      'channelType': (manual == 'auto' || manual.isEmpty)
          ? WebhookChannel.detectTypeFromUrl(url).value
          : manual,
      'enabled': _enabled,
      if (_supportsSigning) 'secret': _orNull(_secretController.text),
      if (_supportsCustomTemplate) ...{
        'message_format': _messageFormat,
        'message_template': _orNull(_templateController.text),
      },
    };
  }

  /// 空串 → null（DB 契约：既不写空串占位，也不写字符串 "null"）
  String? _orNull(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  /// 当前通道是否显示 secret 输入框。
  ///
  /// 判据来自描述符的 `usesSecretField` 能力位（= 原生签名表 + 传输事实派生：
  /// 有签名方案 / secret 走 Bearer 头 / secret 作为 URL token）。此前这里是本页
  /// 自带的一份「排除 6 个平台」黑名单 —— 原生加一个签名方案时这边不会跟着变，
  /// 表现就是"能签名却没地方填密钥"。
  /// 描述符没拉到时**按显示处理**：宁可多给一个入口，也不能让凭据没地方填。
  bool get _supportsSigning => _descriptor?.usesSecretField ?? true;

  /// 「消息格式 / 自定义模板」对该通道是否生效（不生效时不给入口）。
  /// Server酱 / PushPlus 有实发正文覆写，ntfy / gotify / slack / discord 没有平台
  /// 模板包装 —— 用户选了格式也不会进正文，以前照样给一整排选择器。
  bool get _supportsCustomTemplate =>
      _descriptor?.supportsCustomTemplate ?? true;

  /// 可选的消息格式档位：**名单只在原生**（`TemplateEngine.formatOptions`，随
  /// `getChannelDescriptors` 一起导出）。Dart 不再存第二份枚举 —— 加一个格式只改原生，
  /// 界面自动跟着走。
  ///
  /// 描述符还没到手时不编一份自己的名单，只显示"该通道当前存着的那个值"：
  /// 用户既看不到凭空多出来的档位，也不会看到自己存的值被换掉。
  List<String> get _formatOptions {
    final native = _descriptors.messageFormats;
    if (native.isEmpty) return <String>[_messageFormat];
    if (native.contains(_messageFormat)) return native;
    // 存量值不在原生名单里（老数据、或原生删掉了某个档位）：仍然显示它，
    // 否则选择器会显示成"没选中任何项"，用户以为设置丢了。
    return <String>[...native, _messageFormat];
  }

  /// 右上角「测试并保存」：先校验落库，再按当前值测这一条。
  ///
  /// 测试失败**不回滚**保存：配置是对的、只是这一刻连不上，回滚会把用户的有效编辑
  /// 一起吞掉（与 T04 的决策一致）。
  Future<void> _saveChannelAndTest() async {
    final l10n = AppLocalizations.of(context);
    final url = _urlController.text.trim();
    // 必填/合法性一律点名到**字段**（T03）：单通道形态下没有"第几行"可指。
    // 为什么必须挡在保存前，而不是"让它存进去、发的时候再说"：
    //  - 空 URL 的通道会在落库后被原生 filter 掉（`WebhookSender.updateChannelConfigs`），
    //    用户敲过的名字与密钥等于白填；
    //  - `requiresSecret` 的平台缺密钥时签名算不出来，服务端直接拒收（钉钉 31000），
    //    用户看到的是"配好了却永远收不到"。
    // 判据不在本页另立：URL 规则用 `ChannelUrlPolicy`（与原生、备份恢复同一份），
    // "必须要密钥"读描述符能力位。描述符没拉到就不凭猜测拦人保存。
    if (url.isEmpty) {
      _saveBlocked(l10n.webhookErrUrlRequired);
      return;
    }
    if (!ChannelUrlPolicy.isHttpUrl(url)) {
      _saveBlocked(l10n.webhookErrUrlInvalid);
      return;
    }
    if (_supportsSigning &&
        (_descriptor?.requiresSecret ?? false) &&
        _secretController.text.trim().isEmpty) {
      _saveBlocked(l10n.webhookErrSecretRequired);
      return;
    }
    setState(() => _isSaving = true);
    // 新通道在写库前发号：载荷带上它 ⇒ 服务层按"追加"处理，之后的测试结论也有稳定归属
    // （没有归属的记账会把徽标钉到别处，见 T04）。
    _channelId ??= 'wh_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await _service.saveChannel(_channelPayload());
    } catch (e) {
      _saveBlocked('${l10n.saveFailedPrefix}$e');
      return;
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    _showToast(l10n.webhookConfigSaved, true);
    if (_enabled) await _testThis();
  }

  /// 右上角「仅测试」：按**当前表单值**测这一条，不落库、不退出页面。
  ///
  /// 测出来的结论写健康单点 ⇒ 即使不保存，异常也能冒到首页与通道状态页（T04 的链路）。
  /// ⚠ 未保存的新通道（还没有 id）**不记**。
  Future<void> _testThis() async {
    final l10n = AppLocalizations.of(context);
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testResult = l10n.webhookUrlRequired;
        _testSigned = null;
      });
      return;
    }
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
      _testSigned = null;
    });
    final watch = Stopwatch()..start();
    try {
      // 传 secret 让原生做签名验证，返回真实送达结果（含状态/HTTP 码/签名标识）；
      // 类型一起传：只给 URL 时，自建 Gotify / 私有 ntfy 会被原生按 host 降级成通用
      // webhook 判定，测试结论与真实推送不一致。
      final secret = _secretController.text.trim();
      final result = await _channel.invokeMethod('testWebhook', {
        'url': url,
        if (secret.isNotEmpty) 'secret': secret,
        'channelType': _channelType,
      });
      final success = result['success'] as bool? ?? false;
      if (!mounted) return;
      final id = _channelId;
      if (id != null && id.isNotEmpty) {
        await _health.record(
          'webhook',
          id,
          reachable: success,
          latencyMs: watch.elapsedMilliseconds,
        );
        if (!mounted) return;
      }
      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testResult = result['message'] as String? ?? l10n.unknownError;
        _testSigned = result['signed'] as bool? ?? false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testSigned = false;
        _testResult = l10n.testFailedMsg(e.toString());
      });
    }
  }

  void _toggleSecretVisible() {
    setState(() {
      _secretVisible = !_secretVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(_title(l10n)),
        actions: [
          // T04 的形状：「仅测试」在左、「测试并保存」在右，三族同一。
          TextButton(
            onPressed: _isSaving || _isTesting ? null : _testThis,
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
            onPressed: _isSaving ? null : _saveChannelAndTest,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
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
            l10n.webhookDesc1,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildChannelCard(context),
        ],
      ),
    );
  }
}
