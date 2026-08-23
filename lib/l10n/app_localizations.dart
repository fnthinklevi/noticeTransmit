import 'package:flutter/material.dart';
import '../models/notification_rule.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const _zh = <String, String>{
    // 通用
    'appName': '通知推送助手',
    'cancel': '取消',
    'confirm': '确定',
    'save': '保存',
    'delete': '删除',
    'edit': '编辑',
    'add': '添加',
    'test': '测试',
    'send': '发送',
    'close': '关闭',
    'ok': '好的',
    'later': '稍后',
    'goSettings': '去设置',
    'loading': '加载中...',
    'unknown': '未知',
    'notSet': '未设置',
    'enabled': '已开启',
    'disabled': '未开启',
    'on': '开',
    'off': '关',
    // Tab
    'tabNotification': '通知',
    'tabBattery': '电量',
    'tabMore': '更多',
    // 通知页
    'serviceRunning': '通知监听服务正在运行，点击可停止',
    'serviceStopped': '通知监听服务未启动，点击可启动',
    'running': '运行中',
    'stopped': '已停止',
    'currentChannels': '当前推送通道',
    'noChannels': '未配置推送通道',
    'statusOk': '状态正常',
    'statusError': '状态异常',
    'permSettings': '权限设置',
    'permSettingsDesc': '配置通知、电池、后台运行等权限',
    'pushHistory': '推送历史',
    'recordCount': '共 {n} 条记录',
    'notificationPermissionTitle': '通知读取权限未开启',
    'notificationPermissionMsg':
        '通知读取权限未开启，软件无法读取设备通知内容。\n\n请先前往「权限设置」开启通知读取权限后再启动服务。',
    // 更多页
    'appearance': '外观设置',
    'pushSettings': '推送设置',
    'pushChannels': '推送通道',
    'filterRules': '过滤规则',
    'webhookChannel': 'Webhook 推送通道',
    'webhookNotConfigured': '未配置',
    'webhookConfigured': '已配置 {n} 个 · 启用 {m} 个',
    'emailChannel': '邮件转发通道',
    'emailChannelDesc': 'SMTP 邮件通知',
    'appFilter': '应用筛选',
    'appFilterBlocked': '已屏蔽 {n} 个应用',
    'appFilterSelected': '已选择 {n} 个应用',
    'appFilterAll': '全部应用都推送',
    'keywordFilter': '关键词过滤',
    'keywordWhitelistBlacklist': '白名单 {n} 条 · 黑名单 {m} 条',
    'ruleEngine': '规则引擎',
    'ruleCount': '{n} 条规则',
    'ruleEmpty': '点击添加规则',
    'device': '设备',
    'deviceName': '设备名称',
    'widgetSection': '桌面小部件',
    'widgetGuide': '推送开关',
    'widgetGuideDesc': '桌面一键开启/暂停推送服务',
    'widgetGuideIntro': '将「推送开关」小部件添加到桌面后，无需打开应用即可一键开启或暂停推送。',
    'widgetGuideStep1': '1. 长按桌面空白处',
    'widgetGuideStep2': '2. 点击「小部件 / 插件 / Widgets」',
    'widgetGuideStep3': '3. 找到「通知推送助手」，将「推送开关」拖到桌面',
    'widgetGuideBrand': '各品牌添加路径',
    'widgetBrandXiaomi': '小米 / 红米：桌面长按 → 添加小部件 → 通知推送助手',
    'widgetBrandHuawei': '华为 / 荣耀：双指捏合或长按桌面 → 服务卡片 / 小部件 → 通知推送助手',
    'widgetBrandOppo': 'OPPO / realme / 一加：桌面长按 → 添加插件 → 通知推送助手',
    'widgetBrandVivo': 'vivo / iQOO：桌面长按 → 原子组件 / 小部件 → 通知推送助手',
    'widgetBrandSamsung': '三星：桌面长按 → 小组件 → 通知推送助手',
    'widgetBrandOthers':
        '其他品牌（原生 / 谷歌 Pixel / 摩托罗拉 / 索尼等）：桌面长按 → Widgets / 小部件 → 通知推送助手',
    'widgetTipsTitle': '使用提示',
    'widgetTip1': '点击小部件即可切换推送状态（推送中 ⇄ 已暂停）',
    'widgetTip2': '暂停后监听继续，仅不发送推送消息',
    'widgetTip3': '部分品牌需允许应用自启动，小部件状态才能实时刷新',
    'widgetTip4': '若桌面找不到小部件，请先打开一次应用或重启桌面',
    'widgetPinTitle': '一键添加（推荐）',
    'widgetPinDesc': '点击下方按钮，在系统弹窗中确认后即可将 2×2 推送开关小部件添加到桌面，无需手动拖拽。',
    'widgetPinAction': '一键添加 2×2 小部件',
    'widgetPinWideAction': '添加 4×2 横条小部件',
    'widgetPinSuccess': '已发起添加，请在桌面放置小部件',
    'widgetPinUnsupported': '当前桌面不支持一键添加，请长按桌面空白处手动添加',
    'widgetPinLowApi': '一键添加需要 Android 8.0 及以上，请长按桌面空白处手动添加',
    'widgetPin2x2': '2×2 圆形开关：标题 + 状态圆 + 点击提示',
    'widgetPin4x2': '4×2 横条：标题 + 状态圆 + 当日已推送数量',
    'pushStats': '推送统计',
    'pushStatsDesc': '查看推送数据统计',
    'aboutUpdate': '关于与更新',
    'checkUpdate': '检查更新',
    'checking': '正在检查...',
    'clickToCheck': '点击检查新版本',
    'privacyPolicyTitle': '隐私政策',
    'privacyPolicyDesc': '数据采集与隐私保护说明',
    'aboutTitle': '关于',
    'aboutDesc': '版本信息、作者介绍',
    'followSystem': '跟随系统',
    'lightMode': '浅色模式',
    'darkMode': '深色模式',
    'language': '语言',
    'langDefault': '默认',
    'langChinese': '中文',
    'langEnglish': 'English',
    // 语言切换
    'switchLangTitle': '切换语言',
    'switchLangMsg': '检测到系统语言已变为 {lang}，是否同步切换应用语言？',
    'switchBtn': '切换',
    'notNow': '暂不',
    // 隐私弹窗
    'privacyTitle': '隐私政策',
    'privacyWelcome': '欢迎使用通知推送助手！',
    'privacyBody':
        '在使用本应用前，请您仔细阅读我们的隐私政策。\n\n• 所有通知内容仅在设备本地处理，仅按您的配置转发到您指定的 Webhook 或邮件地址\n• 推送历史记录使用 AES-256 加密存储在本地数据库\n• 仅收集必要的崩溃日志（腾讯 Bugly）用于修复应用问题，不采集个人身份信息\n• 通道配置（Webhook/邮件）使用 AndroidKeyStore 加密存储\n\n点击"同意"即表示您已阅读并接受我们的隐私政策。',
    'disagree': '不同意',
    'agree': '同意',
    'privacyWarnTitle': '注意',
    'privacyWarnBody': '您需要同意隐私政策才能使用本软件。\n\n不同意将无法继续使用，软件将会退出。\n\n确定要退出吗？',
    'returnAgree': '返回同意',
    'confirmExit': '确定退出',
    // 更新
    'latestVersion': '当前已是最新版本',
    'checkUpdateFailed': '检查更新失败：{e}',
    'checkUpdateNetworkError': '检查更新失败，请检查网络连接',
    'importantUpdate': '重要更新',
    'mustUpdate': '必须更新才能继续使用',
    'newVersionFound': '发现新版本',
    'latestVer': '最新版本：',
    'currentVer': '当前版本：',
    'fileSize': '文件大小：',
    'updateContent': '更新内容',
    'updateNow': '立即更新',
    'ignore': '忽略',
    'update': '更新',
    'downloading': '正在下载更新',
    'downloadFailed': '下载失败：{e}',
    'storagePermissionRequired': '需要存储权限',
    'storagePermissionMsg': '在线更新需要存储权限来保存 APK 文件，请前往设置开启。',
    'noStoragePermission': '未获得存储权限，无法下载更新',
    'enable': '去开启',
    // 导出
    'confirmExport': '确认导出',
    'exportMsg':
        '通知记录将导出为 JSON 文件，包含通知内容和设备信息。\n\n请选择保存位置，建议在导出后妥善保管或及时删除。\n\n确定要导出吗？',
    'exportBtn': '确定导出',
    'exportCancelled': '已取消',
    'exportError': '导出异常',
    // 历史
    'historyTitle': '历史记录 ({n})',
    'exportJson': '导出 JSON',
    'clearRecords': '清除记录',
    'clearToday': '清除今日',
    'clearLast10': '清除最近 10 条',
    'clearLast50': '清除最近 50 条',
    'clearAll': '清除全部',
    'confirmClear': '确认清除',
    'clearConfirmMsg': '确定要清空全部 {n} 条记录吗？',
    'clearedN': '已清除 {n} 条记录',
    'searchHint': '搜索标题/内容/应用',
    'noRecords': '暂无推送记录',
    'noMatchRecords': '没有匹配的记录',
    'notificationDetail': '通知详情',
    'detailInfo': '详细信息',
    'noTitle': '（无标题）',
    // 邮件设置
    'emailSettingsTitle': '邮件转发通道',
    'noEmailChannels': '暂无邮件通道',
    'clickToAdd': '点击下方按钮添加',
    'addEmailChannel': '添加邮件通道',
    'editEmailChannel': '编辑邮件通道',
    'testSend': '测试发送',
    'testAndSave': '测试并保存',
    'testPassed': '✅ 验证通过',
    'testFailed': '❌ 验证失败',
    'testPassedSaved': '测试通过，配置已保存',
    'verifyFailed': '验证失败: {msg}',
    'testing': '测试中...',
    'channelNameHint': '如：QQ邮箱',
    'smtpHost': 'SMTP 服务器',
    'smtpPort': '端口号',
    'smtpAccount': 'SMTP 账号',
    'smtpPassword': '密码/授权码',
    'fromEmail': '发件人',
    'toEmail': '收件人',
    'useSSL': 'SSL 加密',
    'subjectTemplate': '主题模板（可选）',
    'bodyTemplate': '正文模板（可选）',
    'presetDefault': '默认',
    'presetSimple': '简洁',
    'presetDetailed': '详细',
    'presetTime': '时间',
    'presetCode': '验证码',
    'presetDevice': '设备',
    'presetStandard': '标准',
    'presetComplete': '完整',
    'presetMinimal': '极简',
    'availableVars':
        '可用变量：%appName% %title% %content% %subText% %packageName% %deviceName% %time% %type% %date% %datetime%',
    // Webhook 设置
    'webhookSettingsTitle': 'Webhook 推送通道',
    'webhookUrlRequired': '请先输入 Webhook URL',
    'channelList': '通道列表',
    'addChannel': '添加通道',
    'webhookDesc1': '支持同时配置多个 Webhook 通道，每个通道独立开关',
    'webhookDesc2': '自动识别企业微信、钉钉、飞书等平台格式',
    'webhookDesc3': '新添加的通道默认启用',
    'channelN': '通道 {n}',
    'channelNameOptional': '通道名称（可选，如 企业微信·通知）',
    'webhookUrlPlaceholder': 'https://example.com/webhook',
    'webhookSecretLabel': '签名密钥（可选）',
    'webhookSigned': '已签名',
    'webhookTemplateLabel': '推送模板（可选）',
    'webhookFormatLabel': '消息格式',
    'feishuMarkdownDowngradeHint':
        '飞书自定义机器人不支持 markdown，将降级为纯文本发送（markdown 符号原样显示）。建议使用 text 格式。',
    'webhookTemplateHint': '留空则使用预置模板；支持变量：',
    'webhookTemplateInsertVar': '插入变量',
    'webhookTemplatePreview': '预览',
    'platformWechat': 'WeCom',
    'platformDingtalk': 'DingTalk',
    'platformFeishu': 'Feishu',
    'platformGeneric': '通用 JSON',
    'platformWechatDesc': '文本格式推送',
    'platformGenericDesc': '自定义 JSON 格式',
    // 推送渠道类型（渠道类型选择器 / 签名提示）
    'channelTypeLabel': '渠道类型',
    'channelTypeAuto': '自动识别',
    'channelTypeAutoWith': '自动识别（{type}）',
    'selectChannelType': '选择推送渠道',
    'channelTypeWechat': '企业微信群机器人',
    'channelTypeDingtalk': '钉钉群机器人',
    'channelTypeFeishu': '飞书群机器人',
    'channelTypeTelegram': 'Telegram',
    'channelTypeBark': 'Bark',
    'channelTypeServerChan': 'Server酱',
    'channelTypePushPlus': 'PushPlus',
    'channelTypeGeneric': '通用 Webhook',
    'signingHintWechat': '企业微信群机器人开启「签名校验」后生成的密钥',
    'signingHintDingtalk': '钉钉机器人开启「加签」后生成的密钥（SEC 开头）',
    'signingHintFeishu': '飞书自定义机器人开启「签名校验」后的密钥',
    'signingHintTelegram': 'Telegram 使用 Bot Token 鉴权，无需签名密钥',
    'signingHintBark': 'Bark 使用设备 Key 鉴权，无需签名密钥',
    'signingHintServerChan': 'Server酱 使用 SendKey 鉴权，无需签名密钥',
    'signingHintPushPlus': 'PushPlus 使用 Token 鉴权，无需签名密钥',
    'signingHintGeneric': '自建服务端校验签名用的密钥（通过 X-Signature 头传递）',
    'msgFormatDefault': '默认格式',
    'msgFormatText': '纯文本',
    'urlEmpty': '待输入',
    'urlPlaceholder': '请输入 Webhook URL',
    // 权限设置
    'permSettingsTitle': '权限设置',
    'essentialPerms': '必要权限',
    'notifAccessPerm': '通知访问权限',
    'allowNotifications': '允许通知',
    'ignoreBatteryOpt': '忽略电池优化',
    'vendorBgSettings': '厂商后台设置',
    'xiaomiAutoStart': '小米自启动',
    'meizuBgRun': '魅族后台运行',
    'huaweiProtected': '华为自启动/受保护应用',
    'oppoAutoStart': 'OPPO自启动管理',
    'vivoBgStart': 'vivo后台启动管理',
    'samsungSettings': '三星设备设置',
    'nativeAndroid': '原生Android设置',
    'optionalPerms': '非必要权限',
    'smsPerm': '短信权限',
    'smsPermDesc': '用于获取短信发送者号码和内容',
    'phonePerm': '电话权限',
    'phonePermDesc': '用于获取来电号码和通话状态',
    'appListPerm': '应用列表权限',
    'appListPermDesc': '非必要权限用于提升特定功能的准确性',
    'appListPermTitle': '需要应用列表权限',
    'appListPermMsg':
        '该权限用于获取已安装应用列表，支持按应用过滤通知功能。\n\n点击「允许」后将跳转到系统设置页，请手动开启权限。',
    'appListPermExtra': '用于获取已安装应用列表，支持按应用过滤通知功能',
    'clickToSettings': '点击前往设置',
    'samsungSmartManagerDesc': '请在智能管理器中将本应用加入自启动白名单',
    'nativeBatteryOptDesc': '请在系统设置中确认电池优化已关闭',
    'exactAlarmTitle': '精确闹钟（准时推送）',
    'exactAlarmDesc': '延迟/定时推送到点更准时；Android 12+ 需系统授权',
    'exactAlarmGranted': '已授权',
    'exactAlarmNeedGrant': '点击授权',
    'exactAlarmUnsupported': '需 Android 12+',
    'keepAliveGuideTitle': '后台保活引导',
    'keepAliveGuideDesc': '部分系统会限制后台服务，可能导致收不到通知。按以下步骤设置可提高稳定性：',
    'keepAliveStep1': '省电策略设为不限制',
    'keepAliveStep2': '允许自启动',
    'keepAliveStep3': '后台运行不受限（任务锁定）',
    'keepAliveStep4': '确认已开启通知使用权',
    'notes': '说明',
    'allow': '允许',
    'reject': '拒绝',
    // 电池页
    'batteryTitle': '电量',
    'addRule': '添加规则',
    'charging': '充电中',
    'notCharging': '未充电',
    'reminderSettings': '提醒设置',
    'batteryNotifToggle': '电量通知总开关',
    'batteryNotifToggleDesc': '开启后以下提醒才会生效',
    'notifRules': '通知规则',
    'batteryNotes1': '低电量提醒仅在非充电状态下触发',
    'batteryNotes2': '电量回升到阈值以上才会重置提醒状态',
    'batteryNotes3': '电量通知随通知监听服务一起运行',
    'batteryNotes4': '点击规则可编辑，左滑或长按可删除',
    'closeBatteryOpt': '关闭电池优化',
    'batteryOptDesc': '息屏后系统会限制后台运行，可能导致通知监听服务停止',
    'ruleStartCharging': '手机接入充电器时推送',
    'ruleStopCharging': '手机断开充电器时推送',
    'ruleAboveThreshold': '电量达到 {n}% 时推送',
    'ruleBelowThreshold': '电量低于 {n}% 时推送',
    'ruleEqualThreshold': '电量等于 {n}% 时推送',
    'ruleUnknown': '未知规则类型',
    'confirmDeleteRule': '确认删除',
    'confirmDeleteRuleMsg': '确定要删除规则「{title}」吗？',
    'editRule': '编辑规则',
    'ruleType': '规则类型',
    'startCharging': '开始充电',
    'stopCharging': '断开充电',
    'belowValue': '低于某值',
    'aboveValue': '高于某值',
    'equalValue': '等于某值',
    'threshold': '电量阈值（%）',
    'customTitle': '自定义标题（可选）',
    'customTitleHint': '留空则使用默认标题',
    'batteryReminder': '电量提醒',
    'deleteRule': '删除规则',
    'confirmDeleteThisRule': '确定要删除这条通知规则吗？',
    // 设备名称
    'setDeviceName': '设置设备名称',
    'deviceNameLabel': '设备名称',
    // 关于弹窗
    'aboutDialogTitle': '关于',
    'author': '作者：幻念团队 fnthinklevi',
    'appDesc': '监听通知栏所有通知并推送到 Webhook',
    'appFeatures': '支持：微信 / QQ / 短信 / 来电 / 电量提醒',
    // 规则管理（规则列表页）
    'ruleListTitle': '规则管理',
    'ruleNew': '新规则',
    'ruleNoCondition': '无条件',
    'ruleNoAction': '无动作',
    'ruleListEmpty': '暂无规则',
    'ruleAddFirst': '添加第一条规则',
    'rulePriorityBadge': '优先级 {n}',
    'ruleGuideTitle': '规则引擎介绍',
    'ruleGuideAdd': '添加规则',
    'ruleGuideAddDesc': '点击右上角「+」或右下角浮动按钮创建新规则',
    'ruleGuideCondition': '设置条件',
    'ruleGuideConditionDesc': '配置触发规则的条件（IF），如应用包名、关键词、时间等',
    'ruleGuideAction': '执行动作',
    'ruleGuideActionDesc': '设置满足条件后执行的动作（THEN），如推送通知、静默忽略等',
    'ruleGuideEnable': '启用规则',
    'ruleGuideEnableDesc': '通过开关控制规则是否生效，未启用的规则不会执行',
    'ruleGuideTip': '提示：规则按优先级顺序执行，匹配第一条规则后即停止。可通过编辑规则调整优先级。',
    'ruleGuideGotIt': '知道了',
    'ruleHelp': '使用帮助',
    'ruleAddTooltip': '添加规则',
    'ruleDeleteMsg': '确定要删除规则「{name}」吗？',
    // 规则编辑页
    'ruleEditTitle': '编辑规则',
    'ruleName': '规则名称',
    'ruleNameHint': '输入规则名称',
    'ruleDescription': '规则描述',
    'ruleDescriptionHint': '可选，描述规则用途',
    'ruleConditions': '条件（IF）',
    'ruleActions': '动作（THEN）',
    'ruleAddCondition': '添加条件',
    'ruleAddAction': '添加动作',
    'rulePriority': '规则优先级',
    'rulePriorityNote': '优先级越高，规则越先执行。相同优先级按添加顺序执行。',
    'rulePDefault': '默认 (0)',
    'rulePLow': '低 (50)',
    'rulePMedium': '中 (100)',
    'rulePHigh': '高 (200)',
    'rulePHighest': '最高 (500)',
    'ruleSelect': '请选择',
    'ruleEditCondition': '编辑条件',
    'ruleAddConditionTitle': '添加条件',
    'ruleConditionType': '条件类型',
    'ruleConditionValue': '条件值',
    'ruleLogic': '逻辑运算符',
    'ruleEditAction': '编辑动作',
    'ruleAddActionTitle': '添加动作',
    'ruleActionType': '动作类型',
    'ruleDelayTitle': '延迟推送参数（至少填写一项）',
    'ruleDelaySeconds': '延迟秒数',
    'ruleDelaySecondsHint': '如 60 = 延迟 1 分钟',
    'ruleScheduleTime': '定时时间',
    'ruleScheduleTimeHint': '如 22:00（当日到点推送）',
    'ruleBasicInfo': '基本信息',
    'ruleEnableRule': '启用规则',
    'ruleEmptyConditions': '暂无条件，点击添加',
    'ruleEmptyActions': '暂无动作，点击添加',
    'ruleDelayMinute': '延迟 {n} 分钟',
    'ruleDelaySecond': '延迟 {n} 秒',
    'ruleScheduleAt': '定时 {t}',
    // 条件类型
    'condPackage': '应用包名',
    'condTitleContains': '标题包含',
    'condTitleNotContains': '标题不包含',
    'condContentContains': '内容包含',
    'condContentNotContains': '内容不包含',
    'condPriority': '通知优先级',
    'condTimeRange': '时间范围',
    'condRegex': '正则表达式',
    'hintPackage': '例如: com.example.app',
    'hintKeyword': '输入关键词',
    'hintPriority': '高/中/低',
    'hintTimeRange': '09:00-18:00',
    'hintRegex': '正则表达式',
    // 动作类型
    'actionPush': '推送通知',
    'actionSilent': '静默忽略',
    'actionDelay': '延迟推送',
    'actionMerge': '合并推送',
    'actionRecord': '仅记录',
    'actionPushDesc': '将通知推送到指定渠道',
    'actionSilentDesc': '不推送，静默处理',
    'actionDelayDesc': '延迟一段时间后推送',
    'actionMergeDesc': '合并同应用多条通知',
    'actionRecordDesc': '仅记录到历史，不推送',
    // 逻辑运算符
    'logicAnd': '且',
    'logicOr': '或',
    // 关键词过滤页
    'keywordTitle': '关键词过滤',
    'keywordWhitelist': '白名单',
    'keywordBlacklist': '黑名单',
    'keywordWhitelistHint': '输入白名单关键词',
    'keywordBlacklistHint': '输入黑名单关键词',
    'keywordWhitelistDesc': '白名单：通知内容包含任一关键词时，即使应用未被选中也会推送（优先级最高）',
    'keywordBlacklistDesc': '黑名单：通知内容包含任一关键词时，即使应用被选中也不会推送',
    'keywordWhitelistEmpty': '暂无白名单关键词',
    'keywordBlacklistEmpty': '暂无黑名单关键词',
    // 启动页
    'initializing': '正在初始化...',
    'loadWebhook': '加载 Webhook 配置...',
    'loadBattery': '加载电池配置...',
    'loadRecords': '加载通知记录...',
    'loadFilter': '加载过滤配置...',
    'initUpdate': '初始化更新服务...',
    'initRetry': '初始化重试服务...',
    'initComplete': '初始化完成',
    // 错误
    'initFailed': '应用启动失败',
    'initFailedMsg': '依赖注入初始化失败，请重启应用',
    'retry': '重试',
    'pageInitFailed': '页面初始化失败: {e}',
    'webhookSaved': 'Webhook 配置已保存',
    'emailSaved': '邮件通道配置已保存',
    'unknownError': '未知错误',
    'testFailedMsg': '测试失败: {e}',
    'unknownResult': '未知结果',
    // 应用图标
    'iconDefault': '默认图标',
    'iconBlue': '蓝色',
    'iconCyan': '天蓝',
    'iconTeal': '青色',
    'iconMint': '薄荷',
    'iconGreen': '绿色',
    'iconYellow': '黄色',
    'iconOrange': '橙色',
    'iconRed': '红色',
    'iconPink': '粉色',
    'iconRose': '玫红',
    'iconPurple': '紫色',
    'iconIndigo': '靛蓝',
    'iconBrown': '棕色',
    'iconGray': '灰色',
    'iconGraphite': '深灰',
    'iconBlack': '墨黑',
    'appIconTitle': '应用图标',
    'currentIcon': '当前：{label}',
    'iconSwitched': '已切换至「{label}」，桌面稍后刷新',
    'iconSwitchFailed': '切换失败',
    // 应用筛选
    'done': '完成',
    'refreshAppList': '更新软件列表',
    'appFilterBlockModeInfo': '当前模式：不通知应用 — 未选择时全部应用都推送通知',
    'appFilterBlockModeSelected': '已选择 {n} 个应用，这些应用的通知不会被推送',
    'appFilterAllowModeInfo': '当前模式：通知应用 — 未选择时全部应用都推送通知（默认）',
    'appFilterAllowModeSelected': '已选择 {n} 个应用，仅这些应用的通知会被推送',
    'filterNotifyApps': '通知应用',
    'filterBlockApps': '不通知应用',
    'appListPermDesc2': '为了能够筛选需要推送通知的应用，请授予应用读取已安装应用列表的权限。',
    'goEnablePermission': '前往开启权限',
    'refreshRetry': '刷新重试',
    'searchAppHint': '搜索应用名称或包名',
    'showSystemApps': '显示系统应用',
    'selectAll': '全选',
    'deselectAll': '清空',
    'invertSelection': '反选',
    'selectedCount': '已选 {n}',
    'noAppsFound': '没有找到应用',
    'refreshFailed': '刷新失败：{e}',
    // 推送统计
    'statsToday': '今日推送',
    'statsTotal': '总推送数',
    'statsApps': '应用数',
    'statsTrend': '近7天推送趋势',
    'statsNoData': '暂无数据',
    'statsRank': '应用推送排行',
    // 送达状态
    'deliverySuccess': '推送成功',
    'deliveryFailed': '推送失败',
    'deliveryPending': '发送中',
    // 隐私政策
    'privacyOverviewTitle': '隐私政策概述',
    'privacyOverviewContent':
        '通知推送助手（以下简称"本应用"）由幻念团队开发并运营。本应用高度重视您的个人信息与隐私保护，在您使用本应用前，请仔细阅读本隐私政策，了解我们如何收集、使用、存储和保护您的信息。\n\n本政策适用于本应用提供的所有服务。当您安装并使用本应用时，即表示您已阅读、理解并同意本政策的全部内容。',
    'privacyInfoTitle': '我们收集的信息',
    'privacyInfoContent':
        '本应用遵循"最小必要"原则，仅收集实现核心功能所必需的信息：\n\n1. 通知内容（本地处理）\n   - 应用通过系统通知监听服务读取通知内容\n   - 所有通知内容仅在设备本地完成规则匹配、关键词过滤，并按您自行配置的 Webhook 或邮件地址转发\n   - 通知内容不会上传至除您指定目标以外的任何服务器\n\n2. 崩溃统计信息（腾讯 Bugly）\n   - 收集应用崩溃时的堆栈信息、设备型号、系统版本、应用版本号、CPU 架构\n   - 仅用于定位和修复崩溃问题，提升应用稳定性\n\n3. 推送统计与历史记录（本地存储）\n   - 通知记录、推送状态、每日统计等数据使用 AES-256 加密存储在本地数据库\n   - 这些数据仅保存在您的设备上，不会对外发送\n\n4. 延迟推送队列（本地存储）\n   - 规则引擎产生的延迟/定时推送任务持久化保存在本机，重启后不丢失\n\n5. 电池状态（本地监控）\n   - 电量及充电状态监控仅在本机采集，用于首页展示，不对外发送\n\n6. 已安装应用列表（本地使用）\n   - 用于规则引擎条件配置与应用过滤，仅在本机使用',
    'privacyNoCollectTitle': '我们不收集的信息',
    'privacyNoCollectContent':
        '本应用不会收集以下个人隐私信息：\n\n• 通讯录、短信内容（除非您主动授权用于短信通知识别）\n• 位置信息\n• 通话记录\n• 相册、文件内容\n• 麦克风、摄像头数据\n• 个人身份信息（姓名、身份证号、手机号等）\n\n当您不同意授权时，本应用的相关可选功能将不可用，但核心通知转发功能不受影响。',
    'privacyShareTitle': '信息共享与披露',
    'privacyShareContent':
        '本应用不会出售、出租或交易您的个人信息。仅在以下情形中共享必要的信息：\n\n1. 您主动配置的转发目标\n   - 当您配置 Webhook（企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus）或 SMTP 邮件后，您选择转发的通知内容将发送至这些您指定的第三方平台\n   - 发送前需要您明确配置目标地址，未配置不会发生任何数据外发\n\n2. 第三方崩溃统计服务（腾讯 Bugly）\n   - 仅共享崩溃堆栈及设备基础环境信息，用于修复问题\n\n3. 法律法规要求\n   - 依据法律、法规或有权机关的要求披露相关信息',
    'privacyStorageTitle': '数据存储与安全',
    'privacyStorageContent':
        '本应用采用多层安全机制保护您的数据：\n\n1. 本地数据库加密\n   - 通知历史记录、推送统计使用 AES-256 加密存储（sqflite_sqlcipher）\n   - 加密密钥保存在 Android 系统密钥库（AndroidKeyStore）中\n   - 即使设备被他人获取，也无法直接读取数据库内容\n\n2. 敏感配置加密\n   - Webhook URL、SMTP 账号、TOTP 密钥等敏感配置使用 AndroidKeyStore / AES-256-GCM 加密存储\n   - 不会以明文形式保存在 SharedPreferences 中\n\n3. 网络传输安全\n   - 全站强制 HTTPS，禁止明文 HTTP 传输\n   - 管理后台 Token 仅通过 HTTP Header 传递，不出现在 URL 中\n\n4. 其他安全措施\n   - 管理后台二步验证（TOTP）\n   - 应用备份已禁用（allowBackup=false），防止数据通过云备份泄露\n   - 应用内广播接收器已加固，防止外部伪造通知数据\n\n5. 数据保留\n   - 您可随时在应用内清除全部或部分推送历史记录\n   - 卸载应用将清除全部本地数据',
    'privacyThirdPartyTitle': '第三方服务',
    'privacyThirdPartyContent':
        '本应用使用以下第三方服务：\n\n腾讯 Bugly（崩溃统计）\n• 服务商：深圳市腾讯计算机系统有限公司\n• 用途：收集应用崩溃信息，帮助定位和修复问题\n• 隐私政策：https://privacy.qq.com/\n• 采集数据：崩溃堆栈、设备型号、系统版本、应用版本、CPU 架构\n\n用户主动配置的推送目标（非 SDK）\n• 企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus、SMTP 邮件服务器\n• 本应用仅向您自行配置的地址发送您选择转发的通知内容，不对第三方平台的数据处理行为负责\n• 涉及上述平台的隐私政策，请查阅对应平台官方文档',
    'privacyPermTitle': '权限说明',
    'privacyPermContent':
        '本应用遵循最小权限原则，以下为完整权限清单及用途说明：\n\n核心权限（必需）：\n• 通知使用权（Notification Listener）：读取通知内容，实现转发与规则引擎功能\n• 网络访问（INTERNET）：Webhook/邮件推送与版本更新检查\n• 前台服务（FOREGROUND_SERVICE 等）：保持通知监听服务常驻，确保消息及时推送\n• 开机自启动（RECEIVE_BOOT_COMPLETED）：设备重启后自动恢复通知监听服务\n• 通知发送（POST_NOTIFICATIONS）：发送本地通知提示\n• 唤醒锁（WAKE_LOCK）：延迟/定时推送到点唤醒设备\n\n辅助权限（可选）：\n• 电量优化白名单（REQUEST_IGNORE_BATTERY_OPTIMIZATIONS）：避免系统限制后台服务\n• 短信（RECEIVE_SMS/READ_SMS）：可选，用于短信通知识别与转发\n• 电话状态（READ_PHONE_STATE）：可选，用于来电通知识别\n• 存储（READ/WRITE_EXTERNAL_STORAGE、MANAGE_EXTERNAL_STORAGE）：导出推送历史 JSON、保存更新 APK\n• 安装未知应用（REQUEST_INSTALL_PACKAGES）：应用内在线更新时安装 APK\n• 查询已安装应用（QUERY_ALL_PACKAGES）：规则引擎条件配置与应用过滤\n• 振动（VIBRATE）：推送提示振动\n• 网络状态（ACCESS_NETWORK_STATE）：检测网络连接状态\n\n以上辅助权限均在您主动授权后使用，可随时在系统设置中关闭。',
    'privacyChildTitle': '儿童隐私',
    'privacyChildContent':
        '本应用面向一般用户，不针对 14 周岁以下儿童设计，也不会故意收集儿童的个人信息。若您是未成年人，请在监护人陪同下阅读本政策，并在监护人同意后使用本应用。',
    'privacyRightsTitle': '您的权利',
    'privacyRightsContent':
        '您对本应用所处理的本地数据享有以下权利：\n\n• 访问权：在应用内查看推送历史记录与统计信息\n• 删除权：随时清除全部或部分推送历史记录，卸载应用将删除全部本地数据\n• 撤回同意权：可在系统设置中关闭任何已授权的权限\n• 知情权：本政策将随应用功能变化及时更新并在应用内公示',
    'privacyUpdateTitle': '政策更新',
    'privacyUpdateContent':
        '本隐私政策可能会不定期更新。当政策发生变更时，我们将在应用内发布更新后的政策，并更新页面底部的"最后更新"日期。您继续使用本应用即表示您同意更新后的政策。',
    'privacyContactTitle': '联系我们',
    'privacyContactContent':
        '如果您对本隐私政策或数据处理有任何疑问、意见或建议，可通过以下方式联系我们：\n\n• 在应用内「更多」页查看最新版本与更新说明\n• 通过 GitHub 仓库提交 Issue：https://github.com/fnthinklevi/noticeTransmit\n\n我们将在收到您的反馈后尽快予以回复。',
    'lastUpdate': '最后更新：2026年8月15日',
  };

  static const _en = <String, String>{
    // Common
    'appName': 'NoticeTransmit',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
    'save': 'Save',
    'delete': 'Delete',
    'edit': 'Edit',
    'add': 'Add',
    'test': 'Test',
    'send': 'Send',
    'close': 'Close',
    'ok': 'OK',
    'later': 'Later',
    'goSettings': 'Go to Settings',
    'loading': 'Loading...',
    'unknown': 'Unknown',
    'notSet': 'Not Set',
    'enabled': 'Enabled',
    'disabled': 'Disabled',
    'on': 'On',
    'off': 'Off',
    // Tab
    'tabNotification': 'Notifications',
    'tabBattery': 'Battery',
    'tabMore': 'More',
    // Notification page
    'serviceRunning': 'Notification service is running, tap to stop',
    'serviceStopped': 'Notification service is stopped, tap to start',
    'running': 'Running',
    'stopped': 'Stopped',
    'currentChannels': 'Push Channels',
    'noChannels': 'No channels configured',
    'statusOk': 'Normal',
    'statusError': 'Abnormal',
    'permSettings': 'Permissions',
    'permSettingsDesc':
        'Configure notification, battery, background permissions',
    'pushHistory': 'Push History',
    'recordCount': '{n} records',
    'notificationPermissionTitle': 'Notification Access Not Enabled',
    'notificationPermissionMsg':
        'Notification access is not enabled. The app cannot read device notifications.\n\nPlease go to Permissions and enable notification access before starting the service.',
    // More page
    'appearance': 'Appearance',
    'pushSettings': 'Push Settings',
    'pushChannels': 'Push Channels',
    'filterRules': 'Filter Rules',
    'webhookChannel': 'Webhook Channels',
    'webhookNotConfigured': 'Not configured',
    'webhookConfigured': '{n} configured · {m} enabled',
    'emailChannel': 'Email Forwarding',
    'emailChannelDesc': 'SMTP email notifications',
    'appFilter': 'App Filter',
    'appFilterBlocked': '{n} apps blocked',
    'appFilterSelected': '{n} apps selected',
    'appFilterAll': 'All apps push',
    'keywordFilter': 'Keyword Filter',
    'keywordWhitelistBlacklist': 'Whitelist {n} · Blacklist {m}',
    'ruleEngine': 'Rule Engine',
    'ruleCount': '{n} rules',
    'ruleEmpty': 'Tap to add rule',
    'device': 'Device',
    'deviceName': 'Device Name',
    'widgetSection': 'Desktop Widget',
    'widgetGuide': 'Push Toggle',
    'widgetGuideDesc': 'One-tap start/pause push from home screen',
    'widgetGuideIntro':
        'After adding the "Push Toggle" widget to your home screen, you can start or pause push with one tap without opening the app.',
    'widgetGuideStep1': '1. Long-press an empty area of the home screen',
    'widgetGuideStep2': '2. Tap "Widgets" (小部件 / 插件)',
    'widgetGuideStep3':
        '3. Find "NoticeTransmit" and drag "Push Toggle" to the home screen',
    'widgetGuideBrand': 'Add widget by brand',
    'widgetBrandXiaomi':
        'Xiaomi / Redmi: long-press home screen → Add widgets → NoticeTransmit',
    'widgetBrandHuawei':
        'Huawei / Honor: pinch or long-press home screen → Widgets → NoticeTransmit',
    'widgetBrandOppo':
        'OPPO / realme / OnePlus: long-press home screen → Add widgets → NoticeTransmit',
    'widgetBrandVivo':
        'vivo / iQOO: long-press home screen → Widgets → NoticeTransmit',
    'widgetBrandSamsung':
        'Samsung: long-press home screen → Widgets → NoticeTransmit',
    'widgetBrandOthers':
        'Other brands (Stock / Pixel / Motorola / Sony, etc.): long-press home screen → Widgets → NoticeTransmit',
    'widgetTipsTitle': 'Tips',
    'widgetTip1': 'Tap the widget to toggle push (Active ⇄ Paused)',
    'widgetTip2':
        'While paused, monitoring continues but messages are not sent',
    'widgetTip3':
        'Some brands require autostart permission for the widget to refresh in real time',
    'widgetTip4':
        'If the widget is not listed, open the app once or restart the launcher',
    'widgetPinTitle': 'Quick Add (Recommended)',
    'widgetPinDesc':
        'Tap below and confirm in the system dialog to place the 2×2 push toggle widget on your home screen, no dragging needed.',
    'widgetPinAction': 'Add 2×2 widget',
    'widgetPinWideAction': 'Add 4×2 wide widget',
    'widgetPinSuccess': 'Request sent, place the widget on the home screen',
    'widgetPinUnsupported':
        'This launcher does not support quick-add. Long-press an empty area of the home screen to add manually',
    'widgetPinLowApi':
        'Quick-add requires Android 8.0+. Long-press an empty area of the home screen to add manually',
    'widgetPin2x2': '2×2 round toggle: title + status circle + tap hint',
    'widgetPin4x2': '4×2 wide bar: title + status circle + daily pushed count',
    'pushStats': 'Push Statistics',
    'pushStatsDesc': 'View push data statistics',
    'aboutUpdate': 'About & Update',
    'checkUpdate': 'Check Update',
    'checking': 'Checking...',
    'clickToCheck': 'Tap to check for updates',
    'privacyPolicyTitle': 'Privacy Policy',
    'privacyPolicyDesc': 'Data collection and privacy',
    'aboutTitle': 'About',
    'aboutDesc': 'Version info and author',
    'followSystem': 'Follow System',
    'lightMode': 'Light Mode',
    'darkMode': 'Dark Mode',
    'language': 'Language',
    'langDefault': 'Default',
    'langChinese': '中文',
    'langEnglish': 'English',
    // Language switch
    'switchLangTitle': 'Switch Language',
    'switchLangMsg': 'System language changed to {lang}. Switch app language?',
    'switchBtn': 'Switch',
    'notNow': 'Not Now',
    // Privacy dialog
    'privacyTitle': 'Privacy Policy',
    'privacyWelcome': 'Welcome to NoticeTransmit!',
    'privacyBody':
        'Please read our privacy policy before using this app.\n\n• All notifications are processed on-device and only forwarded to Webhook or email addresses you configure\n• Push history is AES-256 encrypted and stored in a local database\n• Only crash logs are collected (Tencent Bugly) for fixing issues; no personal information is collected\n• Channel credentials (Webhook/email) are encrypted with AndroidKeyStore\n\nBy tapping "Agree", you agree to our privacy policy.',
    'disagree': 'Disagree',
    'agree': 'Agree',
    'privacyWarnTitle': 'Notice',
    'privacyWarnBody':
        'You must agree to the privacy policy to use this app.\n\nIf you disagree, the app will exit.\n\nAre you sure you want to exit?',
    'returnAgree': 'Go Back',
    'confirmExit': 'Exit',
    // Update
    'latestVersion': 'You are on the latest version',
    'checkUpdateFailed': 'Update check failed: {e}',
    'checkUpdateNetworkError': 'Update check failed, please check your network',
    'importantUpdate': 'Important Update',
    'mustUpdate': 'You must update to continue using this app',
    'newVersionFound': 'New Version Available',
    'latestVer': 'Latest version: ',
    'currentVer': 'Current version: ',
    'fileSize': 'File size: ',
    'updateContent': 'Changelog',
    'updateNow': 'Update Now',
    'ignore': 'Ignore',
    'update': 'Update',
    'downloading': 'Downloading update',
    'downloadFailed': 'Download failed: {e}',
    'storagePermissionRequired': 'Storage Permission Required',
    'storagePermissionMsg':
        'Storage permission is needed to save the APK file. Please go to Settings to enable it.',
    'noStoragePermission':
        'Storage permission not granted, cannot download update',
    'enable': 'Enable',
    // Export
    'confirmExport': 'Confirm Export',
    'exportMsg':
        'Notification records will be exported as a JSON file containing notification content and device info.\n\nChoose a save location. Please keep the file safe or delete it after use.\n\nExport now?',
    'exportBtn': 'Export',
    'exportCancelled': 'Cancelled',
    'exportError': 'Export error',
    // History
    'historyTitle': 'History ({n})',
    'exportJson': 'Export JSON',
    'clearRecords': 'Clear Records',
    'clearToday': 'Clear Today',
    'clearLast10': 'Clear Last 10',
    'clearLast50': 'Clear Last 50',
    'clearAll': 'Clear All',
    'confirmClear': 'Confirm Clear',
    'clearConfirmMsg': 'Clear all {n} records?',
    'clearedN': '{n} records cleared',
    'searchHint': 'Search title/content/app',
    'noRecords': 'No records yet',
    'noMatchRecords': 'No matching records',
    'notificationDetail': 'Notification Detail',
    'detailInfo': 'Details',
    'noTitle': '(No title)',
    // Email settings
    'emailSettingsTitle': 'Email Forwarding',
    'noEmailChannels': 'No email channels',
    'clickToAdd': 'Tap the button below to add',
    'addEmailChannel': 'Add Email Channel',
    'editEmailChannel': 'Edit Email Channel',
    'testSend': 'Test Send',
    'testAndSave': 'Test & Save',
    'testPassed': '✅ Verified',
    'testFailed': '❌ Verification Failed',
    'testPassedSaved': 'Test passed, config saved',
    'verifyFailed': 'Verification failed: {msg}',
    'testing': 'Testing...',
    'channelNameHint': 'e.g. QQ Mail',
    'smtpHost': 'SMTP Server',
    'smtpPort': 'Port',
    'smtpAccount': 'SMTP Account',
    'smtpPassword': 'Password / Auth Code',
    'fromEmail': 'From',
    'toEmail': 'To',
    'useSSL': 'SSL',
    'subjectTemplate': 'Subject Template (optional)',
    'bodyTemplate': 'Body Template (optional)',
    'presetDefault': 'Default',
    'presetSimple': 'Simple',
    'presetDetailed': 'Detailed',
    'presetTime': 'Time',
    'presetCode': 'Code',
    'presetDevice': 'Device',
    'presetStandard': 'Standard',
    'presetComplete': 'Complete',
    'presetMinimal': 'Minimal',
    'availableVars':
        'Variables: %appName% %title% %content% %subText% %packageName% %deviceName% %time% %type% %date% %datetime%',
    // Webhook settings
    'webhookSettingsTitle': 'Webhook Channels',
    'webhookUrlRequired': 'Please enter a Webhook URL first',
    'channelList': 'Channel List',
    'addChannel': 'Add Channel',
    'webhookDesc1':
        'Support multiple Webhook channels with independent switches',
    'webhookDesc2': 'Auto-detect WeCom, DingTalk, Feishu formats',
    'webhookDesc3': 'Newly added channels are enabled by default',
    'channelN': 'Channel {n}',
    'channelNameOptional': 'Channel name (optional)',
    'webhookUrlPlaceholder': 'https://example.com/webhook',
    'webhookSecretLabel': 'Signing Secret (optional)',
    'webhookSigned': 'Signed',
    'webhookTemplateLabel': 'Push Template (optional)',
    'webhookFormatLabel': 'Message Format',
    'feishuMarkdownDowngradeHint':
        'Feishu custom bots do not support markdown. It will be sent as plain text (markdown symbols shown as-is). Consider using text format.',
    'webhookTemplateHint': 'Leave empty to use preset; supported variables:',
    'webhookTemplateInsertVar': 'Insert Variable',
    'webhookTemplatePreview': 'Preview',
    'platformWechat': 'WeCom',
    'platformDingtalk': 'DingTalk',
    'platformFeishu': 'Feishu',
    'platformGeneric': 'Generic JSON',
    'platformWechatDesc': 'Text format push',
    'platformGenericDesc': 'Custom JSON format',
    // Channel types (channel type selector / signing hints)
    'channelTypeLabel': 'Channel Type',
    'channelTypeAuto': 'Auto Detect',
    'channelTypeAutoWith': 'Auto Detect ({type})',
    'selectChannelType': 'Select Channel Type',
    'channelTypeWechat': 'WeCom Bot',
    'channelTypeDingtalk': 'DingTalk Bot',
    'channelTypeFeishu': 'Feishu Bot',
    'channelTypeTelegram': 'Telegram',
    'channelTypeBark': 'Bark',
    'channelTypeServerChan': 'ServerChan',
    'channelTypePushPlus': 'PushPlus',
    'channelTypeGeneric': 'Generic Webhook',
    'signingHintWechat':
        'Secret generated after enabling signature verification for WeCom bot',
    'signingHintDingtalk':
        'Secret generated after enabling sign verification for DingTalk bot (starts with SEC)',
    'signingHintFeishu':
        'Secret generated after enabling signature verification for Feishu custom bot',
    'signingHintTelegram':
        'Telegram uses Bot Token auth, no signing secret needed',
    'signingHintBark': 'Bark uses device Key auth, no signing secret needed',
    'signingHintServerChan':
        'ServerChan uses SendKey auth, no signing secret needed',
    'signingHintPushPlus': 'PushPlus uses Token auth, no signing secret needed',
    'signingHintGeneric':
        'Secret for your server to verify the signature (sent via X-Signature header)',
    'msgFormatDefault': 'Default Format',
    'msgFormatText': 'Plain Text',
    'urlEmpty': 'Empty',
    'urlPlaceholder': 'Enter Webhook URL',
    // Permission settings
    'permSettingsTitle': 'Permissions',
    'essentialPerms': 'Essential Permissions',
    'notifAccessPerm': 'Notification Access',
    'allowNotifications': 'Allow Notifications',
    'ignoreBatteryOpt': 'Ignore Battery Optimization',
    'vendorBgSettings': 'Vendor Background Settings',
    'xiaomiAutoStart': 'Xiaomi Auto-start',
    'meizuBgRun': 'Meizu Background',
    'huaweiProtected': 'Huawei Protected Apps',
    'oppoAutoStart': 'OPPO Auto-start',
    'vivoBgStart': 'vivo Background Start',
    'samsungSettings': 'Samsung Settings',
    'nativeAndroid': 'Native Android Settings',
    'optionalPerms': 'Optional Permissions',
    'smsPerm': 'SMS Permission',
    'smsPermDesc': 'Read SMS sender and content',
    'phonePerm': 'Phone Permission',
    'phonePermDesc': 'Get call number and status',
    'appListPerm': 'App List Permission',
    'appListPermDesc': 'Improves accuracy of specific features',
    'appListPermTitle': 'App List Permission Required',
    'appListPermMsg':
        'This permission is needed to get installed apps list for app filtering.\n\nTap "Allow" to go to system settings and enable it manually.',
    'appListPermExtra':
        'Used to get installed apps list for app-based notification filtering',
    'clickToSettings': 'Tap to open settings',
    'samsungSmartManagerDesc':
        'Add this app to auto-start whitelist in Smart Manager',
    'nativeBatteryOptDesc':
        'Confirm battery optimization is disabled in system settings',
    'exactAlarmTitle': 'Exact Alarm (On-time Push)',
    'exactAlarmDesc':
        'Delayed/scheduled pushes fire on time; requires system grant on Android 12+',
    'exactAlarmGranted': 'Granted',
    'exactAlarmNeedGrant': 'Tap to grant',
    'exactAlarmUnsupported': 'Requires Android 12+',
    'keepAliveGuideTitle': 'Keep-alive Guide',
    'keepAliveGuideDesc':
        'Some systems restrict background services and may miss notifications. Follow these steps:',
    'keepAliveStep1': 'Set battery optimization to Unrestricted',
    'keepAliveStep2': 'Allow auto-start',
    'keepAliveStep3': 'Keep running in background (task lock)',
    'keepAliveStep4': 'Confirm notification access is enabled',
    'notes': 'Notes',
    'allow': 'Allow',
    'reject': 'Reject',
    // Battery page
    'batteryTitle': 'Battery',
    'addRule': 'Add Rule',
    'charging': 'Charging',
    'notCharging': 'Not Charging',
    'reminderSettings': 'Reminder Settings',
    'batteryNotifToggle': 'Battery Notification Master Switch',
    'batteryNotifToggleDesc': 'Reminders below only work when enabled',
    'notifRules': 'Notification Rules',
    'batteryNotes1': 'Low battery alerts only trigger when not charging',
    'batteryNotes2': 'Alert resets when battery rises above threshold',
    'batteryNotes3':
        'Battery notification runs with the notification listener service',
    'batteryNotes4': 'Tap to edit, swipe or long-press to delete',
    'closeBatteryOpt': 'Close Battery Optimization',
    'batteryOptDesc': 'System may restrict background running when screen off',
    'ruleStartCharging': 'Push when charger connected',
    'ruleStopCharging': 'Push when charger disconnected',
    'ruleAboveThreshold': 'Push when battery reaches {n}%',
    'ruleBelowThreshold': 'Push when battery below {n}%',
    'ruleEqualThreshold': 'Push when battery equals {n}%',
    'ruleUnknown': 'Unknown rule type',
    'confirmDeleteRule': 'Confirm Delete',
    'confirmDeleteRuleMsg': 'Delete rule "{title}"?',
    'editRule': 'Edit Rule',
    'ruleType': 'Rule Type',
    'startCharging': 'Start Charging',
    'stopCharging': 'Stop Charging',
    'belowValue': 'Below Value',
    'aboveValue': 'Above Value',
    'equalValue': 'Equal Value',
    'threshold': 'Threshold (%)',
    'customTitle': 'Custom Title (optional)',
    'customTitleHint': 'Leave empty for default title',
    'batteryReminder': 'Battery Reminder',
    'deleteRule': 'Delete Rule',
    'confirmDeleteThisRule': 'Delete this notification rule?',
    // Device name
    'setDeviceName': 'Set Device Name',
    'deviceNameLabel': 'Device Name',
    // About dialog
    'aboutDialogTitle': 'About',
    'author': 'Author: fnthinklevi',
    'appDesc': 'Listen to all notifications and push to Webhook',
    'appFeatures': 'Supports: WeChat / QQ / SMS / Call / Battery',
    // Rule Management (rule list page)
    'ruleListTitle': 'Rule Management',
    'ruleNew': 'New Rule',
    'ruleNoCondition': 'No conditions',
    'ruleNoAction': 'No actions',
    'ruleListEmpty': 'No rules yet',
    'ruleAddFirst': 'Add Your First Rule',
    'rulePriorityBadge': 'Priority {n}',
    'ruleGuideTitle': 'Rule Engine Intro',
    'ruleGuideAdd': 'Add Rule',
    'ruleGuideAddDesc':
        'Tap "+" in the top bar or the FAB to create a new rule',
    'ruleGuideCondition': 'Set Conditions',
    'ruleGuideConditionDesc':
        'Configure the IF conditions (app package, keyword, time, etc.)',
    'ruleGuideAction': 'Add Actions',
    'ruleGuideActionDesc':
        'Configure the THEN actions (push notification, silent ignore, etc.)',
    'ruleGuideEnable': 'Enable Rule',
    'ruleGuideEnableDesc':
        'Toggle to control whether the rule takes effect; disabled rules won\'t run',
    'ruleGuideTip':
        'Tip: rules run by priority; execution stops after the first match. Edit a rule to adjust priority.',
    'ruleGuideGotIt': 'Got It',
    'ruleHelp': 'Help',
    'ruleAddTooltip': 'Add Rule',
    'ruleDeleteMsg': 'Delete rule "{name}"?',
    // Rule Edit Page
    'ruleEditTitle': 'Edit Rule',
    'ruleName': 'Rule Name',
    'ruleNameHint': 'Enter rule name',
    'ruleDescription': 'Description',
    'ruleDescriptionHint': 'Optional',
    'ruleConditions': 'Conditions (IF)',
    'ruleActions': 'Actions (THEN)',
    'ruleAddCondition': 'Add Condition',
    'ruleAddAction': 'Add Action',
    'rulePriority': 'Rule Priority',
    'rulePriorityNote':
        'Higher priority runs first; equal priority runs in add order',
    'rulePDefault': 'Default (0)',
    'rulePLow': 'Low (50)',
    'rulePMedium': 'Medium (100)',
    'rulePHigh': 'High (200)',
    'rulePHighest': 'Highest (500)',
    'ruleSelect': 'Please select',
    'ruleEditCondition': 'Edit Condition',
    'ruleAddConditionTitle': 'Add Condition',
    'ruleConditionType': 'Condition Type',
    'ruleConditionValue': 'Value',
    'ruleLogic': 'Logic Operator',
    'ruleEditAction': 'Edit Action',
    'ruleAddActionTitle': 'Add Action',
    'ruleActionType': 'Action Type',
    'ruleDelayTitle': 'Delayed Push Params (fill at least one)',
    'ruleDelaySeconds': 'Delay (seconds)',
    'ruleDelaySecondsHint': 'e.g. 60 = 1 minute',
    'ruleScheduleTime': 'Schedule Time',
    'ruleScheduleTimeHint': 'e.g. 22:00 (push when due)',
    'ruleBasicInfo': 'Basic Info',
    'ruleEnableRule': 'Enable Rule',
    'ruleEmptyConditions': 'No conditions yet, tap to add',
    'ruleEmptyActions': 'No actions yet, tap to add',
    'ruleDelayMinute': 'Delay {n} min',
    'ruleDelaySecond': 'Delay {n} s',
    'ruleScheduleAt': 'Scheduled {t}',
    // Condition types
    'condPackage': 'App Package',
    'condTitleContains': 'Title Contains',
    'condTitleNotContains': 'Title Not Contains',
    'condContentContains': 'Content Contains',
    'condContentNotContains': 'Content Not Contains',
    'condPriority': 'Priority',
    'condTimeRange': 'Time Range',
    'condRegex': 'Regex',
    'hintPackage': 'e.g. com.example.app',
    'hintKeyword': 'Enter keyword',
    'hintPriority': 'High/Medium/Low',
    'hintTimeRange': '09:00-18:00',
    'hintRegex': 'Regex',
    // Action types
    'actionPush': 'Push Notification',
    'actionSilent': 'Silent Ignore',
    'actionDelay': 'Delayed Push',
    'actionMerge': 'Merge Push',
    'actionRecord': 'Record Only',
    'actionPushDesc': 'Push to configured channels',
    'actionSilentDesc': 'Don\'t push, process silently',
    'actionDelayDesc': 'Push after a delay',
    'actionMergeDesc': 'Merge notifications from the same app',
    'actionRecordDesc': 'Record to history only, no push',
    // Logic operators
    'logicAnd': 'And',
    'logicOr': 'Or',
    // Keyword Filter Page
    'keywordTitle': 'Keyword Filter',
    'keywordWhitelist': 'Whitelist',
    'keywordBlacklist': 'Blacklist',
    'keywordWhitelistHint': 'Enter whitelist keyword',
    'keywordBlacklistHint': 'Enter blacklist keyword',
    'keywordWhitelistDesc':
        'Whitelist: notification containing any keyword is pushed even if the app is not selected (highest priority)',
    'keywordBlacklistDesc':
        'Blacklist: notification containing any keyword won\'t be pushed even if the app is selected',
    'keywordWhitelistEmpty': 'No whitelist keywords',
    'keywordBlacklistEmpty': 'No blacklist keywords',
    // Splash
    'initializing': 'Initializing...',
    'loadWebhook': 'Loading Webhook config...',
    'loadBattery': 'Loading battery config...',
    'loadRecords': 'Loading notification records...',
    'loadFilter': 'Loading filter config...',
    'initUpdate': 'Initializing update service...',
    'initRetry': 'Initializing retry service...',
    'initComplete': 'Initialization complete',
    // Errors
    'initFailed': 'App startup failed',
    'initFailedMsg': 'DI initialization failed, please restart the app',
    'retry': 'Retry',
    'pageInitFailed': 'Page init failed: {e}',
    'webhookSaved': 'Webhook config saved',
    'emailSaved': 'Email channel config saved',
    'unknownError': 'Unknown error',
    'testFailedMsg': 'Test failed: {e}',
    'unknownResult': 'Unknown result',
    // App Icon
    'iconDefault': 'Default',
    'iconBlue': 'Blue',
    'iconCyan': 'Cyan',
    'iconTeal': 'Teal',
    'iconMint': 'Mint',
    'iconGreen': 'Green',
    'iconYellow': 'Yellow',
    'iconOrange': 'Orange',
    'iconRed': 'Red',
    'iconPink': 'Pink',
    'iconRose': 'Rose',
    'iconPurple': 'Purple',
    'iconIndigo': 'Indigo',
    'iconBrown': 'Brown',
    'iconGray': 'Gray',
    'iconGraphite': 'Graphite',
    'iconBlack': 'Black',
    'appIconTitle': 'App Icon',
    'currentIcon': 'Current: {label}',
    'iconSwitched': 'Switched to "{label}", home screen will refresh soon',
    'iconSwitchFailed': 'Switch failed',
    // App Filter
    'done': 'Done',
    'refreshAppList': 'Refresh App List',
    'appFilterBlockModeInfo':
        'Mode: Block — when none selected, all app notifications are pushed',
    'appFilterBlockModeSelected':
        '{n} app(s) selected — notifications from these apps will NOT be pushed',
    'appFilterAllowModeInfo':
        'Mode: Allow — when none selected, all app notifications are pushed (default)',
    'appFilterAllowModeSelected':
        '{n} app(s) selected — only notifications from these apps will be pushed',
    'filterNotifyApps': 'Notify Apps',
    'filterBlockApps': 'Block Apps',
    'appListPermDesc2':
        'To filter apps for push notifications, please grant permission to read installed apps.',
    'goEnablePermission': 'Go to Enable Permission',
    'refreshRetry': 'Refresh & Retry',
    'searchAppHint': 'Search app name or package',
    'showSystemApps': 'Show System Apps',
    'selectAll': 'Select All',
    'deselectAll': 'Clear All',
    'invertSelection': 'Invert',
    'selectedCount': 'Selected {n}',
    'noAppsFound': 'No apps found',
    'refreshFailed': 'Refresh failed: {e}',
    // Push Stats
    'statsToday': 'Today',
    'statsTotal': 'Total',
    'statsApps': 'Apps',
    'statsTrend': 'Last 7 Days Trend',
    'statsNoData': 'No data',
    'statsRank': 'App Push Ranking',
    // Delivery status
    'deliverySuccess': 'Sent',
    'deliveryFailed': 'Failed',
    'deliveryPending': 'Sending',
    'pushPausedByUser': 'Paused by user',
    'pushNow': 'Push Now',
    // Privacy Policy
    'privacyOverviewTitle': 'Privacy Policy Overview',
    'privacyOverviewContent':
        'NoticeTransmit (hereinafter referred to as "this App") is developed and operated by the Fnthink team. This App takes your privacy seriously. Please read this Privacy Policy carefully before using this App to understand how we collect, use, store, and protect your information.\n\nThis Policy applies to all services provided by this App. By installing and using this App, you acknowledge that you have read, understood, and agreed to this Policy.',
    'privacyInfoTitle': 'Information We Collect',
    'privacyInfoContent':
        'This App follows the principle of "minimum necessary" and only collects information required for core functionality:\n\n1. Notification Content (Local Processing)\n   - The app reads notification content through the system notification listener service\n   - All notification content is matched against rules, filtered by keywords, and forwarded to Webhook or email addresses you configure, all on-device\n   - Notification content is never uploaded to any server other than the targets you specify\n\n2. Crash Statistics (Tencent Bugly)\n   - Collects crash stack traces, device model, system version, app version, and CPU architecture\n   - Used solely to locate and fix crash issues and improve app stability\n\n3. Push Statistics & History (Local Storage)\n   - Notification records, delivery status, and daily statistics are AES-256 encrypted and stored in a local database\n   - These data stay on your device and are never transmitted externally\n\n4. Delayed Push Queue (Local Storage)\n   - Delay/scheduled push tasks from the rule engine are persisted locally and survive reboots\n\n5. Battery Status (Local Monitoring)\n   - Battery level and charging status are monitored locally for the home page display only\n\n6. Installed App List (Local Use)\n   - Used for rule engine condition configuration and app filtering, on-device only',
    'privacyNoCollectTitle': 'Information We Do Not Collect',
    'privacyNoCollectContent':
        'This App does NOT collect the following personal privacy information:\n\n• Contacts, or SMS content (unless you explicitly authorize SMS notification recognition)\n• Location information\n• Call logs\n• Photos, or file contents\n• Microphone or camera data\n• Personally identifiable information (name, ID number, phone number, etc.)\n\nIf you decline authorization, the related optional features will be unavailable, but core notification forwarding remains unaffected.',
    'privacyShareTitle': 'Information Sharing & Disclosure',
    'privacyShareContent':
        'This App never sells, rents, or trades your personal information. Information is only shared in the following circumstances:\n\n1. Forwarding Targets You Configure\n   - Once you configure Webhook (WeCom, DingTalk, Feishu, Telegram, Bark, ServerChan, PushPlus) or SMTP email, the notification content you choose to forward is sent to these third-party platforms you specified\n   - No data is transmitted externally until you explicitly configure a target address\n\n2. Third-Party Crash Statistics (Tencent Bugly)\n   - Only crash stack traces and basic device environment info are shared for issue fixing\n\n3. Legal Requirements\n   - Information may be disclosed as required by laws, regulations, or competent authorities',
    'privacyStorageTitle': 'Data Storage & Security',
    'privacyStorageContent':
        'This App uses multi-layer security mechanisms to protect your data:\n\n1. Local Database Encryption\n   - Notification history and push statistics are AES-256 encrypted (sqflite_sqlcipher)\n   - Encryption keys are stored in the Android system KeyStore (AndroidKeyStore)\n   - Even if the device is obtained by others, the database content cannot be read directly\n\n2. Sensitive Configuration Encryption\n   - Webhook URLs, SMTP credentials, and TOTP secrets are encrypted with AndroidKeyStore / AES-256-GCM\n   - Never stored in plain text in SharedPreferences\n\n3. Network Transport Security\n   - HTTPS is enforced site-wide; plain HTTP transmission is prohibited\n   - Admin backend tokens are only passed via HTTP headers, never in URLs\n\n4. Other Security Measures\n   - Admin backend two-step verification (TOTP)\n   - App backup is disabled (allowBackup=false) to prevent data leakage via cloud backup\n   - In-app broadcast receivers are hardened against forged notification data\n\n5. Data Retention\n   - You may clear all or part of the push history at any time in the app\n   - Uninstalling the app deletes all local data',
    'privacyThirdPartyTitle': 'Third-Party Services',
    'privacyThirdPartyContent':
        'This App uses the following third-party services:\n\nTencent Bugly (Crash Statistics)\n• Provider: Shenzhen Tencent Computer Systems Co., Ltd.\n• Purpose: Collect app crash information for issue diagnosis and fixing\n• Privacy Policy: https://privacy.qq.com/\n• Data Collected: Crash stack traces, device model, system version, app version, CPU architecture\n\nForwarding Targets You Configure (Not SDKs)\n• WeCom, DingTalk, Feishu, Telegram, Bark, ServerChan, PushPlus, SMTP email servers\n• This App only sends the notification content you choose to forward to addresses you configured and is not responsible for how third parties process data\n• Refer to the official documentation of the corresponding platform for its privacy policy',
    'privacyPermTitle': 'Permission Notes',
    'privacyPermContent':
        'This App follows the principle of least privilege. The complete permission list and purposes are as follows:\n\nCore Permissions (Required):\n• Notification Listener: Read notification content for forwarding and the rule engine\n• Internet (INTERNET): Webhook/email push and update checks\n• Foreground Service (FOREGROUND_SERVICE, etc.): Keeps the notification listener alive for timely delivery\n• Boot Completed (RECEIVE_BOOT_COMPLETED): Automatically restores the listener after reboot\n• Post Notifications (POST_NOTIFICATIONS): Sends local notification prompts\n• Wake Lock (WAKE_LOCK): Wakes the device for delayed/scheduled pushes\n\nAuxiliary Permissions (Optional):\n• Battery Optimization Whitelist (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS): Prevents the system from restricting background services\n• SMS (RECEIVE_SMS/READ_SMS): Optional, for SMS notification recognition and forwarding\n• Phone State (READ_PHONE_STATE): Optional, for incoming call notification recognition\n• Storage (READ/WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE): Export push history JSON and save update APKs\n• Install Unknown Apps (REQUEST_INSTALL_PACKAGES): Installs APKs for in-app updates\n• Query All Packages (QUERY_ALL_PACKAGES): Rule engine condition configuration and app filtering\n• Vibrate (VIBRATE): Vibration for push prompts\n• Network State (ACCESS_NETWORK_STATE): Detects network connectivity\n\nAuxiliary permissions are only used after your explicit authorization and can be revoked anytime in system settings.',
    'privacyChildTitle': 'Children\'s Privacy',
    'privacyChildContent':
        'This App is designed for the general public, is not intended for children under 14, and does not knowingly collect children\'s personal information. If you are a minor, please read this Policy with a guardian and use this App only with their consent.',
    'privacyRightsTitle': 'Your Rights',
    'privacyRightsContent':
        'You have the following rights regarding the local data processed by this App:\n\n• Access: View push history and statistics in the app\n• Deletion: Clear all or part of the push history at any time; uninstalling the app deletes all local data\n• Withdraw Consent: Disable any authorized permission in system settings at any time\n• Right to Know: This Policy is updated as features change and is published in the app',
    'privacyUpdateTitle': 'Policy Updates',
    'privacyUpdateContent':
        'This Privacy Policy may be updated from time to time. When changes occur, the updated policy will be published in the app and the "Last updated" date at the bottom of this page will be refreshed. Your continued use of this App signifies your agreement to the updated policy.',
    'privacyContactTitle': 'Contact Us',
    'privacyContactContent':
        'If you have any questions, comments, or suggestions about this Privacy Policy or data processing, you can reach us through:\n\n• Check the latest version and release notes on the "More" page in the app\n• Submit an Issue on GitHub: https://github.com/fnthinklevi/noticeTransmit\n\nWe will respond to your feedback as soon as possible.',
    'lastUpdate': 'Last updated: August 15, 2026',
  };

  static const _localizedValues = {'zh': _zh, 'en': _en};

  String _get(String key) =>
      _localizedValues[locale.languageCode]?[key] ??
      _localizedValues['en']![key]!;

  // Auto-generate getters for all keys
  String get appName => _get('appName');
  String get cancel => _get('cancel');
  String get confirm => _get('confirm');
  String get save => _get('save');
  String get delete => _get('delete');
  String get edit => _get('edit');
  String get add => _get('add');
  String get test => _get('test');
  String get send => _get('send');
  String get close => _get('close');
  String get ok => _get('ok');
  String get later => _get('later');
  String get goSettings => _get('goSettings');
  String get loading => _get('loading');
  String get unknown => _get('unknown');
  String get notSet => _get('notSet');
  String get enabled => _get('enabled');
  String get disabled => _get('disabled');
  String get on => _get('on');
  String get off => _get('off');
  String get tabNotification => _get('tabNotification');
  String get tabBattery => _get('tabBattery');
  String get tabMore => _get('tabMore');
  String get serviceRunning => _get('serviceRunning');
  String get serviceStopped => _get('serviceStopped');
  String get running => _get('running');
  String get stopped => _get('stopped');
  String get currentChannels => _get('currentChannels');
  String get noChannels => _get('noChannels');
  String get statusOk => _get('statusOk');
  String get statusError => _get('statusError');
  String get permSettings => _get('permSettings');
  String get permSettingsDesc => _get('permSettingsDesc');
  String get pushHistory => _get('pushHistory');
  String recordCount(int n) =>
      _get('recordCount').replaceAll('{n}', n.toString());
  String get notificationPermissionTitle => _get('notificationPermissionTitle');
  String get notificationPermissionMsg => _get('notificationPermissionMsg');
  String get appearance => _get('appearance');
  String get pushSettings => _get('pushSettings');
  String get pushChannels => _get('pushChannels');
  String get filterRules => _get('filterRules');
  String get webhookChannel => _get('webhookChannel');
  String get webhookNotConfigured => _get('webhookNotConfigured');
  String webhookConfigured(int n, int m) => _get(
    'webhookConfigured',
  ).replaceAll('{n}', n.toString()).replaceAll('{m}', m.toString());
  String get emailChannel => _get('emailChannel');
  String get emailChannelDesc => _get('emailChannelDesc');
  String get appFilter => _get('appFilter');
  String appFilterBlocked(int n) =>
      _get('appFilterBlocked').replaceAll('{n}', n.toString());
  String appFilterSelected(int n) =>
      _get('appFilterSelected').replaceAll('{n}', n.toString());
  String get appFilterAll => _get('appFilterAll');
  String get keywordFilter => _get('keywordFilter');
  String keywordWhitelistBlacklist(int n, int m) => _get(
    'keywordWhitelistBlacklist',
  ).replaceAll('{n}', n.toString()).replaceAll('{m}', m.toString());
  String get ruleEngine => _get('ruleEngine');
  String ruleCount(int n) => _get('ruleCount').replaceAll('{n}', n.toString());
  String get ruleEmpty => _get('ruleEmpty');
  String get device => _get('device');
  String get deviceName => _get('deviceName');
  String get widgetSection => _get('widgetSection');
  String get widgetGuide => _get('widgetGuide');
  String get widgetGuideDesc => _get('widgetGuideDesc');
  String get widgetGuideIntro => _get('widgetGuideIntro');
  String get widgetGuideStep1 => _get('widgetGuideStep1');
  String get widgetGuideStep2 => _get('widgetGuideStep2');
  String get widgetGuideStep3 => _get('widgetGuideStep3');
  String get widgetGuideBrand => _get('widgetGuideBrand');
  String get widgetBrandXiaomi => _get('widgetBrandXiaomi');
  String get widgetBrandHuawei => _get('widgetBrandHuawei');
  String get widgetBrandOppo => _get('widgetBrandOppo');
  String get widgetBrandVivo => _get('widgetBrandVivo');
  String get widgetBrandSamsung => _get('widgetBrandSamsung');
  String get widgetBrandOthers => _get('widgetBrandOthers');
  String get widgetTipsTitle => _get('widgetTipsTitle');
  String get widgetTip1 => _get('widgetTip1');
  String get widgetTip2 => _get('widgetTip2');
  String get widgetTip3 => _get('widgetTip3');
  String get widgetTip4 => _get('widgetTip4');
  String get widgetPinTitle => _get('widgetPinTitle');
  String get widgetPinDesc => _get('widgetPinDesc');
  String get widgetPinAction => _get('widgetPinAction');
  String get widgetPinWideAction => _get('widgetPinWideAction');
  String get widgetPinSuccess => _get('widgetPinSuccess');
  String get widgetPinUnsupported => _get('widgetPinUnsupported');
  String get widgetPinLowApi => _get('widgetPinLowApi');
  String get widgetPin2x2 => _get('widgetPin2x2');
  String get widgetPin4x2 => _get('widgetPin4x2');
  String get pushStats => _get('pushStats');
  String get pushStatsDesc => _get('pushStatsDesc');
  String get aboutUpdate => _get('aboutUpdate');
  String get checkUpdate => _get('checkUpdate');
  String get checking => _get('checking');
  String get clickToCheck => _get('clickToCheck');
  String get privacyPolicyTitle => _get('privacyPolicyTitle');
  String get privacyPolicyDesc => _get('privacyPolicyDesc');
  String get aboutTitle => _get('aboutTitle');
  String get aboutDesc => _get('aboutDesc');
  String get followSystem => _get('followSystem');
  String get lightMode => _get('lightMode');
  String get darkMode => _get('darkMode');
  String get language => _get('language');
  String get exactAlarmTitle => _get('exactAlarmTitle');
  String get exactAlarmDesc => _get('exactAlarmDesc');
  String get exactAlarmGranted => _get('exactAlarmGranted');
  String get exactAlarmNeedGrant => _get('exactAlarmNeedGrant');
  String get exactAlarmUnsupported => _get('exactAlarmUnsupported');
  String get keepAliveGuideTitle => _get('keepAliveGuideTitle');
  String get keepAliveGuideDesc => _get('keepAliveGuideDesc');
  String get keepAliveStep1 => _get('keepAliveStep1');
  String get keepAliveStep2 => _get('keepAliveStep2');
  String get keepAliveStep3 => _get('keepAliveStep3');
  String get keepAliveStep4 => _get('keepAliveStep4');
  String get langDefault => _get('langDefault');
  String get langChinese => _get('langChinese');
  String get langEnglish => _get('langEnglish');
  String get switchLangTitle => _get('switchLangTitle');
  String switchLangMsg(String lang) =>
      _get('switchLangMsg').replaceAll('{lang}', lang);
  String get switchBtn => _get('switchBtn');
  String get notNow => _get('notNow');
  String get privacyTitle => _get('privacyTitle');
  String get privacyWelcome => _get('privacyWelcome');
  String get privacyBody => _get('privacyBody');
  String get disagree => _get('disagree');
  String get agree => _get('agree');
  String get privacyWarnTitle => _get('privacyWarnTitle');
  String get privacyWarnBody => _get('privacyWarnBody');
  String get returnAgree => _get('returnAgree');
  String get confirmExit => _get('confirmExit');
  String get latestVersion => _get('latestVersion');
  String checkUpdateFailed(String e) =>
      _get('checkUpdateFailed').replaceAll('{e}', e);
  String get checkUpdateNetworkError => _get('checkUpdateNetworkError');
  String get importantUpdate => _get('importantUpdate');
  String get mustUpdate => _get('mustUpdate');
  String get newVersionFound => _get('newVersionFound');
  String get latestVer => _get('latestVer');
  String get currentVer => _get('currentVer');
  String get fileSize => _get('fileSize');
  String get updateContent => _get('updateContent');
  String get updateNow => _get('updateNow');
  String get ignore => _get('ignore');
  String get update => _get('update');
  String get downloading => _get('downloading');
  String downloadFailed(String e) =>
      _get('downloadFailed').replaceAll('{e}', e);
  String get storagePermissionRequired => _get('storagePermissionRequired');
  String get storagePermissionMsg => _get('storagePermissionMsg');
  String get noStoragePermission => _get('noStoragePermission');
  String get enable => _get('enable');
  String get confirmExport => _get('confirmExport');
  String get exportMsg => _get('exportMsg');
  String get exportBtn => _get('exportBtn');
  String get exportCancelled => _get('exportCancelled');
  String get exportError => _get('exportError');
  String historyTitle(int n) =>
      _get('historyTitle').replaceAll('{n}', n.toString());
  String get exportJson => _get('exportJson');
  String get clearRecords => _get('clearRecords');
  String get clearToday => _get('clearToday');
  String get clearLast10 => _get('clearLast10');
  String get clearLast50 => _get('clearLast50');
  String get clearAll => _get('clearAll');
  String get confirmClear => _get('confirmClear');
  String clearConfirmMsg(int n) =>
      _get('clearConfirmMsg').replaceAll('{n}', n.toString());
  String clearedN(int n) => _get('clearedN').replaceAll('{n}', n.toString());
  String get searchHint => _get('searchHint');
  String get noRecords => _get('noRecords');
  String get noMatchRecords => _get('noMatchRecords');
  String get notificationDetail => _get('notificationDetail');
  String get detailInfo => _get('detailInfo');
  String get noTitle => _get('noTitle');
  String get emailSettingsTitle => _get('emailSettingsTitle');
  String get noEmailChannels => _get('noEmailChannels');
  String get clickToAdd => _get('clickToAdd');
  String get addEmailChannel => _get('addEmailChannel');
  String get editEmailChannel => _get('editEmailChannel');
  String get testSend => _get('testSend');
  String get testAndSave => _get('testAndSave');
  String get testPassed => _get('testPassed');
  String get testFailed => _get('testFailed');
  String get testPassedSaved => _get('testPassedSaved');
  String verifyFailed(String msg) =>
      _get('verifyFailed').replaceAll('{msg}', msg);
  String get testing => _get('testing');
  String get channelNameHint => _get('channelNameHint');
  String get smtpHost => _get('smtpHost');
  String get smtpPort => _get('smtpPort');
  String get smtpAccount => _get('smtpAccount');
  String get smtpPassword => _get('smtpPassword');
  String get fromEmail => _get('fromEmail');
  String get toEmail => _get('toEmail');
  String get useSSL => _get('useSSL');
  String get subjectTemplate => _get('subjectTemplate');
  String get bodyTemplate => _get('bodyTemplate');
  String get presetDefault => _get('presetDefault');
  String get presetSimple => _get('presetSimple');
  String get presetDetailed => _get('presetDetailed');
  String get presetTime => _get('presetTime');
  String get presetCode => _get('presetCode');
  String get presetDevice => _get('presetDevice');
  String get presetStandard => _get('presetStandard');
  String get presetComplete => _get('presetComplete');
  String get presetMinimal => _get('presetMinimal');
  String get availableVars => _get('availableVars');
  String get webhookSettingsTitle => _get('webhookSettingsTitle');
  String get webhookUrlRequired => _get('webhookUrlRequired');
  String get channelList => _get('channelList');
  String get addChannel => _get('addChannel');
  String get webhookDesc1 => _get('webhookDesc1');
  String get webhookDesc2 => _get('webhookDesc2');
  String get webhookDesc3 => _get('webhookDesc3');
  String channelN(int n) => _get('channelN').replaceAll('{n}', n.toString());
  String get channelNameOptional => _get('channelNameOptional');
  String get webhookUrlPlaceholder => _get('webhookUrlPlaceholder');
  String get webhookSecretLabel => _get('webhookSecretLabel');
  String get webhookSigned => _get('webhookSigned');
  String get webhookTemplateLabel => _get('webhookTemplateLabel');
  String get webhookFormatLabel => _get('webhookFormatLabel');
  String get feishuMarkdownDowngradeHint => _get('feishuMarkdownDowngradeHint');
  String get webhookTemplateHint => _get('webhookTemplateHint');
  String get webhookTemplateInsertVar => _get('webhookTemplateInsertVar');
  String get webhookTemplatePreview => _get('webhookTemplatePreview');
  String get platformWechat => _get('platformWechat');
  String get platformDingtalk => _get('platformDingtalk');
  String get platformFeishu => _get('platformFeishu');
  String get platformGeneric => _get('platformGeneric');
  String get platformWechatDesc => _get('platformWechatDesc');
  String get platformGenericDesc => _get('platformGenericDesc');
  String get channelTypeLabel => _get('channelTypeLabel');
  String get channelTypeAuto => _get('channelTypeAuto');
  String channelTypeAutoWith(String type) =>
      _get('channelTypeAutoWith').replaceAll('{type}', type);
  String get selectChannelType => _get('selectChannelType');
  String get channelTypeWechat => _get('channelTypeWechat');
  String get channelTypeDingtalk => _get('channelTypeDingtalk');
  String get channelTypeFeishu => _get('channelTypeFeishu');
  String get channelTypeTelegram => _get('channelTypeTelegram');
  String get channelTypeBark => _get('channelTypeBark');
  String get channelTypeServerChan => _get('channelTypeServerChan');
  String get channelTypePushPlus => _get('channelTypePushPlus');
  String get channelTypeGeneric => _get('channelTypeGeneric');
  String get signingHintWechat => _get('signingHintWechat');
  String get signingHintDingtalk => _get('signingHintDingtalk');
  String get signingHintFeishu => _get('signingHintFeishu');
  String get signingHintTelegram => _get('signingHintTelegram');
  String get signingHintBark => _get('signingHintBark');
  String get signingHintServerChan => _get('signingHintServerChan');
  String get signingHintPushPlus => _get('signingHintPushPlus');
  String get signingHintGeneric => _get('signingHintGeneric');
  String get msgFormatDefault => _get('msgFormatDefault');
  String get msgFormatText => _get('msgFormatText');
  String get urlEmpty => _get('urlEmpty');
  String get urlPlaceholder => _get('urlPlaceholder');
  String get permSettingsTitle => _get('permSettingsTitle');
  String get essentialPerms => _get('essentialPerms');
  String get notifAccessPerm => _get('notifAccessPerm');
  String get allowNotifications => _get('allowNotifications');
  String get ignoreBatteryOpt => _get('ignoreBatteryOpt');
  String get vendorBgSettings => _get('vendorBgSettings');
  String get xiaomiAutoStart => _get('xiaomiAutoStart');
  String get meizuBgRun => _get('meizuBgRun');
  String get huaweiProtected => _get('huaweiProtected');
  String get oppoAutoStart => _get('oppoAutoStart');
  String get vivoBgStart => _get('vivoBgStart');
  String get samsungSettings => _get('samsungSettings');
  String get nativeAndroid => _get('nativeAndroid');
  String get optionalPerms => _get('optionalPerms');
  String get smsPerm => _get('smsPerm');
  String get smsPermDesc => _get('smsPermDesc');
  String get phonePerm => _get('phonePerm');
  String get phonePermDesc => _get('phonePermDesc');
  String get appListPerm => _get('appListPerm');
  String get appListPermDesc => _get('appListPermDesc');
  String get appListPermTitle => _get('appListPermTitle');
  String get appListPermMsg => _get('appListPermMsg');
  String get appListPermExtra => _get('appListPermExtra');
  String get clickToSettings => _get('clickToSettings');
  String get samsungSmartManagerDesc => _get('samsungSmartManagerDesc');
  String get nativeBatteryOptDesc => _get('nativeBatteryOptDesc');
  String get notes => _get('notes');
  String get allow => _get('allow');
  String get reject => _get('reject');
  String get batteryTitle => _get('batteryTitle');
  String get addRule => _get('addRule');
  String get charging => _get('charging');
  String get notCharging => _get('notCharging');
  String get reminderSettings => _get('reminderSettings');
  String get batteryNotifToggle => _get('batteryNotifToggle');
  String get batteryNotifToggleDesc => _get('batteryNotifToggleDesc');
  String get notifRules => _get('notifRules');
  String get batteryNotes1 => _get('batteryNotes1');
  String get batteryNotes2 => _get('batteryNotes2');
  String get batteryNotes3 => _get('batteryNotes3');
  String get batteryNotes4 => _get('batteryNotes4');
  String get closeBatteryOpt => _get('closeBatteryOpt');
  String get batteryOptDesc => _get('batteryOptDesc');
  String get ruleStartCharging => _get('ruleStartCharging');
  String get ruleStopCharging => _get('ruleStopCharging');
  String ruleAboveThreshold(int n) =>
      _get('ruleAboveThreshold').replaceAll('{n}', n.toString());
  String ruleBelowThreshold(int n) =>
      _get('ruleBelowThreshold').replaceAll('{n}', n.toString());
  String ruleEqualThreshold(int n) =>
      _get('ruleEqualThreshold').replaceAll('{n}', n.toString());
  String get ruleUnknown => _get('ruleUnknown');
  String get confirmDeleteRule => _get('confirmDeleteRule');
  String confirmDeleteRuleMsg(String title) =>
      _get('confirmDeleteRuleMsg').replaceAll('{title}', title);
  String get editRule => _get('editRule');
  String get ruleType => _get('ruleType');
  String get startCharging => _get('startCharging');
  String get stopCharging => _get('stopCharging');
  String get belowValue => _get('belowValue');
  String get aboveValue => _get('aboveValue');
  String get equalValue => _get('equalValue');
  String get threshold => _get('threshold');
  String get customTitle => _get('customTitle');
  String get customTitleHint => _get('customTitleHint');
  String get batteryReminder => _get('batteryReminder');
  String get deleteRule => _get('deleteRule');
  String get confirmDeleteThisRule => _get('confirmDeleteThisRule');
  String get setDeviceName => _get('setDeviceName');
  String get deviceNameLabel => _get('deviceNameLabel');
  String get aboutDialogTitle => _get('aboutDialogTitle');
  String get author => _get('author');
  String get appDesc => _get('appDesc');
  String get appFeatures => _get('appFeatures');
  String get initializing => _get('initializing');
  String get loadWebhook => _get('loadWebhook');
  String get loadBattery => _get('loadBattery');
  String get loadRecords => _get('loadRecords');
  String get loadFilter => _get('loadFilter');
  String get initUpdate => _get('initUpdate');
  String get initRetry => _get('initRetry');
  String get initComplete => _get('initComplete');
  String get initFailed => _get('initFailed');
  String get initFailedMsg => _get('initFailedMsg');
  String get retry => _get('retry');
  String pageInitFailed(String e) =>
      _get('pageInitFailed').replaceAll('{e}', e);
  String get webhookSaved => _get('webhookSaved');
  String get emailSaved => _get('emailSaved');
  String get unknownError => _get('unknownError');
  String testFailedMsg(String e) => _get('testFailedMsg').replaceAll('{e}', e);
  String get unknownResult => _get('unknownResult');
  // App Icon
  String get iconDefault => _get('iconDefault');
  String get iconBlue => _get('iconBlue');
  String get iconCyan => _get('iconCyan');
  String get iconTeal => _get('iconTeal');
  String get iconMint => _get('iconMint');
  String get iconGreen => _get('iconGreen');
  String get iconYellow => _get('iconYellow');
  String get iconOrange => _get('iconOrange');
  String get iconRed => _get('iconRed');
  String get iconPink => _get('iconPink');
  String get iconRose => _get('iconRose');
  String get iconPurple => _get('iconPurple');
  String get iconIndigo => _get('iconIndigo');
  String get iconBrown => _get('iconBrown');
  String get iconGray => _get('iconGray');
  String get iconGraphite => _get('iconGraphite');
  String get iconBlack => _get('iconBlack');
  String get appIconTitle => _get('appIconTitle');
  String currentIcon(String label) =>
      _get('currentIcon').replaceAll('{label}', label);
  String iconSwitched(String label) =>
      _get('iconSwitched').replaceAll('{label}', label);
  String get iconSwitchFailed => _get('iconSwitchFailed');
  // App Filter
  String get done => _get('done');
  String get refreshAppList => _get('refreshAppList');
  String get appFilterBlockModeInfo => _get('appFilterBlockModeInfo');
  String appFilterBlockModeSelected(int n) =>
      _get('appFilterBlockModeSelected').replaceAll('{n}', n.toString());
  String get appFilterAllowModeInfo => _get('appFilterAllowModeInfo');
  String appFilterAllowModeSelected(int n) =>
      _get('appFilterAllowModeSelected').replaceAll('{n}', n.toString());
  String get filterNotifyApps => _get('filterNotifyApps');
  String get filterBlockApps => _get('filterBlockApps');
  String get appListPermDesc2 => _get('appListPermDesc2');
  String get goEnablePermission => _get('goEnablePermission');
  String get refreshRetry => _get('refreshRetry');
  String get searchAppHint => _get('searchAppHint');
  String get showSystemApps => _get('showSystemApps');
  String get selectAll => _get('selectAll');
  String get deselectAll => _get('deselectAll');
  String get invertSelection => _get('invertSelection');
  String selectedCount(int n) =>
      _get('selectedCount').replaceAll('{n}', n.toString());
  String get noAppsFound => _get('noAppsFound');
  String refreshFailed(String e) => _get('refreshFailed').replaceAll('{e}', e);
  // Push Stats
  String get statsToday => _get('statsToday');
  String get statsTotal => _get('statsTotal');
  String get statsApps => _get('statsApps');
  String get statsTrend => _get('statsTrend');
  String get statsNoData => _get('statsNoData');
  String get statsRank => _get('statsRank');
  // Delivery status
  String get deliverySuccess => _get('deliverySuccess');
  String get deliveryFailed => _get('deliveryFailed');
  String get deliveryPending => _get('deliveryPending');
  String get pushPausedByUser => _get('pushPausedByUser');
  String get pushNow => _get('pushNow');
  // Privacy Policy
  String get privacyOverviewTitle => _get('privacyOverviewTitle');
  String get privacyOverviewContent => _get('privacyOverviewContent');
  String get privacyInfoTitle => _get('privacyInfoTitle');
  String get privacyInfoContent => _get('privacyInfoContent');
  String get privacyNoCollectTitle => _get('privacyNoCollectTitle');
  String get privacyNoCollectContent => _get('privacyNoCollectContent');
  String get privacyStorageTitle => _get('privacyStorageTitle');
  String get privacyStorageContent => _get('privacyStorageContent');
  String get privacyThirdPartyTitle => _get('privacyThirdPartyTitle');
  String get privacyThirdPartyContent => _get('privacyThirdPartyContent');
  String get privacyPermTitle => _get('privacyPermTitle');
  String get privacyPermContent => _get('privacyPermContent');
  String get privacyUpdateTitle => _get('privacyUpdateTitle');
  String get privacyUpdateContent => _get('privacyUpdateContent');
  String get lastUpdate => _get('lastUpdate');
  String get privacyShareTitle => _get('privacyShareTitle');
  String get privacyShareContent => _get('privacyShareContent');
  String get privacyChildTitle => _get('privacyChildTitle');
  String get privacyChildContent => _get('privacyChildContent');
  String get privacyRightsTitle => _get('privacyRightsTitle');
  String get privacyRightsContent => _get('privacyRightsContent');
  String get privacyContactTitle => _get('privacyContactTitle');
  String get privacyContactContent => _get('privacyContactContent');
  // Rule Management
  String get ruleListTitle => _get('ruleListTitle');
  String get ruleNew => _get('ruleNew');
  String get ruleNoCondition => _get('ruleNoCondition');
  String get ruleNoAction => _get('ruleNoAction');
  String get ruleListEmpty => _get('ruleListEmpty');
  String get ruleAddFirst => _get('ruleAddFirst');
  String rulePriorityBadge(int n) =>
      _get('rulePriorityBadge').replaceAll('{n}', n.toString());
  String get ruleGuideTitle => _get('ruleGuideTitle');
  String get ruleGuideAdd => _get('ruleGuideAdd');
  String get ruleGuideAddDesc => _get('ruleGuideAddDesc');
  String get ruleGuideCondition => _get('ruleGuideCondition');
  String get ruleGuideConditionDesc => _get('ruleGuideConditionDesc');
  String get ruleGuideAction => _get('ruleGuideAction');
  String get ruleGuideActionDesc => _get('ruleGuideActionDesc');
  String get ruleGuideEnable => _get('ruleGuideEnable');
  String get ruleGuideEnableDesc => _get('ruleGuideEnableDesc');
  String get ruleGuideTip => _get('ruleGuideTip');
  String get ruleGuideGotIt => _get('ruleGuideGotIt');
  String get ruleHelp => _get('ruleHelp');
  String get ruleAddTooltip => _get('ruleAddTooltip');
  String ruleDeleteMsg(String name) =>
      _get('ruleDeleteMsg').replaceAll('{name}', name);
  // Rule Edit
  String get ruleEditTitle => _get('ruleEditTitle');
  String get ruleName => _get('ruleName');
  String get ruleNameHint => _get('ruleNameHint');
  String get ruleDescription => _get('ruleDescription');
  String get ruleDescriptionHint => _get('ruleDescriptionHint');
  String get ruleConditions => _get('ruleConditions');
  String get ruleActions => _get('ruleActions');
  String get ruleAddCondition => _get('ruleAddCondition');
  String get ruleAddAction => _get('ruleAddAction');
  String get rulePriority => _get('rulePriority');
  String get rulePriorityNote => _get('rulePriorityNote');
  String get rulePDefault => _get('rulePDefault');
  String get rulePLow => _get('rulePLow');
  String get rulePMedium => _get('rulePMedium');
  String get rulePHigh => _get('rulePHigh');
  String get rulePHighest => _get('rulePHighest');
  String get ruleSelect => _get('ruleSelect');
  String get ruleEditCondition => _get('ruleEditCondition');
  String get ruleAddConditionTitle => _get('ruleAddConditionTitle');
  String get ruleConditionType => _get('ruleConditionType');
  String get ruleConditionValue => _get('ruleConditionValue');
  String get ruleLogic => _get('ruleLogic');
  String get ruleEditAction => _get('ruleEditAction');
  String get ruleAddActionTitle => _get('ruleAddActionTitle');
  String get ruleActionType => _get('ruleActionType');
  String get ruleDelayTitle => _get('ruleDelayTitle');
  String get ruleDelaySeconds => _get('ruleDelaySeconds');
  String get ruleDelaySecondsHint => _get('ruleDelaySecondsHint');
  String get ruleScheduleTime => _get('ruleScheduleTime');
  String get ruleScheduleTimeHint => _get('ruleScheduleTimeHint');
  String get ruleBasicInfo => _get('ruleBasicInfo');
  String get ruleEnableRule => _get('ruleEnableRule');
  String get ruleEmptyConditions => _get('ruleEmptyConditions');
  String get ruleEmptyActions => _get('ruleEmptyActions');
  String ruleDelayMinute(int n) =>
      _get('ruleDelayMinute').replaceAll('{n}', n.toString());
  String ruleDelaySecond(int n) =>
      _get('ruleDelaySecond').replaceAll('{n}', n.toString());
  String ruleScheduleAt(String t) =>
      _get('ruleScheduleAt').replaceAll('{t}', t);
  // Condition types
  String conditionTypeLabel(ConditionType type) => switch (type) {
    ConditionType.packageName => _get('condPackage'),
    ConditionType.titleContains => _get('condTitleContains'),
    ConditionType.titleNotContains => _get('condTitleNotContains'),
    ConditionType.contentContains => _get('condContentContains'),
    ConditionType.contentNotContains => _get('condContentNotContains'),
    ConditionType.priority => _get('condPriority'),
    ConditionType.timeRange => _get('condTimeRange'),
    ConditionType.regexMatch => _get('condRegex'),
  };
  String conditionTypeHint(ConditionType type) => switch (type) {
    ConditionType.packageName => _get('hintPackage'),
    ConditionType.titleContains => _get('hintKeyword'),
    ConditionType.titleNotContains => _get('hintKeyword'),
    ConditionType.contentContains => _get('hintKeyword'),
    ConditionType.contentNotContains => _get('hintKeyword'),
    ConditionType.priority => _get('hintPriority'),
    ConditionType.timeRange => _get('hintTimeRange'),
    ConditionType.regexMatch => _get('hintRegex'),
  };
  // Action types
  String actionTypeLabel(ActionType type) => switch (type) {
    ActionType.push => _get('actionPush'),
    ActionType.silent => _get('actionSilent'),
    ActionType.delay => _get('actionDelay'),
    ActionType.merge => _get('actionMerge'),
    ActionType.record => _get('actionRecord'),
  };
  String actionTypeDesc(ActionType type) => switch (type) {
    ActionType.push => _get('actionPushDesc'),
    ActionType.silent => _get('actionSilentDesc'),
    ActionType.delay => _get('actionDelayDesc'),
    ActionType.merge => _get('actionMergeDesc'),
    ActionType.record => _get('actionRecordDesc'),
  };
  // Logic operators
  String get logicAnd => _get('logicAnd');
  String get logicOr => _get('logicOr');
  String logicLabel(LogicOperator op) => switch (op) {
    LogicOperator.and => _get('logicAnd'),
    LogicOperator.or => _get('logicOr'),
  };
  // Keyword Filter
  String get keywordTitle => _get('keywordTitle');
  String get keywordWhitelist => _get('keywordWhitelist');
  String get keywordBlacklist => _get('keywordBlacklist');
  String get keywordWhitelistHint => _get('keywordWhitelistHint');
  String get keywordBlacklistHint => _get('keywordBlacklistHint');
  String get keywordWhitelistDesc => _get('keywordWhitelistDesc');
  String get keywordBlacklistDesc => _get('keywordBlacklistDesc');
  String get keywordWhitelistEmpty => _get('keywordWhitelistEmpty');
  String get keywordBlacklistEmpty => _get('keywordBlacklistEmpty');
}
