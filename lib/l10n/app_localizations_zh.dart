// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '通知推送助手';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get add => '添加';

  @override
  String get test => '测试';

  @override
  String get send => '发送';

  @override
  String get close => '关闭';

  @override
  String get ok => '好的';

  @override
  String get later => '稍后';

  @override
  String get goSettings => '去设置';

  @override
  String get loading => '加载中...';

  @override
  String get unknown => '未知';

  @override
  String get notSet => '未设置';

  @override
  String get enabled => '已开启';

  @override
  String get disabled => '未开启';

  @override
  String get on => '开';

  @override
  String get off => '关';

  @override
  String get tabNotification => '通知';

  @override
  String get tabBattery => '电量';

  @override
  String get tabMore => '更多';

  @override
  String get serviceRunning => '通知监听服务正在运行，点击可停止';

  @override
  String get serviceStopped => '通知监听服务未启动，点击可启动';

  @override
  String get running => '运行中';

  @override
  String get stopped => '已停止';

  @override
  String get currentChannels => '当前推送通道';

  @override
  String get noChannels => '未配置推送通道';

  @override
  String get statusOk => '状态正常';

  @override
  String get statusError => '状态异常';

  @override
  String get permSettings => '权限设置';

  @override
  String get permSettingsDesc => '配置通知、电池、后台运行等权限';

  @override
  String get pushHistory => '推送历史';

  @override
  String recordCount(int n) {
    return '共 $n 条记录';
  }

  @override
  String get notificationPermissionTitle => '通知读取权限未开启';

  @override
  String get notificationPermissionMsg =>
      '通知读取权限未开启，软件无法读取设备通知内容。\n\n请先前往「权限设置」开启通知读取权限后再启动服务。';

  @override
  String get appearance => '外观设置';

  @override
  String get pushSettings => '推送设置';

  @override
  String get pushChannels => '推送通道';

  @override
  String get filterRules => '过滤规则';

  @override
  String get webhookChannel => 'Webhook 推送通道';

  @override
  String get webhookNotConfigured => '未配置';

  @override
  String webhookConfigured(int n, int m) {
    return '已配置 $n 个 · 启用 $m 个';
  }

  @override
  String get emailChannel => '邮件转发通道';

  @override
  String get emailChannelDesc => 'SMTP 邮件通知';

  @override
  String get appFilter => '应用筛选';

  @override
  String appFilterBlocked(int n) {
    return '已屏蔽 $n 个应用';
  }

  @override
  String appFilterSelected(int n) {
    return '已选择 $n 个应用';
  }

  @override
  String get appFilterAll => '全部应用都推送';

  @override
  String get keywordFilter => '关键词过滤';

  @override
  String keywordWhitelistBlacklist(int n, int m) {
    return '白名单 $n 条 · 黑名单 $m 条';
  }

  @override
  String get ruleEngine => '规则引擎';

  @override
  String ruleCount(int n) {
    return '$n 条规则';
  }

  @override
  String get ruleEmpty => '点击添加规则';

  @override
  String get device => '设备';

  @override
  String get deviceName => '设备名称';

  @override
  String get widgetSection => '桌面小部件';

  @override
  String get widgetGuide => '推送开关';

  @override
  String get widgetGuideDesc => '桌面一键开启/暂停推送服务';

  @override
  String get widgetGuideIntro => '将「推送开关」小部件添加到桌面后，无需打开应用即可一键开启或暂停推送。';

  @override
  String get widgetGuideStep1 => '1. 长按桌面空白处';

  @override
  String get widgetGuideStep2 => '2. 点击「小部件 / 插件 / Widgets」';

  @override
  String get widgetGuideStep3 => '3. 找到「通知推送助手」，将「推送开关」拖到桌面';

  @override
  String get widgetGuideBrand => '各品牌添加路径';

  @override
  String get widgetBrandXiaomi => '小米 / 红米：桌面长按 → 添加小部件 → 通知推送助手';

  @override
  String get widgetBrandHuawei => '华为 / 荣耀：双指捏合或长按桌面 → 服务卡片 / 小部件 → 通知推送助手';

  @override
  String get widgetBrandOppo => 'OPPO / realme / 一加：桌面长按 → 添加插件 → 通知推送助手';

  @override
  String get widgetBrandVivo => 'vivo / iQOO：桌面长按 → 原子组件 / 小部件 → 通知推送助手';

  @override
  String get widgetBrandSamsung => '三星：桌面长按 → 小组件 → 通知推送助手';

  @override
  String get widgetBrandOthers =>
      '其他品牌（原生 / 谷歌 Pixel / 摩托罗拉 / 索尼等）：桌面长按 → Widgets / 小部件 → 通知推送助手';

  @override
  String get widgetTipsTitle => '使用提示';

  @override
  String get widgetTip1 => '点击小部件即可切换推送状态（推送中 ⇄ 已暂停）';

  @override
  String get widgetTip2 => '暂停后监听继续，仅不发送推送消息';

  @override
  String get widgetTip3 => '部分品牌需允许应用自启动，小部件状态才能实时刷新';

  @override
  String get widgetTip4 => '若桌面找不到小部件，请先打开一次应用或重启桌面';

  @override
  String get widgetPinTitle => '一键添加（推荐）';

  @override
  String get widgetPinDesc => '点击下方按钮，在系统弹窗中确认后即可将 2×2 推送开关小部件添加到桌面，无需手动拖拽。';

  @override
  String get widgetPinAction => '一键添加 2×2 小部件';

  @override
  String get widgetPinWideAction => '添加 4×2 横条小部件';

  @override
  String get widgetPinSuccess => '已发起添加，请在桌面放置小部件';

  @override
  String get widgetPinUnsupported => '当前桌面不支持一键添加，请长按桌面空白处手动添加';

  @override
  String get widgetPinLowApi => '一键添加需要 Android 8.0 及以上，请长按桌面空白处手动添加';

  @override
  String get widgetPin2x2 => '2×2 圆形开关：标题 + 状态圆 + 点击提示';

  @override
  String get widgetPin4x2 => '4×2 横条：标题 + 状态圆 + 当日已推送数量';

  @override
  String get pushStats => '推送统计';

  @override
  String get pushStatsDesc => '查看推送数据统计';

  @override
  String get aboutUpdate => '关于与更新';

  @override
  String get checkUpdate => '检查更新';

  @override
  String get checking => '正在检查...';

  @override
  String get clickToCheck => '点击检查新版本';

  @override
  String get privacyPolicyTitle => '隐私政策';

  @override
  String get privacyPolicyDesc => '数据采集与隐私保护说明';

  @override
  String get crashReport => '崩溃上报';

  @override
  String get crashReportDesc => '默认关闭；开启后崩溃日志将上传至腾讯 Bugly 用于问题分析';

  @override
  String get crashReportOffHint => '已关闭，下次启动后完全生效';

  @override
  String get aboutTitle => '关于';

  @override
  String get aboutDesc => '版本信息、作者介绍';

  @override
  String get followSystem => '跟随系统';

  @override
  String get lightMode => '浅色模式';

  @override
  String get darkMode => '深色模式';

  @override
  String get language => '语言';

  @override
  String get langDefault => '默认';

  @override
  String get langChinese => '中文';

  @override
  String get langEnglish => 'English';

  @override
  String get switchLangTitle => '切换语言';

  @override
  String switchLangMsg(String lang) {
    return '检测到系统语言已变为 $lang，是否同步切换应用语言？';
  }

  @override
  String get switchBtn => '切换';

  @override
  String get notNow => '暂不';

  @override
  String get privacyTitle => '隐私政策';

  @override
  String get privacyWelcome => '欢迎使用通知推送助手！';

  @override
  String get privacyBody =>
      '在使用本应用前，请您仔细阅读我们的隐私政策。\n\n• 所有通知内容仅在设备本地处理，仅按您的配置转发到您指定的 Webhook 或邮件地址\n• 推送历史记录使用 AES-256 加密存储在本地数据库\n• 崩溃上报（腾讯 Bugly）默认关闭，仅在你于设置中主动开启后收集必要的崩溃日志用于修复应用问题，不采集个人身份信息\n• 通道配置（Webhook/邮件）使用 AndroidKeyStore 加密存储\n\n点击\"同意\"即表示您已阅读并接受我们的隐私政策。';

  @override
  String get disagree => '不同意';

  @override
  String get agree => '同意';

  @override
  String get privacyWarnTitle => '注意';

  @override
  String get privacyWarnBody =>
      '您需要同意隐私政策才能使用本软件。\n\n不同意将无法继续使用，软件将会退出。\n\n确定要退出吗？';

  @override
  String get returnAgree => '返回同意';

  @override
  String get confirmExit => '确定退出';

  @override
  String get latestVersion => '当前已是最新版本';

  @override
  String checkUpdateFailed(String e) {
    return '检查更新失败：$e';
  }

  @override
  String get checkUpdateNetworkError => '检查更新失败，请检查网络连接';

  @override
  String get importantUpdate => '重要更新';

  @override
  String get mustUpdate => '必须更新才能继续使用';

  @override
  String get newVersionFound => '发现新版本';

  @override
  String get latestVer => '最新版本：';

  @override
  String get currentVer => '当前版本：';

  @override
  String get fileSize => '文件大小：';

  @override
  String get updateContent => '更新内容';

  @override
  String get updateNow => '立即更新';

  @override
  String get ignore => '忽略';

  @override
  String get update => '更新';

  @override
  String get downloading => '正在下载更新';

  @override
  String downloadFailed(String e) {
    return '下载失败：$e';
  }

  @override
  String get storagePermissionRequired => '需要存储权限';

  @override
  String get storagePermissionMsg => '在线更新需要存储权限来保存 APK 文件，请前往设置开启。';

  @override
  String get noStoragePermission => '未获得存储权限，无法下载更新';

  @override
  String get enable => '去开启';

  @override
  String get confirmExport => '确认导出';

  @override
  String get exportMsg =>
      '通知记录将导出为 JSON 文件，包含通知内容和设备信息。\n\n请选择保存位置，建议在导出后妥善保管或及时删除。\n\n确定要导出吗？';

  @override
  String get exportBtn => '确定导出';

  @override
  String get exportCancelled => '已取消';

  @override
  String get exportError => '导出异常';

  @override
  String historyTitle(int n) {
    return '历史记录 ($n)';
  }

  @override
  String get exportJson => '导出 JSON';

  @override
  String get clearRecords => '清除记录';

  @override
  String get clearToday => '清除今日';

  @override
  String get clearLast10 => '清除最近 10 条';

  @override
  String get clearLast50 => '清除最近 50 条';

  @override
  String get clearAll => '清除全部';

  @override
  String get confirmClear => '确认清除';

  @override
  String clearConfirmMsg(int n) {
    return '确定要清空全部 $n 条记录吗？';
  }

  @override
  String clearedN(int n) {
    return '已清除 $n 条记录';
  }

  @override
  String get searchHint => '搜索标题/内容/应用';

  @override
  String searchResultCount(int n) {
    return '搜索结果 ($n)';
  }

  @override
  String get clearSearchFilter => '清除筛选';

  @override
  String get filterTitle => '筛选条件';

  @override
  String get filterTimeAll => '全部时间';

  @override
  String get filterToday => '今天';

  @override
  String get filterYesterday => '昨天';

  @override
  String get filterLast7Days => '最近 7 天';

  @override
  String get filterLast30Days => '最近 30 天';

  @override
  String get filterCustomRange => '自定义';

  @override
  String get filterDateRange => '日期范围';

  @override
  String get filterAppName => '应用名（含则筛选）';

  @override
  String get filterPackageName => '包名（含则筛选）';

  @override
  String get filterDeliveryStatus => '送达状态';

  @override
  String get deliveryAll => '全部';

  @override
  String get deliverySuccessOnly => '仅成功';

  @override
  String get deliveryFailedOnly => '仅失败';

  @override
  String get filterApply => '应用筛选';

  @override
  String get filterReset => '重置';

  @override
  String get loadMoreHint => '上拉加载更多';

  @override
  String get noRecords => '暂无推送记录';

  @override
  String get noMatchRecords => '没有匹配的记录';

  @override
  String get notificationDetail => '通知详情';

  @override
  String get detailInfo => '详细信息';

  @override
  String get noTitle => '（无标题）';

  @override
  String get emailSettingsTitle => '邮件转发通道';

  @override
  String get noEmailChannels => '暂无邮件通道';

  @override
  String get clickToAdd => '点击下方按钮添加';

  @override
  String get addEmailChannel => '添加邮件通道';

  @override
  String get editEmailChannel => '编辑邮件通道';

  @override
  String get testSend => '测试发送';

  @override
  String get testAndSave => '测试并保存';

  @override
  String get turnOn => '开启';

  @override
  String get turnOff => '停用';

  @override
  String get fieldRequired => '必填';

  @override
  String get fillRequiredFields => '请填写所有必填项';

  @override
  String get channelName => '通道名称';

  @override
  String deleteEmailChannelConfirm(String name) {
    return '确定删除邮件通道「$name」吗？';
  }

  @override
  String get autoSavePath => '自动保存路径';

  @override
  String get autoSavePathDesc => '每日自动归档推送历史 JSON 的保存位置';

  @override
  String get archivePathDefault => '默认（应用专属目录）';

  @override
  String get chooseFolder => '选择自定义文件夹';

  @override
  String get resetToDefault => '恢复默认路径';

  @override
  String get archivePathUpdated => '自动保存路径已更新';

  @override
  String get archivePathReset => '已恢复默认保存路径';

  @override
  String get testPassed => '✅ 验证通过';

  @override
  String get testFailed => '❌ 验证失败';

  @override
  String get testPassedSaved => '测试通过，配置已保存';

  @override
  String verifyFailed(String msg) {
    return '验证失败: $msg';
  }

  @override
  String get testing => '测试中...';

  @override
  String get channelNameHint => '如：QQ邮箱';

  @override
  String get smtpHost => 'SMTP 服务器';

  @override
  String get smtpPort => '端口号';

  @override
  String get smtpAccount => 'SMTP 账号';

  @override
  String get smtpPassword => '密码/授权码';

  @override
  String get fromEmail => '发件人';

  @override
  String get toEmail => '收件人';

  @override
  String get useSSL => 'SSL 加密';

  @override
  String get subjectTemplate => '主题模板（可选）';

  @override
  String get bodyTemplate => '正文模板（可选）';

  @override
  String get presetDefault => '默认';

  @override
  String get presetSimple => '简洁';

  @override
  String get presetDetailed => '详细';

  @override
  String get presetTime => '时间';

  @override
  String get presetCode => '验证码';

  @override
  String get presetDevice => '设备';

  @override
  String get presetStandard => '标准';

  @override
  String get presetComplete => '完整';

  @override
  String get presetMinimal => '极简';

  @override
  String get availableVars =>
      '可用变量：%appName% %title% %content% %subText% %packageName% %deviceName% %time% %type% %date% %datetime%';

  @override
  String get webhookSettingsTitle => 'Webhook 推送通道';

  @override
  String get webhookUrlRequired => '请先输入 Webhook URL';

  @override
  String get channelList => '通道列表';

  @override
  String get addChannel => '添加通道';

  @override
  String get webhookDesc1 => '支持同时配置多个 Webhook 通道，每个通道独立开关';

  @override
  String get webhookDesc2 => '自动识别企业微信、钉钉、飞书等平台格式';

  @override
  String get webhookDesc3 => '新添加的通道默认启用';

  @override
  String channelN(int n) {
    return '通道 $n';
  }

  @override
  String get channelNameOptional => '通道名称（可选，如 企业微信·通知）';

  @override
  String get webhookUrlPlaceholder => 'https://example.com/webhook';

  @override
  String get webhookSecretLabel => '签名密钥（可选）';

  @override
  String get webhookSigned => '已签名';

  @override
  String get webhookTemplateLabel => '推送模板（可选）';

  @override
  String get webhookFormatLabel => '消息格式';

  @override
  String get feishuMarkdownDowngradeHint =>
      '飞书自定义机器人不支持 markdown，将降级为纯文本发送（markdown 符号原样显示）。建议使用 text 格式。';

  @override
  String get webhookTemplateHint => '留空则使用预置模板；支持变量：';

  @override
  String get webhookTemplateInsertVar => '插入变量';

  @override
  String get webhookTemplatePreview => '预览';

  @override
  String get platformWechat => 'WeCom';

  @override
  String get platformDingtalk => 'DingTalk';

  @override
  String get platformFeishu => 'Feishu';

  @override
  String get platformGeneric => '通用 JSON';

  @override
  String get platformWechatDesc => '文本格式推送';

  @override
  String get platformGenericDesc => '自定义 JSON 格式';

  @override
  String get channelTypeLabel => '渠道类型';

  @override
  String get channelTypeAuto => '自动识别';

  @override
  String channelTypeAutoWith(String type) {
    return '自动识别（$type）';
  }

  @override
  String get selectChannelType => '选择推送渠道';

  @override
  String get channelTypeWechat => '企业微信群机器人';

  @override
  String get channelTypeDingtalk => '钉钉群机器人';

  @override
  String get channelTypeFeishu => '飞书群机器人';

  @override
  String get channelTypeTelegram => 'Telegram';

  @override
  String get channelTypeBark => 'Bark';

  @override
  String get channelTypeServerChan => 'Server酱';

  @override
  String get channelTypePushPlus => 'PushPlus';

  @override
  String get channelTypeGeneric => '通用 Webhook';

  @override
  String get signingHintWechat => '企业微信群机器人开启「签名校验」后生成的密钥';

  @override
  String get signingHintDingtalk => '钉钉机器人开启「加签」后生成的密钥（SEC 开头）';

  @override
  String get signingHintFeishu => '飞书自定义机器人开启「签名校验」后的密钥';

  @override
  String get signingHintTelegram => 'Telegram 使用 Bot Token 鉴权，无需签名密钥';

  @override
  String get signingHintBark => 'Bark 使用设备 Key 鉴权，无需签名密钥';

  @override
  String get signingHintServerChan => 'Server酱 使用 SendKey 鉴权，无需签名密钥';

  @override
  String get signingHintPushPlus => 'PushPlus 使用 Token 鉴权，无需签名密钥';

  @override
  String get signingHintGeneric => '自建服务端校验签名用的密钥（通过 X-Signature 头传递）';

  @override
  String get msgFormatDefault => '默认格式';

  @override
  String get msgFormatText => '纯文本';

  @override
  String get urlEmpty => '待输入';

  @override
  String get urlPlaceholder => '请输入 Webhook URL';

  @override
  String get permSettingsTitle => '权限设置';

  @override
  String get essentialPerms => '必要权限';

  @override
  String get notifAccessPerm => '通知访问权限';

  @override
  String get allowNotifications => '允许通知';

  @override
  String get ignoreBatteryOpt => '忽略电池优化';

  @override
  String get vendorBgSettings => '厂商后台设置';

  @override
  String get xiaomiAutoStart => '小米自启动';

  @override
  String get meizuBgRun => '魅族后台运行';

  @override
  String get huaweiProtected => '华为自启动/受保护应用';

  @override
  String get oppoAutoStart => 'OPPO自启动管理';

  @override
  String get vivoBgStart => 'vivo后台启动管理';

  @override
  String get samsungSettings => '三星设备设置';

  @override
  String get nativeAndroid => '原生Android设置';

  @override
  String get optionalPerms => '非必要权限';

  @override
  String get smsPerm => '短信权限';

  @override
  String get smsPermDesc => '用于获取短信发送者号码和内容';

  @override
  String get phonePerm => '电话权限';

  @override
  String get phonePermDesc => '用于获取来电号码和通话状态';

  @override
  String get appListPerm => '应用列表权限';

  @override
  String get appListPermDesc => '非必要权限用于提升特定功能的准确性';

  @override
  String get appListPermTitle => '需要应用列表权限';

  @override
  String get appListPermMsg =>
      '该权限用于获取已安装应用列表，支持按应用过滤通知功能。\n\n点击「允许」后将跳转到系统设置页，请手动开启权限。';

  @override
  String get appListPermExtra => '用于获取已安装应用列表，支持按应用过滤通知功能';

  @override
  String get clickToSettings => '点击前往设置';

  @override
  String get samsungSmartManagerDesc => '请在智能管理器中将本应用加入自启动白名单';

  @override
  String get nativeBatteryOptDesc => '请在系统设置中确认电池优化已关闭';

  @override
  String get exactAlarmTitle => '精确闹钟（准时推送）';

  @override
  String get exactAlarmDesc => '延迟/定时推送到点更准时；Android 12+ 需系统授权';

  @override
  String get exactAlarmGranted => '已授权';

  @override
  String get exactAlarmNeedGrant => '点击授权';

  @override
  String get exactAlarmUnsupported => '需 Android 12+';

  @override
  String get keepAliveGuideTitle => '后台保活引导';

  @override
  String get keepAliveGuideDesc => '部分系统会限制后台服务，可能导致收不到通知。按以下步骤设置可提高稳定性：';

  @override
  String get keepAliveStep1 => '省电策略设为不限制';

  @override
  String get keepAliveStep2 => '允许自启动';

  @override
  String get keepAliveStep3 => '后台运行不受限（任务锁定）';

  @override
  String get keepAliveStep4 => '确认已开启通知使用权';

  @override
  String get notes => '说明';

  @override
  String get allow => '允许';

  @override
  String get reject => '拒绝';

  @override
  String get batteryTitle => '电量';

  @override
  String get addRule => '添加规则';

  @override
  String get charging => '充电中';

  @override
  String get notCharging => '未充电';

  @override
  String get reminderSettings => '提醒设置';

  @override
  String get batteryNotifToggle => '电量通知总开关';

  @override
  String get batteryNotifToggleDesc => '开启后以下提醒才会生效';

  @override
  String get notifRules => '通知规则';

  @override
  String get batteryNotes1 => '低电量提醒仅在非充电状态下触发';

  @override
  String get batteryNotes2 => '电量回升到阈值以上才会重置提醒状态';

  @override
  String get batteryNotes3 => '电量通知随通知监听服务一起运行';

  @override
  String get batteryNotes4 => '点击规则可编辑，左滑或长按可删除';

  @override
  String get closeBatteryOpt => '关闭电池优化';

  @override
  String get batteryOptDesc => '息屏后系统会限制后台运行，可能导致通知监听服务停止';

  @override
  String get ruleStartCharging => '手机接入充电器时推送';

  @override
  String get ruleStopCharging => '手机断开充电器时推送';

  @override
  String ruleAboveThreshold(int n) {
    return '电量达到 $n% 时推送';
  }

  @override
  String ruleBelowThreshold(int n) {
    return '电量低于 $n% 时推送';
  }

  @override
  String ruleEqualThreshold(int n) {
    return '电量等于 $n% 时推送';
  }

  @override
  String get ruleUnknown => '未知规则类型';

  @override
  String get confirmDeleteRule => '确认删除';

  @override
  String confirmDeleteRuleMsg(String title) {
    return '确定要删除规则「$title」吗？';
  }

  @override
  String get editRule => '编辑规则';

  @override
  String get ruleType => '规则类型';

  @override
  String get startCharging => '开始充电';

  @override
  String get stopCharging => '断开充电';

  @override
  String get belowValue => '低于某值';

  @override
  String get aboveValue => '高于某值';

  @override
  String get equalValue => '等于某值';

  @override
  String get threshold => '电量阈值（%）';

  @override
  String get customTitle => '自定义标题（可选）';

  @override
  String get customTitleHint => '留空则使用默认标题';

  @override
  String get batteryReminder => '电量提醒';

  @override
  String get deleteRule => '删除规则';

  @override
  String get confirmDeleteThisRule => '确定要删除这条通知规则吗？';

  @override
  String get setDeviceName => '设置设备名称';

  @override
  String get deviceNameLabel => '设备名称';

  @override
  String get aboutDialogTitle => '关于';

  @override
  String get author => '作者：幻念团队 fnthinklevi';

  @override
  String get appDesc => '监听通知栏所有通知并推送到 Webhook';

  @override
  String get appFeatures => '支持：微信 / QQ / 短信 / 来电 / 电量提醒';

  @override
  String get ruleListTitle => '规则管理';

  @override
  String get ruleNew => '新规则';

  @override
  String get ruleNoCondition => '无条件';

  @override
  String get ruleNoAction => '无动作';

  @override
  String get ruleListEmpty => '暂无规则';

  @override
  String get ruleAddFirst => '添加第一条规则';

  @override
  String rulePriorityBadge(int n) {
    return '优先级 $n';
  }

  @override
  String get ruleGuideTitle => '规则引擎介绍';

  @override
  String get ruleGuideAdd => '添加规则';

  @override
  String get ruleGuideAddDesc => '点击右上角「+」或右下角浮动按钮创建新规则';

  @override
  String get ruleGuideCondition => '设置条件';

  @override
  String get ruleGuideConditionDesc => '配置触发规则的条件（IF），如应用包名、关键词、时间等';

  @override
  String get ruleGuideAction => '执行动作';

  @override
  String get ruleGuideActionDesc => '设置满足条件后执行的动作（THEN），如推送通知、静默忽略等';

  @override
  String get ruleGuideEnable => '启用规则';

  @override
  String get ruleGuideEnableDesc => '通过开关控制规则是否生效，未启用的规则不会执行';

  @override
  String get ruleGuideTip => '提示：规则按优先级顺序执行，匹配第一条规则后即停止。可通过编辑规则调整优先级。';

  @override
  String get ruleGuideGotIt => '知道了';

  @override
  String get ruleHelp => '使用帮助';

  @override
  String get ruleAddTooltip => '添加规则';

  @override
  String ruleDeleteMsg(String name) {
    return '确定要删除规则「$name」吗？';
  }

  @override
  String get ruleEditTitle => '编辑规则';

  @override
  String get ruleName => '规则名称';

  @override
  String get ruleNameHint => '输入规则名称';

  @override
  String get ruleDescription => '规则描述';

  @override
  String get ruleDescriptionHint => '可选，描述规则用途';

  @override
  String get ruleConditions => '条件（IF）';

  @override
  String get ruleActions => '动作（THEN）';

  @override
  String get ruleAddCondition => '添加条件';

  @override
  String get ruleAddAction => '添加动作';

  @override
  String get rulePriority => '规则优先级';

  @override
  String get rulePriorityNote => '优先级越高，规则越先执行。相同优先级按添加顺序执行。';

  @override
  String get rulePDefault => '默认 (0)';

  @override
  String get rulePLow => '低 (50)';

  @override
  String get rulePMedium => '中 (100)';

  @override
  String get rulePHigh => '高 (200)';

  @override
  String get rulePHighest => '最高 (500)';

  @override
  String get rulePriorityCustom => '自定义…';

  @override
  String get rulePriorityCustomTitle => '自定义优先级';

  @override
  String get rulePriorityCustomHint => '0-500 的整数';

  @override
  String get rulePriorityCustomInvalid => '请输入 0-500 的整数';

  @override
  String get ruleAppScope => '适用应用';

  @override
  String get ruleAppScopeAll => '全部应用';

  @override
  String ruleAppScopeExcluded(int n) {
    return '已排除 $n 个应用';
  }

  @override
  String get ruleAppScopeDesc => '被排除的应用不再适用本规则';

  @override
  String get ruleAppPickTitle => '选择适用应用';

  @override
  String get ruleAppPinnedSms => '系统短信';

  @override
  String get ruleAppPinnedCall => '电话';

  @override
  String get ruleAppPinnedNote => '系统短信与电话由独立链路转发，不经过规则引擎，此处列出仅便于统一管理。';

  @override
  String get ruleAppNoPermission => '无应用列表读取权限，无法加载应用列表';

  @override
  String get ruleMergeWindowRow => '聚合等待时长';

  @override
  String ruleMergeWindowSummary(int n) {
    return '等待 $n 秒';
  }

  @override
  String get ruleMergeWindowPresets => '常用时长（点击填入）：';

  @override
  String get ruleMergeWindowInvalid => '请输入 5-86400 的整数（最小 5 秒）';

  @override
  String get historyActionBlockApp => '屏蔽该应用的通知';

  @override
  String get historyActionBlockAppShort => '屏蔽该应用';

  @override
  String get historyActionBlockAppDescAllow => '白名单模式：将该应用移出推送白名单';

  @override
  String get historyActionBlockAppDescBlock => '黑名单模式：将该应用加入屏蔽名单';

  @override
  String get historyActionBlockAppDescAlreadyExcluded => '该应用已不在推送范围，无需操作';

  @override
  String get historyActionBlockAppDescAlreadyBlocked => '该应用已在屏蔽名单中';

  @override
  String get historyActionBlockContent => '屏蔽含本通知内容的通知';

  @override
  String get historyActionBlockContentShort => '屏蔽内容';

  @override
  String get historyBlockContentDialogTitle => '新增黑名单关键词';

  @override
  String get historyBlockContentEditHint => '可编辑后保存，含此文本的通知将被屏蔽';

  @override
  String get historyBlockContentSuccess => '已加入黑名单关键词';

  @override
  String get historyBlockContentDuplicate => '该关键词已在黑名单中';

  @override
  String historyBlockAppRemoved(String app) {
    return '已将「$app」移出推送白名单';
  }

  @override
  String historyBlockAppAdded(String app) {
    return '已将「$app」加入屏蔽名单';
  }

  @override
  String historyBlockAppAlreadyExcluded(String app) {
    return '「$app」已不在推送范围内';
  }

  @override
  String historyBlockAppAlreadyBlocked(String app) {
    return '「$app」已在屏蔽名单中';
  }

  @override
  String get historyBlockNoAppName => '该记录缺少应用信息，无法屏蔽';

  @override
  String get historyBlockNoText => '该记录无文本内容，无法屏蔽';

  @override
  String get ruleSelect => '请选择';

  @override
  String get ruleEditCondition => '编辑条件';

  @override
  String get ruleAddConditionTitle => '添加条件';

  @override
  String get ruleConditionType => '条件类型';

  @override
  String get ruleConditionValue => '条件值';

  @override
  String get ruleLogic => '逻辑运算符';

  @override
  String get ruleEditAction => '编辑动作';

  @override
  String get ruleAddActionTitle => '添加动作';

  @override
  String get ruleActionType => '动作类型';

  @override
  String get ruleDelayTitle => '延迟推送参数（至少填写一项）';

  @override
  String get ruleDelaySeconds => '延迟秒数';

  @override
  String get ruleDelaySecondsHint => '如 60 = 延迟 1 分钟';

  @override
  String get ruleScheduleTime => '定时时间';

  @override
  String get ruleScheduleTimeHint => '如 22:00（当日到点推送）';

  @override
  String get ruleBasicInfo => '基本信息';

  @override
  String get ruleEnableRule => '启用规则';

  @override
  String get ruleEmptyConditions => '暂无条件，点击添加';

  @override
  String get ruleEmptyActions => '暂无动作，点击添加';

  @override
  String ruleDelayMinute(int n) {
    return '延迟 $n 分钟';
  }

  @override
  String ruleDelaySecond(int n) {
    return '延迟 $n 秒';
  }

  @override
  String ruleScheduleAt(String t) {
    return '定时 $t';
  }

  @override
  String get condPackage => '应用包名';

  @override
  String get condTitleContains => '标题包含';

  @override
  String get condTitleNotContains => '标题不包含';

  @override
  String get condContentContains => '内容包含';

  @override
  String get condContentNotContains => '内容不包含';

  @override
  String get condPriority => '通知优先级';

  @override
  String get mergeWindowSeconds => '合并窗口（秒）';

  @override
  String get mergeWindowHint => '默认 60，同应用通知在此窗口内合并为一条推送';

  @override
  String get condTimeRange => '时间范围';

  @override
  String get condRegex => '正则表达式';

  @override
  String get hintPackage => '例如: com.example.app';

  @override
  String get hintKeyword => '输入关键词';

  @override
  String get hintPriority => '高/中/低';

  @override
  String get hintTimeRange => '09:00-18:00';

  @override
  String get hintRegex => '正则表达式';

  @override
  String get actionPush => '推送通知';

  @override
  String get actionSilent => '静默忽略';

  @override
  String get actionDelay => '延迟推送';

  @override
  String get actionMerge => '合并推送';

  @override
  String get actionRecord => '仅记录';

  @override
  String get actionPushDesc => '将通知推送到指定渠道';

  @override
  String get actionSilentDesc => '不推送，静默处理';

  @override
  String get actionDelayDesc => '延迟一段时间后推送';

  @override
  String get actionMergeDesc => '合并同应用多条通知';

  @override
  String get actionRecordDesc => '仅记录到历史，不推送';

  @override
  String get logicAnd => '且';

  @override
  String get logicOr => '或';

  @override
  String get keywordTitle => '关键词过滤';

  @override
  String get keywordWhitelist => '白名单';

  @override
  String get keywordBlacklist => '黑名单';

  @override
  String get keywordWhitelistHint => '输入白名单关键词';

  @override
  String get keywordBlacklistHint => '输入黑名单关键词';

  @override
  String get keywordWhitelistDesc => '白名单：通知内容包含任一关键词时，即使应用未被选中也会推送（优先级最高）';

  @override
  String get keywordBlacklistDesc => '黑名单：通知内容包含任一关键词时，即使应用被选中也不会推送';

  @override
  String get keywordWhitelistEmpty => '暂无白名单关键词';

  @override
  String get keywordBlacklistEmpty => '暂无黑名单关键词';

  @override
  String get initializing => '正在初始化...';

  @override
  String get loadWebhook => '加载 Webhook 配置...';

  @override
  String get loadBattery => '加载电池配置...';

  @override
  String get loadRecords => '加载通知记录...';

  @override
  String get loadFilter => '加载过滤配置...';

  @override
  String get initUpdate => '初始化更新服务...';

  @override
  String get initRetry => '初始化重试服务...';

  @override
  String get initComplete => '初始化完成';

  @override
  String get initFailed => '应用启动失败';

  @override
  String get initFailedMsg => '依赖注入初始化失败，请重启应用';

  @override
  String get retry => '重试';

  @override
  String pageInitFailed(String e) {
    return '页面初始化失败: $e';
  }

  @override
  String get webhookSaved => 'Webhook 配置已保存';

  @override
  String get emailSaved => '邮件通道配置已保存';

  @override
  String get unknownError => '未知错误';

  @override
  String testFailedMsg(String e) {
    return '测试失败: $e';
  }

  @override
  String get unknownResult => '未知结果';

  @override
  String get iconDefault => '默认图标';

  @override
  String get iconBlue => '蓝色';

  @override
  String get iconCyan => '天蓝';

  @override
  String get iconTeal => '青色';

  @override
  String get iconMint => '薄荷';

  @override
  String get iconGreen => '绿色';

  @override
  String get iconYellow => '黄色';

  @override
  String get iconOrange => '橙色';

  @override
  String get iconRed => '红色';

  @override
  String get iconPink => '粉色';

  @override
  String get iconRose => '玫红';

  @override
  String get iconPurple => '紫色';

  @override
  String get iconIndigo => '靛蓝';

  @override
  String get iconBrown => '棕色';

  @override
  String get iconGray => '灰色';

  @override
  String get iconGraphite => '深灰';

  @override
  String get iconBlack => '墨黑';

  @override
  String get appIconTitle => '应用图标';

  @override
  String currentIcon(String label) {
    return '当前：$label';
  }

  @override
  String iconSwitched(String label) {
    return '已切换至「$label」，桌面稍后刷新';
  }

  @override
  String get iconSwitchFailed => '切换失败';

  @override
  String get done => '完成';

  @override
  String get refreshAppList => '更新软件列表';

  @override
  String get appFilterBlockModeInfo => '当前模式：不通知应用 — 未选择时全部应用都推送通知';

  @override
  String appFilterBlockModeSelected(int n) {
    return '已选择 $n 个应用，这些应用的通知不会被推送';
  }

  @override
  String get appFilterAllowModeInfo => '当前模式：通知应用 — 未选择时全部应用都推送通知（默认）';

  @override
  String appFilterAllowModeSelected(int n) {
    return '已选择 $n 个应用，仅这些应用的通知会被推送';
  }

  @override
  String get filterNotifyApps => '通知应用';

  @override
  String get filterBlockApps => '不通知应用';

  @override
  String get appListPermDesc2 => '为了能够筛选需要推送通知的应用，请授予应用读取已安装应用列表的权限。';

  @override
  String get goEnablePermission => '前往开启权限';

  @override
  String get refreshRetry => '刷新重试';

  @override
  String get searchAppHint => '搜索应用名称或包名';

  @override
  String get showSystemApps => '显示系统应用';

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '清空';

  @override
  String get invertSelection => '反选';

  @override
  String selectedCount(int n) {
    return '已选 $n';
  }

  @override
  String unselectedCount(int n) {
    return '未选 $n';
  }

  @override
  String get noAppsFound => '没有找到应用';

  @override
  String refreshFailed(String e) {
    return '刷新失败：$e';
  }

  @override
  String get appFilterNoPermPrompt =>
      '当前无应用列表读取权限，无法进行应用筛选。\n若需进行应用筛选，请点击授予应用列表读取权限';

  @override
  String get smsMonitor => '短信监听';

  @override
  String get smsMonitorDesc => '控制是否监听收到的短信并推送';

  @override
  String get smsMonitorSettings => '短信监听设置';

  @override
  String get smsMonitorTotalDesc => '关闭后将不再监听、推送任何短信';

  @override
  String get simFilterTitle => '监听卡';

  @override
  String get simFilterDesc => '同时作用于短信和电话';

  @override
  String get simFilterSingleSim => '当前设备仅检测到一张SIM卡，无需选择';

  @override
  String get simFilterAll => '全部';

  @override
  String get simFilterSim1 => '仅卡1';

  @override
  String get simFilterSim2 => '仅卡2';

  @override
  String get simFilterRemindTitle => '部分短信可能无法识别所属卡';

  @override
  String get simFilterRemindMsg =>
      '由于小米等系统的限制，部分短信无法识别所属卡（通知栏兜底链路）。这些短信不受该设置影响，将照常推送。';

  @override
  String get codeMonitor => '监听验证码';

  @override
  String get codeMonitorDesc => '关闭后，包含验证码的短信将不会被推送';

  @override
  String get widgetBrandCurrentDevice => '当前设备';

  @override
  String get statsToday => '今日推送';

  @override
  String get statsTotal => '总推送数';

  @override
  String get statsApps => '应用数';

  @override
  String get statsTrend => '近7天推送趋势';

  @override
  String get statsNoData => '暂无数据';

  @override
  String get statsRank => '应用推送排行';

  @override
  String get deliverySuccess => '推送成功';

  @override
  String get deliveryFailed => '推送失败';

  @override
  String get deliveryPending => '发送中';

  @override
  String get pushPausedByUser => '已暂停';

  @override
  String get deliveryIntercepted => '已拦截';

  @override
  String get pushNow => '现在推送';

  @override
  String get privacyOverviewTitle => '隐私政策概述';

  @override
  String get privacyOverviewContent =>
      '通知推送助手（以下简称\"本应用\"）由幻念团队开发并运营。本应用高度重视您的个人信息与隐私保护，在您使用本应用前，请仔细阅读本隐私政策，了解我们如何收集、使用、存储和保护您的信息。\n\n本政策适用于本应用提供的所有服务。当您安装并使用本应用时，即表示您已阅读、理解并同意本政策的全部内容。';

  @override
  String get privacyInfoTitle => '我们收集的信息';

  @override
  String get privacyInfoContent =>
      '本应用遵循\"最小必要\"原则，仅收集实现核心功能所必需的信息：\n\n1. 通知内容（本地处理）\n   - 应用通过系统通知监听服务读取通知内容\n   - 所有通知内容仅在设备本地完成规则匹配、关键词过滤，并按您自行配置的 Webhook 或邮件地址转发\n   - 通知内容不会上传至除您指定目标以外的任何服务器\n\n2. 崩溃统计信息（腾讯 Bugly，默认关闭）\n   - 仅当你在「更多 → 崩溃上报」主动开启后，才收集应用崩溃时的堆栈信息、设备型号、系统版本、应用版本号、CPU 架构\n   - 未开启时 SDK 不初始化、数据不出网；开启后仅用于定位和修复崩溃问题，提升应用稳定性\n\n3. 推送统计与历史记录（本地存储）\n   - 通知记录、推送状态、每日统计等数据使用 AES-256 加密存储在本地数据库\n   - 这些数据仅保存在您的设备上，不会对外发送\n\n4. 延迟推送队列（本地存储）\n   - 规则引擎产生的延迟/定时推送任务持久化保存在本机，重启后不丢失\n\n5. 电池状态（本地监控）\n   - 电量及充电状态监控仅在本机采集，用于首页展示，不对外发送\n\n6. 已安装应用列表（本地使用）\n   - 用于规则引擎条件配置与应用过滤，仅在本机使用';

  @override
  String get privacyNoCollectTitle => '我们不收集的信息';

  @override
  String get privacyNoCollectContent =>
      '本应用不会收集以下个人隐私信息：\n\n• 通讯录、短信内容（除非您主动授权用于短信通知识别）\n• 位置信息\n• 通话记录\n• 相册、文件内容\n• 麦克风、摄像头数据\n• 个人身份信息（姓名、身份证号、手机号等）\n\n当您不同意授权时，本应用的相关可选功能将不可用，但核心通知转发功能不受影响。';

  @override
  String get privacyShareTitle => '信息共享与披露';

  @override
  String get privacyShareContent =>
      '本应用不会出售、出租或交易您的个人信息。仅在以下情形中共享必要的信息：\n\n1. 您主动配置的转发目标\n   - 当您配置 Webhook（企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus）或 SMTP 邮件后，您选择转发的通知内容将发送至这些您指定的第三方平台\n   - 发送前需要您明确配置目标地址，未配置不会发生任何数据外发\n\n2. 第三方崩溃统计服务（腾讯 Bugly，默认关闭）\n   - 仅在你主动开启崩溃上报后，才共享崩溃堆栈及设备基础环境信息，用于修复问题\n\n3. 法律法规要求\n   - 依据法律、法规或有权机关的要求披露相关信息';

  @override
  String get privacyStorageTitle => '数据存储与安全';

  @override
  String get privacyStorageContent =>
      '本应用采用多层安全机制保护您的数据：\n\n1. 本地数据库加密\n   - 通知历史记录、推送统计使用 AES-256 加密存储（sqflite_sqlcipher）\n   - 加密密钥保存在 Android 系统密钥库（AndroidKeyStore）中\n   - 即使设备被他人获取，也无法直接读取数据库内容\n\n2. 敏感配置加密\n   - Webhook URL、SMTP 账号、TOTP 密钥等敏感配置使用 AndroidKeyStore / AES-256-GCM 加密存储\n   - 不会以明文形式保存在 SharedPreferences 中\n\n3. 网络传输安全\n   - 全站强制 HTTPS，禁止明文 HTTP 传输\n   - 管理后台 Token 仅通过 HTTP Header 传递，不出现在 URL 中\n\n4. 其他安全措施\n   - 管理后台二步验证（TOTP）\n   - 应用备份已禁用（allowBackup=false），防止数据通过云备份泄露\n   - 应用内广播接收器已加固，防止外部伪造通知数据\n\n5. 数据保留\n   - 您可随时在应用内清除全部或部分推送历史记录\n   - 卸载应用将清除全部本地数据';

  @override
  String get privacyThirdPartyTitle => '第三方服务';

  @override
  String get privacyThirdPartyContent =>
      '本应用使用以下第三方服务：\n\n腾讯 Bugly（崩溃统计，默认关闭）\n• 服务商：深圳市腾讯计算机系统有限公司\n• 用途：需你在「更多 → 崩溃上报」主动开启后才收集应用崩溃信息，帮助定位和修复问题；关闭后下次启动不再初始化\n• 隐私政策：https://privacy.qq.com/\n• 采集数据：崩溃堆栈、设备型号、系统版本、应用版本、CPU 架构\n\n用户主动配置的推送目标（非 SDK）\n• 企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus、SMTP 邮件服务器\n• 本应用仅向您自行配置的地址发送您选择转发的通知内容，不对第三方平台的数据处理行为负责\n• 涉及上述平台的隐私政策，请查阅对应平台官方文档';

  @override
  String get privacyPermTitle => '权限说明';

  @override
  String get privacyPermContent =>
      '本应用遵循最小权限原则，以下为完整权限清单及用途说明：\n\n核心权限（必需）：\n• 通知使用权（Notification Listener）：读取通知内容，实现转发与规则引擎功能\n• 网络访问（INTERNET）：Webhook/邮件推送与版本更新检查\n• 前台服务（FOREGROUND_SERVICE 等）：保持通知监听服务常驻，确保消息及时推送\n• 开机自启动（RECEIVE_BOOT_COMPLETED）：设备重启后自动恢复通知监听服务\n• 通知发送（POST_NOTIFICATIONS）：发送本地通知提示\n• 唤醒锁（WAKE_LOCK）：延迟/定时推送到点唤醒设备\n\n辅助权限（可选）：\n• 电量优化白名单（REQUEST_IGNORE_BATTERY_OPTIMIZATIONS）：避免系统限制后台服务\n• 短信（RECEIVE_SMS/READ_SMS）：可选，用于短信通知识别与转发\n• 电话状态（READ_PHONE_STATE）：可选，用于来电通知识别\n• 存储（READ/WRITE_EXTERNAL_STORAGE）：导出推送历史 JSON、保存更新 APK\n• 安装未知应用（REQUEST_INSTALL_PACKAGES）：应用内在线更新时安装 APK\n• 查询已安装应用（QUERY_ALL_PACKAGES）：规则引擎条件配置与应用过滤\n• 振动（VIBRATE）：推送提示振动\n• 网络状态（ACCESS_NETWORK_STATE）：检测网络连接状态\n\n以上辅助权限均在您主动授权后使用，可随时在系统设置中关闭。';

  @override
  String get privacyChildTitle => '儿童隐私';

  @override
  String get privacyChildContent =>
      '本应用面向一般用户，不针对 14 周岁以下儿童设计，也不会故意收集儿童的个人信息。若您是未成年人，请在监护人陪同下阅读本政策，并在监护人同意后使用本应用。';

  @override
  String get privacyRightsTitle => '您的权利';

  @override
  String get privacyRightsContent =>
      '您对本应用所处理的本地数据享有以下权利：\n\n• 访问权：在应用内查看推送历史记录与统计信息\n• 删除权：随时清除全部或部分推送历史记录，卸载应用将删除全部本地数据\n• 撤回同意权：可在系统设置中关闭任何已授权的权限\n• 知情权：本政策将随应用功能变化及时更新并在应用内公示';

  @override
  String get privacyUpdateTitle => '政策更新';

  @override
  String get privacyUpdateContent =>
      '本隐私政策可能会不定期更新。当政策发生变更时，我们将在应用内发布更新后的政策，并更新页面底部的\"最后更新\"日期。您继续使用本应用即表示您同意更新后的政策。';

  @override
  String get privacyContactTitle => '联系我们';

  @override
  String get privacyContactContent =>
      '如果您对本隐私政策或数据处理有任何疑问、意见或建议，可通过以下方式联系我们：\n\n• 在应用内「更多」页查看最新版本与更新说明\n• 通过 GitHub 仓库提交 Issue：https://github.com/fnthinklevi/noticeTransmit\n\n我们将在收到您的反馈后尽快予以回复。';

  @override
  String get lastUpdate => '最后更新：2026年8月15日';

  @override
  String get deliveryLogTitle => '送达记录';

  @override
  String get deliveryLogEmpty => '暂无送达日志（可能已过 30 天保留期，或该通知早于送达日志功能启用）';

  @override
  String get backupRestoreTitle => '备份与恢复';

  @override
  String get backupSectionTitle => '备份配置';

  @override
  String get backupSectionDesc =>
      '把你的所有设置打包成一个文件，换手机或重装后可以一键恢复。\n\n包含：Webhook 和邮件通道（含密钥）、通知规则、短信监听开关、应用筛选和黑白名单关键词。\n不含：已经推送过的通知历史。\n\n文件有密码保护，恢复时需要输入同一个密码，请务必记住。';

  @override
  String get restoreSectionTitle => '恢复配置';

  @override
  String get restoreSectionDesc =>
      '选择 .nbackup 备份文件并输入口令恢复。检测到现有配置时，可选择覆盖或仅导入空缺项。';

  @override
  String get backupCreate => '生成备份文件';

  @override
  String get restorePick => '选择备份文件恢复';

  @override
  String get backupPasswordTitle => '设置备份口令';

  @override
  String get backupPasswordHint => '口令（至少 8 位；忘记将无法恢复）';

  @override
  String get restorePasswordTitle => '输入备份口令';

  @override
  String get backupTooShort => '口令至少 8 位';

  @override
  String get backupOk => '备份已生成并保存';

  @override
  String get backupCancelled => '已取消';

  @override
  String get backupFailed => '备份失败：';

  @override
  String get restoreWrongPassword => '口令错误或文件已损坏';

  @override
  String get restoreInvalidFile => '不是有效的备份文件';

  @override
  String get restoreConfirmTitle => '检测到现有配置';

  @override
  String get restoreConflictMsg => '当前已有部分配置。覆盖将替换对应类别的全部内容；仅导入空缺项则保留现有配置不动。';

  @override
  String get restoreOverwriteAll => '覆盖全部';

  @override
  String get restoreFillGaps => '仅导入空缺项';

  @override
  String get restoreDoneReTest => '恢复完成。含凭据的通道（Webhook/邮件）请重新「测试」验证。';

  @override
  String get restoreFailed => '恢复失败：';

  @override
  String get backupRestoreSubtitle => '加密备份通道、规则与设置，支持换机恢复';

  @override
  String get developerDiagEnabled => '开发者诊断已开启（logcat 输出规则/聚合链路日志）';

  @override
  String get developerDiagDisabled => '开发者诊断已关闭';

  @override
  String get ruleTesterTitle => '规则测试器';

  @override
  String get ruleTesterTooltip => '规则测试器（模拟通知查看命中链路）';

  @override
  String get testerHint => '输入模拟通知，实时查看完整命中链路（过滤 → 规则 → 动作，与原生引擎逐条对齐）';

  @override
  String get testerInputSection => '模拟通知';

  @override
  String get testerAppPackage => '应用包名';

  @override
  String get testerPickApp => '选择应用';

  @override
  String get testerTitleField => '通知标题';

  @override
  String get testerContentField => '通知内容';

  @override
  String get testerPriorityLabel => '通知优先级';

  @override
  String get testerPriorityHigh => '高';

  @override
  String get testerPriorityMid => '中';

  @override
  String get testerPriorityLow => '低';

  @override
  String get testerStageFilter => '① 过滤链路';

  @override
  String get testerStageRules => '② 规则匹配';

  @override
  String get testerStageAction => '③ 最终动作';

  @override
  String get testerAllowed => '放行';

  @override
  String get testerBlocked => '拦截';

  @override
  String get testerSrcAppFilter => '应用过滤拦截（当前模式的应用选择列表未包含/已包含该应用）';

  @override
  String get testerSrcDefault => '默认放行（未命中黑/白名单关键词与应用过滤）';

  @override
  String get testerNoRules => '未命中任何规则 → 默认立即推送';

  @override
  String get testerRuleHit => '命中';

  @override
  String get testerRuleMissed => '未命中';

  @override
  String get testerRuleDisabled => '已禁用';

  @override
  String get testerRuleExcluded => '不适用（该应用被排除）';

  @override
  String get testerActionPush => '立即推送';

  @override
  String get testerActionSilent => '静默忽略';

  @override
  String get testerActionRecord => '仅记录（不推送）';

  @override
  String get testerFilteredNote => '该通知会被过滤掉，不会进入规则引擎与推送链路';

  @override
  String testerSrcBlacklist(String kw) {
    return '黑名单关键词命中：$kw';
  }

  @override
  String testerSrcWhitelist(String kw) {
    return '白名单关键词命中：$kw';
  }

  @override
  String testerActionDelay(String when) {
    return '延迟推送（$when）';
  }

  @override
  String testerActionMerge(int n) {
    return '合并推送（窗口 $n 秒）';
  }
}
