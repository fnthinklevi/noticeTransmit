import 'package:flutter/material.dart';

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
        '在使用本应用前，请您仔细阅读我们的隐私政策。\n\n• 所有通知内容仅在设备本地处理，不会上传到任何服务器\n• 推送历史使用 AES-256 加密存储在本地\n• 仅收集必要的崩溃日志（腾讯 Bugly）用于修复应用问题：崩溃堆栈、设备型号、系统版本、应用版本，不采集个人身份信息\n• Webhook 配置使用 AndroidKeyStore 加密存储\n\n点击"同意"即表示您已阅读并接受我们的隐私政策。',
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
    'webhookTemplateHint': '留空则使用预置模板；支持变量：',
    'webhookTemplateInsertVar': '插入变量',
    'webhookTemplatePreview': '预览',
    'platformWechat': 'WeCom',
    'platformDingtalk': 'DingTalk',
    'platformFeishu': 'Feishu',
    'platformGeneric': '通用 JSON',
    'platformWechatDesc': '文本格式推送',
    'platformGenericDesc': '自定义 JSON 格式',
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
    // 隐私政策
    'privacyOverviewTitle': '隐私政策概述',
    'privacyOverviewContent':
        '通知推送助手（以下简称"本应用"）非常重视用户的隐私保护。本隐私政策将帮助您了解我们如何收集、使用和保护您的信息。',
    'privacyInfoTitle': '信息收集与使用',
    'privacyInfoContent':
        '本应用仅收集以下类型的信息：\n\n1. 崩溃统计信息\n   - 通过腾讯 Bugly SDK 收集应用崩溃时的堆栈信息\n   - 收集设备型号、系统版本、应用版本号、CPU 架构等基础信息\n   - 用于定位和修复崩溃问题，提升应用稳定性\n\n2. 通知内容（本地处理）\n   - 应用通过通知监听服务获取系统通知内容\n   - 所有通知内容仅在设备本地处理，不会上传到任何服务器\n   - 仅通过用户自行配置的 Webhook URL 进行推送',
    'privacyNoCollectTitle': '我们不收集的信息',
    'privacyNoCollectContent':
        '本应用不会收集以下个人隐私信息：\n\n• 通讯录、短信内容\n• 位置信息\n• 通话记录\n• 相册、文件\n• 麦克风、摄像头数据\n• 其他个人身份信息',
    'privacyStorageTitle': '数据存储与安全',
    'privacyStorageContent':
        '本应用采用多层安全机制保护您的数据：\n\n1. 本地数据库加密\n   - 所有通知历史记录、推送统计使用 AES-256 加密存储\n   - 加密密钥保存在 Android 系统密钥库（AndroidKeyStore）中\n   - 即使设备被他人获取，也无法直接读取数据库内容\n\n2. 敏感配置加密\n   - Webhook URL（含企业微信、钉钉、飞书认证密钥）使用 AndroidKeyStore 加密存储\n   - 不会以明文形式保存在 SharedPreferences 中\n\n3. 网络传输安全\n   - 全站强制 HTTPS，禁止明文 HTTP 传输\n   - 已部署 SSL 证书固定（Certificate Pinning）基础设施\n   - 管理后台 Token 仅通过 HTTP Header 传递，不出现在 URL 中\n\n4. 其他安全措施\n   - 管理后台二步验证（TOTP）\n   - 应用备份已禁用，防止通知数据通过云备份泄露\n   - 应用内广播接收器已加固，防止外部伪造通知数据',
    'privacyThirdPartyTitle': '第三方服务',
    'privacyThirdPartyContent':
        '本应用使用以下第三方服务：\n\n腾讯 Bugly（崩溃统计）\n• 服务商：深圳市腾讯计算机系统有限公司\n• 用途：收集应用崩溃信息，帮助定位和修复问题\n• 隐私政策：https://privacy.qq.com/\n• 采集数据：崩溃堆栈、设备型号、系统版本、应用版本',
    'privacyPermTitle': '权限说明',
    'privacyPermContent':
        '本应用遵循最小权限原则，仅申请必要权限：\n\n• 通知访问权限：用于监听系统通知，实现推送功能\n• 网络权限：用于 Webhook 推送和版本更新检查\n• 前台服务：保活通知监听服务，确保消息及时推送\n• 开机自启动：开机后自动启动通知监听服务\n• 电量优化白名单：避免系统杀死后台服务\n• 短信/电话状态：增强短信和来电通知类型识别（可选）\n\n已移除的权限（v1.5.40 安全加固）：\n• WiFi 状态变更（CHANGE_WIFI_STATE）\n• WiFi 状态读取（ACCESS_WIFI_STATE）\n• 网络状态变更（CHANGE_NETWORK_STATE）',
    'privacyUpdateTitle': '政策更新',
    'privacyUpdateContent': '本隐私政策可能会不定期更新。更新后的政策将在应用内发布，继续使用即表示您同意更新后的政策。',
    'lastUpdate': '最后更新：2026年7月19日',
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
        'Please read our privacy policy before using this app.\n\n• All notifications are processed on-device, never uploaded to any server\n• Push history is AES-256 encrypted and stored locally\n• Only crash logs are collected (Tencent Bugly) for fixing issues: crash stack, device model, OS version, app version. No personal information is collected.\n• Webhook credentials are encrypted with AndroidKeyStore\n\nBy tapping "Agree", you agree to our privacy policy.',
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
    'webhookTemplateHint': 'Leave empty to use preset; supported variables:',
    'webhookTemplateInsertVar': 'Insert Variable',
    'webhookTemplatePreview': 'Preview',
    'platformWechat': 'WeCom',
    'platformDingtalk': 'DingTalk',
    'platformFeishu': 'Feishu',
    'platformGeneric': 'Generic JSON',
    'platformWechatDesc': 'Text format push',
    'platformGenericDesc': 'Custom JSON format',
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
        'Confirm battery optimization is off in system settings',
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
    // Privacy Policy
    'privacyOverviewTitle': 'Privacy Policy Overview',
    'privacyOverviewContent':
        'NoticePush (hereinafter referred to as "this App") attaches great importance to user privacy protection. This Privacy Policy will help you understand how we collect, use, and protect your information.',
    'privacyInfoTitle': 'Information Collection & Use',
    'privacyInfoContent':
        'This App only collects the following types of information:\n\n1. Crash Statistics\n   - Collects crash stack traces via Tencent Bugly SDK\n   - Collects device model, system version, app version, CPU architecture, and other basic info\n   - Used to locate and fix crash issues, improving app stability\n\n2. Notification Content (Local Processing)\n   - The app obtains system notification content through the notification listener service\n   - All notification content is processed locally on the device only and is not uploaded to any server\n   - Only pushed via user-configured Webhook URLs',
    'privacyNoCollectTitle': 'Information We Do Not Collect',
    'privacyNoCollectContent':
        'This App does NOT collect the following personal privacy information:\n\n• Contacts, SMS content\n• Location information\n• Call logs\n• Photos, files\n• Microphone, camera data\n• Other personally identifiable information',
    'privacyStorageTitle': 'Data Storage & Security',
    'privacyStorageContent':
        'This App uses multi-layer security mechanisms to protect your data:\n\n1. Local Database Encryption\n   - All notification history and push statistics are AES-256 encrypted\n   - Encryption keys are stored in the Android system KeyStore (AndroidKeyStore)\n   - Even if the device is obtained by others, the database content cannot be read directly\n\n2. Sensitive Configuration Encryption\n   - Webhook URLs (including WeCom, DingTalk, Feishu authentication keys) are encrypted using AndroidKeyStore\n   - Never stored in plain text in SharedPreferences\n\n3. Network Transport Security\n   - HTTPS is enforced site-wide; plain HTTP transmission is prohibited\n   - SSL Certificate Pinning infrastructure has been deployed\n   - Admin backend Tokens are only passed via HTTP Headers, never in URLs\n\n4. Other Security Measures\n   - Admin backend two-step verification (TOTP)\n   - App backup is disabled to prevent notification data leakage via cloud backup\n   - In-app broadcast receivers are hardened to prevent external forged notification data',
    'privacyThirdPartyTitle': 'Third-Party Services',
    'privacyThirdPartyContent':
        'This App uses the following third-party services:\n\nTencent Bugly (Crash Statistics)\n• Provider: Shenzhen Tencent Computer Systems Co., Ltd.\n• Purpose: Collect app crash information for issue diagnosis and fixing\n• Privacy Policy: https://privacy.qq.com/\n• Data Collected: Crash stack traces, device model, system version, app version',
    'privacyPermTitle': 'Permission Notes',
    'privacyPermContent':
        'This App follows the principle of least privilege and only requests necessary permissions:\n\n• Notification Access: Used to listen to system notifications for push functionality\n• Network: Used for Webhook push and version update checks\n• Foreground Service: Keeps the notification listener service alive for timely message delivery\n• Boot Completed: Automatically starts the notification listener service after reboot\n• Battery Optimization Whitelist: Prevents the system from killing the background service\n• SMS/Phone State: Enhanced SMS and call notification type recognition (optional)\n\nRemoved Permissions (v1.5.40 Security Hardening):\n• CHANGE_WIFI_STATE\n• ACCESS_WIFI_STATE\n• CHANGE_NETWORK_STATE',
    'privacyUpdateTitle': 'Policy Updates',
    'privacyUpdateContent':
        'This Privacy Policy may be updated from time to time. Updated policies will be published within the app, and continued use signifies your agreement to the updated policy.',
    'lastUpdate': 'Last updated: July 19, 2026',
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
  String get webhookTemplateHint => _get('webhookTemplateHint');
  String get webhookTemplateInsertVar => _get('webhookTemplateInsertVar');
  String get webhookTemplatePreview => _get('webhookTemplatePreview');
  String get platformWechat => _get('platformWechat');
  String get platformDingtalk => _get('platformDingtalk');
  String get platformFeishu => _get('platformFeishu');
  String get platformGeneric => _get('platformGeneric');
  String get platformWechatDesc => _get('platformWechatDesc');
  String get platformGenericDesc => _get('platformGenericDesc');
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
}
