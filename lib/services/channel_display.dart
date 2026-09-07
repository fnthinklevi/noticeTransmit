import 'package:get_it/get_it.dart';

import 'locale_service.dart';

/// 渠道类型显示名（语言感知）。
///
/// 使用场景：首页通道状态、通知记录送达标签、历史记录等**无 BuildContext** 的位置
/// （有 BuildContext 的 UI 一律走 l10n 的 channelTypeXxx getter）。
/// 输入兼容三种来源：DB 存储值（feishu/wechat_work）、历史遗留枚举名（feishu）、
/// Kotlin 端送达回传的枚举名（FEISHU/WECHAT_WORK）。
///
/// 命名随软件语言：中文「企业微信/飞书/Server酱」，英文官方名「WeCom/Feishu/ServerChan」。
String channelTypeDisplayName(String rawType) {
  String? localeCode;
  try {
    localeCode = GetIt.instance<LocaleService>().currentLocale.languageCode;
  } catch (_) {
    // GetIt 未初始化（极早期调用）时回退系统语言
    localeCode = null;
  }
  final isEn = (localeCode ?? 'zh') == 'en';
  switch (rawType) {
    case '0':
    case 'wechatWork':
    case 'wechat_work':
    case 'WECHAT_WORK':
      return isEn ? 'webhook:WeCom' : 'webhook:企业微信';
    case '1':
    case 'dingtalk':
    case 'DINGTALK':
      return isEn ? 'webhook:DingTalk' : 'webhook:钉钉';
    case '2':
    case 'feishu':
    case 'FEISHU':
      return isEn ? 'webhook:Feishu' : 'webhook:飞书';
    case 'telegram':
    case 'TELEGRAM':
      return 'webhook:Telegram';
    case 'bark':
    case 'BARK':
      return 'webhook:Bark';
    case 'server_chan':
    case 'serverChan':
    case 'SERVER_CHAN':
      return isEn ? 'webhook:ServerChan' : 'webhook:Server酱';
    case 'push_plus':
    case 'pushPlus':
    case 'PUSH_PLUS':
      return 'webhook:PushPlus';
    case 'email':
    case 'EMAIL':
      return isEn ? 'Email' : '邮件';
    case 'sms':
    case 'SMS':
    case 'filter':
    case 'FILTER':
      // 拦截伪通道类型（短信/通知被黑白名单或应用过滤拦截时由原生回传），
      // 与 FILTER 同义：内容不会实际投递，历史送达标签显示为「过滤拦截」
      return isEn ? 'Blocked' : '过滤拦截';
    default:
      return isEn ? 'webhook:Generic' : 'webhook:通用';
  }
}
