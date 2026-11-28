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
  String get duplicate => '复制';

  @override
  String copyOfName(String name) {
    return '$name 副本';
  }

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
  String get goSettings => '前往设置';

  @override
  String get unknown => '未知';

  @override
  String get notSet => '未设置';

  @override
  String get enabled => '已开启';

  @override
  String get disabled => '未开启';

  @override
  String get tabHome => '首页';

  @override
  String get tabNotificationEngine => '通知引擎';

  @override
  String get tabMore => '更多';

  @override
  String get notificationEngineTitle => '通知引擎';

  @override
  String get notificationEngineShort =>
      '电量、温度等设备自身状态达到条件时提醒；是否转发在「更多 → 筛选与规则」中配置。';

  @override
  String get notificationEngineScopeTitle => '本页的职责范围';

  @override
  String get notificationEngineDesc =>
      '设备自身状态达到条件时提醒：电量、温度。已到达的通知是否转发，在「更多 → 筛选与规则」中配置。';

  @override
  String get engineBatteryEntry => '电量告警';

  @override
  String get engineTemperatureEntry => '温度告警';

  @override
  String get serviceRunning => '通知监听服务正在运行，点击可停止服务';

  @override
  String get serviceStopped => '通知监听服务未启动，点击可启动服务';

  @override
  String get serviceStoppedCallSmsOnly => '通知转发已停止，仅转发电话与短信';

  @override
  String get callSmsForwarding => '仅转发电话与短信';

  @override
  String get callSmsForwardingDesc => '通知监听关闭时仍转发来电与短信';

  @override
  String get callSmsOnlyShort => '仅电话短信';

  @override
  String get pushPausedShort => '已暂停';

  @override
  String get servicePausedWhileListening => '当前仍读取设备通知，但推送已暂停；点击可恢复推送';

  @override
  String get running => '运行中';

  @override
  String get stopped => '已停止';

  @override
  String get currentChannels => '当前推送通道';

  @override
  String homeOnlyPrimaryShown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条',
      one: '1 条',
    );
    return '仅显示主通道，另有 $_temp0在「通道状态」里';
  }

  @override
  String homeNoPrimaryChannel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条',
      one: '1 条',
    );
    return '未设主通道（另有 $_temp0启用，见「通道状态」）';
  }

  @override
  String get noChannels => '未配置推送通道';

  @override
  String get lockscreenDiagTitle => '锁屏后推送失败？';

  @override
  String get lockscreenDiagExemptOk => '电池优化白名单：已豁免（深睡下网络可用）';

  @override
  String get lockscreenDiagExemptMissing => '电池优化白名单：未豁免';

  @override
  String get lockscreenDiagGoSettings => '去设置';

  @override
  String lockscreenDiagFailCount(int n) {
    return '近 24 小时推送失败：$n 次';
  }

  @override
  String lockscreenDiagFailCountWithTime(
    int n,
    String month,
    String day,
    String hour,
    String minute,
  ) {
    return '近 24 小时推送失败：$n 次（最近一次 $month-$day $hour:$minute）';
  }

  @override
  String get lockscreenDiagFailNone => '近 24 小时推送失败：无';

  @override
  String get lockscreenDiagExplain =>
      '灭屏静置且未充电时，Android 会进入 Doze 深睡并暂停应用网络（官方文档原文：Suspends network access）；已加入电池优化白名单的应用在深睡下可继续使用网络并持有唤醒锁。锁屏期间失败的推送已自动转入重试队列，解锁或联网后会自动补发。';

  @override
  String get statusOk => '状态正常';

  @override
  String get statusError => '状态异常';

  @override
  String get statusUnknown => '状态未知';

  @override
  String get channelStatusTitle => '通道状态';

  @override
  String get channelStatusShort => '此处列出所有已启用通道，以及各通道最近一次探测的结果与地址。';

  @override
  String get channelStatusGuide =>
      '此处列出所有已启用通道，以及各通道最近一次探测的结果与地址。点击任意条目可直接进入其配置页。';

  @override
  String get channelStatusNeverProbed => '从未探测';

  @override
  String channelFailureLastLine(String ago, String kind, int count) {
    return '最近一次失败：$ago · $kind · 连续 $count 次';
  }

  @override
  String get channelFailureKindNetwork => '网络没连上';

  @override
  String get channelFailureKindHttp => '服务器返回错误';

  @override
  String get channelFailureKindRateLimited => '平台限流';

  @override
  String get channelFailureKindBusiness => '平台业务拒绝';

  @override
  String get channelFailureKindInterrupted => '本机中断';

  @override
  String get channelFailureKindUnknown => '没对上号';

  @override
  String get channelFailureHelpTitle => '如何解读最近一次失败';

  @override
  String get channelFailureHelpBody =>
      '此行仅为取证记录，不代表当前判定：即使通道后来恢复，该记录仍会保留。\n\n网络未连通 —— 请求未到达对端（断网、DNS 解析失败或连接超时）。\n服务器返回错误 —— 对端返回 4xx 或 5xx，具体状态码见送达记录。\n平台限流 —— 对端要求降低发送频率（429），系统将自动等待后重试。\n平台业务拒绝 —— HTTP 连接正常，但平台判定内容不合规（errcode 非 0），重试无效。\n本机中断 —— 消息尚未发出即被本机终止（推送已暂停或引擎未运行）。\n无法归类 —— 存在 HTTP 状态码，但为 2xx 或 3xx，且无业务拒绝迹象；系统不作推测。\n\n连续 N 次 —— 截至本次失败，向前连续失败的条数；中间出现一次成功即重新计数。';

  @override
  String get channelSelfCheck => '全链路自检';

  @override
  String get channelSelfCheckConfirmTitle => '四个通道族各发送一条测试消息？';

  @override
  String get channelSelfCheckConfirmBody =>
      '将从每个通道族中选取一条通道，实际发送一条最小测试消息；幻念仅执行探针，不投递，不占用额度。自检不写入推送历史，也不改变主备状态。';

  @override
  String get channelSelfCheckRunning => '自检中…';

  @override
  String get channelSelfCheckResultTitle => '全链路自检结果';

  @override
  String get channelSelfCheckOk => '通过';

  @override
  String get channelSelfCheckFailed => '未通过';

  @override
  String channelSelfCheckLine(String family, String channel, String state) {
    return '$family · $channel — $state';
  }

  @override
  String channelSelfCheckLineWithMessage(
    String family,
    String channel,
    String state,
    String message,
  ) {
    return '$family · $channel — $state（$message）';
  }

  @override
  String channelSelfCheckNoChannelLine(String family) {
    return '$family — 此通道族无已启用通道';
  }

  @override
  String get mainBackupSettings => '主备设置';

  @override
  String get mainBackupHint => '主通道全量推送；仅当所有主通道都不可用时，才推给备用通道。同一通知不会被主备各推一次。';

  @override
  String get mainBackupRecommend => '主通道建议不超过 5 条；超出后仍可保存，但通道数量越多，并发发送与失败判定越慢。';

  @override
  String get rolePrimary => '主';

  @override
  String get roleBackup => '备';

  @override
  String get roleNone => '不参与';

  @override
  String get mainBackupExcluded => '标记为「不参与」的通道保留配置但不推送，可随时重新启用。';

  @override
  String get roleUnset => '未设置';

  @override
  String get mainBackupUnsetNotice =>
      '「未设置」是新增通道的初始状态：不会随主通道重复推送，仅在未设置任何主通道时使用。将常用通道设为「主」更为准确。';

  @override
  String get roleGuideTitle => '要不要分一下主备通道';

  @override
  String roleGuideBody(Object n) {
    return '你有 $n 条通道需要确认一下主备角色。全部标在「主」档时，同一条通知会重复推送 $n 次；把不常用的改成「备」，它就只在所有主通道都不可用时才接手。';
  }

  @override
  String get roleGuideAction => '去设置';

  @override
  String get roleGuideLater => '以后再说';

  @override
  String get mainBackupChannelGone => '该通道已不存在，本次设置未保存。';

  @override
  String backupModeBanner(int n) {
    return '当前正通过备用通道推送：主通道连续不可用时会自动降级，连续 $n 次探测成功后自动恢复主通道；也可随时手动切回。';
  }

  @override
  String get backupModeSwitchBack => '切回主通道';

  @override
  String backupModeReturnedAuto(String ago, int n) {
    return '已于 $ago 自动回到主通道（连续 $n 次探测成功）。';
  }

  @override
  String backupModeReturnedManual(String ago) {
    return '已于 $ago 切回主通道。';
  }

  @override
  String get backupAutoSwitchLabel => '主通道不可用时自动切到备用通道';

  @override
  String get backupAutoSwitchOffNote =>
      '关闭后仅发送主通道：即使判定主通道不可用仍会发送，失败自动重试，不会切换至备用通道。';

  @override
  String get permSettings => '权限设置';

  @override
  String get permSettingsDesc => '配置通知、电池、后台运行等权限';

  @override
  String get pushHistory => '历史记录';

  @override
  String recordCount(int n) {
    return '共 $n 条记录';
  }

  @override
  String get appearance => '外观设置';

  @override
  String get pushChannels => '推送通道';

  @override
  String get filterRules => '过滤规则';

  @override
  String get webhookChannel => 'Webhook 推送通道';

  @override
  String get channelNotConfigured => '未配置';

  @override
  String channelConfigured(int n, int m) {
    return '已配置 $n 个 · 启用 $m 个';
  }

  @override
  String get emailChannel => '邮件转发通道';

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
  String get ruleEngine => '规则约束';

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
  String get widgetGuide => '推送开关';

  @override
  String get widgetGuideDesc => '在桌面一键开启或暂停推送服务';

  @override
  String get widgetGuideIntro => '将「推送开关」小部件添加到桌面后，无需打开应用即可一键开启或暂停推送。';

  @override
  String get widgetGuideStep1 => '1. 长按桌面空白处';

  @override
  String get widgetGuideStep2 => '2. 点击「小部件 / 插件 / Widgets」';

  @override
  String get widgetGuideStep3 => '3. 找到「通知推送助手」，将「推送开关」拖动至桌面';

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
  String get widgetTip2 => '暂停后监听仍持续，仅停止发送推送消息';

  @override
  String get widgetTip3 => '部分品牌需允许应用自启动，小部件状态才能实时刷新';

  @override
  String get widgetTip4 => '若桌面找不到小部件，请先打开一次应用或重启桌面启动器';

  @override
  String get widgetPinTitle => '一键添加（推荐）';

  @override
  String get widgetPinDesc => '点击下方按钮，在系统弹窗中确认后即可将 2×2 推送开关小部件添加到桌面，无需手动拖拽。';

  @override
  String get widgetPinAction => '一键添加 2×2 小部件';

  @override
  String get widgetPinWideAction => '添加 4×2 横条小部件';

  @override
  String get widgetPinSuccess => '已发起添加请求，请在桌面上放置小部件';

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
      '• 通知内容在设备本地完成规则匹配与过滤，仅按您的配置转发到您指定的 Webhook、邮件地址或幻念设备\n• 幻念推送的消息会经您选定的服务器中转送达对端；不使用幻念推送时，通知内容始终不出本机\n• 推送历史记录使用 AES-256 加密存储在本地数据库\n• 通道配置（Webhook/邮件）使用 AndroidKeyStore 加密存储\n• 崩溃上报（腾讯 Bugly）默认关闭，仅在你于设置中主动开启后收集必要的崩溃日志用于修复应用问题，不采集个人身份信息\n• 拍照回传（默认关闭）：在你于本机打开「拍照」并授权相机后，已配对的设备可让这台拍一张；照片文件保存在本机，图像随回传消息经你选定的服务器中转发给对端，并保存在双方的消息历史里';

  @override
  String get privacyGateLinkAfter => '（同意前即可查看全文）。点击\"同意\"即表示您已阅读并同意该内容。';

  @override
  String get privacyPolicyLink => '《隐私政策》';

  @override
  String get privacyGateLinkBefore => '请阅读 ';

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
  String get fileSize => '文件大小：';

  @override
  String get updateNow => '立即更新';

  @override
  String get ignore => '忽略';

  @override
  String get update => '更新';

  @override
  String get enable => '启用';

  @override
  String get confirmExport => '确认导出';

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
  String get historyGroupMerge => '聚合推送';

  @override
  String get historyGroupDelay => '延迟推送';

  @override
  String get historyGroupBadge => '组';

  @override
  String get historyGroupMembersTitle => '这一组的成员';

  @override
  String get historyGroupMembersEmpty => '这一组没有可显示记录';

  @override
  String get historyGroupMembersNote => '组本身不是一条记录，不能整组重推；要重发请点开成员那条。';

  @override
  String historyGroupTally(int n, int failed) {
    return '扇出 $n · 失败 $failed';
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
  String get deliveryDeliveredOnly => '已送达';

  @override
  String get deliveryNotDeliveredOnly => '没发出去的';

  @override
  String get filterApply => '应用筛选';

  @override
  String get filterReset => '重置';

  @override
  String get loadMoreHint => '上拉加载更多';

  @override
  String get noRecords => '暂无推送记录';

  @override
  String get noMatchRecords => '无匹配记录';

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
  String get clickToAdd => '点击下方按钮以添加通道';

  @override
  String get addEmailChannel => '添加邮件通道';

  @override
  String get editEmailChannel => '编辑邮件通道';

  @override
  String get testAndSave => '测试并保存';

  @override
  String get testOnly => '仅测试';

  @override
  String get turnOn => '开启';

  @override
  String get turnOff => '停用';

  @override
  String get fieldRequired => '必填';

  @override
  String fillRequiredFieldsNamed(String fields) {
    return '保存失败：请填写以下字段：$fields';
  }

  @override
  String get channelName => '通道名称';

  @override
  String get confirmDelete => '确认删除';

  @override
  String deleteChannelConfirm(String name) {
    return '确定删除通道「$name」吗？其凭据与健康记录将一并清除；已推送的历史记录不受影响。';
  }

  @override
  String deleteKeywordConfirm(String keyword) {
    return '确定删除关键词「$keyword」吗？它当前不再参与过滤。';
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
    return '验证失败：$msg';
  }

  @override
  String get testing => '正在测试…';

  @override
  String get channelNameHint => '例如：QQ 邮箱';

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
  String availableVars(String vars) {
    return '可用变量：$vars';
  }

  @override
  String get webhookSettingsTitle => 'Webhook 推送通道';

  @override
  String get webhookUrlRequired => '请先输入 Webhook URL';

  @override
  String get webhookChannelNewTitle => '新增 Webhook 通道';

  @override
  String get noWebhookChannels => '暂无 Webhook 通道';

  @override
  String get channelUntitled => '未命名通道';

  @override
  String get saveFailedPrefix => '保存失败：';

  @override
  String get webhookErrUrlRequired => '保存失败：Webhook 地址不能为空';

  @override
  String get webhookErrUrlInvalid => '保存失败：Webhook 地址必须以 http(s):// 开头';

  @override
  String get webhookErrSecretRequired =>
      '保存失败：该平台必需的凭据（签名密钥或 Token）不能为空，缺了会被服务端直接拒收';

  @override
  String get addChannel => '添加通道';

  @override
  String get webhookDesc1 => '支持同时配置多个 Webhook 通道，每个通道独立开关';

  @override
  String get webhookDesc2 => '自动识别企业微信、钉钉、飞书等平台格式';

  @override
  String get webhookDesc3 => '新添加的通道默认启用';

  @override
  String get webhookChannelNameHint => '可选，如 企业微信·通知';

  @override
  String get webhookUrlLabel => 'Webhook 地址';

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
  String get webhookHttpMethodLabel => '请求方法';

  @override
  String get webhookHeadersLabel => '自定义请求头（可选）';

  @override
  String get webhookHeadersHint => '每行一个，格式为 Name: Value，如 X-Api-Key: xxx';

  @override
  String get feishuMarkdownDowngradeHint =>
      '飞书自定义机器人不支持 markdown，将降级为纯文本发送（markdown 符号原样显示）。建议使用 text 格式。';

  @override
  String get webhookTemplateHint => '留空则使用预置模板；支持变量：';

  @override
  String get platformWechat => 'WeCom';

  @override
  String get platformDingtalk => 'DingTalk';

  @override
  String get platformFeishu => 'Feishu';

  @override
  String get platformSlack => 'Slack';

  @override
  String get platformDiscord => 'Discord';

  @override
  String get platformGeneric => '通用 JSON';

  @override
  String get platformWechatDesc => '文本格式推送';

  @override
  String get platformFnthinkDesc => '自家幻念端点：URL 带端点口令，POST JSON，2xx 即受理';

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
      '此权限用于读取已安装应用列表，以支持按应用过滤通知。\n\n点击「允许」后将跳转至系统设置页，请手动授予权限。';

  @override
  String get appListPermGuideTitle => '应用列表权限需由系统放行';

  @override
  String get appListPermGuideMsg =>
      '系统里这一项名为「读取已安装的应用列表」（部分机型位于「权限」页，部分位于「其他权限」或「应用权限」中）。\n\n点「去开启」将跳转至本应用的系统设置页，请找到该项并允许；设置完成后返回应用即可生效。';

  @override
  String get autostartGuideTitle => '自启动需在厂商设置中开启';

  @override
  String get autostartGuideMsg =>
      '自启动不属于 Android 的标准权限，各厂商将其置于自家的管家类应用内，系统没有统一开关，应用内亦无法申请。\n\n点「去开启」将跳转至本机对应的设置页，请将本应用设为「允许自启动」；设置完成后返回应用即可生效。';

  @override
  String get appListPermExtra => '用于获取已安装应用列表，支持按应用过滤通知功能';

  @override
  String get appListPermUnknown => '该系统版本不提供明确状态，以能否读取应用列表为准';

  @override
  String get clickToSettings => '点击前往设置';

  @override
  String get samsungSmartManagerDesc => '请在智能管理器中将本应用加入自启动白名单';

  @override
  String get nativeBatteryOptDesc => '请在系统设置中确认电池优化已关闭';

  @override
  String get exactAlarmTitle => '精确闹钟（准时推送）';

  @override
  String get exactAlarmDesc => '延迟/定时推送可更准时触发；Android 12 及以上需系统授权';

  @override
  String get exactAlarmGranted => '已授权';

  @override
  String get exactAlarmNeedGrant => '点击以授权';

  @override
  String get keepAliveGuideTitle => '后台保活引导';

  @override
  String get keepAliveGuideDesc => '部分系统会限制后台服务，可能导致无法接收通知。按以下步骤设置可提高稳定性：';

  @override
  String get keepAliveStep1 => '省电策略设为不限制';

  @override
  String get keepAliveStep2 => '允许自启动';

  @override
  String get keepAliveStepAssoc => '允许关联启动（荣耀/华为等系统需要）';

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
  String get notifToggleDesc => '开启后，以下提醒方可生效';

  @override
  String get notifRules => '通知规则';

  @override
  String get batteryNotes1 => '低电量提醒仅在非充电状态下触发';

  @override
  String get batteryNotes2 => '电量回升到阈值以上才会重置提醒状态';

  @override
  String get batteryNotes3 => '电量通知随通知监听服务一同运行';

  @override
  String get batteryNotes4 => '点击规则可编辑；左滑或长按可删除';

  @override
  String get closeBatteryOpt => '关闭电池优化限制';

  @override
  String get batteryOptDesc => '息屏后系统会限制后台运行，可能导致通知监听服务中断';

  @override
  String get ruleStartCharging => '设备接入充电器时推送';

  @override
  String get ruleStopCharging => '设备断开充电器时推送';

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
  String get customTitleHint => '留空时使用默认标题';

  @override
  String get batteryReminder => '电量提醒';

  @override
  String get setDeviceName => '设置设备名称';

  @override
  String get deviceNameLabel => '设备名称';

  @override
  String get author => '作者：幻念团队 fnthinklevi';

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
  String get ruleGuideTitle => '规则约束介绍';

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
  String get ruleNameHint => '请输入规则名称';

  @override
  String get ruleDescription => '规则描述';

  @override
  String get ruleDescriptionHint => '可选；用于描述规则用途';

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
  String rulePriorityCustomValue(int value) {
    return '自定义…（$value）';
  }

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
  String get ruleAppScopeDesc => '被排除的应用不再匹配本规则';

  @override
  String get ruleAppPickTitle => '选择适用应用';

  @override
  String get ruleAppNoPermission => '无应用列表读取权限，无法加载应用列表';

  @override
  String get ruleMergeWindowRow => '聚合等待时长';

  @override
  String ruleMergeWindowSummary(int n) {
    return '等待 $n 秒';
  }

  @override
  String get ruleMergeWindowPresets => '常用时长（点击以填入）：';

  @override
  String get ruleMergeWindowInvalid => '请输入 5-86400 的整数（最小 5 秒）';

  @override
  String get historyActionBlockAppShort => '屏蔽该应用';

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
  String get ruleEmptyConditions => '暂无条件，点击即可添加';

  @override
  String get ruleEmptyActions => '暂无动作，点击即可添加';

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
  String get mergeWindowHint => '默认 5 秒；同一应用的通知在此窗口内合并为一条推送';

  @override
  String get condTimeRange => '时间范围';

  @override
  String get condRegex => '正则表达式';

  @override
  String get condChargingState => '充电状态';

  @override
  String get condNetworkType => '网络类型';

  @override
  String get condUnknown => '不认得的条件类型';

  @override
  String get hintPackage => '例如：com.example.app';

  @override
  String get hintKeyword => '输入关键词';

  @override
  String get hintPriority => '高/中/低';

  @override
  String get hintTimeRange => '09:00-18:00';

  @override
  String get hintRegex => '正则表达式';

  @override
  String get hintUnknown => '本机不认得这一型条件 ⇒ 一律判不匹配（不会拿它去比标题）；保存时原样保留，不改写成别的类型';

  @override
  String hintAllowedValues(String values) {
    return '填 $values 之一（大小写不敏感）；本机读不到这一项时一律不匹配';
  }

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
  String get initializing => '正在初始化…';

  @override
  String get loadWebhook => '正在加载 Webhook 配置…';

  @override
  String get loadBattery => '正在加载电池配置…';

  @override
  String get loadRecords => '正在加载通知记录…';

  @override
  String get loadFilter => '正在加载过滤配置…';

  @override
  String get initUpdate => '正在初始化更新服务…';

  @override
  String get initComplete => '初始化完成';

  @override
  String get initFailed => '应用启动失败';

  @override
  String get initFailedMsg => '依赖注入初始化失败，请重启应用';

  @override
  String initTimeout(int seconds) {
    return '初始化在 $seconds 秒内未完成';
  }

  @override
  String get retry => '重试';

  @override
  String get startupDbStalled => '数据库被后台残留连接占用，初始化无法继续。请点「重启应用」恢复（已保存的数据不受影响）。';

  @override
  String get restartApp => '重启应用';

  @override
  String get databaseUnavailableTitle => '数据库无法打开';

  @override
  String get databaseUnavailableBody =>
      '加密数据库无法打开；原文件已保留，历史记录未被清空。请点击「重试」再次打开。';

  @override
  String get secureStorageUnavailableTitle => '安全存储不可用';

  @override
  String get secureStorageUnavailableBody =>
      '加密数据库的密钥已失效（无法读取 Android Keystore 主密钥），「重试」无法恢复。请前往系统设置 → 应用 → 通知推送助手 → 存储 → 清除应用数据，然后重新打开；历史记录与配对信息将一并丢失，本应用不会代为执行此操作。';

  @override
  String get databaseRecoveryTitle => '检测到旧数据库备份';

  @override
  String databaseRecoveryBody(String time, String size) {
    return '重建前保留的旧数据库备份：$time，$size。恢复将使用此备份覆盖当前数据库；当前数据库会先另行保存，不会被直接删除。';
  }

  @override
  String get databaseRecoveryConfirm => '恢复';

  @override
  String get databaseRecoveryDone => '已从旧数据库备份恢复，正在刷新页面数据。';

  @override
  String databaseRecoveryFailed(String reason) {
    return '旧数据库备份未通过完整性校验，未进行任何覆盖：$reason';
  }

  @override
  String get databaseMigrationBackupTitle => '数据库升级未完成';

  @override
  String databaseMigrationBackupBody(String time, String size) {
    return '升级前已自动备份旧数据库：$time，$size。可恢复此备份（当前数据库会先另行保存），或重试本次升级。';
  }

  @override
  String get databaseMigrationRestore => '恢复备份';

  @override
  String get databaseMigrationRestoreDone =>
      '已恢复迁移前备份，数据库已重新打开。请重新打开应用以完成页面加载。';

  @override
  String databaseMigrationRestoreFailed(String reason) {
    return '恢复迁移前备份失败，当前库未被覆盖：$reason。迁移前备份仍在原处。';
  }

  @override
  String pageInitFailed(String e) {
    return '页面初始化失败：$e';
  }

  @override
  String get unknownError => '未知错误';

  @override
  String testFailedMsg(String e) {
    return '测试失败：$e';
  }

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
  String get refreshAppList => '刷新应用列表';

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
  String get searchAppHint => '搜索应用名称或包名';

  @override
  String get showSystemApps => '显示系统应用';

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String get invertSelection => '反选';

  @override
  String selectedCount(int n) {
    return '已选择 $n';
  }

  @override
  String unselectedCount(int n) {
    return '未选 $n';
  }

  @override
  String get noAppsFound => '未找到应用';

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
  String get smsMonitorDesc => '控制是否监听并推送收到的短信';

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
  String get deliveryPeerDelivered => '已送达';

  @override
  String get deliveryPeerDisplayed => '对方已显示';

  @override
  String get deliveryFailed => '推送失败';

  @override
  String get deliveryPending => '发送中';

  @override
  String get deliveryQueued => '已推送到服务器 · 待目标设备上线';

  @override
  String get deliveryNotAccounted => '未入账';

  @override
  String get deliveryUnknown => '状态未知';

  @override
  String get deliveryPausedNotSent => '暂停未发送';

  @override
  String get pushPausedByUser => '已暂停';

  @override
  String get deliveryIntercepted => '已拦截';

  @override
  String get deliveryViaBackupTag => '备用';

  @override
  String get pushNow => '现在推送';

  @override
  String get pushAgain => '再发一次';

  @override
  String historyTallyTotal(int n) {
    return '共 $n 条通道';
  }

  @override
  String historyTallyDone(int n) {
    return '$n 成功';
  }

  @override
  String historyTallyFailed(int n) {
    return '$n 失败';
  }

  @override
  String historyTallyInFlight(int n) {
    return '$n 在途';
  }

  @override
  String get historyDeliveryDetail => '查看详情';

  @override
  String get historyDeliveryDetailTitle => '这条推给了谁';

  @override
  String get historyChannelRepush => '重推此通道';

  @override
  String get historyChannelRepushAll => '全部重推';

  @override
  String historyChannelRepushGone(Object n) {
    return '其中 $n 条通道已删除，不能重推';
  }

  @override
  String get deliveryRetryHelpShort => '自动重试与「没拿到回执」的说明';

  @override
  String get deliveryRetryHelpTitle => '自动重试与回执';

  @override
  String get deliveryRetryHelpBody =>
      '· 会重试：网络错误、HTTP 失败与限流。先当场重试 3 次（约 2 秒起逐次加长）；仍失败则进入跨进程重放队列（最多 3 次、间隔约 15 分钟、24 小时内）。\n· 不重试：业务性拒绝（例如企微 errcode 非 0、签名或关键词不匹配）。重试不会成功，还可能让对面群里重复刷屏。\n· 邮件通道没有出站队列，失败后不会自动重发。\n· 「没拿到回执」＝ 发出 30 分钟后本机仍没有结论，且只在打开 App / 回到前台时清扫（没有后台定时器）。它不等于通道失败，也不等于对面没收到。';

  @override
  String get privacyOverviewTitle => '隐私政策概述';

  @override
  String get privacyOverviewContent =>
      '通知推送助手（以下简称\"本应用\"）由幻念团队开发并运营。本应用高度重视您的个人信息与隐私保护，在您使用本应用前，请仔细阅读本隐私政策，了解我们如何收集、使用、存储和保护您的信息。\n\n本政策适用于本应用提供的所有服务。当您安装并使用本应用时，即表示您已阅读、理解并同意本政策的全部内容。';

  @override
  String get privacyInfoTitle => '我们收集的信息';

  @override
  String get privacyInfoContent =>
      '本应用遵循“最小必要”原则，仅收集实现核心功能所必需的信息：\n\n1. 通知内容（本地处理）\n   - 应用通过系统通知监听服务读取通知内容\n   - 通知内容在设备本地完成规则匹配与关键词过滤，仅按您自行配置的目标转发：Webhook、邮件地址或幻念设备\n   - 除您指定的上述目标外，通知内容不会上传至任何其他服务器；其中「幻念设备」路径经您选定的中转服务器投递，详见第 7 项\n\n2. 崩溃统计信息（腾讯 Bugly，默认关闭）\n   - 仅在您于「更多 → 崩溃上报」主动开启后，才收集应用崩溃时的堆栈信息、设备型号、系统版本、应用版本号、CPU 架构\n   - 未开启时 SDK 不初始化，数据不离开设备；开启后仅用于定位和修复崩溃问题，提升应用稳定性\n\n3. 推送统计与历史记录（本地存储）\n   - 通知记录、推送状态、每日统计等数据使用 AES-256 加密存储在本地数据库\n   - 这些数据仅保存在您的设备上，不会对外发送\n\n4. 延迟推送队列（本地存储）\n   - 规则约束产生的延迟/定时推送任务持久化保存在本机，重启后不丢失\n\n5. 电池状态（本地监控）\n   - 电量及充电状态监控仅在本机采集，用于首页展示，不对外发送\n\n6. 已安装应用列表（本地使用）\n   - 用于规则约束的条件配置与应用过滤，仅在本机使用\n\n7. 幻念推送（设备互推 / 第三方经接入端点推给手机，需您显式同意）\n   - 仅在您使用「幻念推送」并在应用内一次性显式同意后，消息才会经您选定的服务器中转送达目标设备；不使用或不同意时，通知内容始终不离开本机\n   - 未送达期间，消息正文在服务器端加密暂存，最长保留 7 天，送达或到期后立即删除\n   - 配对口令与身份私钥不上传，服务器与审计日志只保存投递所需的元数据（不含正文）\n   - 若您选择自行部署幻念推送服务器，上述中转与保留规则由您自己的服务器执行，数据处于您掌控的基础设施内\n   - 远程读取（默认关、单独开启）：您在「可被远程读取的内容」中为某一项单独开启开关并授予系统权限后，已配对设备方可经同一条中转链路读回该项数据（例如按关键词检索到的通话记录、最近一次定位、让这台拍的一张照片、按姓名或号码检索到的联系人）；关闭后即失效\n   - 拍照回传：照片文件保存在拍摄设备上（Android 10 及以上保存至相册，9 及以下保存至本应用图片目录）；图像随回传消息经您选定的服务器中转发回发起设备，并保存在双方的消息历史中。该项与其他远程读取项一样默认关闭、单独开启，关闭后不再执行\n   - 「搜索短信」还可检索本机已监听的留存内容（默认关闭）：该留存保存的是监听短信时写入本机数据库的正文，此开关仅决定对端能否检索；关闭时仅查询系统短信库\n   - ⚠ 若您选择的实例属于别人运营的实例：该服务器使用其自身密钥进行落盘加密，「服务器不落明文正文」描述的是存储形态，并不等于运营方无法读取；投递元数据与运维日志亦由其掌握。这与配置 Webhook 转发目标属于同一类决定，请仅连接您信得过的实例';

  @override
  String get privacyNoCollectTitle => '我们不收集的信息';

  @override
  String get privacyNoCollectContent =>
      '本应用不会收集以下个人隐私信息：\n\n• 通讯录、短信内容（除非您主动授权用于短信通知识别）\n• 位置信息\n• 通话记录\n• 相册、文件内容\n• 麦克风、摄像头数据\n• 个人身份信息（姓名、身份证号、手机号等）\n\n当您不同意授权时，本应用的相关可选功能将不可用，但核心通知转发功能不受影响。';

  @override
  String get privacyShareTitle => '信息共享与披露';

  @override
  String get privacyShareContent =>
      '本应用不会出售、出租或交易您的个人信息。仅在以下情形中共享必要的信息：\n\n1. 您主动配置的转发目标\n   - 当您配置 Webhook（企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus）或 SMTP 邮件后，您选择转发的通知内容将发送至这些您指定的第三方平台\n   - 发送前需要您明确配置目标地址，未配置不会发生任何数据外发\n\n2. 第三方崩溃统计服务（腾讯 Bugly，默认关闭）\n   - 仅在您主动开启崩溃上报后，才共享崩溃堆栈及设备基础环境信息，用于修复问题\n\n3. 法律法规要求\n   - 依据法律、法规或有权机关的要求披露相关信息';

  @override
  String get privacyStorageTitle => '数据存储与安全';

  @override
  String get privacyStorageContent =>
      '本应用采用多层安全机制保护您的数据：\n\n1. 本地数据库加密\n   - 通知历史记录、推送统计使用 AES-256 加密存储（sqflite_sqlcipher）\n   - 加密密钥保存在 Android 系统密钥库（AndroidKeyStore）中\n   - 即使设备被他人获取，也无法直接读取数据库内容\n\n2. 敏感配置加密\n   - Webhook URL、SMTP 账号、TOTP 密钥等敏感配置使用 AndroidKeyStore / AES-256-GCM 加密存储\n   - 不会以明文形式保存在 SharedPreferences 中\n\n3. 网络传输安全\n   - 全站强制 HTTPS，禁止明文 HTTP 传输\n   - 管理后台 Token 仅通过 HTTP Header 传递，不出现在 URL 中\n\n4. 其他安全措施\n   - 管理后台二步验证（TOTP）\n   - 应用备份已禁用（allowBackup=false），防止数据通过云备份泄露\n   - 应用内广播接收器已加固，防止外部伪造通知数据\n\n5. 数据保留\n   - 您可随时在应用内清除全部或部分推送历史记录\n   - 卸载应用将清除全部本地数据';

  @override
  String get privacyThirdPartyTitle => '第三方服务';

  @override
  String get privacyThirdPartyContent =>
      '本应用使用以下第三方服务：\n\n腾讯 Bugly（崩溃统计，默认关闭）\n• 服务商：深圳市腾讯计算机系统有限公司\n• 用途：需您在「更多 → 崩溃上报」主动开启后才收集应用崩溃信息，帮助定位和修复问题；关闭后下次启动不再初始化\n• 隐私政策：https://privacy.qq.com/\n• 采集数据：崩溃堆栈、设备型号、系统版本、应用版本、CPU 架构\n\n用户主动配置的推送目标（非 SDK）\n• 企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus、SMTP 邮件服务器\n• 本应用仅向您自行配置的地址发送您选择转发的通知内容，不对第三方平台的数据处理行为负责\n• 涉及上述平台的隐私政策，请查阅对应平台官方文档';

  @override
  String get privacyPermTitle => '权限说明';

  @override
  String get privacyPermContent =>
      '本应用遵循最小权限原则，以下为完整权限清单及用途说明：\n\n核心权限（必需）：\n• 通知使用权（Notification Listener）：读取通知内容，实现转发与规则约束功能\n• 网络访问（INTERNET）：Webhook/邮件推送与版本更新检查\n• 前台服务（FOREGROUND_SERVICE 等）：保持通知监听服务常驻，确保消息及时推送\n• 开机自启动（RECEIVE_BOOT_COMPLETED）：设备重启后自动恢复通知监听服务\n• 通知发送（POST_NOTIFICATIONS）：发送本地通知提示\n• 唤醒锁（WAKE_LOCK）：延迟/定时推送到点唤醒设备\n\n辅助权限（可选）：\n• 电量优化白名单（REQUEST_IGNORE_BATTERY_OPTIMIZATIONS）：避免系统限制后台服务\n• 短信（RECEIVE_SMS/READ_SMS）：可选，用于短信通知识别与转发\n• 本机短信留存（通知监听写入数据库的部分）：无需额外系统权限；仅在「可被远程读取的内容」中开启此项后，允许已配对设备按关键词检索该留存（关闭时不会查询该留存）\n• 电话状态（READ_PHONE_STATE）：可选，用于来电通知识别\n• 通话记录（READ_CALL_LOG）：可选，仅在「可被远程读取的内容」中开启并授权后，允许已配对设备按关键词检索本机通话记录\n• 位置（ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION）：可选，仅在「可被远程读取的内容」中开启并授权后，允许已配对设备读取本机最近一次定位（只读，不发起新的定位）\n• 相机（CAMERA）：可选，仅在「可被远程读取的内容」中开启并授权后，允许已配对设备让本机拍一张照片（照片文件保存在本机，图像随回传消息经服务器中转发回发起设备，双方消息历史各保存一份；且要求本应用界面处于开启状态）\n• 通讯录（READ_CONTACTS）：可选，仅在「可被远程读取的内容」中开启并授权后，允许已配对设备按姓名或号码检索本机通讯录（只读，不写入）\n• 存储（READ/WRITE_EXTERNAL_STORAGE）：导出推送历史 JSON、保存更新 APK\n• 安装未知应用（REQUEST_INSTALL_PACKAGES）：应用内在线更新时安装 APK\n• 查询已安装应用（QUERY_ALL_PACKAGES）：规则约束的条件配置与应用过滤\n• 振动（VIBRATE）：推送提示振动\n• 网络状态（ACCESS_NETWORK_STATE）：检测网络连接状态\n\n以上辅助权限均在您主动授权后使用，可随时在系统设置中关闭。';

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
  String get lastUpdate => '最后更新：2026年11月28日';

  @override
  String get deliveryLogTitle => '送达记录';

  @override
  String get deliveryLogEmpty => '暂无送达日志（可能已过 30 天保留期，或该通知早于送达日志功能启用）';

  @override
  String get backupRestoreTitle => '备份与恢复';

  @override
  String get backupSectionTitle => '备份配置';

  @override
  String get backupSectionShort => '把你的所有设置打包成一个文件，换手机或重装后一键恢复。';

  @override
  String get backupSectionDesc =>
      '把你的所有设置打包成一个文件，换手机或重装后可以一键恢复。\n\n包含：Webhook 和邮件通道（含密钥）、通知规则、短信监听开关、应用筛选和黑白名单关键词。\n不含：已经推送过的通知历史。\n\n文件有密码保护，恢复时需要输入同一个密码，请务必记住。';

  @override
  String get restoreSectionTitle => '恢复配置';

  @override
  String get restoreSectionDesc => '选择备份文件并输入口令恢复。检测到现有配置时，可选择覆盖或仅导入空缺项。';

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
  String restoreSkippedInvalid(int n) {
    return '已跳过 $n 条地址非法的 Webhook 通道';
  }

  @override
  String get restorePartialFailed => '部分配置未恢复成功，请逐项检查设置页';

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
  String testerDeviceStateLine(String charging, String network) {
    return '本机此刻：充电 $charging · 网络 $network';
  }

  @override
  String get testerDeviceStateUnavailable => '读不到';

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
  String get testerFilteredNote => '该通知会被过滤掉，不会进入规则约束判定与推送链路';

  @override
  String get engineConstraintEntry => '设备状态告警同样受约束';

  @override
  String get engineConstraintTitle => '设备状态告警受哪些约束，以及被拦截后的处理';

  @override
  String get engineConstraintShort => '开启后，电量/温度告警在推送前同样经过关键词黑白名单过滤。';

  @override
  String get engineConstraintDesc =>
      '开启后，电量/温度告警在推送前同样经过关键词黑白名单过滤；应用黑白名单不适用（此类告警由本机自身产生）。被拦截的告警将写入推送历史并标注原因。';

  @override
  String get tempTestEntry => '试运行';

  @override
  String get tempTestTitle => '温度告警试运行';

  @override
  String get tempTestReadings => '当前读数：';

  @override
  String get tempTestSteps => '检查步骤：';

  @override
  String get tempTestFired => '会触发：';

  @override
  String get tempTestSilent => '不会触发：';

  @override
  String get tempTestFailed => '试运行失败（未完成测量，不代表不会触发）';

  @override
  String get tempTestNoDims => '本机无法读取任何温度维度';

  @override
  String get tempOutcomeFire => '触发';

  @override
  String get tempSilenceNoRules => '没有启用中的温度规则';

  @override
  String get tempSilenceNoReading => '本机无法读取该维度';

  @override
  String get tempSilenceNotTriggered => '未达到阈值';

  @override
  String get tempSilenceNotCrossing => '未发生跨越（上一次已在阈值之上）';

  @override
  String get tempSilenceBaseline => '首轮只记录基准，不触发';

  @override
  String get tempSilenceInCooldown => '冷却中';

  @override
  String get tempSilenceDisabled => '温度告警总开关已关闭';

  @override
  String get deviceStateEntry => '设备状态告警';

  @override
  String get deviceStateDesc =>
      '屏幕亮度与网络状态的变化也能触发提醒。只有「跨越」的那一刻算一次事件（一直在阈值之下不会反复提醒），触发后 30 分钟内同一类不再重复提醒。';

  @override
  String brightnessPercentOnly(int percent) {
    return '$percent%';
  }

  @override
  String networkCaption(Object network) {
    return '网络：$network';
  }

  @override
  String get temperatureNotes1 =>
      '阈值范围 30–90℃：仅在「跨越」阈值的那一刻计为一次事件；已在阈值之上时不会重复提醒。';

  @override
  String get temperatureNotes2 => '触发后 30 分钟内同一维度不再重复提醒。';

  @override
  String get temperatureNotes3 =>
      '电池温度、设备温度、屏幕温度三个维度分别判定；本机无法读取的维度会在「试运行」中明确说明。';

  @override
  String get deviceStateNotes2 => '亮度按百分比判定；网络类触发只看「断网」与「联网」这两件事，不需要阈值。';

  @override
  String get deviceStateNotifyEnabled => '设备状态告警推送';

  @override
  String get brightnessBelow => '亮度低于';

  @override
  String get brightnessAbove => '亮度高于';

  @override
  String get networkConnected => '恢复联网时';

  @override
  String get networkDisconnected => '断网时';

  @override
  String get deviceStateValueLabel => '亮度阈值（%）';

  @override
  String get deviceStateNoValue => '网络触发不需要阈值';

  @override
  String get noDeviceStateRules => '暂无设备状态规则，点右上角 + 添加';

  @override
  String get deviceStatusEntry => '设备状态快照';

  @override
  String deviceStatusBrief(String model, int level) {
    return '$model · 电量 $level%';
  }

  @override
  String deviceStatusBriefCharging(String model, int level) {
    return '$model · 电量 $level% · 充电中';
  }

  @override
  String deviceStatusBriefNoReading(String model) {
    return '$model · 电量读数还没到';
  }

  @override
  String get deviceStatusShort => '下面每一项都来自**同一次**读取。';

  @override
  String get deviceStatusDesc =>
      '下面每一项都来自**同一次**读取。显示「这台设备读不到」表示这个系统接口在本机不可用，不等于数值是 0。';

  @override
  String get deviceStatusSnapshotFailed => '没读到设备快照（原生通道没有回话）';

  @override
  String get deviceStatusRefresh => '重新读取';

  @override
  String snapshotCapturedAt(String time) {
    return '读取于 $time';
  }

  @override
  String get snapshotModel => '型号';

  @override
  String get snapshotManufacturer => '厂商';

  @override
  String get snapshotBrand => '品牌';

  @override
  String get snapshotSystemVersion => '系统版本';

  @override
  String snapshotSystemVersionValue(String version, int sdk) {
    return 'Android $version（API $sdk）';
  }

  @override
  String get snapshotNetwork => '网络';

  @override
  String get netWifi => 'Wi-Fi';

  @override
  String get netCellular => '蜂窝数据';

  @override
  String get netVpn => 'VPN';

  @override
  String get netEthernet => '以太网';

  @override
  String get netNone => '未联网';

  @override
  String get netOther => '其他网络';

  @override
  String get snapshotBattery => '电量';

  @override
  String snapshotBatteryValue(int level, String state) {
    return '$level%（$state）';
  }

  @override
  String get batteryChargingState => '充电中';

  @override
  String get batteryDischargingState => '未充电';

  @override
  String get snapshotBatteryTemp => '电池温度';

  @override
  String snapshotBatteryTempValue(String value) {
    return '$value℃';
  }

  @override
  String get snapshotStorage => '存储';

  @override
  String snapshotStorageValue(String used, String total) {
    return '已用 $used GB / 共 $total GB';
  }

  @override
  String get snapshotMemory => '内存';

  @override
  String snapshotMemoryValue(String available, String total) {
    return '可用 $available GB / 共 $total GB';
  }

  @override
  String get snapshotBrightness => '屏幕亮度';

  @override
  String snapshotBrightnessValue(int percent, String mode) {
    return '$percent%（$mode）';
  }

  @override
  String get brightnessModeAuto => '自动';

  @override
  String get brightnessModeManual => '手动';

  @override
  String get snapshotUptime => '已运行';

  @override
  String snapshotUptimeValue(int days, int hours, int minutes) {
    return '$days 天 $hours 小时 $minutes 分';
  }

  @override
  String get unreadableField => '这台设备读不到';

  @override
  String get pushDeviceInfo => '推送设备信息';

  @override
  String get pushDeviceInfoShort => '把上面这份快照作为一条通知推到你启用的通道。';

  @override
  String get pushDeviceInfoDesc =>
      '把上面这份快照作为一条通知推到你启用的通道；走的是与告警同一条推送链，送达结果在推送历史里看。';

  @override
  String get pushDeviceInfoSent => '已交给通道推送，结果见推送历史';

  @override
  String get pushDeviceInfoBusy => '正在推送…';

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

  @override
  String get batchPushEntry => '批量补推';

  @override
  String get batchPushNothingToResend => '当前列表没有可再发的记录';

  @override
  String batchSelectedCount(int n) {
    return '已选择 $n 条';
  }

  @override
  String get batchSelectAll => '全选可重新发送的记录';

  @override
  String get batchSelectNone => '取消全选';

  @override
  String batchPushAction(int n) {
    return '补推 $n 条';
  }

  @override
  String get batchPushConfirmTitle => '确认补推';

  @override
  String batchPushConfirmMsg(int n) {
    return '将对 $n 条有通道没发出去的记录重新发起推送，实际送达结果以记录状态为准。';
  }

  @override
  String batchPushRunning(int done, int total) {
    return '正在补推 $done/$total';
  }

  @override
  String batchPushDone(int n) {
    return '已提交 $n 条补推';
  }

  @override
  String get batchPushUnsupported => '当前页面不支持补推';

  @override
  String get mergeMaxItemsLabel => '满 N 条提前推送';

  @override
  String get mergeMaxItemsHint => '达到此条数立即推送；0 或留空表示等待窗口结束（可选）';

  @override
  String get mergeGroupByTitleLabel => '按会话分组';

  @override
  String get mergeGroupByTitleDesc => '同一应用下按标题（联系人或群）分别聚合；默认按应用聚合';

  @override
  String ruleMergeMaxItemsSummary(int n) {
    return '达到 $n 条提前推送';
  }

  @override
  String get ruleMergeGroupByTitleSummary => '按会话分组';

  @override
  String get historyBlockAppSelfToast => '本应用自身的通知由电量规则控制，请在电量设置中调整';

  @override
  String get exportConfirmDesc =>
      '通知记录将导出为 JSON 文件，包含通知内容和设备信息。请选择保存位置，建议在导出后妥善保管或及时删除。';

  @override
  String fnthinkExportInboxDesc(Object count) {
    return '幻念收件记录（$count 条）将导出为 JSON 文件，包含消息内容与设备信息。';
  }

  @override
  String fnthinkExportSentDesc(Object count) {
    return '幻念发件记录（$count 条）将导出为 JSON 文件，包含消息内容与设备信息。';
  }

  @override
  String get exportDone => '导出完成';

  @override
  String get historyMoreActions => '更多操作';

  @override
  String get updateAlreadyLatest => '当前已是最新版本';

  @override
  String get updateCheckFailed => '检查更新失败，请检查网络连接';

  @override
  String updateCheckFailedWithError(String error) {
    return '检查更新失败：$error';
  }

  @override
  String updateDownloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String get updateForceBadge => '重要更新';

  @override
  String get updateForceRequired => '必须更新才能继续使用';

  @override
  String get updateFoundNew => '发现新版本';

  @override
  String get updateLatestVersionLabel => '最新版本：';

  @override
  String get updateCurrentVersionLabel => '当前版本：';

  @override
  String get updateFileSizeLabel => '文件大小：';

  @override
  String get updateChangelogTitle => '更新内容';

  @override
  String get updateChangelogShowAll => '查看完整更新内容';

  @override
  String get updateChangelogCollapse => '收起';

  @override
  String get updateIgnore => '忽略';

  @override
  String get updateLater => '稍后';

  @override
  String get updateButton => '更新';

  @override
  String get updateDownloading => '正在下载更新';

  @override
  String get webhookConfigSaved => 'Webhook 配置已保存';

  @override
  String get emailConfigSaved => '邮件通道配置已保存';

  @override
  String get emailPasswordSecureUnavailable =>
      '邮件密码未能写入系统加密存储，后台推送将用不到它；已拒绝明文保存，请稍后重试';

  @override
  String get notificationPermOffMsg =>
      '通知读取权限未开启，应用无法读取设备通知内容。\n\n请先前往「权限设置」开启通知读取权限，再启动服务。';

  @override
  String get historyBlockAppWhitelistNote =>
      '已确认屏蔽；注意：白名单关键词命中仍会推送该应用，可删除相关白名单关键词';

  @override
  String get channelTypeNtfy => 'ntfy 推送';

  @override
  String get channelTypeGotify => 'Gotify 推送';

  @override
  String get channelTypeSlack => 'Slack 通知';

  @override
  String get channelTypeDiscord => 'Discord 通知';

  @override
  String get channelTypeFnthink => '幻念推送';

  @override
  String get channelTypeRedetect => '重新识别';

  @override
  String get channelTypeRedetectUnknown => '没认出这家端点，仍按通用 Webhook';

  @override
  String get platformNtfyDesc => '向 ntfy topic 推送通知，支持官方与自建服务器（可选访问令牌）';

  @override
  String get platformGotifyDesc => '向自建 Gotify 服务器推送，使用应用 Token 鉴权（填于密钥字段）';

  @override
  String get platformSlackDesc => '通过 Slack Incoming Webhook 发送消息';

  @override
  String get platformDiscordDesc => '通过 Discord Webhook 发送消息，正文上限 2000 字符';

  @override
  String get platformDingtalkDesc => 'URL 加签（timestamp+sign），正文可发 Markdown';

  @override
  String get platformFeishuDesc =>
      '签名写在请求体（timestamp+sign）；正文按纯文本发送，Markdown 会降级';

  @override
  String get platformTelegramDesc =>
      'Bot Token 与 chat_id 取自 URL；纯文本，正文上限 4096 字符';

  @override
  String get platformBarkDesc => '设备 Key 取自 URL 路径；标题与正文以 JSON 发送，无需签名密钥';

  @override
  String get platformServerChanDesc =>
      'SendKey 取自 URL 路径；正文以表单提交（title/desp），无签名';

  @override
  String get platformPushPlusDesc => 'token 取自 URL 并写入请求体，正文按纯文本模板发送，无需签名密钥';

  @override
  String get signingHintNtfy => '可选：ntfy 访问令牌（Bearer Token），自建服务器开启鉴权时填写';

  @override
  String get signingHintGotify => '必填：Gotify 应用 Token（客户端 Token 无法推送）';

  @override
  String get signingHintSlack => 'Slack 使用 Incoming Webhook URL 鉴权，无需签名密钥';

  @override
  String get signingHintDiscord => 'Discord 使用 Webhook URL 鉴权，无需签名密钥';

  @override
  String historyBlockAppSwitchedToBlock(String app) {
    return '已屏蔽「$app」，过滤模式已切换为黑名单（其余应用推送不受影响）';
  }

  @override
  String ruleAppGroupApplied(int n) {
    return '适用 · $n 个';
  }

  @override
  String ruleAppGroupExcludedN(int n) {
    return '已排除 · $n 个';
  }

  @override
  String get ruleAppQuickSelect => '快速选择';

  @override
  String get ruleAppQuickComm => '通讯';

  @override
  String get ruleAppQuickMail => '邮箱';

  @override
  String get ruleAppQuickSms => '短信';

  @override
  String get ruleAppQuickPhone => '电话';

  @override
  String get ruleAppQuickSmsSub => '系统短信 / 信息应用';

  @override
  String get ruleAppQuickPhoneSub => '系统电话 / 通话应用';

  @override
  String ruleAppGroupOthersN(int n) {
    return '其他应用 · $n 个';
  }

  @override
  String get channelTypeWecomApp => '企业微信自建应用';

  @override
  String get ruleTemplateTitle => '规则模板库';

  @override
  String get ruleTemplatePreset => '预设模板';

  @override
  String get ruleTemplateMine => '我的模板';

  @override
  String get ruleTemplateMineEmpty => '暂无自定义模板；在规则卡片上点「存为模板」即可保存';

  @override
  String get ruleTemplateSaveAs => '存为模板';

  @override
  String ruleTemplateSavedToast(String app) {
    return '已将「$app」存为模板';
  }

  @override
  String get ruleTemplateImport => '从文件导入';

  @override
  String get ruleTemplateExport => '导出分享';

  @override
  String get ruleTemplateImportPasswordTitle => '输入模板文件口令';

  @override
  String get ruleTemplateImportPasswordHint => '该文件已加密，请输入导出时设置的口令';

  @override
  String get ruleTemplateExportPasswordTitle => '导出口令（可选）';

  @override
  String get ruleTemplateExportPasswordHint => '留空则明文导出；设置口令后需凭口令导入（文件有密码保护）';

  @override
  String get ruleTemplateImportEmpty => '模板文件中没有模板';

  @override
  String get ruleTemplateInvalidFile => '不是有效的模板文件';

  @override
  String get ruleTemplateExportOk => '模板已导出';

  @override
  String get statsDeliveryHealth => '送达健康';

  @override
  String get statsChannelSuccess => '通道成功率';

  @override
  String get statsFailureTop => '失败原因 TOP';

  @override
  String get statsHourly => '高峰时段分布';

  @override
  String get statsRange7 => '近 7 天';

  @override
  String get statsRange30 => '近 30 天';

  @override
  String get statsNoDeliveryData => '该时间范围内暂无送达记录';

  @override
  String get statsFailNetwork => '网络 / 连接失败';

  @override
  String statsFailCount(int n) {
    return '$n 次';
  }

  @override
  String healthReachable(int n) {
    return '连通 · $n ms';
  }

  @override
  String get healthUnreachable => '连接失败';

  @override
  String healthProbedMinutes(int n) {
    return '$n 分钟前探测';
  }

  @override
  String healthProbedHours(int n) {
    return '$n 小时前探测';
  }

  @override
  String get appChannelTitle => '自建应用通道';

  @override
  String get appChannelNewTitle => '新增自建应用通道';

  @override
  String get noAppChannels => '暂无自建应用通道';

  @override
  String get appChannelPageTitle => '自建应用通道的消息发送流程';

  @override
  String get appChannelPageShort =>
      '企业微信／飞书的自建应用：先以凭据换取 token，再向消息端点发送；密钥加密存储。';

  @override
  String get appChannelPageDesc =>
      '自建应用通道走「凭据换 token → 消息端点」的两阶段 API（区别于 webhook），支持企业微信自建应用与飞书自建应用；密钥加密存储，送达结果与失败重试同 webhook 通道。';

  @override
  String get appChannelNameLabel => '通道名称';

  @override
  String get appChannelBaseUrlHint =>
      'API 地址（留空使用官方地址；支持私有化部署，须为 HTTPS 且证书受系统信任）';

  @override
  String get appChannelSecretWecomHint => 'corpsecret（用于获取 access_token）';

  @override
  String get appChannelSecretFeishuHint =>
      'app_secret（用于获取 tenant_access_token）';

  @override
  String get appChannelCorpidLabel => '企业 ID（corpid）';

  @override
  String get appChannelAgentidLabel => '应用 agentid（纯数字）';

  @override
  String get appChannelTouserLabel => '接收人 touser（可选，@all；多人 | 分隔）';

  @override
  String get appChannelAppidLabel => '应用 app_id';

  @override
  String get appChannelReceiveIdTypeLabel => '接收人类型（chat_id 或 open_id）';

  @override
  String get appChannelReceiveIdLabel => '接收人 ID receive_id';

  @override
  String get appChannelDeleteHint => '删除后需点击右上角保存方可生效。';

  @override
  String get appChannelTestFailed => '测试失败：';

  @override
  String get appChannelSaveOk => '自建应用通道已保存并同步';

  @override
  String get appChannelErrNameRequired => '保存失败：通道名称不能为空';

  @override
  String get appChannelErrBaseUrlRequired => '保存失败：API 地址不能为空';

  @override
  String appChannelErrFieldsRequired(String fields) {
    return '保存失败：必填字段未填写（$fields）';
  }

  @override
  String get priorityBadgeHigh => '高';

  @override
  String get priorityBadgeLow => '低';

  @override
  String get channelBadgeFallback => '通';

  @override
  String storageRootPath(String path) {
    return '存储根目录$path';
  }

  @override
  String get recordTypeSms => '短信';

  @override
  String get recordTypeCallIncoming => '来电';

  @override
  String get recordTypeCallAnswered => '接听';

  @override
  String get recordTypeCallEnded => '挂断';

  @override
  String get recordTypeWechat => '微信';

  @override
  String get recordTypeQq => 'QQ';

  @override
  String get recordTypeAlipay => '支付宝';

  @override
  String get recordTypeSystem => '系统';

  @override
  String get recordTypeTest => '测试';

  @override
  String get recordTypeCharging => '充电';

  @override
  String get recordTypeFull => '充满';

  @override
  String get recordTypeLow30 => '低电量30%';

  @override
  String get recordTypeLow20 => '低电量20%';

  @override
  String get recordTypeNotification => '通知';

  @override
  String get emailHintPort => '465 (SSL) 或 587 (STARTTLS)';

  @override
  String get emailHintPassword => 'SMTP 授权码（非邮箱密码）';

  @override
  String get emailHintRecipients => '可多个，逗号分隔';

  @override
  String get emailHintHostExample => 'smtp.qq.com';

  @override
  String get emailHintAddressExample => 'your@email.com';

  @override
  String get emailMetaUnavailable => '通道元数据尚未就绪，请稍后重试（本次操作未更改任何配置）';

  @override
  String get testUnknownResult => '未知结果';

  @override
  String get emailHintSubject => '留空则用默认主题（应用名 + 标题）';

  @override
  String get emailHintBody => '留空则用默认正文（应用/标题/内容/包名/时间/设备）';

  @override
  String get emailPresetSubjectDefault => '🔔 %appName% — %title%';

  @override
  String get emailPresetSubjectSimple => '%appName% — %title%';

  @override
  String get emailPresetSubjectDetailed => '%appName% — %title%\n内容：%content%';

  @override
  String get emailPresetSubjectTime => '%time% %appName% — %title%';

  @override
  String get emailPresetSubjectCode => '[%appName%] 验证码通知 — %title%';

  @override
  String get emailPresetSubjectDevice => '[%deviceName%] %appName% — %title%';

  @override
  String get emailPresetBodyStandard =>
      '应用：%appName%\n标题：%title%\n内容：%content%\n时间：%time%\n设备：%deviceName%';

  @override
  String get emailPresetBodyComplete =>
      '应用：%appName%\n标题：%title%\n内容：%content%\n副标题：%subText%\n包名：%packageName%\n时间：%time%\n设备：%deviceName%';

  @override
  String get emailPresetBodyCode =>
      '验证码：%content%\n来源：%appName%(%packageName%)\n时间：%time%';

  @override
  String get emailPresetBodyMinimal => '%appName%：%title%\n%content%';

  @override
  String get channelTypeFeishuApp => '飞书自建应用';

  @override
  String get appChannelGuideEntry => '首次接入？请点击卡片右上角的「?」查看参数获取步骤';

  @override
  String get appChannelGuideOpen => '查看接入步骤';

  @override
  String get appChannelGuideTitleWecom => '企业微信自建应用 · 接入步骤';

  @override
  String get appChannelGuideTitleFeishu => '飞书自建应用 · 接入步骤';

  @override
  String get appChannelGuidePrepWecom =>
      '前置条件：需要企业微信管理员（或应用管理员）权限，并已在管理后台创建自建应用。';

  @override
  String get appChannelGuidePrepFeishu =>
      '前置条件：需要飞书开放平台开发者权限（可创建企业自建应用），发布版本需企业管理员审批。';

  @override
  String get appChannelGuideWecomS1 => '获取企业 ID（corpid）';

  @override
  String get appChannelGuideWecomS1Desc =>
      '管理后台 work.weixin.qq.com →「我的企业」→「企业信息」→ 滚动至底部复制「企业 ID」。';

  @override
  String get appChannelGuideWecomS2 => '创建自建应用';

  @override
  String get appChannelGuideWecomS2Desc =>
      '「应用管理」→「应用」→「自建」→「创建应用」，填写名称与图标后创建。';

  @override
  String get appChannelGuideWecomS3 => '获取 AgentId 与 Secret';

  @override
  String get appChannelGuideWecomS3Desc =>
      '进入刚创建的应用：顶部显示「AgentId」（纯数字，对应本软件的 agentid）；点击「Secret」旁的「查看」，按提示发送至企业微信后复制该密钥（corpsecret，对应本软件的密钥字段）。';

  @override
  String get appChannelGuideWecomS4 => '设置可见范围（接收人）';

  @override
  String get appChannelGuideWecomS4Desc =>
      '应用详情 →「可见范围」添加需要接收推送的成员/部门。本应用中「接收人」留空即推送至全部可见成员（@all），也可填成员账号（多个用 | 分隔）。';

  @override
  String get appChannelGuideWecomS5 => '（可选）配置企业可信 IP';

  @override
  String get appChannelGuideWecomS5Desc =>
      '若企业开启了「企业可信 IP」限制：应用详情 →「开发者接口」→「企业可信 IP」添加手机的出口 IP；未开启则跳过。';

  @override
  String get appChannelGuideWecomS6 => '填入软件并测试';

  @override
  String get appChannelGuideWecomS6Desc =>
      '在企业 ID / agentid / 密钥 三处填入上述值，点击卡片内「测试」按钮确认可收到消息后保存。';

  @override
  String get appChannelGuideFeishuS1 => '创建企业自建应用';

  @override
  String get appChannelGuideFeishuS1Desc =>
      '打开 open.feishu.cn「开发者后台」→「创建企业自建应用」，填写名称、描述与图标。';

  @override
  String get appChannelGuideFeishuS2 => '获取 App ID 与 App Secret';

  @override
  String get appChannelGuideFeishuS2Desc =>
      '应用详情 →「凭证与基础信息」→ 复制「App ID」与「App Secret」。';

  @override
  String get appChannelGuideFeishuS3 => '开通消息权限';

  @override
  String get appChannelGuideFeishuS3Desc =>
      '「权限管理」中搜索并开通 im:message（发送单聊消息）与 im:message:send_as_bot（以应用身份发消息）权限。';

  @override
  String get appChannelGuideFeishuS4 => '创建版本并发布';

  @override
  String get appChannelGuideFeishuS4Desc =>
      '「版本管理与发布」→「创建版本」→ 申请发布；经企业管理员审批通过后权限才会生效（未发布时推送会失败）。';

  @override
  String get appChannelGuideFeishuS5 => '获取接收人 ID';

  @override
  String get appChannelGuideFeishuS5Desc =>
      'receive_id_type 选择 chat_id（群）或 open_id（用户）。群 ID 可用「API 调试台」调用 im/v1/chats 获取；用户 open_id 可在通讯录成员详情或通过调试台获取。';

  @override
  String get appChannelGuideFeishuS6 => '填入软件并测试';

  @override
  String get appChannelGuideFeishuS6Desc =>
      '填入 App ID / App Secret / 接收人类型 / 接收人 ID，点击卡片内「测试」按钮确认可收到消息后保存。';

  @override
  String get appChannelGuideNoteTitle => '注意事项';

  @override
  String get appChannelGuideNote1 => 'Secret 通常只在创建时可查看，请妥善保存；软件内该字段加密存储。';

  @override
  String get appChannelGuideNote2 => '私有化部署：把「API 地址」改为你的部署地址（留空则使用官方地址）。';

  @override
  String get appChannelGuideNote3 =>
      '推送失败常见原因：权限未开通 / 应用版本未发布 / 接收人不在可见范围 / Secret 或接收人 ID 填错。';

  @override
  String get appChannelGuideNote4 =>
      '自建应用通道与 Webhook 通道互不影响，可同时启用；推送结果与失败重试与 Webhook 一致。';

  @override
  String get appChannelGuideClose => '了解';

  @override
  String get appChannelGuideNote5 =>
      '自定义 API 地址须使用 HTTPS（明文 http 会被系统拒绝）；自签名证书不受系统信任会连接失败——请使用正式证书，或留空以使用官方地址。';

  @override
  String get textMenuCopy => '复制';

  @override
  String get textMenuPaste => '粘贴';

  @override
  String get textMenuCut => '剪切';

  @override
  String get textMenuSelectAll => '全选';

  @override
  String get batteryTempAbove => '电池温度';

  @override
  String get deviceTempAbove => '设备温度';

  @override
  String get screenTempAbove => '屏幕温度';

  @override
  String ruleBatteryTempAbove(int value) {
    return '电池温度达到$value℃';
  }

  @override
  String ruleDeviceTempAbove(int value) {
    return '设备温度达到$value℃';
  }

  @override
  String ruleScreenTempAbove(int value) {
    return '屏幕温度达到$value℃';
  }

  @override
  String get tempThreshold => '温度阈值（℃）';

  @override
  String get temperatureTitle => '温度推送';

  @override
  String get noRules => '暂无温度规则，点击右上角 + 添加';

  @override
  String get disable => '停用';

  @override
  String get temperatureNotifyEnabled => '温度推送通知';

  @override
  String get textMenuShare => '分享';

  @override
  String offlineCacheDropped(int n) {
    return '离线期间缓存已满，$n 条最旧通知没能进历史记录';
  }

  @override
  String get fnthinkPush => '幻念推送';

  @override
  String get fnthinkSettingsTitle => '幻念推送设置';

  @override
  String get fnthinkReceive => '接收推送';

  @override
  String get fnthinkReceiveDesc => '开启后才会从服务器收取消息；关闭后既不发送也不接收';

  @override
  String get fnthinkChannelDisclosure =>
      '收到的推送是否响铃、振动或显示横幅，由系统通知设置中的「幻念推送 · 收件」渠道决定。本机已按最高档创建该渠道：重要性为紧急（显示横幅）、声音为系统默认通知音、振动已开启。部分厂商系统（如小米）在该层之上另有按应用管理的悬浮窗与锁屏开关，需在系统设置中核对。';

  @override
  String get fnthinkOpenChannelSettings => '打开系统渠道设置';

  @override
  String get fnthinkConsentTitle => '允许通知内容经服务器中转？';

  @override
  String get fnthinkConsentMsg =>
      '① 不用幻念推送：全部逻辑在本机完成，通知内容不经过任何服务器。\n② 只用本软件转发通知：同样不经过服务器，服务器不收集任何通知内容。\n③ 使用幻念推送：消息需经服务器中转才能送到这台手机 —— 未送达期间正文在服务端加密暂存，最长 7 天，送达或到期立即删除；配对口令与身份私钥不上传，审计只保存元数据（不含正文）。';

  @override
  String get fnthinkConsentAgree => '我已了解并同意';

  @override
  String get fnthinkConsentGranted => '已同意内容经服务器中转';

  @override
  String get fnthinkConsentPending => '尚未同意中转：经服务器的收发均已停止';

  @override
  String get fnthinkConsentNotGranted => '本机尚未同意内容经服务器中转，本次操作未执行';

  @override
  String get fnthinkRelayConsentSection => '经服务器中转';

  @override
  String get fnthinkConsentRevoke => '撤销同意';

  @override
  String get fnthinkConsentRevokeTitle => '要撤销「经服务器中转」的同意吗？';

  @override
  String get fnthinkConsentRevokeMsg =>
      '撤销后，以下功能立即停止：经服务器的收发（收货循环下一轮起中断）、远程控制、接入端点的增/改/删、发起与批准配对、幻念通道的创建/启用与发送、以及携带正文的测试。非浸入探针不受影响（仅读取能力级，不触发实际投递）。配对名单、接入端点、幻念通道配置、收发历史与配对记录不会删除。恢复需重新完成同意流程';

  @override
  String get fnthinkConsentRevokeDone => '已撤销：经服务器的收发与远程控制均不可用，配置与历史记录未删除。';

  @override
  String get fnthinkConsentGateTitle => '此操作需先将内容交由服务器中转';

  @override
  String fnthinkConsentGateMsg(Object action) {
    return '「$action」须先获得「内容经服务器中转」授权：幻念收发、接入端点管理、配对关系与通道发送均经中转服务器处理，使用前须先行同意。授权入口位于「幻念推送 → 接收推送」页（授权前可阅读完整说明）。完成授权后请返回此处，再次点击即可继续。';
  }

  @override
  String get fnthinkConsentGateGo => '前往该页授权';

  @override
  String get fnthinkConsentGateThisStep => '本操作';

  @override
  String get fnthinkSendTargetGoPair => '前往配对';

  @override
  String get fnthinkSendTargetTitle => '发送目标';

  @override
  String get fnthinkSendTargetDevices => '已配对的设备';

  @override
  String get fnthinkSendTargetNoPeer =>
      '本机尚未配对任何设备，请先在「设备配对」页完成配对，或在下方选择一条 Webhook 通道。';

  @override
  String get fnthinkSendTargetWebhooks => 'Webhook 通道';

  @override
  String get fnthinkSendTargetWebhookEmpty =>
      '尚无已启用的 Webhook 通道，请在「幻念通道」页创建一条（填写接入端点的推送地址并保持启用）。';

  @override
  String get fnthinkSendTargetWebhookOnlyForNotice =>
      '远程指令只能发送至已配对设备；Webhook 通道没有配对关系，也没有档位授权。如需发送至通道，请切换回「一条通知」。';

  @override
  String get fnthinkSendNoticeVsCommand =>
      '「一条通知」是让对端查看一段内容（无需任何授权，也不执行动作）；「一条远程指令」是让对端执行一个动作（需要配对关系与档位授权，最高档位还需通过延时确认）。';

  @override
  String get fnthinkHubSendDesc => '发送至已配对设备，或发送至 Webhook 通道；与「远程指令」不属于同一层级';

  @override
  String get fnthinkHealthNever => '协议面未知：暂无协议请求读数';

  @override
  String get fnthinkHealthReachable => '协议面就绪：最近一次幻念请求成功';

  @override
  String get fnthinkHealthUnreachable => '协议面不可用：最近一次幻念请求失败';

  @override
  String get fnthinkPollGatewayTimeout => '网关超时（源站 25 秒内没有响应）';

  @override
  String get fnthinkPollRoundInProgress => '上一轮还在跑，本次跳过';

  @override
  String fnthinkPollGatewayUnavailable(String code) {
    return '网关暂时不可用（HTTP $code）';
  }

  @override
  String get fnthinkReachabilityLabel => '服务可达';

  @override
  String get fnthinkProtocolLabel => '协议面';

  @override
  String fnthinkReachabilityOk(int n, String ago) {
    return '可达 · $n ms（$ago）';
  }

  @override
  String fnthinkReachabilityFailed(String ago) {
    return '不可达（$ago）';
  }

  @override
  String fnthinkReachabilityStale(String ago) {
    return '上次探测于 $ago，当前未知';
  }

  @override
  String get fnthinkReachabilityNever => '尚未探测';

  @override
  String fnthinkProtocolReadyShort(String ago) {
    return '就绪 · 最近一次幻念请求成功（$ago）';
  }

  @override
  String fnthinkProtocolFailedShort(String ago) {
    return '不可用 · 最近一次幻念请求失败（$ago）';
  }

  @override
  String fnthinkProtocolStale(String ago) {
    return '上次成功于 $ago，当前未知';
  }

  @override
  String get fnthinkProtocolNever => '未知 · 暂无协议请求读数';

  @override
  String get fnthinkProtocolUnverified => '未验证 · 服务有响应，但尚无成功的协议请求';

  @override
  String get fnthinkStatusRunning => '正在收取';

  @override
  String get fnthinkStatusIdle => '当前未运行';

  @override
  String get fnthinkReceiveNow => '立即收取';

  @override
  String get fnthinkReceiveDisabled => '接收功能未开启，本次操作未执行';

  @override
  String get fnthinkReceiveSkipped => '上一轮尚未结束，本轮结果将在其结束后显示';

  @override
  String get fnthinkIdentitySection => '本机身份';

  @override
  String get fnthinkAddressCode => '本机地址码';

  @override
  String get fnthinkAddressCodeNone => '还没生成（第一次挂口令或开始接收时生成）';

  @override
  String get fnthinkCopy => '复制';

  @override
  String get fnthinkCopied => '已复制到剪贴板';

  @override
  String get fnthinkResetCode => '重置地址码';

  @override
  String get fnthinkResetCodeTitle => '更换地址码？';

  @override
  String get fnthinkResetCodeMsg => '本机地址码将在所有对端白名单中立即失效，原有配对关系全部失效，需重新配对。';

  @override
  String get fnthinkPairingCode => '配对口令';

  @override
  String get fnthinkPairingNone => '现在没挂出口令';

  @override
  String get fnthinkRevokePairing => '撤掉口令';

  @override
  String get fnthinkArmPairing => '挂出一枚新口令';

  @override
  String fnthinkPairingHeld(String n) {
    return '已挂出 $n';
  }

  @override
  String get fnthinkPairingExpireNote => '是否过期、有没有被用掉都由服务器判，这台手机只负责把它挂出来';

  @override
  String get fnthinkPairingPeersHint => '对端需要以下两项：本机地址码与本次一次性口令';

  @override
  String get fnthinkPairingLifecycleActive => '这一枚看起来还有效：对端现在可以用它配对';

  @override
  String get fnthinkPairingLifecycleConsumed => '这一枚已经用过了：成功配对过一次，它不会再被接受';

  @override
  String get fnthinkPairingLifecycleExpired => '这一枚看起来过期了：请重新生成';

  @override
  String get fnthinkPairingLifecycleNotPublished => '这一枚已失效：服务器没收到它，对端配上不去';

  @override
  String get fnthinkPairingLifecycleUnknown => '这一枚的时限读数不完整（不知道挂了多久/服务器收没收到）';

  @override
  String get fnthinkPairingRegenerate => '重新生成';

  @override
  String get fnthinkIdentityKey => '身份密钥';

  @override
  String get fnthinkKeystoreOn => '由系统密钥库保管';

  @override
  String get fnthinkKeystoreOff => '只存在本机文件（这台设备没有可用的密钥库）';

  @override
  String get fnthinkKeystoreUnknown => '取不到身份 —— 这是身份问题，不是网络问题';

  @override
  String get fnthinkServerSection => '服务器';

  @override
  String get fnthinkHost => '服务地址';

  @override
  String get fnthinkHostEditTitle => '修改服务地址';

  @override
  String get fnthinkHostDesc => '仅填写主机名（可含端口）；scheme 由协议确定，无需填写 https://';

  @override
  String get fnthinkHostReset => '恢复默认';

  @override
  String get fnthinkHostSwitch => '切换服务';

  @override
  String get fnthinkHostProbeNow => '测量延迟';

  @override
  String get fnthinkHostProbing => '正在测量延迟…';

  @override
  String get fnthinkHostRegionInternational => '海外（洛杉矶）';

  @override
  String get fnthinkHostRegionMainland => '大陆（成都）';

  @override
  String get fnthinkHostNoCandidates => '协议契约未声明可选的服务地址';

  @override
  String get fnthinkHostUpdateNote => '检查更新使用独立链路，不随此处切换。';

  @override
  String get fnthinkContractVersionMismatch => '服务器上的协议版本较旧，部分消息将无法发送';

  @override
  String get fnthinkContractVersionUnreadable => '无法判断服务器协议版本是否为最新';

  @override
  String get fnthinkBoundary => '开着接收之后，通知内容会经过服务器中转：服务器那一侧看得见消息正文与元数据。';

  @override
  String fnthinkContractUnavailable(String reason) {
    return '无法读取随包协议契约，本页暂时无法修改任何设置：$reason';
  }

  @override
  String get fnthinkDirForwarded => '转发';

  @override
  String get fnthinkDirInbox => '收件（幻念）';

  @override
  String get fnthinkInboxEmpty => '还没有收到过消息';

  @override
  String get fnthinkMessageGoneFromHistory => '这一条已经不在本机的收件历史里（可能被保留策略清掉了）';

  @override
  String get fnthinkInboxEntry => '幻念收件';

  @override
  String fnthinkInboxUnread(int n) {
    return '未读 $n 条';
  }

  @override
  String get fnthinkPairingAcked => '服务器已收到这枚口令，对端现在可以拿它来配';

  @override
  String fnthinkPairingLocalOnly(String reason) {
    return '只有这台设备记下了它，服务器还没收到（$reason）。对端现在扫这串会失败';
  }

  @override
  String get fnthinkPairingAckUnknown => '这台没有问过服务器收没收到 —— 重新挂一枚才能确认';

  @override
  String get fnthinkOutcomeDone => '这一步做完了';

  @override
  String get fnthinkOutcomeFailed => '这一步没做成';

  @override
  String get fnthinkPairRequests => '待你确认的配对请求';

  @override
  String fnthinkPairRequestLine(String peer, String level, String at) {
    return '$peer 请求与本机配对，请求档位为 $level · $at';
  }

  @override
  String get fnthinkPairRefresh => '向服务器查询对端答复';

  @override
  String get fnthinkPairRefreshQuiet => '已向服务器查询，对端暂无新结论';

  @override
  String get fnthinkPairRequestsSent => '本机发起的配对请求';

  @override
  String fnthinkPairSentLine(
    String peer,
    String level,
    String status,
    String at,
  ) {
    return '发送至 $peer · 请求档位 $level · $status · $at';
  }

  @override
  String get fnthinkPairStatePending => '等待对端答复';

  @override
  String get fnthinkPairStateApproved => '对端已同意';

  @override
  String get fnthinkPairStateDenied => '对端已拒绝';

  @override
  String get fnthinkPairStateExpired => '配对口令已过期';

  @override
  String fnthinkPairStateUnknown(String status) {
    return '未知状态：$status';
  }

  @override
  String get fnthinkPairHistoryTitle => '配对历史';

  @override
  String fnthinkPairHistoryWants(String level) {
    return '请求档位 $level';
  }

  @override
  String get fnthinkPairHistoryOutgoing => '本机发起';

  @override
  String get fnthinkPairHistoryIncoming => '对端请求';

  @override
  String agoMinutes(int n) {
    return '$n 分钟前';
  }

  @override
  String agoHours(int n) {
    return '$n 小时前';
  }

  @override
  String agoSeconds(int n) {
    return '$n 秒前';
  }

  @override
  String fnthinkHubPeersWaiting(int n) {
    return '$n 条待您答复';
  }

  @override
  String fnthinkHubPeersOutgoing(int n) {
    return '$n 条仍在等待对端答复';
  }

  @override
  String fnthinkPairWillGrant(String level) {
    return '本机本次最多可授予 $level；更高档位需在本机确认';
  }

  @override
  String fnthinkPairUnknownLevel(String level) {
    return '对端所报档位「$level」不在本机档位表中，无法同意，仅可拒绝';
  }

  @override
  String get fnthinkPairApprove => '同意';

  @override
  String get fnthinkPairDeny => '拒绝';

  @override
  String get fnthinkPairApproveOutbound => '同意时同时将其设为外发目标';

  @override
  String get fnthinkPairApproveOutboundDesc =>
      '勾选后，本机将立即完成两项：勾选名单项，并创建一条目标为该设备的通道。';

  @override
  String get fnthinkPairChannelIdLabel => '本机哪一条通道（号）';

  @override
  String get fnthinkPairApprovedOneWay =>
      '两台设备现已可互相发送通知：本次确认写入了两段授权，分别保存在被投设备的名单中。尚未完成的是逐项权限：L2 动作与 L3 设置需由对端在其同意界面上自行勾选，本机无法代为操作。';

  @override
  String get fnthinkPairAskTitle => '同意配对？';

  @override
  String fnthinkPairAskMsg(String peer, String level) {
    return '将 $peer 加入本机名单并授予 $level。同意后，该设备可向本机推送消息。';
  }

  @override
  String fnthinkPairApproved(String peer, String level) {
    return '已同意 $peer，服务端记录档位为 $level';
  }

  @override
  String fnthinkPairDenied(String peer) {
    return '已拒绝 $peer';
  }

  @override
  String fnthinkPairKeySwapped(String peer) {
    return '$peer 的地址码上次使用另一把公钥，本机未作任何修改。该设备可能已重建身份，也可能有人冒用该地址码';
  }

  @override
  String fnthinkPairFailed(String reason) {
    return '未获同意：$reason';
  }

  @override
  String get fnthinkPairNoGrantedLevel => '服务端已接受，但未返回记录的档位，本机名单未写入';

  @override
  String get fnthinkPeerStoreUnavailable => '服务端已接受，但本机未接入名单存储，名单未写入';

  @override
  String get fnthinkPeerWriteFailed => '服务端已接受，但本机写入名单失败，名单未写入';

  @override
  String get fnthinkPeersTitle => '设备配对';

  @override
  String get fnthinkSenderDisplayLabel => '收件中发送人的显示方式';

  @override
  String get fnthinkSenderDisplayAliasFirst => '备注优先';

  @override
  String get fnthinkSenderDisplayDeviceName => '设备名';

  @override
  String get fnthinkSenderDisplayBoth => '两者均显示';

  @override
  String get fnthinkHubTitle => '幻念推送';

  @override
  String get fnthinkHubDesc => '发送去向：设备绑定、发起推送与接收设置均位于此区域。';

  @override
  String get fnthinkHubPeersDesc => '显示已配对设备数量，可向设备发送消息，也可撤销指定设备。';

  @override
  String get fnthinkHubReceiveDesc => '接收消息、轮询间隔，以及对端可让本机执行的操作（远程执行），均在此处配置。';

  @override
  String get fnthinkHubSettingsDesc => '本机身份信息（地址码、配对口令、身份密钥），以及所连接的服务器。';

  @override
  String get fnthinkChannelTitle => '幻念通道';

  @override
  String get fnthinkChannelDesc => '本机作为发送方时的转发目标：收到的通知将按此处配置转发。';

  @override
  String get fnthinkPushChannel => '幻念推送通道';

  @override
  String get fnthinkChannelNote =>
      '徽标记录的是最近一次「仅探测/探测并保存」的结果，并非自动探测：幻念通道无法在不打扰对端的情况下判断连通性。';

  @override
  String get fnthinkHubChannelsDesc => '本机作为发送方时的转发目标。';

  @override
  String get fnthinkChannelEmpty => '尚无幻念通道。新建通道后，本机收到的通知将转发至指定目标。';

  @override
  String get fnthinkChannelDeleteAskTitle => '删除此通道？';

  @override
  String fnthinkChannelDeleteAskMsg(Object name) {
    return '删除后，本机将不再向「$name」转发。';
  }

  @override
  String get fnthinkChannelDeleted => '通道已删除';

  @override
  String get fnthinkChannelName => '名称';

  @override
  String get fnthinkChannelNameHint => '为此通道命名';

  @override
  String get fnthinkChannelNameEmpty => '名称不能为空';

  @override
  String get fnthinkChannelTargetKind => '转发目标';

  @override
  String get fnthinkChannelTargetKindDevice => '一台已勾选的设备';

  @override
  String get fnthinkChannelTargetKindWebhook => '一个 Webhook 地址';

  @override
  String get fnthinkChannelTarget => '目标';

  @override
  String get fnthinkChannelTargetEmpty => '目标不能为空';

  @override
  String get fnthinkChannelTargetBadScheme => 'Webhook 目标必须以 https:// 开头';

  @override
  String get fnthinkChannelNoTargetPicked => '尚未勾选任何设备，请先前往「设备配对」勾选一台。';

  @override
  String get fnthinkChannelTargetNotChecked => '此设备尚未勾选为转发目标';

  @override
  String get fnthinkChannelTargetPick => '从名单中选择一台设备';

  @override
  String get fnthinkChannelEnabled => '启用这条通道';

  @override
  String get fnthinkChannelRole => '主备';

  @override
  String get fnthinkChannelProbeOnly => '仅探测';

  @override
  String get fnthinkChannelProbeAndSave => '探测并保存';

  @override
  String get fnthinkChannelProbeUnavailable =>
      'Webhook 目标无法从本页测试（发送实现在原生侧），因此仅保存、不探测。';

  @override
  String get fnthinkChannelProbeWhy => '将实际向对端发送一条消息（此通道族无不打扰对端的探针），对端会收到该消息。';

  @override
  String get fnthinkChannelProbeTitle => '通道测试';

  @override
  String get fnthinkChannelProbeBody => '这是一条从对端设备通道设置中发出的测试消息。';

  @override
  String fnthinkChannelProbeOk(Object ms) {
    return '已发送（$ms 毫秒），徽标记录的就是本次结果。';
  }

  @override
  String get fnthinkChannelProbeRejected => '对端未接受此消息（无报错，但状态不是 accepted）。';

  @override
  String fnthinkChannelProbeFail(Object reason) {
    return '未发送：$reason';
  }

  @override
  String get fnthinkChannelSave => '保存';

  @override
  String get fnthinkChannelSaved => '已保存';

  @override
  String get fnthinkChannelNewTitle => '新建幻念通道';

  @override
  String fnthinkChannelSaveFailed(Object reason) {
    return '没存上：$reason';
  }

  @override
  String get fnthinkPeerForwardToggle => '本机 → 对端 · 可接收本机转发的通知';

  @override
  String get fnthinkPeerForwardChannelMade => '已为对端创建通道，三项条件均已具备';

  @override
  String get fnthinkPeerForwardChannelKept => '已存在通往该对端的通道，未重复创建';

  @override
  String fnthinkPeerPresenceOnline(String ago) {
    return '在线 · 上次收取 $ago';
  }

  @override
  String fnthinkPeerPresenceOffline(String ago) {
    return '离线 · 上次收取 $ago';
  }

  @override
  String get fnthinkPeerPresenceOfflineQueued =>
      '离线只影响到达时间：发给它的消息会排在服务器，等它上线再投。';

  @override
  String get fnthinkPeerPresenceUnknown => '未知 · 还没上过线';

  @override
  String get fnthinkPeerPresenceNotShared => '对方没有共享在线状态';

  @override
  String get fnthinkPeerPresenceLoading => '正在读取对端状态…';

  @override
  String fnthinkPeerPresenceFailed(String reason) {
    return '这次没拿到对端状态（$reason）';
  }

  @override
  String get fnthinkPeerPresenceMissingRoute =>
      '服务器没有对端状态读口（服务端版本较旧）；需要部署新版 server/ 与契约。';

  @override
  String get fnthinkSelfCheck => '自检';

  @override
  String get fnthinkSelfChecking => '自检中…';

  @override
  String get fnthinkSelfCheckPresenceOk => '对端状态读取接口正常';

  @override
  String fnthinkSelfCheckHealth(Object verdict) {
    return '服务可达；契约版本：$verdict';
  }

  @override
  String get fnthinkSelfCheckHealthUnknown => '服务可达；协议契约版本不可读';

  @override
  String get fnthinkPeerForwardHint => '勾选后，本机收到的通知才会转发至该对端。';

  @override
  String fnthinkPeerLine(String level, String at) {
    return '对端 → 本机 · 已授予 $level · $at';
  }

  @override
  String get fnthinkPeersEmpty => '尚未配对任何设备';

  @override
  String fnthinkPeersError(String reason) {
    return '无法读取名单（$reason）；显示失败并不表示没有已配对设备';
  }

  @override
  String get fnthinkPeersBoundary =>
      '此处记录本机已同意的设备。撤销时先由服务器收回授权，本机对应行随后消失；已收到的通知不会被删除。对端授予本机的许可，需由对端自行撤销。';

  @override
  String get fnthinkPeerRevoke => '撤销';

  @override
  String get fnthinkPeerSend => '发送一条';

  @override
  String get fnthinkPeerRename => '改名';

  @override
  String get fnthinkPeerRenameTitle => '为该设备设置名称（仅本机可见）';

  @override
  String fnthinkPeerRenameSaved(String alias) {
    return '名称已改为 $alias';
  }

  @override
  String get fnthinkPeerRenameCleared => '名称已清除';

  @override
  String get fnthinkPeerRenameGone => '该设备已不在名单中';

  @override
  String get fnthinkPeerDetailTitle => '设备详情';

  @override
  String get fnthinkPeerPermissions => '权限';

  @override
  String get fnthinkPeerPermissionsShort => '允许对端在本机执行的操作；修改后请点击保存。';

  @override
  String get fnthinkPeerPermissionsHelp =>
      '本页仅修改「对端 → 本机」方向的授权：保存后服务端立即按新清单判定，本机也同时按新清单放行或拒绝。希望在对方设备上执行的操作，须由对方自行修改。服务器版本较旧时将直接提示无权限修改入口。';

  @override
  String get fnthinkPeerGrantImpact => '允许后，对方可以在这台设备上执行这一项。';

  @override
  String get fnthinkPeerGrantAdvanced => '高级项（默认收起）';

  @override
  String fnthinkPeerGrantLevelNote(String level) {
    return '档位仍为 $level；本页仅修改逐项清单。';
  }

  @override
  String get fnthinkPeerGrantSave => '保存权限';

  @override
  String get fnthinkPeerGrantNoChange => '无改动';

  @override
  String get fnthinkPeerGrantSaved => '权限已保存；服务端与这台设备都已按新清单执行。';

  @override
  String fnthinkPeerGrantFailed(String reason) {
    return '没保存：$reason';
  }

  @override
  String get fnthinkPeerGrantMissingRoute => '服务器版本旧，没有改权限的入口。先升级服务端，或重新配对。';

  @override
  String get fnthinkPeerGrantNoRelationship => '服务器上已经没有这条配对关系，请重新配对。';

  @override
  String get fnthinkPeerGrantLocalNotWritten =>
      '服务器已按新清单执行，但这台本机的名单没写成；请重新打开这一页确认。';

  @override
  String get fnthinkPairPeer => '与另一台设备配对';

  @override
  String get fnthinkPairPeerTitle => '向该设备发起配对';

  @override
  String get fnthinkPairPeerTargetHint => '对端地址码（那台设备上显示的那一串）';

  @override
  String get fnthinkPairPeerCodeHint => '它刚挂出的一次性口令';

  @override
  String get fnthinkPairPeerCodeNote =>
      '这串口令只活在这一次输入里：这台不留副本、不写日志、不进数据库。关掉这一层就得让对方重新挂一枚。';

  @override
  String fnthinkPairPeerLevelNote(String level) {
    return '这里只列到 $level 为止：更高那一档要在那台设备上本地确认（锁屏或生物认证），远程把它请求过去只会被整条拒。';
  }

  @override
  String get fnthinkPairPeerSubmit => '发过去';

  @override
  String get fnthinkPairPeerIncomplete => '地址码和口令都填了才发得出去';

  @override
  String get fnthinkPairPeerPendingNote =>
      '提交后仅在对端新增一条待确认请求：是否同意由对端决定，本机名单中的对应行将在下一轮收取后出现。';

  @override
  String fnthinkPairPeerSubmitted(String id, String status) {
    return '已发送到服务器，等待对方确认（请求 $id · 状态 $status）。这台还没拿到任何许可。';
  }

  @override
  String get fnthinkPairPeerNotConsented =>
      '这台还没同意过「通知内容经服务器中转」，这一发一个字节都没出去 —— 先到上面翻开同意那一格';

  @override
  String get fnthinkPairPeerNoSignature =>
      '这一发签不出来（本机拿不到那把身份密钥），一个字节都没出去 —— 到上面重置三件套';

  @override
  String get fnthinkPairPeerTransportError =>
      '服务端未在预期窗口内响应。本条指令可能未送达或响应在回途中丢失。请先核对对端的待确认列表后再重试，单枚配对口令仅一次有效';

  @override
  String get fnthinkPairPeerUnsigned => '服务器没认这枚签名：本机身份还没登记，或那把公钥与登记的那枚已经不是同一把';

  @override
  String get fnthinkPairPeerRateLimited => '问得太频繁，这一发被挡回 —— 等一会儿再点一次，连点不会更快';

  @override
  String get fnthinkPairPeerReplayed => '这一发被当成重复提交（nonce 撞了）—— 让对方重新挂一枚口令';

  @override
  String get fnthinkPairPeerNeedsCalibration =>
      '本机时钟与服务器差得太远 —— 先点一次「立即收取」让它校上时，再发这一发';

  @override
  String fnthinkPairPeerFailed(String reason) {
    return '没交上去：$reason';
  }

  @override
  String get fnthinkPairPeerPrefilled => '这两格是刚才那条链接里读出来的，不是你打的 —— 先确认那是你要配的那台';

  @override
  String get fnthinkPairLinkRejected =>
      '本机无法使用此链接：该链接不是幻念推送配对链接，或协议版本不匹配。请回到该设备重新生成配对口令后再试';

  @override
  String fnthinkSendSheetTitle(String peer) {
    return '发送至 $peer';
  }

  @override
  String get fnthinkSendTitleHint => '标题（可留空）';

  @override
  String get fnthinkSendBodyHint => '正文';

  @override
  String get fnthinkSendTierLabel => '本次发送内容';

  @override
  String get fnthinkSendTierNotice => '一条通知';

  @override
  String get fnthinkSendTierCommand => '一条远程指令';

  @override
  String get fnthinkSendTierNote => '两档为同一条出站请求的两种载荷；是否执行由对端判定。';

  @override
  String get fnthinkSendNeedsPeer => '尚未选择目标设备';

  @override
  String get fnthinkSendEnvelopeHelpTitle => '标题随正文信封传输';

  @override
  String get fnthinkSendEnvelopeNote =>
      '设备通道的标题随正文信封传输：签名数据中没有独立标题字段，仅端点两种形态具备该字段。收件人看到的标题来自这段正文。';

  @override
  String get fnthinkSendEmptyBody => '正文为空时不发送，对端只会收到空内容';

  @override
  String get fnthinkSendSubmit => '发送';

  @override
  String fnthinkSendSent(String id) {
    return '已提交服务端排队（$id）。送达状态以该设备的回执为准。';
  }

  @override
  String fnthinkSendEvicted(int count) {
    return '另有 $count 条消息因超出每设备上限被移除。';
  }

  @override
  String get fnthinkSendRejectedUnsigned => '签名无法识别：本机身份与服务端记录不一致（可能需要重新配对）';

  @override
  String get fnthinkSendRejectedCapability => '对端未授予本档权限，或双方尚未配对';

  @override
  String get fnthinkSendReplayed => '触发去重窗口：请稍后重新发送，以免重复触发';

  @override
  String get fnthinkSendNeedsCalibration => '时间未校准：请先执行一次「立即收取」，再发送';

  @override
  String fnthinkSendRateLimited(int seconds) {
    return '本分钟发送次数过多，请在 $seconds 秒后重试';
  }

  @override
  String get fnthinkSendTransportError => '无法连接服务端，本次消息未发送';

  @override
  String get fnthinkSendSigningUnavailable => '本机签名不可用：请在上方重置凭据三件套，或重新配对';

  @override
  String fnthinkSendPrecondition(String reason) {
    return '本机尚未就绪：$reason';
  }

  @override
  String get fnthinkSendBadInput => '正文包含无法发送的字符，本次消息未发送';

  @override
  String get fnthinkSendUnparseable => '服务端已接收但未返回编号，无法追踪本次消息';

  @override
  String get fnthinkSendBoundary =>
      '「发送一条」走设备签名通道，只能发送至名单中的设备；发送成功不等同于送达，仅当该设备实际显示并返回回执后，方可视为送达。';

  @override
  String get fnthinkRevokeAskTitle => '撤销这台设备的推送许可？';

  @override
  String fnthinkRevokeAskMsg(String peer) {
    return '撤销后，$peer 将无法再向本机推送；已收到的通知保留。此次仅终止该方向，本机授予对端的推送权限不受影响（需在对端自行撤销）。此操作需由服务器收回授权，离线时无法完成。';
  }

  @override
  String fnthinkRevoked(String peer) {
    return '已撤销 $peer：该设备此后无法向本机推送';
  }

  @override
  String fnthinkRevokeAlreadyGone(String peer) {
    return '服务器已不存在 $peer 的授权（撤销具有幂等性，目标已达成）';
  }

  @override
  String get fnthinkRevokeStoreUnavailable => '服务器已撤销，但本机未接入名单删除功能，该行仍保留';

  @override
  String get fnthinkRevokeRowRemains => '服务器已撤销，但本机删除该行失败，该行仍保留';

  @override
  String fnthinkRevokeFailed(String reason) {
    return '撤销失败（$reason）；名单中该行仍保留，反映当前实际状态';
  }

  @override
  String get fnthinkEndpointTitle => '接入端点（供 NAS / 脚本使用）';

  @override
  String get fnthinkEndpointWhy =>
      '第三方平台向本机推送通知所用的长期口令。服务端仅保存摘要；下方口令仅在本次显示，离开页面后无法再次查看。';

  @override
  String get fnthinkEndpointEntryDesc => '供 NAS、脚本、监控等外部服务接入的长期口令。多数用户无需修改此项。';

  @override
  String fnthinkEndpointCap(int max) {
    return '本机最多可创建 $max 个端点；达到上限后仅拒绝新建，不会挤占正在使用的端点。';
  }

  @override
  String fnthinkEndpointCountOf(int n, int max) {
    return '本机已有 $n 个端点（上限 $max）。';
  }

  @override
  String get fnthinkEndpointNeverUsed => '从未接收';

  @override
  String fnthinkEndpointLastUsed(String ago) {
    return '上次接收于 $ago';
  }

  @override
  String get fnthinkEndpointLastUsedUnknown => '未报告（对端版本较旧）';

  @override
  String get fnthinkEndpointCreate => '创建端点';

  @override
  String get fnthinkEndpointDefaultName => '在 App 内创建';

  @override
  String fnthinkEndpointId(String id) {
    return '端点 ID：$id';
  }

  @override
  String fnthinkEndpointSecret(String secret) {
    return '口令：$secret';
  }

  @override
  String get fnthinkEndpointOnce => '此口令仅显示一次，请立即复制；此后只能重新创建端点（旧口令无法找回）。';

  @override
  String get fnthinkEndpointTutorial => '调用方式';

  @override
  String get fnthinkEndpointPostWhy => '令牌置于请求头而非 URL，不会出现在反代访问日志中。可直接复制完整请求示例';

  @override
  String get fnthinkEndpointGetWarning =>
      'GET 形态仅用于展示结构：口令位于 URL 路径段，会进入反向代理访问日志。在本站日志脱敏配置完成前，此方式不提供可整行复制的真实口令；如需立即使用，请采用上方的 POST 方式。';

  @override
  String get fnthinkEndpointCopyPushUrl => '复制推送地址';

  @override
  String get fnthinkEndpointPushUrlWhy =>
      '仅需粘贴到其他软件的单个 Webhook 输入框时，此方式将口令放在 URL 最后一段，直接 POST 即可，无需请求头。⚠ 口令进入 URL 后会进入反向代理访问日志；在本站日志脱敏配置完成前，能够发送请求头的客户端应优先使用上方的 Bearer 方式。';

  @override
  String fnthinkEndpointFieldAlias(String title, String body) {
    return '不同平台的字段名存在差异，取第一个非空值：标题依次尝试 $title；正文依次尝试 $body。携带 type／level／item 等字段不影响投递，一律按普通通知处理（令牌仅限投递通知，携带 action／setting 的动作请求将被明确拒绝）。投递目标不可由请求指定 —— 仅限本机接收';
  }

  @override
  String get fnthinkEndpointCopyId => '复制端点 ID';

  @override
  String get fnthinkEndpointCopySecret => '复制口令';

  @override
  String get fnthinkEndpointCopyCommand => '一键复制这条命令';

  @override
  String get fnthinkEndpointCopyHint =>
      '「一键复制」仅在创建（或轮换）后的一段时间内可用：口令只保存在当前页面内存中，离开后返回将无法再填入；如需再次复制，只能轮换口令。';

  @override
  String fnthinkEndpointFailed(String reason) {
    return '端点创建失败（$reason）；服务端未返回口令，因此不存在「已创建但无法复制」的状态。';
  }

  @override
  String get fnthinkEndpointListPending =>
      '尚未查询本机端点数量。「没有」与「尚未查询」含义不同，因此此处不列出任何内容，也不表示没有端点。';

  @override
  String get fnthinkEndpointListRead => '查询本机已创建的端点';

  @override
  String fnthinkEndpointRowNamed(String name, String id) {
    return '「$name」· $id';
  }

  @override
  String fnthinkEndpointRowUnnamed(String id) {
    return '未命名 · $id';
  }

  @override
  String get fnthinkEndpointUsable => '正在接收';

  @override
  String fnthinkEndpointNotUsable(String status) {
    return '已停止接收（服务端记录状态为「$status」）';
  }

  @override
  String get fnthinkEndpointNone => '查询完成：本机名下没有接入端点。如需使用，请点击上方按钮创建。';

  @override
  String fnthinkEndpointListFailed(String reason) {
    return '本次查询失败（$reason）；「查询失败」不等于「没有」，因此此处仍不列出任何内容，也不表示没有端点。';
  }

  @override
  String fnthinkEndpointListCount(int n) {
    return '本机现有 $n 个端点';
  }

  @override
  String get fnthinkEndpointRevoke => '关闭此端点';

  @override
  String get fnthinkEndpointRevokeAskTitle => '关闭此端点？';

  @override
  String fnthinkEndpointRevokeAskMsg(String id) {
    return '关闭「$id」后，持有该口令的调用方将立即被拒绝。口令无法找回：服务端仅保存摘要，如需继续使用须重新创建。';
  }

  @override
  String fnthinkEndpointRevoked(String id) {
    return '已关闭「$id」：该端点不再接收。记录仍保留，列表中可看到其已停止。';
  }

  @override
  String fnthinkEndpointRevokeAlreadyGone(String id) {
    return '「$id」此前已停止接收；本次操作已达到目标，并非失败。';
  }

  @override
  String fnthinkEndpointRevokeFailed(String reason) {
    return '此端点未能关闭（$reason）；它仍在接收，列表显示服务端记录。';
  }

  @override
  String get fnthinkEndpointRotate => '轮换口令';

  @override
  String get fnthinkEndpointRotateAskTitle => '轮换此端点的口令？';

  @override
  String get fnthinkEndpointRotateAskMsg =>
      '轮换后将生成一个新口令，仅显示一次。旧口令可使用至宽限期结束（下方会显示具体时间），此后持有旧口令的调用方将被拒绝。';

  @override
  String fnthinkEndpointRotated(String id) {
    return '已轮换「$id」的口令；新口令仅在上方显示一次。';
  }

  @override
  String fnthinkEndpointRotateGrace(String until) {
    return '旧口令可使用至 $until。';
  }

  @override
  String fnthinkEndpointRotateNotRotated(String id) {
    return '「$id」已停止接收，因此未轮换口令；轮换不会恢复该端点，如需继续使用请重新创建。';
  }

  @override
  String fnthinkEndpointRotateFailed(String reason) {
    return '口令轮换失败（$reason）';
  }

  @override
  String get fnthinkPresenceLive => '后台常驻收取中（长轮询，有消息时立即返回）';

  @override
  String get fnthinkPresenceLiveNoLock => '后台常驻收取中（长轮询，但系统未授予唤醒锁）';

  @override
  String fnthinkPresenceNext(String time, int seconds) {
    return '下次自动唤醒：$time（每 $seconds 秒）';
  }

  @override
  String fnthinkPresenceStreamHealthy(int seconds) {
    return '实时唤醒已连接 · 兜底间隔 $seconds 秒';
  }

  @override
  String fnthinkPresenceNextNoCadence(String time) {
    return '下次自动唤醒：$time（间隔未知）';
  }

  @override
  String fnthinkPresenceBackoff(int minutes, int seconds) {
    return '限流退避中：约 $minutes 分 $seconds 秒后自动重试（本次为一次性退避，非常规间隔）';
  }

  @override
  String get fnthinkPresenceAsleep => '当前未自动运行（开关已关闭，或尚未同意中转）';

  @override
  String get fnthinkPresenceDead => '自动恢复链已中断：本机不再自动唤醒（开关与同意均仍开启）';

  @override
  String get fnthinkPresencePendingFirstRound => '尚未安排首轮收取（刚启动，首轮完成后将自动安排后续轮次）';

  @override
  String get fnthinkPresenceRecover => '立即恢复';

  @override
  String fnthinkLastRoundAt(Object time) {
    return '上次成功收取：$time';
  }

  @override
  String get fnthinkLastRoundNever => '上次成功收取：暂无记录';

  @override
  String fnthinkPersistFailedWarning(int count) {
    return '上一轮有 $count 条幻念消息未能写入本地收件表，可能已丢失；请检查存储空间后重试';
  }

  @override
  String fnthinkPersistQueuedWarning(int count) {
    return '本机仍有 $count 条幻念消息尚未写入收件表，每轮收取开始前将再次尝试写入';
  }

  @override
  String fnthinkPersistAbandonedWarning(int count) {
    return '有 $count 条幻念消息已停止重试（存放超过 24 小时或已尝试 20 次），不会再自动写入收件表';
  }

  @override
  String get fnthinkPersistAbandonedClear => '清除此计数';

  @override
  String fnthinkWorkChain(
    Object fanoutWork,
    Object presenceWork,
    Object queue,
  ) {
    return '后台任务：收取 $presenceWork · 转发 $fanoutWork · 待发 $queue 条';
  }

  @override
  String fnthinkDiagAlarmAt(String time) {
    return '上次闹钟触发：$time';
  }

  @override
  String get fnthinkDiagAlarmNever => '上次闹钟触发：暂无记录';

  @override
  String fnthinkDiagWorkerAt(String result, String time) {
    return '上次后台轮次：$result · $time';
  }

  @override
  String get fnthinkDiagWorkerNever => '上次后台轮次：暂无记录';

  @override
  String fnthinkDiagPollAt(String time, String status) {
    return '上次 poll：$time · $status';
  }

  @override
  String get fnthinkDiagPollNever => '上次 poll：暂无记录';

  @override
  String fnthinkDiagStreamAt(String time) {
    return '上次 SSE 字节：$time';
  }

  @override
  String get fnthinkDiagStreamNever => '上次 SSE 字节：暂无记录';

  @override
  String fnthinkDiagSystem(
    String doze,
    String battery,
    String powerSave,
    String exact,
  ) {
    return '系统：Doze $doze · 电池优化已忽略 $battery · 省电 $powerSave · 精确闹钟 $exact';
  }

  @override
  String get fnthinkDiagYes => '是';

  @override
  String get fnthinkDiagNo => '否';

  @override
  String get fnthinkScreenKeepalive => '锁屏持续接收（耗电增加）';

  @override
  String get fnthinkScreenKeepaliveDesc => '锁屏后仍保持 CPU 唤醒，可更及时收取消息；耗电会明显增加。';

  @override
  String fnthinkDiagScreenLock(String enabled, String held) {
    return '锁屏持续接收：开关 $enabled · 唤醒锁 $held';
  }

  @override
  String get fnthinkExactAlarmMissing => '精确闹钟未授权：后台收取可能延迟。';

  @override
  String get fnthinkBatteryOptMissing => '未忽略电池优化：系统可能限制后台收取。';

  @override
  String get fnthinkGrantNow => '前往授权';

  @override
  String get fnthinkInboxSelfCheckTitle => '通知渠道自检';

  @override
  String get fnthinkInboxSelfCheckOk => '收件渠道配置正常';

  @override
  String get fnthinkInboxIssueNotificationsOff => '系统通知权限已关闭';

  @override
  String get fnthinkInboxIssueChannelMissing => '收件渠道尚未创建（首次收件时将自动创建）';

  @override
  String get fnthinkInboxIssueNotHigh => '渠道已被系统降级（不再显示横幅）';

  @override
  String get fnthinkInboxIssueNoSound => '渠道未设置声音';

  @override
  String get fnthinkInboxIssueNoVibration => '渠道未开启振动';

  @override
  String get fnthinkInboxIssueLockscreen => '锁屏时不显示';

  @override
  String get fnthinkInboxSelfCheckSettings => '系统设置';

  @override
  String get fnthinkInboxSelfCheckRebuild => '重建渠道';

  @override
  String get fnthinkInboxSelfCheckTest => '发送测试通知';

  @override
  String get fnthinkInboxSelfCheckRefresh => '重新自检';

  @override
  String fnthinkInboxSelfCheckRebuilt(Object id) {
    return '已切换至新的高优先级渠道：$id';
  }

  @override
  String get fnthinkInboxSelfCheckTestSent => '测试通知已发出，请查看锁屏以确认响铃与振动';

  @override
  String get fnthinkInboxSelfCheckTestFailed => '测试通知未能发出（请先检查系统通知权限）';

  @override
  String fnthinkRegisterRateLimited(int minutes, int seconds) {
    return '注册被限流，还要等 $minutes 分 $seconds 秒，到点自动重试';
  }

  @override
  String get fnthinkRegisterDayQuota => '今日注册额度已用完，明日恢复；这台会自动重试（不用你手动点）';

  @override
  String get fnthinkReply => '回复';

  @override
  String get fnthinkResend => '重发';

  @override
  String fnthinkReplyTitle(String title) {
    return '回复：$title';
  }

  @override
  String get fnthinkDirSent => '发出（幻念）';

  @override
  String get fnthinkSentEmpty => '还没有发过。这一档只记本机发出去的（对方收到与否要看回执）';

  @override
  String get fnthinkSender => '发送人';

  @override
  String get fnthinkSentAt => '发送时间';

  @override
  String get fnthinkPeerAckedAt => '对端接收时间';

  @override
  String get fnthinkReceivedAt => '接收时间';

  @override
  String get fnthinkRecipient => '收件人';

  @override
  String get l3SettingsSectionTitle => '对端可以请求的系统设置';

  @override
  String get l3SettingsSectionDesc => '本档中的每一项均需在本机手动确认。未授予的项目仍会显示，仅置灰并说明缺失原因。';

  @override
  String get l3StateMissing => '尚未为本机授权';

  @override
  String get l3StateUnreadable => '无法读取本机状态';

  @override
  String get l3StateUnsupported => '本机不支持此项';

  @override
  String get l3ItemAutostart => '自启动（按厂商）';

  @override
  String get l3ItemMonitoring => '通知转发监听';

  @override
  String get l3ItemCollectInbox => '幻念收件开关';

  @override
  String get l3ItemNotificationReply => '回复通知';

  @override
  String get l3NoteAutostart => '系统只有各厂商的入口，不提供统一读数';

  @override
  String get l3NoteLivesInFnthinkPage => '这一格的开关在「幻念推送」页';

  @override
  String get updateBlockIntegrityFailed => '更新包校验未通过，已阻止安装';

  @override
  String get updateBlockChecksumMismatch => '更新包完整性校验未通过（校验和不匹配），已阻止安装';

  @override
  String get updateBlockUnverifiable => '无法完成安全性校验，已阻止安装';

  @override
  String get updateFailAllUrls => '所有下载地址均失败';

  @override
  String get updateFailDownloaderStart => '无法启动系统下载器';

  @override
  String get updateFailProgressQuery => '获取下载进度失败';

  @override
  String updateFailDownloader(String detail) {
    return '系统下载器下载失败$detail';
  }

  @override
  String updateFailHttpStatus(int code) {
    return '下载失败：HTTP $code';
  }

  @override
  String get updateSizeUnknown => '未知';

  @override
  String get updateNotificationTitle => '通知推送助手更新';

  @override
  String get updateServerTitle => '更新服务器';

  @override
  String get updateServerEntryDesc => '选择检查更新走哪一台（大陆／海外）';

  @override
  String get updateServerShort => '检查更新与下载安装包走哪一台由这一页决定，不影响幻念推送的服务地址。';

  @override
  String get updateServerHelpTitle => '两档各是什么，怎么挑';

  @override
  String get updateServerHelpBody =>
      '软件在两台服务器上发布更新：大陆这台是 notice.fnthink.com，海外这台是 notice.fnthink.top，两台的链接除域名后缀与 CDN 主机名外逐字一致。第一次进入时按你网络的实测时延挑一台，之后每打开这一页就两台各探一次；也可以切到手动钉住某一台——钉住之后谁都不会再替你改。「自动」的含义是跟着最近一次实测走：一直不来这一页，用的就还是上次测出来的那台。安装包的实际下载地址由所选那台自己下发，两台的版本信息是各自维护的两份数据，可能短暂不一致；这种情况下这一页把两台各自报的最新版摆出来，让你自己看出该换哪台。';

  @override
  String get updateServerModeSection => '选择方式';

  @override
  String get updateServerModeAuto => '自动（按实测时延挑）';

  @override
  String get updateServerModeManual => '手动（我钉住一台）';

  @override
  String get updateServerListSection => '两台服务器';

  @override
  String get updateRegionMainland => '大陆';

  @override
  String get updateRegionInternational => '海外';

  @override
  String get updateServerInUse => '当前用这一台';

  @override
  String get updateServerProbeNow => '立即探测';

  @override
  String get updateServerProbing => '正在探测…';

  @override
  String get updateServerAutoUnprobed => '自动档还没测出来过：现在用的是默认那一台。';

  @override
  String get updateServerBothDown => '两台都没探通：暂时用默认那一台，可稍后再探，或手动指定一台。';

  @override
  String get updateServerUnprobed => '还没探过';

  @override
  String get updateServerNoAnswer => '没回话（网络或域名解析不通）';

  @override
  String updateServerHttpStatus(int code) {
    return '这一台回了 HTTP $code';
  }

  @override
  String updateServerLatestLine(String version, String build) {
    return '这台报的最新版：$version+$build';
  }

  @override
  String updateServerCdnLine(String host) {
    return '安装包来自 $host';
  }

  @override
  String updateServerCdnMismatch(Object actual, Object expected) {
    return '注意：安装包来自 $actual，与这一档约定的 $expected 不一致';
  }

  @override
  String get updateServerAnswerEmpty => '通了，但这一台没报出版本信息';

  @override
  String get remoteExecSection => '远程执行';

  @override
  String get remoteExecWhyTitle => '远程执行的安全边界由什么决定';

  @override
  String get remoteExecShort => '他方可让本机执行操作；默认关闭，升级不会自动开启。';

  @override
  String get remoteExecWhy =>
      '他方可让本机执行操作。安全边界由两项决定：指令来自哪条渠道，以及是否携带凭据。开关默认关闭，升级不会替用户作出该决定。';

  @override
  String get remoteExecEnabledOn => '已开启';

  @override
  String get remoteExecEnabledOff => '已关闭';

  @override
  String get remoteExecNeedsCredential => '已开启但未设置任何凭据，高风险（L3）指令将无法进入。';

  @override
  String get remoteExecLocalTriggerSection => '本机通知触发';

  @override
  String get remoteExecLocalTriggerShort => '使选中应用通知正文中的指令在本机执行';

  @override
  String get remoteExecLocalTriggerWhyTitle => '本机通知触发机制说明';

  @override
  String get remoteExecLocalTriggerWhy =>
      '此路径不携带凭据：它读取通知栏正文，因此任何能向自身通知写入文本的应用都可能成为指令来源。开启后，来自下方所选应用且命中白名单关键词的通知，若正文以指令信封开头，将在本机执行（仅限 L1）。默认关闭；关闭不影响已配对设备经幻念推送发来的指令。⚠ 此处「可触发的应用」与「需转发的应用」是两份独立清单：前者决定哪些应用的通知可操作本机，后者决定哪些应用的通知需要转发。';

  @override
  String get remoteExecLocalTriggerOn => '已开启：仍仅限所选应用且命中关键词的通知才可能触发';

  @override
  String get remoteExecLocalTriggerOff => '已关闭：任何通知正文均不会被执行';

  @override
  String get remoteExecLocalTriggerApps => '可触发的应用';

  @override
  String get remoteTriggerFilterTitle => '可触发的应用';

  @override
  String get remoteTriggerAllow => '允许触发';

  @override
  String get remoteTriggerBlock => '禁止触发';

  @override
  String get remoteTriggerAllowModeInfo =>
      '当前模式：允许触发 — 只有选中的应用，其通知正文才能触发本机远程指令';

  @override
  String remoteTriggerAllowModeSelected(int n) {
    return '已选择 $n 个应用，仅这些应用的通知能触发远程指令';
  }

  @override
  String get remoteTriggerBlockModeInfo => '当前模式：禁止触发 — 选中的应用除外，其余应用的通知都能触发';

  @override
  String remoteTriggerBlockModeSelected(int n) {
    return '已选择 $n 个应用，这些应用的通知不会触发远程指令';
  }

  @override
  String get remoteExecLocalTriggerAllowNone => '允许 0 个应用，任何通知均不会触发';

  @override
  String remoteExecLocalTriggerAllowCount(int count) {
    return '允许 $count 个应用';
  }

  @override
  String remoteExecLocalTriggerBlockCount(int count) {
    return '除 $count 个应用外均可触发';
  }

  @override
  String get remoteExecOpenSettings => '远程执行设置';

  @override
  String get remoteExecSendPage => '远程指令发送';

  @override
  String get remoteExecHistory => '远程执行历史';

  @override
  String get remoteExecDelayTitle => '延时执行';

  @override
  String remoteExecDelayUsingDefault(int seconds) {
    return '本条将在 $seconds 秒后自动执行（协议默认值）';
  }

  @override
  String remoteExecDelayChosen(int seconds) {
    return '本条将在 $seconds 秒后自动执行（自定义值）';
  }

  @override
  String remoteExecDelayRange(int min, int max) {
    return '可设范围 $min–$max 秒，由协议规定，并非本机偏好';
  }

  @override
  String get remoteExecDelayReset => '恢复协议默认值';

  @override
  String remoteExecDelayInvalid(String reason) {
    return '延时设置未生效：$reason';
  }

  @override
  String remoteExecPendingBanner(String item, int seconds) {
    return '远程指令「$item」等 $seconds 秒后自动执行';
  }

  @override
  String get remoteExecCancel => '撤销';

  @override
  String get remoteExecCancelled => '已撤销：那一条不会执行';

  @override
  String get remoteExecCancelTooLate => '已经动手了，撤不回来（动作可能做完了一半）';

  @override
  String get remoteCredWhyTitle => '凭据与设备身份为何是两把不同的密钥';

  @override
  String get remoteCredShort => '此密钥用于授权他方让本机执行操作，与「证明本机身份」所用的密钥不同。';

  @override
  String get remoteCredWhy =>
      '凭据用于授权某一条远程指令，与设备身份是两把不同的密钥：一把证明本机身份，另一把授权他方让本机执行操作。';

  @override
  String get remoteCredKeySection => '高级密钥';

  @override
  String get remoteCredKeyNone => '尚未设置';

  @override
  String get remoteCredKeySetNoFingerprint => '已设置（本机无其指纹，无法辨别具体密钥）';

  @override
  String remoteCredKeySet(String fingerprint) {
    return '已设置，指纹 $fingerprint';
  }

  @override
  String remoteCredKeyMin(int min) {
    return '至少 $min 个字符，由协议规定';
  }

  @override
  String get remoteCredKeyGenerate => '生成密钥';

  @override
  String get remoteCredKeyCustom => '自行设置密钥';

  @override
  String get remoteCredKeyOnce =>
      '此密钥串仅显示一次：请立即保存至仅有你可访问的位置，或当面交付对端设备。关闭本页后，本机仅保留哈希，任何人（包括你本人）都无法再次读取该密钥串。';

  @override
  String get remoteCredKeyReset => '移除此密钥';

  @override
  String get remoteCredKeyResetAsk => '移除后，对端持有的旧密钥将立即失效；须重新生成并当面交付。';

  @override
  String get remoteCredTotpSection => '二步验证码（TOTP）';

  @override
  String get remoteCredTotpNone => '尚未设置';

  @override
  String get remoteCredTotpSet => '已设置';

  @override
  String get remoteCredTotpGenerate => '生成种子';

  @override
  String get remoteCredTotpLink => '添加至验证器 App 的链接';

  @override
  String get remoteCredTotpSecret => '密钥串（也可在验证器 App 中手动输入）';

  @override
  String get remoteCredTotpOnce =>
      '此验证码种子仅显示一次，且仅存在于接收端：请立即录入对端设备的验证器 App，或当面交付对方录入。此后由验证器保管，不经过任何服务器；本机关闭本页后仅保留该种子。';

  @override
  String get remoteCredTotpClear => '移除此种子';

  @override
  String remoteCredProblem(String reason) {
    return '本机的凭据不可用：$reason';
  }

  @override
  String get remoteCredResetAll => '全部重置';

  @override
  String get remoteCredResetAllAsk =>
      '全部重置后，对端持有的高级密钥与验证码种子将立即失效。如需继续远程执行，须重新生成并当面交付。';

  @override
  String get remotePeersReadFailed =>
      '无法读取名单（未能读取数据库中该表）。这不表示「尚未配对设备」，请先查看「设备配对」页。';

  @override
  String get remoteActionListenerStart => '让对面开始监听通知';

  @override
  String get remoteActionListenerStop => '让对面停止监听通知';

  @override
  String get remoteActionChannelToggle => '启停对面某一条推送通道';

  @override
  String get remoteActionDeviceStatePush => '让对面立刻回一份设备状态';

  @override
  String get remoteActionNotificationsReport => '让对面回传最近的通知原文';

  @override
  String get remoteActionNotificationReply => '让对面回复一条通知';

  @override
  String get remoteActionAlertRing => '让对面响铃＋震动提醒';

  @override
  String get remoteActionSmsSearch => '让对面按关键词搜短信';

  @override
  String get remoteActionAppLaunch => '让对面打开一个已登记的入口';

  @override
  String get remoteActionCallsSearch => '让对面按关键词搜通话记录';

  @override
  String get remoteActionLocationGet => '让对面回一份最近定位';

  @override
  String get remoteActionCameraSnap => '让对面拍一张照片';

  @override
  String get remoteActionContactsSearch => '让对面按关键词搜通讯录';

  @override
  String get fnthinkReadContactsTitle => '通讯录';

  @override
  String get fnthinkReadContactsSubtitle => '允许已配对设备按姓名或号码搜索本机通讯录';

  @override
  String get fnthinkReadContactsDenied =>
      '未获得通讯录权限，该项仍为关闭状态。请再次点击开关重试，或前往系统设置中开启。';

  @override
  String get fnthinkReadSmsRetentionTitle => '已监听的短信留存';

  @override
  String get fnthinkReadSmsRetentionSubtitle => '允许已配对设备按关键词搜索本机已监听的短信';

  @override
  String get fnthinkReadSmsRetentionDenied => '此项无需系统权限：检索的是本机数据库中的记录';

  @override
  String get fnthinkReadCameraTitle => '拍照';

  @override
  String get fnthinkReadCameraSubtitle =>
      '允许已配对设备让本机拍摄一张照片（照片文件保存在本机，图像随回传消息经中转服务器发回至发起设备；本应用界面须处于开启状态）';

  @override
  String get fnthinkReadCameraDenied =>
      '未获得相机权限，该项仍为关闭状态。请再次点击开关重试，或前往系统设置中开启。';

  @override
  String get fnthinkPhotoLabel => '照片';

  @override
  String get fnthinkPhotoBroken => '这张照片没能显示出来';

  @override
  String get fnthinkPhotoOmitted => '照片太大，没有随这条消息发出';

  @override
  String get fnthinkReadLocationTitle => '位置';

  @override
  String get fnthinkReadLocationSubtitle =>
      '允许已配对设备读取本机最近一次定位（仅读取已有结果，不会主动启动 GPS 定位）';

  @override
  String get fnthinkReadLocationDenied =>
      '未获得定位权限，该项仍为关闭状态。请再次点击开关重试，或前往系统设置中开启。';

  @override
  String get fnthinkReadPageTitle => '可被远程读取的内容';

  @override
  String get fnthinkReadEntryShort => '对面能读这台什么；每一项默认关、单独开。';

  @override
  String get fnthinkReadWhy => '各项默认关闭：开启某项后，已配对设备方可远程读取（开启时会向系统申请相应权限）。';

  @override
  String get fnthinkReadWhyTitle => '「可被远程读取」的拦截机制';

  @override
  String get fnthinkReadWhyBody =>
      '须同时启用两项开关：① 本页开关：本机持有者的显式决定，默认关闭，可随时变更，关闭后立即生效；② Android 运行时权限：首次使用时申请，可在系统设置中随时修改。仅已配对设备通过远程指令面发起的读取才会生效；读取内容以普通消息形式回传（带回执并进入收件箱），并不授予设备对本机的任意读取权。';

  @override
  String get fnthinkReadCallsTitle => '通话记录';

  @override
  String get fnthinkReadCallsSubtitle => '允许已配对设备按关键词搜索本机通话记录（号码与姓名）';

  @override
  String get fnthinkReadCallsDenied =>
      '未获得通话记录权限，该项仍为关闭状态。请再次点击开关重试，或前往系统设置中开启。';

  @override
  String get remoteSendCallsKeywordLabel => '搜索词或号码';

  @override
  String get remoteSendCallsKeywordWhy =>
      '仅回传命中的记录（时间／方向／对方／时长）。对端「可被远程读取的内容」中该项关闭时，本次指令不会执行。';

  @override
  String remoteSendNeedsCallsKeyword(int min, int max) {
    return '关键词长度须为 $min–$max 个字符，且不得包含控制字符。';
  }

  @override
  String get fnthinkShortcutsTitle => '可被远程打开的入口';

  @override
  String get fnthinkShortcutsWhy =>
      '对端仅可打开您在此登记的入口：填写名称，再填写用于打开它的目标——该应用自身公开的链接，或本机的「包名/类名」。';

  @override
  String get fnthinkShortcutsEmpty =>
      '尚未登记任何入口：缺少入口时，对端的「打开某个入口」操作将无法匹配名称，不会执行任何动作。';

  @override
  String get fnthinkShortcutsAdd => '新增一条';

  @override
  String get fnthinkShortcutsNameLabel => '名称（对端按此名称调用）';

  @override
  String get fnthinkShortcutsTargetLabel => '目标（链接或包名/类名）';

  @override
  String get fnthinkShortcutsNameInvalid => '名称须为 1–32 个字符，且不得包含控制字符。';

  @override
  String get fnthinkShortcutsTargetInvalid => '目标须为带 scheme 的链接，或「包名/类名」。';

  @override
  String get fnthinkShortcutsDuplicate => '该名称已登记。';

  @override
  String fnthinkShortcutsDeleteAsk(String name) {
    return '删除「$name」后，对端再次按此名称调用将无法打开。是否继续？';
  }

  @override
  String get remoteSettingNotification => '请对面打开「通知监听」权限页';

  @override
  String get remoteSettingExactAlarm => '请对面打开「精确闹钟」权限页';

  @override
  String get remoteSettingBatteryOptimization => '请对面去关掉「电池优化」';

  @override
  String get remoteSettingAutostart => '请对面打开「自启动」（按厂商分流）';

  @override
  String get remoteSettingMonitoring => '开／关对面的通知转发总开关';

  @override
  String get remoteSettingCollectInbox => '开／关对面的幻念收件采集';

  @override
  String get remoteCategoryListening => '监听与转发';

  @override
  String get remoteCategoryChannels => '通道与状态';

  @override
  String get remoteCategorySearch => '查找内容';

  @override
  String get remoteCategoryDevice => '设备动作';

  @override
  String get remoteCategorySystem => '系统与权限';

  @override
  String get remoteCategoryUncategorized => '未分类（这张表还没跟上契约）';

  @override
  String get remoteOutcomePerformed => '这一项本机做完了';

  @override
  String get remoteOutcomeReported => '查到的东西已经送回发起的那一台';

  @override
  String get remoteOutcomeSet => '那一档已经改成对面要的值';

  @override
  String get remoteSendFamilyLabel => '通道族';

  @override
  String get remoteSendChannelIdWhy =>
      '仅此项需手动填写：本机无法查看对端已配置的通道（需协议支持列表查询）。族与开关目标均在下方选择，并按对端可识别的格式拼接。';

  @override
  String get remoteSendWantOn => '设为开启';

  @override
  String get remoteSendWantOff => '设为关闭';

  @override
  String get remoteSendNeedsFamily => '尚未选择通道族。';

  @override
  String get remoteSendNeedsWant => '尚未选择目标开关状态；仅指定「切换」而不指定目标状态时，重复投递会恢复原状。';

  @override
  String get remoteSendLevel => '选择发送档位';

  @override
  String get remoteSendLevelL1 => '低风险：可直接执行，也可由指定应用的通知触发';

  @override
  String get remoteSendLevelL2 => '中风险：仅允许经幻念推送，凭据可选';

  @override
  String get remoteSendLevelL3 => '高风险：必须经幻念推送，且必须携带密钥或二步验证码';

  @override
  String get remoteSendAction => '选择动作';

  @override
  String get remoteSendArgument => '参数（目标通道标识）';

  @override
  String get remoteSendKeyRequired => '高级密钥（本档必填）';

  @override
  String get remoteSendTotpRequired => '二步验证码（本档必填）';

  @override
  String get remoteSendSubmit => '发送';

  @override
  String get remoteSendCancelNote => '取消后不会发送任何数据；本次输入中的凭据也不会带出。';

  @override
  String get remoteSendNeedsCredential => '本档必须携带高级密钥或二步验证码之一；两项均为空时无法发送。';

  @override
  String get remoteSendNeedsArgument => '此项需要参数（目标通道标识），为空时无法发送。';

  @override
  String get remoteSendReportCountLabel => '回传条数';

  @override
  String get remoteSendReportCountWhy =>
      '仅回传以下文字：时间、应用、标题与正文。对端收到的是一条消息，而非设备的读取权限。';

  @override
  String remoteSendNeedsReportCount(int min, int max) {
    return '回传条数必须为 $min–$max 之间的整数。';
  }

  @override
  String get remoteSendSmsKeywordLabel => '搜索关键词';

  @override
  String get remoteSendSmsKeywordWhy =>
      '仅回传命中的消息（时间／号码／正文）。对端的短信监听关闭时，本次指令不会执行。';

  @override
  String remoteSendNeedsSmsKeyword(int min, int max) {
    return '关键词长度须为 $min–$max 个字符，且不得包含控制字符。';
  }

  @override
  String get remoteSendShortcutNameLabel => '打开哪一项';

  @override
  String get remoteSendShortcutNameWhy =>
      '填写对端在本机登记过的名称（本机无法查看该清单）。名称不匹配时，本次指令不会执行。';

  @override
  String remoteSendNeedsShortcutName(int min, int max) {
    return '名称长度须为 $min–$max 个字符，且不得包含控制字符。';
  }

  @override
  String get remoteSendContactsKeywordLabel => '搜索姓名或号码';

  @override
  String get remoteSendContactsKeywordWhy =>
      '仅回传命中的记录（姓名／号码）。对端「可被远程读取的内容」中该项关闭时，本次指令不会执行。';

  @override
  String remoteSendNeedsContactsKeyword(int min, int max) {
    return '姓名或号码长度须为 $min–$max 个字符，且不得包含控制字符。';
  }

  @override
  String get remoteSendStartedNote =>
      '已发出。请等待对端返回「正在执行」与「执行完毕」两条回执，它们将显示在远程执行历史中。';

  @override
  String remoteSendFailed(String reason) {
    return '本次发送未成功：$reason';
  }

  @override
  String remoteSendLevelUnknown(String level) {
    return '档位（$level）不在协议词表中，无法发送。';
  }

  @override
  String get remoteHistoryIn => '收到的指令';

  @override
  String get remoteHistoryOut => '发出的指令';

  @override
  String get remoteHistoryAll => '全部';

  @override
  String get remoteHistoryEmpty => '还没有任何远程执行记录。';

  @override
  String get fnthinkRemoteCommandRowTitle => '一条远程指令';

  @override
  String get fnthinkRetentionLabel => '收件保留';

  @override
  String get fnthinkRetentionDaysUnit => '天';

  @override
  String get fnthinkRetentionDefault => '默认档';

  @override
  String get fnthinkRetentionPick => '选择档位';

  @override
  String get remoteHistoryPending => '等执行';

  @override
  String get remoteHistoryNoReceipt => '这一轮没拿到回执，状态未知';

  @override
  String get remoteHistoryExecuting => '执行中';

  @override
  String get remoteHistoryDone => '执行完毕';

  @override
  String get remoteHistoryFailed => '没做成';

  @override
  String get remoteHistoryCancelled => '已取消';

  @override
  String remoteHistoryStateUnknown(String state) {
    return '不认得的执行状态（$state）';
  }

  @override
  String remoteHistoryResult(String result) {
    return '结果：$result';
  }

  @override
  String remoteHistoryReason(String reason) {
    return '理由：$reason';
  }

  @override
  String remoteHistoryArgument(String argument) {
    return '参数：$argument';
  }

  @override
  String remoteHistoryFromPeer(String peer) {
    return '来自 $peer';
  }

  @override
  String remoteHistoryToPeer(String peer) {
    return '发给 $peer';
  }

  @override
  String get remoteHistoryLocalTrigger => '本机应用的通知触发的（没有远端发送方）';

  @override
  String get remoteReasonSwitchOff => '远程执行总开关关着';

  @override
  String get remoteReasonLocalTriggerOff => '本机通知触发那颗开关关着';

  @override
  String get remoteReasonAppNotAllowed => '这条通知来自没被允许触发的那类应用';

  @override
  String get remoteReasonMissingItem => '指令没带要做的那一项';

  @override
  String get remoteReasonConfirmRequired => '这一项要求本机当场确认一次';

  @override
  String remoteReasonNotGranted(String x) {
    return '对端没被授权做这一项：$x';
  }

  @override
  String remoteReasonMissingGrant(String x) {
    return '这一项要先在本机开着：$x';
  }

  @override
  String remoteReasonUnknownAction(String x) {
    return '认不出这个动作：$x';
  }

  @override
  String remoteReasonUnknownSetting(String x) {
    return '认不出这项设置：$x';
  }

  @override
  String remoteReasonUnknownItem(String x) {
    return '授权清单里有一项认不出：$x';
  }

  @override
  String remoteReasonUnknownCeiling(String x) {
    return '对端那一行的档位天花板认不出：$x';
  }

  @override
  String remoteReasonLevel(String x) {
    return '这一档超出对端被授予的范围：$x';
  }

  @override
  String remoteReasonSourceNotAllowed(String x) {
    return '这一档不许从这个来源进来：$x';
  }

  @override
  String get remoteReasonAuthWrong => '凭据不对';

  @override
  String get remoteReasonAuthMissing => '这一档必须带凭据，而这条没带';

  @override
  String get remoteReasonAuthMode => '用的凭据方式协议里没有';

  @override
  String get remoteReasonTerminalState => '这条已经走到终态，状态不再改它';

  @override
  String get remoteReasonIllegalMove => '状态机被要求走一步不允许的转换';

  @override
  String get remoteReasonInterrupted => '这一轮被打断（应用被重启过）';

  @override
  String get remoteReasonNoReceipt => '这一轮没拿到回执，状态未知';

  @override
  String get remoteReasonCancelledByUser => '你在撤销窗口里撤掉了它';

  @override
  String get remoteReasonCancelledStatusBar => '你在状态栏上撤掉了它';

  @override
  String get remoteReasonReportNotSent => '结果报告没发出去';

  @override
  String get remoteReasonReportFailed => '报告这一发没做成';

  @override
  String get remoteReasonSmsFailed => '短信检索没做成';

  @override
  String get remoteReasonCallsFailed => '通话记录检索没做成';

  @override
  String get remoteReasonLocationFailed => '定位没拿到';

  @override
  String get remoteReasonCameraFailed => '拍照没成功';

  @override
  String get remoteReasonContactsFailed => '联系人检索没做成';

  @override
  String get remoteReasonDeviceStateRefused => '设备状态推送被拒';

  @override
  String get remoteReasonAlertRefused => '响铃被拒';

  @override
  String remoteReasonUnmappedAction(String x) {
    return '这个动作还没有执行器：$x';
  }

  @override
  String get remoteReasonListenerStart => '监听没开起来';

  @override
  String get remoteReasonListenerStop => '监听没停下来';

  @override
  String remoteReasonNotApplied(String x) {
    return '这项设置没有真的改变：$x';
  }

  @override
  String remoteReasonThrew(String x) {
    return '执行时抛了异常：$x';
  }

  @override
  String remoteReasonBadArgumentKind(String x) {
    return '这个动作不接受这一类参数：$x';
  }

  @override
  String remoteReasonBadArgumentFormat(String x) {
    return '参数不是 JSON 对象（$x）';
  }

  @override
  String remoteReasonBadArgumentJson(String x) {
    return '参数 JSON 解析失败（$x）';
  }

  @override
  String remoteReasonBadChannelArgument(String x) {
    return '通道那一段参数不对：$x';
  }

  @override
  String remoteReasonBadKeyword(String x) {
    return '关键词那一项不成形：$x';
  }

  @override
  String remoteReasonBadReportCount(String x) {
    return '报告条数不成形：$x';
  }

  @override
  String remoteReasonMissingArgument(String x) {
    return '这一项要带参数：$x';
  }

  @override
  String remoteReasonNoSuchChannel(String x) {
    return '没有这条通道：$x';
  }

  @override
  String remoteReasonUnexpectedArgument(String x) {
    return '这个动作不接受参数：$x';
  }

  @override
  String remoteReasonUnknownTargetWord(String x) {
    return '目标那一段认不出：$x';
  }

  @override
  String remoteReasonUnknown(String x) {
    return '（没有更多原因可读：$x）';
  }

  @override
  String get remoteHistoryCancel => '取消这一条';

  @override
  String get remoteHistoryCancelNote => '取消只对还没开始执行的那一条有用；已经开始执行的不受这条窗口影响。';

  @override
  String get remoteHistoryRemoved => '这一条已从本机历史里删掉。';

  @override
  String get remoteHistoryBoundary =>
      '远程执行历史只记本机这一份：收到的与发出的都记。凭据与指令正文不进这一层——它们随那条消息的密文正文走，回执与留痕各存自己的那一份。';

  @override
  String get remoteHistoryBoundaryShort => '这一页只记本机这一份';

  @override
  String get fnthinkPeersBoundaryShort => '此处记录本机已同意的设备';

  @override
  String get fnthinkPairPeerPendingNoteShort => '提交后仅在对端新增一条待确认请求';

  @override
  String get fnthinkPairApprovedOneWayShort => '双向发送已开通，逐项权限仍需对端自行勾选';

  @override
  String get fnthinkPairLinkRejectedShort => '本机无法使用此链接';

  @override
  String get fnthinkSendNoticeVsCommandShort => '通知：让对端查看内容；指令：让对端执行动作';

  @override
  String get fnthinkSendTargetWebhookOnlyForNoticeShort => '指令仅发送至已配对设备';

  @override
  String get fnthinkSendTargetWebhookEmptyShort => '尚无已启用的 Webhook 通道';

  @override
  String get remoteSendReportCountWhyShort => '仅回传这段文字，不涉及读取权限';

  @override
  String get remoteSendChannelIdWhyShort => '此项需手动填写：本机无法查看对端通道';

  @override
  String get fnthinkEndpointWhyShort => '接入端点：供第三方平台向本机推送通知';

  @override
  String get fnthinkEndpointListPendingShort => '尚未查询本机端点数量';

  @override
  String fnthinkEndpointListFailedShort(String reason) {
    return '本次查询失败（$reason）';
  }

  @override
  String get fnthinkShortcutsWhyShort => '对端仅可打开您在此登记的入口';

  @override
  String get fnthinkShortcutsEmptyShort => '尚未登记任何入口';

  @override
  String get remotePeersReadFailedShort => '无法读取名单，并不表示尚未配对设备';

  @override
  String get remoteCredKeyOnceShort => '此密钥串仅显示一次，请立即保存';

  @override
  String get remoteCredTotpOnceShort => '此验证码种子仅显示一次，请立即录入对端验证器';

  @override
  String get fnthinkChannelDisclosureShort => '是否响铃、振动或显示横幅，由系统侧的通知渠道决定';

  @override
  String get fnthinkRemoteTitle => '远程控制';

  @override
  String get fnthinkRemoteNeedsReceive => '请先启用接收：本页功能依赖本机开启幻念接收权限';

  @override
  String get fnthinkRemoteNeedsConsent => '尚未通过同意确认：请前往「接收」页阅读说明并同意';

  @override
  String get fnthinkRemoteNeedsSwitch => '远程执行默认关闭：请进入并开启';

  @override
  String get testerSampleAppName => '微信';

  @override
  String get testerSampleTitle => '张三';

  @override
  String get testerSampleContent => '在吗？';

  @override
  String errorWithDetail(String e) {
    return '出错了：$e';
  }

  @override
  String webhookTestTimeout(int seconds) {
    return '原生 $seconds 秒未回复测试结果';
  }

  @override
  String testerRuleHitSummary(String name, int priority) {
    return '$name（P$priority）';
  }

  @override
  String deviceStateThresholdSummary(int value) {
    return '阈值 $value%';
  }

  @override
  String updateCheckCdnBlocked(int code) {
    return '检查更新被 CDN 拦截（HTTP $code），请稍后重试，或访问 GitHub Releases 手动下载最新版';
  }

  @override
  String updateCheckHttpStatus(int code) {
    return '检查更新失败：服务器返回 HTTP $code';
  }

  @override
  String get inboxMarkAllRead => '一键已读';

  @override
  String get inboxMarkReadAction => '确认已读';

  @override
  String inboxMarkAllConfirmMsg(int n) {
    return '将把收件档里的 $n 条未读标为已读。';
  }

  @override
  String inboxMarkReadDone(int n) {
    return '已标记 $n 条为已读';
  }

  @override
  String get fnthinkAppLabel => '应用';

  @override
  String get remoteReasonSendAccepted => '服务器已受理（还不等于对方收到）';

  @override
  String get remoteReasonSendRejectedUnsigned => '服务器没认下这台设备的签名（要重新登记或配对）';

  @override
  String get remoteReasonSendRejectedCapability =>
      '身份已证明，但这一步不被允许（没配对、档位不够或类型不在词表）';

  @override
  String get remoteReasonSendReplayed => '同一个 nonce 已经用过（重发要换一个 nonce）';

  @override
  String get remoteReasonSendNeedsCalibration => '本机时间与服务器差得太多（先校准时间再重试）';

  @override
  String get remoteReasonSendRateLimited => '被服务器限流（按提示等一会再试）';

  @override
  String get remoteReasonSendTransportError => '没连上服务器（网络、代理或证书）—— 这一发什么都没发生';

  @override
  String get remoteReasonSendSigningUnavailable => '本机签不出名（Keystore 被拒或没有私钥）';

  @override
  String get remoteReasonSendPreconditionFailed => '本机还没就绪（地址、契约或开关不完整）';

  @override
  String get remoteReasonSendBadInput => '这一条本身发不出去（内容含签名字段分隔符，或类型不在词表）';

  @override
  String get remoteReasonSendUnparseable => '服务器答了，但载荷看不懂（例如“已受理”却没有消息号）';

  @override
  String get remoteReasonTsExpired => '签名时间超出服务器的容差（先学到服务器时间再重签）';

  @override
  String get remoteReasonNonceReplayed => 'nonce 撞上了服务端的去重窗口（换一个 nonce 重签）';

  @override
  String get remoteReasonUnsignedOrUnknown => '签名没被认下，或服务端没有这台设备';

  @override
  String get remoteReasonAcceptedWithoutId => '服务器说收下了，却没给消息号（这一条追不回来）';

  @override
  String remoteReasonSigningFailed(String x) {
    return '本机签不出名（底层异常：$x）';
  }

  @override
  String remoteReasonTransportFailed(String x) {
    return '没连上服务器（底层异常：$x）—— 这一发什么都没发生';
  }

  @override
  String remoteReasonRateLimitFamily(String x) {
    return '被服务器限流（建议等待秒数：$x）';
  }

  @override
  String remoteReasonCapabilityFamily(String x) {
    return '身份已证明，但这一步不被允许（服务端回执：$x）';
  }

  @override
  String remoteReasonUnexpectedStatus(String x) {
    return '服务器回了一个本机没见过的状态码（$x）';
  }

  @override
  String get remoteReasonBizFail => '通道的业务性拒绝（重试不会成功；例如企微 errcode 非 0）';

  @override
  String get remoteReasonHttpFail => '通道回了 HTTP 失败（会当场重试；仍失败则进入重放队列）';

  @override
  String get remoteReasonNetworkFail => '没能连上通道（会当场重试；仍失败则进入重放队列）';

  @override
  String get remoteReasonRateLimitedNative => '通道限流（会按 Retry-After 等待后重试）';

  @override
  String remoteReasonUnknownCode(String code) {
    return '这条我们还没写过说明（原文：$code）';
  }

  @override
  String get remoteReasonHelpTitle => '这条报错说明';

  @override
  String get remoteReasonHelpShort => '报错说明与常见原因';

  @override
  String get remoteReasonHelpIntro =>
      '下面这些码会出现在「理由」那一格；没有列出的码属于本机还没写过说明的那一类，它会连同原文一起显示，不会变成一句猜出来的原因。';

  @override
  String get remoteReasonHelpFamilyNote => '形如「族：细节」的码：族说明原因，细节原样带出（本机不替它改写）。';

  @override
  String remoteReasonMissSeen(int n) {
    return '本页有 $n 条理由本机还没写过说明（原文见各行）。';
  }

  @override
  String get whatsNewTitle => '这次更新带来了什么';
}
