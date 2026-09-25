import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/channel_descriptor_service.dart';
import '../theme/app_colors.dart';

/// 通道图标 / 品牌色 / 文案键的**唯一**表（按稳定 slug 索引）。
///
/// 此前同一份事实在三处各写一遍：`webhook_settings_page._typeVisual`（图标+色）、
/// 同文件 `_buildWebhookTypeHint`（图标+色+名+提示，12 个分支里的图标与色与前者逐字相同）、
/// 同文件 `_signingHint`（第三份按平台分支的表）。加一个通道要记起改几处 = 迟早漏一处，
/// 漏掉的表现是"通道能配置能推送，但界面上是默认图标/默认名"。
///
/// key 用原生描述符的 `iconKey`（= `WebhookType.name.lowercase()` = Dart 送达键
/// `chan:<slug>` 的 slug），三端同一口径；第 5 步起 UI 一律按 slug 取，不再按平台枚举分支。
@immutable
class ChannelVisual {
  const ChannelVisual({
    required this.icon,
    required this.color,
    required this.labelKey,
    this.descKey,
    this.hintLabelKey,
    this.signingHintKey,
    this.secretHintKey,
  });

  final IconData icon;
  final Color color;

  /// 通道名（选择器 / 列表 / 卡片标题）的 ARB 资源名
  final String labelKey;

  /// 「URL 识别」提示的描述行 ARB 资源名；null = 用通用占位文案。
  ///
  /// ⚠ 12 个 webhook 通道**各写各的**，不得借用别家那句（历史上钉钉/飞书/Telegram/
  /// Bark/Server酱/PushPlus 全复制了企微的「文本格式推送」= roadmap E8，已闭合）。每条只写
  /// 描述符里能核实的事实：签名方案、鉴权取值位置（URL / 请求体 / 表单）、是否走平台 Markdown。
  /// 由 `channel_descriptor_export_contract_test` 的「提示说明不得互相借用」守着。
  final String? descKey;

  /// 提示区的显示名（品牌名，如 WeCom）；null = 与 [labelKey] 同一个词。
  /// 只在两者确实不同（品牌名 ≠ 「钉钉群机器人」这类描述性名称）时才写。
  final String? hintLabelKey;

  /// secret 输入框的 hint（凭据形态说明）；null = 用通用签名提示
  final String? signingHintKey;

  /// 应用通道的凭据输入框提示（corpsecret / app_secret 各自不同）；null = 用通用密钥提示
  final String? secretHintKey;
}

/// slug → 视觉与文案键。新增通道在这里加一行即可（其余界面自动跟随描述符）。
const Map<String, ChannelVisual> _channelVisuals = {
  'wechat_work': ChannelVisual(
    icon: Icons.chat,
    color: Color(0xFF07C160),
    labelKey: 'channelTypeWechat',
    hintLabelKey: 'platformWechat',
    descKey: 'platformWechatDesc',
    signingHintKey: 'signingHintWechat',
  ),
  'dingtalk': ChannelVisual(
    icon: Icons.work,
    color: Color(0xFF1677FF),
    labelKey: 'channelTypeDingtalk',
    hintLabelKey: 'platformDingtalk',
    descKey: 'platformDingtalkDesc',
    signingHintKey: 'signingHintDingtalk',
  ),
  'feishu': ChannelVisual(
    icon: Icons.flight,
    color: AppColors.blue,
    labelKey: 'channelTypeFeishu',
    hintLabelKey: 'platformFeishu',
    descKey: 'platformFeishuDesc',
    signingHintKey: 'signingHintFeishu',
  ),
  'telegram': ChannelVisual(
    icon: Icons.send,
    color: Color(0xFF0088CC),
    labelKey: 'channelTypeTelegram',
    descKey: 'platformTelegramDesc',
    signingHintKey: 'signingHintTelegram',
  ),
  'bark': ChannelVisual(
    icon: Icons.notifications_active,
    color: Color(0xFFE6A23C),
    labelKey: 'channelTypeBark',
    descKey: 'platformBarkDesc',
    signingHintKey: 'signingHintBark',
  ),
  'server_chan': ChannelVisual(
    icon: Icons.forward_to_inbox,
    color: Color(0xFF4E5969),
    labelKey: 'channelTypeServerChan',
    descKey: 'platformServerChanDesc',
    signingHintKey: 'signingHintServerChan',
  ),
  'push_plus': ChannelVisual(
    icon: Icons.bolt,
    color: Color(0xFF00B96B),
    labelKey: 'channelTypePushPlus',
    descKey: 'platformPushPlusDesc',
    signingHintKey: 'signingHintPushPlus',
  ),
  'ntfy': ChannelVisual(
    icon: Icons.cell_tower,
    color: Color(0xFF33B18A),
    labelKey: 'channelTypeNtfy',
    descKey: 'platformNtfyDesc',
    signingHintKey: 'signingHintNtfy',
  ),
  'gotify': ChannelVisual(
    icon: Icons.inbox,
    color: Color(0xFF00A0E9),
    labelKey: 'channelTypeGotify',
    descKey: 'platformGotifyDesc',
    signingHintKey: 'signingHintGotify',
  ),
  'slack': ChannelVisual(
    icon: Icons.tag,
    color: Color(0xFF4A154B),
    labelKey: 'channelTypeSlack',
    hintLabelKey: 'platformSlack',
    descKey: 'platformSlackDesc',
    signingHintKey: 'signingHintSlack',
  ),
  'discord': ChannelVisual(
    icon: Icons.forum,
    color: Color(0xFF5865F2),
    labelKey: 'channelTypeDiscord',
    hintLabelKey: 'platformDiscord',
    descKey: 'platformDiscordDesc',
    signingHintKey: 'signingHintDiscord',
  ),
  'generic': ChannelVisual(
    icon: Icons.code,
    color: Color(0xFFFF9500),
    labelKey: 'channelTypeGeneric',
    hintLabelKey: 'platformGeneric',
    descKey: 'platformGenericDesc',
    signingHintKey: 'signingHintGeneric',
  ),
  'wecom_app': ChannelVisual(
    icon: Icons.business,
    color: AppColors.blue,
    labelKey: 'channelTypeWecomApp',
    secretHintKey: 'appChannelSecretWecomHint',
  ),
  'feishu_app': ChannelVisual(
    icon: Icons.link,
    color: AppColors.blue,
    labelKey: 'channelTypeFeishuApp',
    secretHintKey: 'appChannelSecretFeishuHint',
  ),
  // T08-C：邮件族第一次有描述符（`family=email`，key=iconKey=`email`）。
  // 它此前只在 `email_settings_page` 里就地写了两颗 `Icons.email*`，
  // 而导出守卫要求每条描述符在本判决表里有自己的条目 —— 用它而不是再抄一遍图标名。
  'email': ChannelVisual(
    icon: Icons.email,
    color: AppColors.blue,
    labelKey: 'emailChannel',
  ),
};

/// 通用兜底样式：未知 slug（新通道还没补这张表时）也要能渲染，不能崩。
/// ⚠ 只兜**图标与颜色**；名称不走它 —— 把未知通道显示成「通用 Webhook」是冒充别人，
/// 取名字请走 [channelDisplayNameFor]。
const ChannelVisual _fallback = ChannelVisual(
  icon: Icons.code,
  color: Color(0xFFFF9500),
  labelKey: 'channelTypeGeneric',
);

/// 按 slug（= 描述符的 `iconKey`）取视觉；未知值回退通用样式。
ChannelVisual channelVisual(String slug) => _channelVisuals[slug] ?? _fallback;

/// 该 slug 是否在本表登记过（未登记时名称按原样显示，不套别人的名字）。
bool hasChannelVisual(String slug) => _channelVisuals.containsKey(slug);

/// 通道显示名：表里有条目 → ARB 名称；没有 → 原样显示 slug。
String channelDisplayNameFor(AppLocalizations l10n, String slug) =>
    hasChannelVisual(slug)
    ? channelLabelFor(l10n, _channelVisuals[slug]!.labelKey)
    : slug;

/// 描述符 → 显示名，三级回退：原生 `labelKey` → Dart slug 表 → 原始 slug。
///
/// 原生表是权威（新增通道只改它），但 App 与 APK 不同步升级时，Dart 侧可能没有
/// 对应的 ARB getter —— 这时宁可显示 `matrix` 这样的 slug，也不要显示 `channelTypeMatrix`
/// 这种资源名，更不能崩。
String channelNameOf(AppLocalizations l10n, ChannelDescriptor descriptor) {
  final label = channelLabelFor(l10n, descriptor.labelKey);
  if (label == descriptor.labelKey) {
    return channelDisplayNameFor(l10n, descriptor.key);
  }
  return label;
}

/// ARB 资源名 → 当前语言文案。
///
/// ⚠ 这是 Dart 侧唯一允许的「资源名 → 值」映射（Flutter 的 ARB 生成物是 getter，
/// 没有按字符串取值的 API）。守卫 `channel_visuals_contract_test.dart` 双向核对：
/// 本表引用的每个 key 必须在本 switch 里、且必须真的存在于 ARB；
/// 反过来 ARB 里所有 `channelType*` / `platform*` / `signingHint*` 词条也必须有 case，
/// 否则新通道在原生登记了、Dart 却取不到名字。
String channelLabelFor(AppLocalizations l10n, String labelKey) {
  switch (labelKey) {
    case 'channelTypeWechat':
      return l10n.channelTypeWechat;
    case 'channelTypeDingtalk':
      return l10n.channelTypeDingtalk;
    case 'channelTypeFeishu':
      return l10n.channelTypeFeishu;
    case 'channelTypeTelegram':
      return l10n.channelTypeTelegram;
    case 'channelTypeBark':
      return l10n.channelTypeBark;
    case 'channelTypeServerChan':
      return l10n.channelTypeServerChan;
    case 'channelTypePushPlus':
      return l10n.channelTypePushPlus;
    case 'channelTypeNtfy':
      return l10n.channelTypeNtfy;
    case 'channelTypeGotify':
      return l10n.channelTypeGotify;
    case 'channelTypeSlack':
      return l10n.channelTypeSlack;
    case 'channelTypeDiscord':
      return l10n.channelTypeDiscord;
    case 'channelTypeGeneric':
      return l10n.channelTypeGeneric;
    case 'channelTypeWecomApp':
      return l10n.channelTypeWecomApp;
    case 'channelTypeFeishuApp':
      return l10n.channelTypeFeishuApp;
    case 'platformWechat':
      return l10n.platformWechat;
    case 'platformDingtalk':
      return l10n.platformDingtalk;
    case 'platformFeishu':
      return l10n.platformFeishu;
    case 'platformSlack':
      return l10n.platformSlack;
    case 'platformDiscord':
      return l10n.platformDiscord;
    case 'platformGeneric':
      return l10n.platformGeneric;
    case 'platformWechatDesc':
      return l10n.platformWechatDesc;
    case 'platformNtfyDesc':
      return l10n.platformNtfyDesc;
    case 'platformGotifyDesc':
      return l10n.platformGotifyDesc;
    case 'platformSlackDesc':
      return l10n.platformSlackDesc;
    case 'platformDiscordDesc':
      return l10n.platformDiscordDesc;
    case 'platformGenericDesc':
      return l10n.platformGenericDesc;
    case 'platformDingtalkDesc':
      return l10n.platformDingtalkDesc;
    case 'platformFeishuDesc':
      return l10n.platformFeishuDesc;
    case 'platformTelegramDesc':
      return l10n.platformTelegramDesc;
    case 'platformBarkDesc':
      return l10n.platformBarkDesc;
    case 'platformServerChanDesc':
      return l10n.platformServerChanDesc;
    case 'platformPushPlusDesc':
      return l10n.platformPushPlusDesc;
    case 'signingHintWechat':
      return l10n.signingHintWechat;
    case 'signingHintDingtalk':
      return l10n.signingHintDingtalk;
    case 'signingHintFeishu':
      return l10n.signingHintFeishu;
    case 'signingHintTelegram':
      return l10n.signingHintTelegram;
    case 'signingHintBark':
      return l10n.signingHintBark;
    case 'signingHintServerChan':
      return l10n.signingHintServerChan;
    case 'signingHintPushPlus':
      return l10n.signingHintPushPlus;
    case 'signingHintNtfy':
      return l10n.signingHintNtfy;
    case 'signingHintGotify':
      return l10n.signingHintGotify;
    case 'signingHintSlack':
      return l10n.signingHintSlack;
    case 'signingHintDiscord':
      return l10n.signingHintDiscord;
    case 'signingHintGeneric':
      return l10n.signingHintGeneric;
    case 'appChannelSecretWecomHint':
      return l10n.appChannelSecretWecomHint;
    case 'appChannelSecretFeishuHint':
      return l10n.appChannelSecretFeishuHint;
    case 'webhookSecretLabel':
      return l10n.webhookSecretLabel;
    // 应用通道的扩展参数 labelKey 由原生描述符发来（表单字段标签）：
    // 少一条 case，输入框就显示资源名原文（本仓库第 5 步实测踩过）。
    case 'appChannelCorpidLabel':
      return l10n.appChannelCorpidLabel;
    case 'appChannelAgentidLabel':
      return l10n.appChannelAgentidLabel;
    case 'appChannelTouserLabel':
      return l10n.appChannelTouserLabel;
    case 'appChannelAppidLabel':
      return l10n.appChannelAppidLabel;
    case 'appChannelReceiveIdTypeLabel':
      return l10n.appChannelReceiveIdTypeLabel;
    case 'appChannelReceiveIdLabel':
      return l10n.appChannelReceiveIdLabel;
    // 邮件族的通道名（T08-C：它现在是第三条描述符，labelKey 与其余两族同一条路）
    case 'emailChannel':
      return l10n.emailChannel;
    default:
      // 不硬编码中文兜底：宁可显示 key 名，也不要造出"第二处译文"
      return labelKey;
  }
}

/// 提示区的显示名（品牌名优先）。
String channelHintNameFor(AppLocalizations l10n, ChannelVisual visual) =>
    channelLabelFor(l10n, visual.hintLabelKey ?? visual.labelKey);

/// 该通道的「URL 识别」描述文案。
String channelDescFor(AppLocalizations l10n, ChannelVisual visual) =>
    visual.descKey == null
    ? l10n.urlPlaceholder
    : channelLabelFor(l10n, visual.descKey!);

/// secret 输入框的提示（凭据形态）。未知通道走通用签名提示，不说成某个平台的话。
String channelSigningHintFor(AppLocalizations l10n, ChannelVisual visual) =>
    visual.signingHintKey == null
    ? l10n.signingHintGeneric
    : channelLabelFor(l10n, visual.signingHintKey!);

/// 应用通道凭据输入框的提示（corpsecret / app_secret 形态不同）。
String channelSecretHintFor(AppLocalizations l10n, ChannelVisual visual) =>
    visual.secretHintKey == null
    ? l10n.webhookSecretLabel
    : channelLabelFor(l10n, visual.secretHintKey!);
