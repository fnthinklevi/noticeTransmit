import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'通知推送助手'**
  String get appName;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get add;

  /// No description provided for @test.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get test;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'好的'**
  String get ok;

  /// No description provided for @later.
  ///
  /// In zh, this message translates to:
  /// **'稍后'**
  String get later;

  /// No description provided for @goSettings.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get goSettings;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get loading;

  /// No description provided for @unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @notSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get notSet;

  /// No description provided for @enabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In zh, this message translates to:
  /// **'未开启'**
  String get disabled;

  /// No description provided for @on.
  ///
  /// In zh, this message translates to:
  /// **'开'**
  String get on;

  /// No description provided for @off.
  ///
  /// In zh, this message translates to:
  /// **'关'**
  String get off;

  /// No description provided for @tabNotification.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get tabNotification;

  /// No description provided for @tabBattery.
  ///
  /// In zh, this message translates to:
  /// **'电量'**
  String get tabBattery;

  /// No description provided for @tabMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get tabMore;

  /// No description provided for @serviceRunning.
  ///
  /// In zh, this message translates to:
  /// **'通知监听服务正在运行，点击可停止'**
  String get serviceRunning;

  /// No description provided for @serviceStopped.
  ///
  /// In zh, this message translates to:
  /// **'通知监听服务未启动，点击可启动'**
  String get serviceStopped;

  /// No description provided for @running.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get running;

  /// No description provided for @stopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get stopped;

  /// No description provided for @currentChannels.
  ///
  /// In zh, this message translates to:
  /// **'当前推送通道'**
  String get currentChannels;

  /// No description provided for @noChannels.
  ///
  /// In zh, this message translates to:
  /// **'未配置推送通道'**
  String get noChannels;

  /// No description provided for @statusOk.
  ///
  /// In zh, this message translates to:
  /// **'状态正常'**
  String get statusOk;

  /// No description provided for @statusError.
  ///
  /// In zh, this message translates to:
  /// **'状态异常'**
  String get statusError;

  /// No description provided for @permSettings.
  ///
  /// In zh, this message translates to:
  /// **'权限设置'**
  String get permSettings;

  /// No description provided for @permSettingsDesc.
  ///
  /// In zh, this message translates to:
  /// **'配置通知、电池、后台运行等权限'**
  String get permSettingsDesc;

  /// No description provided for @pushHistory.
  ///
  /// In zh, this message translates to:
  /// **'推送历史'**
  String get pushHistory;

  /// No description provided for @recordCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {n} 条记录'**
  String recordCount(int n);

  /// No description provided for @notificationPermissionTitle.
  ///
  /// In zh, this message translates to:
  /// **'通知读取权限未开启'**
  String get notificationPermissionTitle;

  /// No description provided for @notificationPermissionMsg.
  ///
  /// In zh, this message translates to:
  /// **'通知读取权限未开启，软件无法读取设备通知内容。\n\n请先前往「权限设置」开启通知读取权限后再启动服务。'**
  String get notificationPermissionMsg;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外观设置'**
  String get appearance;

  /// No description provided for @pushSettings.
  ///
  /// In zh, this message translates to:
  /// **'推送设置'**
  String get pushSettings;

  /// No description provided for @pushChannels.
  ///
  /// In zh, this message translates to:
  /// **'推送通道'**
  String get pushChannels;

  /// No description provided for @filterRules.
  ///
  /// In zh, this message translates to:
  /// **'过滤规则'**
  String get filterRules;

  /// No description provided for @webhookChannel.
  ///
  /// In zh, this message translates to:
  /// **'Webhook 推送通道'**
  String get webhookChannel;

  /// No description provided for @webhookNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get webhookNotConfigured;

  /// No description provided for @webhookConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置 {n} 个 · 启用 {m} 个'**
  String webhookConfigured(int n, int m);

  /// No description provided for @emailChannel.
  ///
  /// In zh, this message translates to:
  /// **'邮件转发通道'**
  String get emailChannel;

  /// No description provided for @emailChannelDesc.
  ///
  /// In zh, this message translates to:
  /// **'SMTP 邮件通知'**
  String get emailChannelDesc;

  /// No description provided for @appFilter.
  ///
  /// In zh, this message translates to:
  /// **'应用筛选'**
  String get appFilter;

  /// No description provided for @appFilterBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已屏蔽 {n} 个应用'**
  String appFilterBlocked(int n);

  /// No description provided for @appFilterSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {n} 个应用'**
  String appFilterSelected(int n);

  /// No description provided for @appFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部应用都推送'**
  String get appFilterAll;

  /// No description provided for @keywordFilter.
  ///
  /// In zh, this message translates to:
  /// **'关键词过滤'**
  String get keywordFilter;

  /// No description provided for @keywordWhitelistBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'白名单 {n} 条 · 黑名单 {m} 条'**
  String keywordWhitelistBlacklist(int n, int m);

  /// No description provided for @ruleEngine.
  ///
  /// In zh, this message translates to:
  /// **'规则引擎'**
  String get ruleEngine;

  /// No description provided for @ruleCount.
  ///
  /// In zh, this message translates to:
  /// **'{n} 条规则'**
  String ruleCount(int n);

  /// No description provided for @ruleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'点击添加规则'**
  String get ruleEmpty;

  /// No description provided for @device.
  ///
  /// In zh, this message translates to:
  /// **'设备'**
  String get device;

  /// No description provided for @deviceName.
  ///
  /// In zh, this message translates to:
  /// **'设备名称'**
  String get deviceName;

  /// No description provided for @widgetSection.
  ///
  /// In zh, this message translates to:
  /// **'桌面小部件'**
  String get widgetSection;

  /// No description provided for @widgetGuide.
  ///
  /// In zh, this message translates to:
  /// **'推送开关'**
  String get widgetGuide;

  /// No description provided for @widgetGuideDesc.
  ///
  /// In zh, this message translates to:
  /// **'桌面一键开启/暂停推送服务'**
  String get widgetGuideDesc;

  /// No description provided for @widgetGuideIntro.
  ///
  /// In zh, this message translates to:
  /// **'将「推送开关」小部件添加到桌面后，无需打开应用即可一键开启或暂停推送。'**
  String get widgetGuideIntro;

  /// No description provided for @widgetGuideStep1.
  ///
  /// In zh, this message translates to:
  /// **'1. 长按桌面空白处'**
  String get widgetGuideStep1;

  /// No description provided for @widgetGuideStep2.
  ///
  /// In zh, this message translates to:
  /// **'2. 点击「小部件 / 插件 / Widgets」'**
  String get widgetGuideStep2;

  /// No description provided for @widgetGuideStep3.
  ///
  /// In zh, this message translates to:
  /// **'3. 找到「通知推送助手」，将「推送开关」拖到桌面'**
  String get widgetGuideStep3;

  /// No description provided for @widgetGuideBrand.
  ///
  /// In zh, this message translates to:
  /// **'各品牌添加路径'**
  String get widgetGuideBrand;

  /// No description provided for @widgetBrandXiaomi.
  ///
  /// In zh, this message translates to:
  /// **'小米 / 红米：桌面长按 → 添加小部件 → 通知推送助手'**
  String get widgetBrandXiaomi;

  /// No description provided for @widgetBrandHuawei.
  ///
  /// In zh, this message translates to:
  /// **'华为 / 荣耀：双指捏合或长按桌面 → 服务卡片 / 小部件 → 通知推送助手'**
  String get widgetBrandHuawei;

  /// No description provided for @widgetBrandOppo.
  ///
  /// In zh, this message translates to:
  /// **'OPPO / realme / 一加：桌面长按 → 添加插件 → 通知推送助手'**
  String get widgetBrandOppo;

  /// No description provided for @widgetBrandVivo.
  ///
  /// In zh, this message translates to:
  /// **'vivo / iQOO：桌面长按 → 原子组件 / 小部件 → 通知推送助手'**
  String get widgetBrandVivo;

  /// No description provided for @widgetBrandSamsung.
  ///
  /// In zh, this message translates to:
  /// **'三星：桌面长按 → 小组件 → 通知推送助手'**
  String get widgetBrandSamsung;

  /// No description provided for @widgetBrandOthers.
  ///
  /// In zh, this message translates to:
  /// **'其他品牌（原生 / 谷歌 Pixel / 摩托罗拉 / 索尼等）：桌面长按 → Widgets / 小部件 → 通知推送助手'**
  String get widgetBrandOthers;

  /// No description provided for @widgetTipsTitle.
  ///
  /// In zh, this message translates to:
  /// **'使用提示'**
  String get widgetTipsTitle;

  /// No description provided for @widgetTip1.
  ///
  /// In zh, this message translates to:
  /// **'点击小部件即可切换推送状态（推送中 ⇄ 已暂停）'**
  String get widgetTip1;

  /// No description provided for @widgetTip2.
  ///
  /// In zh, this message translates to:
  /// **'暂停后监听继续，仅不发送推送消息'**
  String get widgetTip2;

  /// No description provided for @widgetTip3.
  ///
  /// In zh, this message translates to:
  /// **'部分品牌需允许应用自启动，小部件状态才能实时刷新'**
  String get widgetTip3;

  /// No description provided for @widgetTip4.
  ///
  /// In zh, this message translates to:
  /// **'若桌面找不到小部件，请先打开一次应用或重启桌面'**
  String get widgetTip4;

  /// No description provided for @widgetPinTitle.
  ///
  /// In zh, this message translates to:
  /// **'一键添加（推荐）'**
  String get widgetPinTitle;

  /// No description provided for @widgetPinDesc.
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮，在系统弹窗中确认后即可将 2×2 推送开关小部件添加到桌面，无需手动拖拽。'**
  String get widgetPinDesc;

  /// No description provided for @widgetPinAction.
  ///
  /// In zh, this message translates to:
  /// **'一键添加 2×2 小部件'**
  String get widgetPinAction;

  /// No description provided for @widgetPinWideAction.
  ///
  /// In zh, this message translates to:
  /// **'添加 4×2 横条小部件'**
  String get widgetPinWideAction;

  /// No description provided for @widgetPinSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已发起添加，请在桌面放置小部件'**
  String get widgetPinSuccess;

  /// No description provided for @widgetPinUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前桌面不支持一键添加，请长按桌面空白处手动添加'**
  String get widgetPinUnsupported;

  /// No description provided for @widgetPinLowApi.
  ///
  /// In zh, this message translates to:
  /// **'一键添加需要 Android 8.0 及以上，请长按桌面空白处手动添加'**
  String get widgetPinLowApi;

  /// No description provided for @widgetPin2x2.
  ///
  /// In zh, this message translates to:
  /// **'2×2 圆形开关：标题 + 状态圆 + 点击提示'**
  String get widgetPin2x2;

  /// No description provided for @widgetPin4x2.
  ///
  /// In zh, this message translates to:
  /// **'4×2 横条：标题 + 状态圆 + 当日已推送数量'**
  String get widgetPin4x2;

  /// No description provided for @pushStats.
  ///
  /// In zh, this message translates to:
  /// **'推送统计'**
  String get pushStats;

  /// No description provided for @pushStatsDesc.
  ///
  /// In zh, this message translates to:
  /// **'查看推送数据统计'**
  String get pushStatsDesc;

  /// No description provided for @aboutUpdate.
  ///
  /// In zh, this message translates to:
  /// **'关于与更新'**
  String get aboutUpdate;

  /// No description provided for @checkUpdate.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkUpdate;

  /// No description provided for @checking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查...'**
  String get checking;

  /// No description provided for @clickToCheck.
  ///
  /// In zh, this message translates to:
  /// **'点击检查新版本'**
  String get clickToCheck;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get privacyPolicyTitle;

  /// No description provided for @privacyPolicyDesc.
  ///
  /// In zh, this message translates to:
  /// **'数据采集与隐私保护说明'**
  String get privacyPolicyDesc;

  /// No description provided for @crashReport.
  ///
  /// In zh, this message translates to:
  /// **'崩溃上报'**
  String get crashReport;

  /// No description provided for @crashReportDesc.
  ///
  /// In zh, this message translates to:
  /// **'默认关闭；开启后崩溃日志将上传至腾讯 Bugly 用于问题分析'**
  String get crashReportDesc;

  /// No description provided for @crashReportOffHint.
  ///
  /// In zh, this message translates to:
  /// **'已关闭，下次启动后完全生效'**
  String get crashReportOffHint;

  /// No description provided for @aboutTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get aboutTitle;

  /// No description provided for @aboutDesc.
  ///
  /// In zh, this message translates to:
  /// **'版本信息、作者介绍'**
  String get aboutDesc;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @lightMode.
  ///
  /// In zh, this message translates to:
  /// **'浅色模式'**
  String get lightMode;

  /// No description provided for @darkMode.
  ///
  /// In zh, this message translates to:
  /// **'深色模式'**
  String get darkMode;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @langDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get langDefault;

  /// No description provided for @langChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get langChinese;

  /// No description provided for @langEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @switchLangTitle.
  ///
  /// In zh, this message translates to:
  /// **'切换语言'**
  String get switchLangTitle;

  /// No description provided for @switchLangMsg.
  ///
  /// In zh, this message translates to:
  /// **'检测到系统语言已变为 {lang}，是否同步切换应用语言？'**
  String switchLangMsg(String lang);

  /// No description provided for @switchBtn.
  ///
  /// In zh, this message translates to:
  /// **'切换'**
  String get switchBtn;

  /// No description provided for @notNow.
  ///
  /// In zh, this message translates to:
  /// **'暂不'**
  String get notNow;

  /// No description provided for @privacyTitle.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get privacyTitle;

  /// No description provided for @privacyWelcome.
  ///
  /// In zh, this message translates to:
  /// **'欢迎使用通知推送助手！'**
  String get privacyWelcome;

  /// No description provided for @privacyBody.
  ///
  /// In zh, this message translates to:
  /// **'在使用本应用前，请您仔细阅读我们的隐私政策。\n\n• 所有通知内容仅在设备本地处理，仅按您的配置转发到您指定的 Webhook 或邮件地址\n• 推送历史记录使用 AES-256 加密存储在本地数据库\n• 崩溃上报（腾讯 Bugly）默认关闭，仅在你于设置中主动开启后收集必要的崩溃日志用于修复应用问题，不采集个人身份信息\n• 通道配置（Webhook/邮件）使用 AndroidKeyStore 加密存储\n\n点击\"同意\"即表示您已阅读并接受我们的隐私政策。'**
  String get privacyBody;

  /// No description provided for @disagree.
  ///
  /// In zh, this message translates to:
  /// **'不同意'**
  String get disagree;

  /// No description provided for @agree.
  ///
  /// In zh, this message translates to:
  /// **'同意'**
  String get agree;

  /// No description provided for @privacyWarnTitle.
  ///
  /// In zh, this message translates to:
  /// **'注意'**
  String get privacyWarnTitle;

  /// No description provided for @privacyWarnBody.
  ///
  /// In zh, this message translates to:
  /// **'您需要同意隐私政策才能使用本软件。\n\n不同意将无法继续使用，软件将会退出。\n\n确定要退出吗？'**
  String get privacyWarnBody;

  /// No description provided for @returnAgree.
  ///
  /// In zh, this message translates to:
  /// **'返回同意'**
  String get returnAgree;

  /// No description provided for @confirmExit.
  ///
  /// In zh, this message translates to:
  /// **'确定退出'**
  String get confirmExit;

  /// No description provided for @latestVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本'**
  String get latestVersion;

  /// No description provided for @checkUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：{e}'**
  String checkUpdateFailed(String e);

  /// No description provided for @checkUpdateNetworkError.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，请检查网络连接'**
  String get checkUpdateNetworkError;

  /// No description provided for @importantUpdate.
  ///
  /// In zh, this message translates to:
  /// **'重要更新'**
  String get importantUpdate;

  /// No description provided for @mustUpdate.
  ///
  /// In zh, this message translates to:
  /// **'必须更新才能继续使用'**
  String get mustUpdate;

  /// No description provided for @newVersionFound.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get newVersionFound;

  /// No description provided for @latestVer.
  ///
  /// In zh, this message translates to:
  /// **'最新版本：'**
  String get latestVer;

  /// No description provided for @currentVer.
  ///
  /// In zh, this message translates to:
  /// **'当前版本：'**
  String get currentVer;

  /// No description provided for @fileSize.
  ///
  /// In zh, this message translates to:
  /// **'文件大小：'**
  String get fileSize;

  /// No description provided for @updateContent.
  ///
  /// In zh, this message translates to:
  /// **'更新内容'**
  String get updateContent;

  /// No description provided for @updateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get updateNow;

  /// No description provided for @ignore.
  ///
  /// In zh, this message translates to:
  /// **'忽略'**
  String get ignore;

  /// No description provided for @update.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get update;

  /// No description provided for @downloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载更新'**
  String get downloading;

  /// No description provided for @downloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败：{e}'**
  String downloadFailed(String e);

  /// No description provided for @storagePermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要存储权限'**
  String get storagePermissionRequired;

  /// No description provided for @storagePermissionMsg.
  ///
  /// In zh, this message translates to:
  /// **'在线更新需要存储权限来保存 APK 文件，请前往设置开启。'**
  String get storagePermissionMsg;

  /// No description provided for @noStoragePermission.
  ///
  /// In zh, this message translates to:
  /// **'未获得存储权限，无法下载更新'**
  String get noStoragePermission;

  /// No description provided for @enable.
  ///
  /// In zh, this message translates to:
  /// **'去开启'**
  String get enable;

  /// No description provided for @confirmExport.
  ///
  /// In zh, this message translates to:
  /// **'确认导出'**
  String get confirmExport;

  /// No description provided for @exportMsg.
  ///
  /// In zh, this message translates to:
  /// **'通知记录将导出为 JSON 文件，包含通知内容和设备信息。\n\n请选择保存位置，建议在导出后妥善保管或及时删除。\n\n确定要导出吗？'**
  String get exportMsg;

  /// No description provided for @exportBtn.
  ///
  /// In zh, this message translates to:
  /// **'确定导出'**
  String get exportBtn;

  /// No description provided for @exportCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get exportCancelled;

  /// No description provided for @exportError.
  ///
  /// In zh, this message translates to:
  /// **'导出异常'**
  String get exportError;

  /// No description provided for @historyTitle.
  ///
  /// In zh, this message translates to:
  /// **'历史记录 ({n})'**
  String historyTitle(int n);

  /// No description provided for @exportJson.
  ///
  /// In zh, this message translates to:
  /// **'导出 JSON'**
  String get exportJson;

  /// No description provided for @clearRecords.
  ///
  /// In zh, this message translates to:
  /// **'清除记录'**
  String get clearRecords;

  /// No description provided for @clearToday.
  ///
  /// In zh, this message translates to:
  /// **'清除今日'**
  String get clearToday;

  /// No description provided for @clearLast10.
  ///
  /// In zh, this message translates to:
  /// **'清除最近 10 条'**
  String get clearLast10;

  /// No description provided for @clearLast50.
  ///
  /// In zh, this message translates to:
  /// **'清除最近 50 条'**
  String get clearLast50;

  /// No description provided for @clearAll.
  ///
  /// In zh, this message translates to:
  /// **'清除全部'**
  String get clearAll;

  /// No description provided for @confirmClear.
  ///
  /// In zh, this message translates to:
  /// **'确认清除'**
  String get confirmClear;

  /// No description provided for @clearConfirmMsg.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空全部 {n} 条记录吗？'**
  String clearConfirmMsg(int n);

  /// No description provided for @clearedN.
  ///
  /// In zh, this message translates to:
  /// **'已清除 {n} 条记录'**
  String clearedN(int n);

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索标题/内容/应用'**
  String get searchHint;

  /// No description provided for @noRecords.
  ///
  /// In zh, this message translates to:
  /// **'暂无推送记录'**
  String get noRecords;

  /// No description provided for @noMatchRecords.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的记录'**
  String get noMatchRecords;

  /// No description provided for @notificationDetail.
  ///
  /// In zh, this message translates to:
  /// **'通知详情'**
  String get notificationDetail;

  /// No description provided for @detailInfo.
  ///
  /// In zh, this message translates to:
  /// **'详细信息'**
  String get detailInfo;

  /// No description provided for @noTitle.
  ///
  /// In zh, this message translates to:
  /// **'（无标题）'**
  String get noTitle;

  /// No description provided for @emailSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'邮件转发通道'**
  String get emailSettingsTitle;

  /// No description provided for @noEmailChannels.
  ///
  /// In zh, this message translates to:
  /// **'暂无邮件通道'**
  String get noEmailChannels;

  /// No description provided for @clickToAdd.
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮添加'**
  String get clickToAdd;

  /// No description provided for @addEmailChannel.
  ///
  /// In zh, this message translates to:
  /// **'添加邮件通道'**
  String get addEmailChannel;

  /// No description provided for @editEmailChannel.
  ///
  /// In zh, this message translates to:
  /// **'编辑邮件通道'**
  String get editEmailChannel;

  /// No description provided for @testSend.
  ///
  /// In zh, this message translates to:
  /// **'测试发送'**
  String get testSend;

  /// No description provided for @testAndSave.
  ///
  /// In zh, this message translates to:
  /// **'测试并保存'**
  String get testAndSave;

  /// No description provided for @testPassed.
  ///
  /// In zh, this message translates to:
  /// **'✅ 验证通过'**
  String get testPassed;

  /// No description provided for @testFailed.
  ///
  /// In zh, this message translates to:
  /// **'❌ 验证失败'**
  String get testFailed;

  /// No description provided for @testPassedSaved.
  ///
  /// In zh, this message translates to:
  /// **'测试通过，配置已保存'**
  String get testPassedSaved;

  /// No description provided for @verifyFailed.
  ///
  /// In zh, this message translates to:
  /// **'验证失败: {msg}'**
  String verifyFailed(String msg);

  /// No description provided for @testing.
  ///
  /// In zh, this message translates to:
  /// **'测试中...'**
  String get testing;

  /// No description provided for @channelNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如：QQ邮箱'**
  String get channelNameHint;

  /// No description provided for @smtpHost.
  ///
  /// In zh, this message translates to:
  /// **'SMTP 服务器'**
  String get smtpHost;

  /// No description provided for @smtpPort.
  ///
  /// In zh, this message translates to:
  /// **'端口号'**
  String get smtpPort;

  /// No description provided for @smtpAccount.
  ///
  /// In zh, this message translates to:
  /// **'SMTP 账号'**
  String get smtpAccount;

  /// No description provided for @smtpPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码/授权码'**
  String get smtpPassword;

  /// No description provided for @fromEmail.
  ///
  /// In zh, this message translates to:
  /// **'发件人'**
  String get fromEmail;

  /// No description provided for @toEmail.
  ///
  /// In zh, this message translates to:
  /// **'收件人'**
  String get toEmail;

  /// No description provided for @useSSL.
  ///
  /// In zh, this message translates to:
  /// **'SSL 加密'**
  String get useSSL;

  /// No description provided for @subjectTemplate.
  ///
  /// In zh, this message translates to:
  /// **'主题模板（可选）'**
  String get subjectTemplate;

  /// No description provided for @bodyTemplate.
  ///
  /// In zh, this message translates to:
  /// **'正文模板（可选）'**
  String get bodyTemplate;

  /// No description provided for @presetDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get presetDefault;

  /// No description provided for @presetSimple.
  ///
  /// In zh, this message translates to:
  /// **'简洁'**
  String get presetSimple;

  /// No description provided for @presetDetailed.
  ///
  /// In zh, this message translates to:
  /// **'详细'**
  String get presetDetailed;

  /// No description provided for @presetTime.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get presetTime;

  /// No description provided for @presetCode.
  ///
  /// In zh, this message translates to:
  /// **'验证码'**
  String get presetCode;

  /// No description provided for @presetDevice.
  ///
  /// In zh, this message translates to:
  /// **'设备'**
  String get presetDevice;

  /// No description provided for @presetStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get presetStandard;

  /// No description provided for @presetComplete.
  ///
  /// In zh, this message translates to:
  /// **'完整'**
  String get presetComplete;

  /// No description provided for @presetMinimal.
  ///
  /// In zh, this message translates to:
  /// **'极简'**
  String get presetMinimal;

  /// No description provided for @availableVars.
  ///
  /// In zh, this message translates to:
  /// **'可用变量：%appName% %title% %content% %subText% %packageName% %deviceName% %time% %type% %date% %datetime%'**
  String get availableVars;

  /// No description provided for @webhookSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'Webhook 推送通道'**
  String get webhookSettingsTitle;

  /// No description provided for @webhookUrlRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先输入 Webhook URL'**
  String get webhookUrlRequired;

  /// No description provided for @channelList.
  ///
  /// In zh, this message translates to:
  /// **'通道列表'**
  String get channelList;

  /// No description provided for @addChannel.
  ///
  /// In zh, this message translates to:
  /// **'添加通道'**
  String get addChannel;

  /// No description provided for @webhookDesc1.
  ///
  /// In zh, this message translates to:
  /// **'支持同时配置多个 Webhook 通道，每个通道独立开关'**
  String get webhookDesc1;

  /// No description provided for @webhookDesc2.
  ///
  /// In zh, this message translates to:
  /// **'自动识别企业微信、钉钉、飞书等平台格式'**
  String get webhookDesc2;

  /// No description provided for @webhookDesc3.
  ///
  /// In zh, this message translates to:
  /// **'新添加的通道默认启用'**
  String get webhookDesc3;

  /// No description provided for @channelN.
  ///
  /// In zh, this message translates to:
  /// **'通道 {n}'**
  String channelN(int n);

  /// No description provided for @channelNameOptional.
  ///
  /// In zh, this message translates to:
  /// **'通道名称（可选，如 企业微信·通知）'**
  String get channelNameOptional;

  /// No description provided for @webhookUrlPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com/webhook'**
  String get webhookUrlPlaceholder;

  /// No description provided for @webhookSecretLabel.
  ///
  /// In zh, this message translates to:
  /// **'签名密钥（可选）'**
  String get webhookSecretLabel;

  /// No description provided for @webhookSigned.
  ///
  /// In zh, this message translates to:
  /// **'已签名'**
  String get webhookSigned;

  /// No description provided for @webhookTemplateLabel.
  ///
  /// In zh, this message translates to:
  /// **'推送模板（可选）'**
  String get webhookTemplateLabel;

  /// No description provided for @webhookFormatLabel.
  ///
  /// In zh, this message translates to:
  /// **'消息格式'**
  String get webhookFormatLabel;

  /// No description provided for @feishuMarkdownDowngradeHint.
  ///
  /// In zh, this message translates to:
  /// **'飞书自定义机器人不支持 markdown，将降级为纯文本发送（markdown 符号原样显示）。建议使用 text 格式。'**
  String get feishuMarkdownDowngradeHint;

  /// No description provided for @webhookTemplateHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用预置模板；支持变量：'**
  String get webhookTemplateHint;

  /// No description provided for @webhookTemplateInsertVar.
  ///
  /// In zh, this message translates to:
  /// **'插入变量'**
  String get webhookTemplateInsertVar;

  /// No description provided for @webhookTemplatePreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get webhookTemplatePreview;

  /// No description provided for @platformWechat.
  ///
  /// In zh, this message translates to:
  /// **'WeCom'**
  String get platformWechat;

  /// No description provided for @platformDingtalk.
  ///
  /// In zh, this message translates to:
  /// **'DingTalk'**
  String get platformDingtalk;

  /// No description provided for @platformFeishu.
  ///
  /// In zh, this message translates to:
  /// **'Feishu'**
  String get platformFeishu;

  /// No description provided for @platformGeneric.
  ///
  /// In zh, this message translates to:
  /// **'通用 JSON'**
  String get platformGeneric;

  /// No description provided for @platformWechatDesc.
  ///
  /// In zh, this message translates to:
  /// **'文本格式推送'**
  String get platformWechatDesc;

  /// No description provided for @platformGenericDesc.
  ///
  /// In zh, this message translates to:
  /// **'自定义 JSON 格式'**
  String get platformGenericDesc;

  /// No description provided for @channelTypeLabel.
  ///
  /// In zh, this message translates to:
  /// **'渠道类型'**
  String get channelTypeLabel;

  /// No description provided for @channelTypeAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动识别'**
  String get channelTypeAuto;

  /// No description provided for @channelTypeAutoWith.
  ///
  /// In zh, this message translates to:
  /// **'自动识别（{type}）'**
  String channelTypeAutoWith(String type);

  /// No description provided for @selectChannelType.
  ///
  /// In zh, this message translates to:
  /// **'选择推送渠道'**
  String get selectChannelType;

  /// No description provided for @channelTypeWechat.
  ///
  /// In zh, this message translates to:
  /// **'企业微信群机器人'**
  String get channelTypeWechat;

  /// No description provided for @channelTypeDingtalk.
  ///
  /// In zh, this message translates to:
  /// **'钉钉群机器人'**
  String get channelTypeDingtalk;

  /// No description provided for @channelTypeFeishu.
  ///
  /// In zh, this message translates to:
  /// **'飞书群机器人'**
  String get channelTypeFeishu;

  /// No description provided for @channelTypeTelegram.
  ///
  /// In zh, this message translates to:
  /// **'Telegram'**
  String get channelTypeTelegram;

  /// No description provided for @channelTypeBark.
  ///
  /// In zh, this message translates to:
  /// **'Bark'**
  String get channelTypeBark;

  /// No description provided for @channelTypeServerChan.
  ///
  /// In zh, this message translates to:
  /// **'Server酱'**
  String get channelTypeServerChan;

  /// No description provided for @channelTypePushPlus.
  ///
  /// In zh, this message translates to:
  /// **'PushPlus'**
  String get channelTypePushPlus;

  /// No description provided for @channelTypeGeneric.
  ///
  /// In zh, this message translates to:
  /// **'通用 Webhook'**
  String get channelTypeGeneric;

  /// No description provided for @signingHintWechat.
  ///
  /// In zh, this message translates to:
  /// **'企业微信群机器人开启「签名校验」后生成的密钥'**
  String get signingHintWechat;

  /// No description provided for @signingHintDingtalk.
  ///
  /// In zh, this message translates to:
  /// **'钉钉机器人开启「加签」后生成的密钥（SEC 开头）'**
  String get signingHintDingtalk;

  /// No description provided for @signingHintFeishu.
  ///
  /// In zh, this message translates to:
  /// **'飞书自定义机器人开启「签名校验」后的密钥'**
  String get signingHintFeishu;

  /// No description provided for @signingHintTelegram.
  ///
  /// In zh, this message translates to:
  /// **'Telegram 使用 Bot Token 鉴权，无需签名密钥'**
  String get signingHintTelegram;

  /// No description provided for @signingHintBark.
  ///
  /// In zh, this message translates to:
  /// **'Bark 使用设备 Key 鉴权，无需签名密钥'**
  String get signingHintBark;

  /// No description provided for @signingHintServerChan.
  ///
  /// In zh, this message translates to:
  /// **'Server酱 使用 SendKey 鉴权，无需签名密钥'**
  String get signingHintServerChan;

  /// No description provided for @signingHintPushPlus.
  ///
  /// In zh, this message translates to:
  /// **'PushPlus 使用 Token 鉴权，无需签名密钥'**
  String get signingHintPushPlus;

  /// No description provided for @signingHintGeneric.
  ///
  /// In zh, this message translates to:
  /// **'自建服务端校验签名用的密钥（通过 X-Signature 头传递）'**
  String get signingHintGeneric;

  /// No description provided for @msgFormatDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认格式'**
  String get msgFormatDefault;

  /// No description provided for @msgFormatText.
  ///
  /// In zh, this message translates to:
  /// **'纯文本'**
  String get msgFormatText;

  /// No description provided for @urlEmpty.
  ///
  /// In zh, this message translates to:
  /// **'待输入'**
  String get urlEmpty;

  /// No description provided for @urlPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'请输入 Webhook URL'**
  String get urlPlaceholder;

  /// No description provided for @permSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'权限设置'**
  String get permSettingsTitle;

  /// No description provided for @essentialPerms.
  ///
  /// In zh, this message translates to:
  /// **'必要权限'**
  String get essentialPerms;

  /// No description provided for @notifAccessPerm.
  ///
  /// In zh, this message translates to:
  /// **'通知访问权限'**
  String get notifAccessPerm;

  /// No description provided for @allowNotifications.
  ///
  /// In zh, this message translates to:
  /// **'允许通知'**
  String get allowNotifications;

  /// No description provided for @ignoreBatteryOpt.
  ///
  /// In zh, this message translates to:
  /// **'忽略电池优化'**
  String get ignoreBatteryOpt;

  /// No description provided for @vendorBgSettings.
  ///
  /// In zh, this message translates to:
  /// **'厂商后台设置'**
  String get vendorBgSettings;

  /// No description provided for @xiaomiAutoStart.
  ///
  /// In zh, this message translates to:
  /// **'小米自启动'**
  String get xiaomiAutoStart;

  /// No description provided for @meizuBgRun.
  ///
  /// In zh, this message translates to:
  /// **'魅族后台运行'**
  String get meizuBgRun;

  /// No description provided for @huaweiProtected.
  ///
  /// In zh, this message translates to:
  /// **'华为自启动/受保护应用'**
  String get huaweiProtected;

  /// No description provided for @oppoAutoStart.
  ///
  /// In zh, this message translates to:
  /// **'OPPO自启动管理'**
  String get oppoAutoStart;

  /// No description provided for @vivoBgStart.
  ///
  /// In zh, this message translates to:
  /// **'vivo后台启动管理'**
  String get vivoBgStart;

  /// No description provided for @samsungSettings.
  ///
  /// In zh, this message translates to:
  /// **'三星设备设置'**
  String get samsungSettings;

  /// No description provided for @nativeAndroid.
  ///
  /// In zh, this message translates to:
  /// **'原生Android设置'**
  String get nativeAndroid;

  /// No description provided for @optionalPerms.
  ///
  /// In zh, this message translates to:
  /// **'非必要权限'**
  String get optionalPerms;

  /// No description provided for @smsPerm.
  ///
  /// In zh, this message translates to:
  /// **'短信权限'**
  String get smsPerm;

  /// No description provided for @smsPermDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于获取短信发送者号码和内容'**
  String get smsPermDesc;

  /// No description provided for @phonePerm.
  ///
  /// In zh, this message translates to:
  /// **'电话权限'**
  String get phonePerm;

  /// No description provided for @phonePermDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于获取来电号码和通话状态'**
  String get phonePermDesc;

  /// No description provided for @appListPerm.
  ///
  /// In zh, this message translates to:
  /// **'应用列表权限'**
  String get appListPerm;

  /// No description provided for @appListPermDesc.
  ///
  /// In zh, this message translates to:
  /// **'非必要权限用于提升特定功能的准确性'**
  String get appListPermDesc;

  /// No description provided for @appListPermTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要应用列表权限'**
  String get appListPermTitle;

  /// No description provided for @appListPermMsg.
  ///
  /// In zh, this message translates to:
  /// **'该权限用于获取已安装应用列表，支持按应用过滤通知功能。\n\n点击「允许」后将跳转到系统设置页，请手动开启权限。'**
  String get appListPermMsg;

  /// No description provided for @appListPermExtra.
  ///
  /// In zh, this message translates to:
  /// **'用于获取已安装应用列表，支持按应用过滤通知功能'**
  String get appListPermExtra;

  /// No description provided for @clickToSettings.
  ///
  /// In zh, this message translates to:
  /// **'点击前往设置'**
  String get clickToSettings;

  /// No description provided for @samsungSmartManagerDesc.
  ///
  /// In zh, this message translates to:
  /// **'请在智能管理器中将本应用加入自启动白名单'**
  String get samsungSmartManagerDesc;

  /// No description provided for @nativeBatteryOptDesc.
  ///
  /// In zh, this message translates to:
  /// **'请在系统设置中确认电池优化已关闭'**
  String get nativeBatteryOptDesc;

  /// No description provided for @exactAlarmTitle.
  ///
  /// In zh, this message translates to:
  /// **'精确闹钟（准时推送）'**
  String get exactAlarmTitle;

  /// No description provided for @exactAlarmDesc.
  ///
  /// In zh, this message translates to:
  /// **'延迟/定时推送到点更准时；Android 12+ 需系统授权'**
  String get exactAlarmDesc;

  /// No description provided for @exactAlarmGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授权'**
  String get exactAlarmGranted;

  /// No description provided for @exactAlarmNeedGrant.
  ///
  /// In zh, this message translates to:
  /// **'点击授权'**
  String get exactAlarmNeedGrant;

  /// No description provided for @exactAlarmUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'需 Android 12+'**
  String get exactAlarmUnsupported;

  /// No description provided for @keepAliveGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台保活引导'**
  String get keepAliveGuideTitle;

  /// No description provided for @keepAliveGuideDesc.
  ///
  /// In zh, this message translates to:
  /// **'部分系统会限制后台服务，可能导致收不到通知。按以下步骤设置可提高稳定性：'**
  String get keepAliveGuideDesc;

  /// No description provided for @keepAliveStep1.
  ///
  /// In zh, this message translates to:
  /// **'省电策略设为不限制'**
  String get keepAliveStep1;

  /// No description provided for @keepAliveStep2.
  ///
  /// In zh, this message translates to:
  /// **'允许自启动'**
  String get keepAliveStep2;

  /// No description provided for @keepAliveStep3.
  ///
  /// In zh, this message translates to:
  /// **'后台运行不受限（任务锁定）'**
  String get keepAliveStep3;

  /// No description provided for @keepAliveStep4.
  ///
  /// In zh, this message translates to:
  /// **'确认已开启通知使用权'**
  String get keepAliveStep4;

  /// No description provided for @notes.
  ///
  /// In zh, this message translates to:
  /// **'说明'**
  String get notes;

  /// No description provided for @allow.
  ///
  /// In zh, this message translates to:
  /// **'允许'**
  String get allow;

  /// No description provided for @reject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get reject;

  /// No description provided for @batteryTitle.
  ///
  /// In zh, this message translates to:
  /// **'电量'**
  String get batteryTitle;

  /// No description provided for @addRule.
  ///
  /// In zh, this message translates to:
  /// **'添加规则'**
  String get addRule;

  /// No description provided for @charging.
  ///
  /// In zh, this message translates to:
  /// **'充电中'**
  String get charging;

  /// No description provided for @notCharging.
  ///
  /// In zh, this message translates to:
  /// **'未充电'**
  String get notCharging;

  /// No description provided for @reminderSettings.
  ///
  /// In zh, this message translates to:
  /// **'提醒设置'**
  String get reminderSettings;

  /// No description provided for @batteryNotifToggle.
  ///
  /// In zh, this message translates to:
  /// **'电量通知总开关'**
  String get batteryNotifToggle;

  /// No description provided for @batteryNotifToggleDesc.
  ///
  /// In zh, this message translates to:
  /// **'开启后以下提醒才会生效'**
  String get batteryNotifToggleDesc;

  /// No description provided for @notifRules.
  ///
  /// In zh, this message translates to:
  /// **'通知规则'**
  String get notifRules;

  /// No description provided for @batteryNotes1.
  ///
  /// In zh, this message translates to:
  /// **'低电量提醒仅在非充电状态下触发'**
  String get batteryNotes1;

  /// No description provided for @batteryNotes2.
  ///
  /// In zh, this message translates to:
  /// **'电量回升到阈值以上才会重置提醒状态'**
  String get batteryNotes2;

  /// No description provided for @batteryNotes3.
  ///
  /// In zh, this message translates to:
  /// **'电量通知随通知监听服务一起运行'**
  String get batteryNotes3;

  /// No description provided for @batteryNotes4.
  ///
  /// In zh, this message translates to:
  /// **'点击规则可编辑，左滑或长按可删除'**
  String get batteryNotes4;

  /// No description provided for @closeBatteryOpt.
  ///
  /// In zh, this message translates to:
  /// **'关闭电池优化'**
  String get closeBatteryOpt;

  /// No description provided for @batteryOptDesc.
  ///
  /// In zh, this message translates to:
  /// **'息屏后系统会限制后台运行，可能导致通知监听服务停止'**
  String get batteryOptDesc;

  /// No description provided for @ruleStartCharging.
  ///
  /// In zh, this message translates to:
  /// **'手机接入充电器时推送'**
  String get ruleStartCharging;

  /// No description provided for @ruleStopCharging.
  ///
  /// In zh, this message translates to:
  /// **'手机断开充电器时推送'**
  String get ruleStopCharging;

  /// No description provided for @ruleAboveThreshold.
  ///
  /// In zh, this message translates to:
  /// **'电量达到 {n}% 时推送'**
  String ruleAboveThreshold(int n);

  /// No description provided for @ruleBelowThreshold.
  ///
  /// In zh, this message translates to:
  /// **'电量低于 {n}% 时推送'**
  String ruleBelowThreshold(int n);

  /// No description provided for @ruleEqualThreshold.
  ///
  /// In zh, this message translates to:
  /// **'电量等于 {n}% 时推送'**
  String ruleEqualThreshold(int n);

  /// No description provided for @ruleUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知规则类型'**
  String get ruleUnknown;

  /// No description provided for @confirmDeleteRule.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get confirmDeleteRule;

  /// No description provided for @confirmDeleteRuleMsg.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除规则「{title}」吗？'**
  String confirmDeleteRuleMsg(String title);

  /// No description provided for @editRule.
  ///
  /// In zh, this message translates to:
  /// **'编辑规则'**
  String get editRule;

  /// No description provided for @ruleType.
  ///
  /// In zh, this message translates to:
  /// **'规则类型'**
  String get ruleType;

  /// No description provided for @startCharging.
  ///
  /// In zh, this message translates to:
  /// **'开始充电'**
  String get startCharging;

  /// No description provided for @stopCharging.
  ///
  /// In zh, this message translates to:
  /// **'断开充电'**
  String get stopCharging;

  /// No description provided for @belowValue.
  ///
  /// In zh, this message translates to:
  /// **'低于某值'**
  String get belowValue;

  /// No description provided for @aboveValue.
  ///
  /// In zh, this message translates to:
  /// **'高于某值'**
  String get aboveValue;

  /// No description provided for @equalValue.
  ///
  /// In zh, this message translates to:
  /// **'等于某值'**
  String get equalValue;

  /// No description provided for @threshold.
  ///
  /// In zh, this message translates to:
  /// **'电量阈值（%）'**
  String get threshold;

  /// No description provided for @customTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义标题（可选）'**
  String get customTitle;

  /// No description provided for @customTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用默认标题'**
  String get customTitleHint;

  /// No description provided for @batteryReminder.
  ///
  /// In zh, this message translates to:
  /// **'电量提醒'**
  String get batteryReminder;

  /// No description provided for @deleteRule.
  ///
  /// In zh, this message translates to:
  /// **'删除规则'**
  String get deleteRule;

  /// No description provided for @confirmDeleteThisRule.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除这条通知规则吗？'**
  String get confirmDeleteThisRule;

  /// No description provided for @setDeviceName.
  ///
  /// In zh, this message translates to:
  /// **'设置设备名称'**
  String get setDeviceName;

  /// No description provided for @deviceNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'设备名称'**
  String get deviceNameLabel;

  /// No description provided for @aboutDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get aboutDialogTitle;

  /// No description provided for @author.
  ///
  /// In zh, this message translates to:
  /// **'作者：幻念团队 fnthinklevi'**
  String get author;

  /// No description provided for @appDesc.
  ///
  /// In zh, this message translates to:
  /// **'监听通知栏所有通知并推送到 Webhook'**
  String get appDesc;

  /// No description provided for @appFeatures.
  ///
  /// In zh, this message translates to:
  /// **'支持：微信 / QQ / 短信 / 来电 / 电量提醒'**
  String get appFeatures;

  /// No description provided for @ruleListTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则管理'**
  String get ruleListTitle;

  /// No description provided for @ruleNew.
  ///
  /// In zh, this message translates to:
  /// **'新规则'**
  String get ruleNew;

  /// No description provided for @ruleNoCondition.
  ///
  /// In zh, this message translates to:
  /// **'无条件'**
  String get ruleNoCondition;

  /// No description provided for @ruleNoAction.
  ///
  /// In zh, this message translates to:
  /// **'无动作'**
  String get ruleNoAction;

  /// No description provided for @ruleListEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无规则'**
  String get ruleListEmpty;

  /// No description provided for @ruleAddFirst.
  ///
  /// In zh, this message translates to:
  /// **'添加第一条规则'**
  String get ruleAddFirst;

  /// No description provided for @rulePriorityBadge.
  ///
  /// In zh, this message translates to:
  /// **'优先级 {n}'**
  String rulePriorityBadge(int n);

  /// No description provided for @ruleGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则引擎介绍'**
  String get ruleGuideTitle;

  /// No description provided for @ruleGuideAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加规则'**
  String get ruleGuideAdd;

  /// No description provided for @ruleGuideAddDesc.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角「+」或右下角浮动按钮创建新规则'**
  String get ruleGuideAddDesc;

  /// No description provided for @ruleGuideCondition.
  ///
  /// In zh, this message translates to:
  /// **'设置条件'**
  String get ruleGuideCondition;

  /// No description provided for @ruleGuideConditionDesc.
  ///
  /// In zh, this message translates to:
  /// **'配置触发规则的条件（IF），如应用包名、关键词、时间等'**
  String get ruleGuideConditionDesc;

  /// No description provided for @ruleGuideAction.
  ///
  /// In zh, this message translates to:
  /// **'执行动作'**
  String get ruleGuideAction;

  /// No description provided for @ruleGuideActionDesc.
  ///
  /// In zh, this message translates to:
  /// **'设置满足条件后执行的动作（THEN），如推送通知、静默忽略等'**
  String get ruleGuideActionDesc;

  /// No description provided for @ruleGuideEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用规则'**
  String get ruleGuideEnable;

  /// No description provided for @ruleGuideEnableDesc.
  ///
  /// In zh, this message translates to:
  /// **'通过开关控制规则是否生效，未启用的规则不会执行'**
  String get ruleGuideEnableDesc;

  /// No description provided for @ruleGuideTip.
  ///
  /// In zh, this message translates to:
  /// **'提示：规则按优先级顺序执行，匹配第一条规则后即停止。可通过编辑规则调整优先级。'**
  String get ruleGuideTip;

  /// No description provided for @ruleGuideGotIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get ruleGuideGotIt;

  /// No description provided for @ruleHelp.
  ///
  /// In zh, this message translates to:
  /// **'使用帮助'**
  String get ruleHelp;

  /// No description provided for @ruleAddTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加规则'**
  String get ruleAddTooltip;

  /// No description provided for @ruleDeleteMsg.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除规则「{name}」吗？'**
  String ruleDeleteMsg(String name);

  /// No description provided for @ruleEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑规则'**
  String get ruleEditTitle;

  /// No description provided for @ruleName.
  ///
  /// In zh, this message translates to:
  /// **'规则名称'**
  String get ruleName;

  /// No description provided for @ruleNameHint.
  ///
  /// In zh, this message translates to:
  /// **'输入规则名称'**
  String get ruleNameHint;

  /// No description provided for @ruleDescription.
  ///
  /// In zh, this message translates to:
  /// **'规则描述'**
  String get ruleDescription;

  /// No description provided for @ruleDescriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'可选，描述规则用途'**
  String get ruleDescriptionHint;

  /// No description provided for @ruleConditions.
  ///
  /// In zh, this message translates to:
  /// **'条件（IF）'**
  String get ruleConditions;

  /// No description provided for @ruleActions.
  ///
  /// In zh, this message translates to:
  /// **'动作（THEN）'**
  String get ruleActions;

  /// No description provided for @ruleAddCondition.
  ///
  /// In zh, this message translates to:
  /// **'添加条件'**
  String get ruleAddCondition;

  /// No description provided for @ruleAddAction.
  ///
  /// In zh, this message translates to:
  /// **'添加动作'**
  String get ruleAddAction;

  /// No description provided for @rulePriority.
  ///
  /// In zh, this message translates to:
  /// **'规则优先级'**
  String get rulePriority;

  /// No description provided for @rulePriorityNote.
  ///
  /// In zh, this message translates to:
  /// **'优先级越高，规则越先执行。相同优先级按添加顺序执行。'**
  String get rulePriorityNote;

  /// No description provided for @rulePDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认 (0)'**
  String get rulePDefault;

  /// No description provided for @rulePLow.
  ///
  /// In zh, this message translates to:
  /// **'低 (50)'**
  String get rulePLow;

  /// No description provided for @rulePMedium.
  ///
  /// In zh, this message translates to:
  /// **'中 (100)'**
  String get rulePMedium;

  /// No description provided for @rulePHigh.
  ///
  /// In zh, this message translates to:
  /// **'高 (200)'**
  String get rulePHigh;

  /// No description provided for @rulePHighest.
  ///
  /// In zh, this message translates to:
  /// **'最高 (500)'**
  String get rulePHighest;

  /// No description provided for @ruleSelect.
  ///
  /// In zh, this message translates to:
  /// **'请选择'**
  String get ruleSelect;

  /// No description provided for @ruleEditCondition.
  ///
  /// In zh, this message translates to:
  /// **'编辑条件'**
  String get ruleEditCondition;

  /// No description provided for @ruleAddConditionTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加条件'**
  String get ruleAddConditionTitle;

  /// No description provided for @ruleConditionType.
  ///
  /// In zh, this message translates to:
  /// **'条件类型'**
  String get ruleConditionType;

  /// No description provided for @ruleConditionValue.
  ///
  /// In zh, this message translates to:
  /// **'条件值'**
  String get ruleConditionValue;

  /// No description provided for @ruleLogic.
  ///
  /// In zh, this message translates to:
  /// **'逻辑运算符'**
  String get ruleLogic;

  /// No description provided for @ruleEditAction.
  ///
  /// In zh, this message translates to:
  /// **'编辑动作'**
  String get ruleEditAction;

  /// No description provided for @ruleAddActionTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加动作'**
  String get ruleAddActionTitle;

  /// No description provided for @ruleActionType.
  ///
  /// In zh, this message translates to:
  /// **'动作类型'**
  String get ruleActionType;

  /// No description provided for @ruleDelayTitle.
  ///
  /// In zh, this message translates to:
  /// **'延迟推送参数（至少填写一项）'**
  String get ruleDelayTitle;

  /// No description provided for @ruleDelaySeconds.
  ///
  /// In zh, this message translates to:
  /// **'延迟秒数'**
  String get ruleDelaySeconds;

  /// No description provided for @ruleDelaySecondsHint.
  ///
  /// In zh, this message translates to:
  /// **'如 60 = 延迟 1 分钟'**
  String get ruleDelaySecondsHint;

  /// No description provided for @ruleScheduleTime.
  ///
  /// In zh, this message translates to:
  /// **'定时时间'**
  String get ruleScheduleTime;

  /// No description provided for @ruleScheduleTimeHint.
  ///
  /// In zh, this message translates to:
  /// **'如 22:00（当日到点推送）'**
  String get ruleScheduleTimeHint;

  /// No description provided for @ruleBasicInfo.
  ///
  /// In zh, this message translates to:
  /// **'基本信息'**
  String get ruleBasicInfo;

  /// No description provided for @ruleEnableRule.
  ///
  /// In zh, this message translates to:
  /// **'启用规则'**
  String get ruleEnableRule;

  /// No description provided for @ruleEmptyConditions.
  ///
  /// In zh, this message translates to:
  /// **'暂无条件，点击添加'**
  String get ruleEmptyConditions;

  /// No description provided for @ruleEmptyActions.
  ///
  /// In zh, this message translates to:
  /// **'暂无动作，点击添加'**
  String get ruleEmptyActions;

  /// No description provided for @ruleDelayMinute.
  ///
  /// In zh, this message translates to:
  /// **'延迟 {n} 分钟'**
  String ruleDelayMinute(int n);

  /// No description provided for @ruleDelaySecond.
  ///
  /// In zh, this message translates to:
  /// **'延迟 {n} 秒'**
  String ruleDelaySecond(int n);

  /// No description provided for @ruleScheduleAt.
  ///
  /// In zh, this message translates to:
  /// **'定时 {t}'**
  String ruleScheduleAt(String t);

  /// No description provided for @condPackage.
  ///
  /// In zh, this message translates to:
  /// **'应用包名'**
  String get condPackage;

  /// No description provided for @condTitleContains.
  ///
  /// In zh, this message translates to:
  /// **'标题包含'**
  String get condTitleContains;

  /// No description provided for @condTitleNotContains.
  ///
  /// In zh, this message translates to:
  /// **'标题不包含'**
  String get condTitleNotContains;

  /// No description provided for @condContentContains.
  ///
  /// In zh, this message translates to:
  /// **'内容包含'**
  String get condContentContains;

  /// No description provided for @condContentNotContains.
  ///
  /// In zh, this message translates to:
  /// **'内容不包含'**
  String get condContentNotContains;

  /// No description provided for @condPriority.
  ///
  /// In zh, this message translates to:
  /// **'通知优先级'**
  String get condPriority;

  /// No description provided for @condTimeRange.
  ///
  /// In zh, this message translates to:
  /// **'时间范围'**
  String get condTimeRange;

  /// No description provided for @condRegex.
  ///
  /// In zh, this message translates to:
  /// **'正则表达式'**
  String get condRegex;

  /// No description provided for @hintPackage.
  ///
  /// In zh, this message translates to:
  /// **'例如: com.example.app'**
  String get hintPackage;

  /// No description provided for @hintKeyword.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词'**
  String get hintKeyword;

  /// No description provided for @hintPriority.
  ///
  /// In zh, this message translates to:
  /// **'高/中/低'**
  String get hintPriority;

  /// No description provided for @hintTimeRange.
  ///
  /// In zh, this message translates to:
  /// **'09:00-18:00'**
  String get hintTimeRange;

  /// No description provided for @hintRegex.
  ///
  /// In zh, this message translates to:
  /// **'正则表达式'**
  String get hintRegex;

  /// No description provided for @actionPush.
  ///
  /// In zh, this message translates to:
  /// **'推送通知'**
  String get actionPush;

  /// No description provided for @actionSilent.
  ///
  /// In zh, this message translates to:
  /// **'静默忽略'**
  String get actionSilent;

  /// No description provided for @actionDelay.
  ///
  /// In zh, this message translates to:
  /// **'延迟推送'**
  String get actionDelay;

  /// No description provided for @actionMerge.
  ///
  /// In zh, this message translates to:
  /// **'合并推送'**
  String get actionMerge;

  /// No description provided for @actionRecord.
  ///
  /// In zh, this message translates to:
  /// **'仅记录'**
  String get actionRecord;

  /// No description provided for @actionPushDesc.
  ///
  /// In zh, this message translates to:
  /// **'将通知推送到指定渠道'**
  String get actionPushDesc;

  /// No description provided for @actionSilentDesc.
  ///
  /// In zh, this message translates to:
  /// **'不推送，静默处理'**
  String get actionSilentDesc;

  /// No description provided for @actionDelayDesc.
  ///
  /// In zh, this message translates to:
  /// **'延迟一段时间后推送'**
  String get actionDelayDesc;

  /// No description provided for @actionMergeDesc.
  ///
  /// In zh, this message translates to:
  /// **'合并同应用多条通知'**
  String get actionMergeDesc;

  /// No description provided for @actionRecordDesc.
  ///
  /// In zh, this message translates to:
  /// **'仅记录到历史，不推送'**
  String get actionRecordDesc;

  /// No description provided for @logicAnd.
  ///
  /// In zh, this message translates to:
  /// **'且'**
  String get logicAnd;

  /// No description provided for @logicOr.
  ///
  /// In zh, this message translates to:
  /// **'或'**
  String get logicOr;

  /// No description provided for @keywordTitle.
  ///
  /// In zh, this message translates to:
  /// **'关键词过滤'**
  String get keywordTitle;

  /// No description provided for @keywordWhitelist.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get keywordWhitelist;

  /// No description provided for @keywordBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get keywordBlacklist;

  /// No description provided for @keywordWhitelistHint.
  ///
  /// In zh, this message translates to:
  /// **'输入白名单关键词'**
  String get keywordWhitelistHint;

  /// No description provided for @keywordBlacklistHint.
  ///
  /// In zh, this message translates to:
  /// **'输入黑名单关键词'**
  String get keywordBlacklistHint;

  /// No description provided for @keywordWhitelistDesc.
  ///
  /// In zh, this message translates to:
  /// **'白名单：通知内容包含任一关键词时，即使应用未被选中也会推送（优先级最高）'**
  String get keywordWhitelistDesc;

  /// No description provided for @keywordBlacklistDesc.
  ///
  /// In zh, this message translates to:
  /// **'黑名单：通知内容包含任一关键词时，即使应用被选中也不会推送'**
  String get keywordBlacklistDesc;

  /// No description provided for @keywordWhitelistEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无白名单关键词'**
  String get keywordWhitelistEmpty;

  /// No description provided for @keywordBlacklistEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无黑名单关键词'**
  String get keywordBlacklistEmpty;

  /// No description provided for @initializing.
  ///
  /// In zh, this message translates to:
  /// **'正在初始化...'**
  String get initializing;

  /// No description provided for @loadWebhook.
  ///
  /// In zh, this message translates to:
  /// **'加载 Webhook 配置...'**
  String get loadWebhook;

  /// No description provided for @loadBattery.
  ///
  /// In zh, this message translates to:
  /// **'加载电池配置...'**
  String get loadBattery;

  /// No description provided for @loadRecords.
  ///
  /// In zh, this message translates to:
  /// **'加载通知记录...'**
  String get loadRecords;

  /// No description provided for @loadFilter.
  ///
  /// In zh, this message translates to:
  /// **'加载过滤配置...'**
  String get loadFilter;

  /// No description provided for @initUpdate.
  ///
  /// In zh, this message translates to:
  /// **'初始化更新服务...'**
  String get initUpdate;

  /// No description provided for @initRetry.
  ///
  /// In zh, this message translates to:
  /// **'初始化重试服务...'**
  String get initRetry;

  /// No description provided for @initComplete.
  ///
  /// In zh, this message translates to:
  /// **'初始化完成'**
  String get initComplete;

  /// No description provided for @initFailed.
  ///
  /// In zh, this message translates to:
  /// **'应用启动失败'**
  String get initFailed;

  /// No description provided for @initFailedMsg.
  ///
  /// In zh, this message translates to:
  /// **'依赖注入初始化失败，请重启应用'**
  String get initFailedMsg;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @pageInitFailed.
  ///
  /// In zh, this message translates to:
  /// **'页面初始化失败: {e}'**
  String pageInitFailed(String e);

  /// No description provided for @webhookSaved.
  ///
  /// In zh, this message translates to:
  /// **'Webhook 配置已保存'**
  String get webhookSaved;

  /// No description provided for @emailSaved.
  ///
  /// In zh, this message translates to:
  /// **'邮件通道配置已保存'**
  String get emailSaved;

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get unknownError;

  /// No description provided for @testFailedMsg.
  ///
  /// In zh, this message translates to:
  /// **'测试失败: {e}'**
  String testFailedMsg(String e);

  /// No description provided for @unknownResult.
  ///
  /// In zh, this message translates to:
  /// **'未知结果'**
  String get unknownResult;

  /// No description provided for @iconDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认图标'**
  String get iconDefault;

  /// No description provided for @iconBlue.
  ///
  /// In zh, this message translates to:
  /// **'蓝色'**
  String get iconBlue;

  /// No description provided for @iconCyan.
  ///
  /// In zh, this message translates to:
  /// **'天蓝'**
  String get iconCyan;

  /// No description provided for @iconTeal.
  ///
  /// In zh, this message translates to:
  /// **'青色'**
  String get iconTeal;

  /// No description provided for @iconMint.
  ///
  /// In zh, this message translates to:
  /// **'薄荷'**
  String get iconMint;

  /// No description provided for @iconGreen.
  ///
  /// In zh, this message translates to:
  /// **'绿色'**
  String get iconGreen;

  /// No description provided for @iconYellow.
  ///
  /// In zh, this message translates to:
  /// **'黄色'**
  String get iconYellow;

  /// No description provided for @iconOrange.
  ///
  /// In zh, this message translates to:
  /// **'橙色'**
  String get iconOrange;

  /// No description provided for @iconRed.
  ///
  /// In zh, this message translates to:
  /// **'红色'**
  String get iconRed;

  /// No description provided for @iconPink.
  ///
  /// In zh, this message translates to:
  /// **'粉色'**
  String get iconPink;

  /// No description provided for @iconRose.
  ///
  /// In zh, this message translates to:
  /// **'玫红'**
  String get iconRose;

  /// No description provided for @iconPurple.
  ///
  /// In zh, this message translates to:
  /// **'紫色'**
  String get iconPurple;

  /// No description provided for @iconIndigo.
  ///
  /// In zh, this message translates to:
  /// **'靛蓝'**
  String get iconIndigo;

  /// No description provided for @iconBrown.
  ///
  /// In zh, this message translates to:
  /// **'棕色'**
  String get iconBrown;

  /// No description provided for @iconGray.
  ///
  /// In zh, this message translates to:
  /// **'灰色'**
  String get iconGray;

  /// No description provided for @iconGraphite.
  ///
  /// In zh, this message translates to:
  /// **'深灰'**
  String get iconGraphite;

  /// No description provided for @iconBlack.
  ///
  /// In zh, this message translates to:
  /// **'墨黑'**
  String get iconBlack;

  /// No description provided for @appIconTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用图标'**
  String get appIconTitle;

  /// No description provided for @currentIcon.
  ///
  /// In zh, this message translates to:
  /// **'当前：{label}'**
  String currentIcon(String label);

  /// No description provided for @iconSwitched.
  ///
  /// In zh, this message translates to:
  /// **'已切换至「{label}」，桌面稍后刷新'**
  String iconSwitched(String label);

  /// No description provided for @iconSwitchFailed.
  ///
  /// In zh, this message translates to:
  /// **'切换失败'**
  String get iconSwitchFailed;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @refreshAppList.
  ///
  /// In zh, this message translates to:
  /// **'更新软件列表'**
  String get refreshAppList;

  /// No description provided for @appFilterBlockModeInfo.
  ///
  /// In zh, this message translates to:
  /// **'当前模式：不通知应用 — 未选择时全部应用都推送通知'**
  String get appFilterBlockModeInfo;

  /// No description provided for @appFilterBlockModeSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {n} 个应用，这些应用的通知不会被推送'**
  String appFilterBlockModeSelected(int n);

  /// No description provided for @appFilterAllowModeInfo.
  ///
  /// In zh, this message translates to:
  /// **'当前模式：通知应用 — 未选择时全部应用都推送通知（默认）'**
  String get appFilterAllowModeInfo;

  /// No description provided for @appFilterAllowModeSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {n} 个应用，仅这些应用的通知会被推送'**
  String appFilterAllowModeSelected(int n);

  /// No description provided for @filterNotifyApps.
  ///
  /// In zh, this message translates to:
  /// **'通知应用'**
  String get filterNotifyApps;

  /// No description provided for @filterBlockApps.
  ///
  /// In zh, this message translates to:
  /// **'不通知应用'**
  String get filterBlockApps;

  /// No description provided for @appListPermDesc2.
  ///
  /// In zh, this message translates to:
  /// **'为了能够筛选需要推送通知的应用，请授予应用读取已安装应用列表的权限。'**
  String get appListPermDesc2;

  /// No description provided for @goEnablePermission.
  ///
  /// In zh, this message translates to:
  /// **'前往开启权限'**
  String get goEnablePermission;

  /// No description provided for @refreshRetry.
  ///
  /// In zh, this message translates to:
  /// **'刷新重试'**
  String get refreshRetry;

  /// No description provided for @searchAppHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索应用名称或包名'**
  String get searchAppHint;

  /// No description provided for @showSystemApps.
  ///
  /// In zh, this message translates to:
  /// **'显示系统应用'**
  String get showSystemApps;

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get deselectAll;

  /// No description provided for @invertSelection.
  ///
  /// In zh, this message translates to:
  /// **'反选'**
  String get invertSelection;

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n}'**
  String selectedCount(int n);

  /// No description provided for @unselectedCount.
  ///
  /// In zh, this message translates to:
  /// **'未选 {n}'**
  String unselectedCount(int n);

  /// No description provided for @noAppsFound.
  ///
  /// In zh, this message translates to:
  /// **'没有找到应用'**
  String get noAppsFound;

  /// No description provided for @refreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败：{e}'**
  String refreshFailed(String e);

  /// No description provided for @appFilterNoPermPrompt.
  ///
  /// In zh, this message translates to:
  /// **'当前无应用列表读取权限，无法进行应用筛选。\n若需进行应用筛选，请点击授予应用列表读取权限'**
  String get appFilterNoPermPrompt;

  /// No description provided for @smsMonitor.
  ///
  /// In zh, this message translates to:
  /// **'短信监听'**
  String get smsMonitor;

  /// No description provided for @smsMonitorDesc.
  ///
  /// In zh, this message translates to:
  /// **'控制是否监听收到的短信并推送'**
  String get smsMonitorDesc;

  /// No description provided for @smsMonitorSettings.
  ///
  /// In zh, this message translates to:
  /// **'短信监听设置'**
  String get smsMonitorSettings;

  /// No description provided for @smsMonitorTotalDesc.
  ///
  /// In zh, this message translates to:
  /// **'关闭后将不再监听、推送任何短信'**
  String get smsMonitorTotalDesc;

  /// No description provided for @simFilterTitle.
  ///
  /// In zh, this message translates to:
  /// **'监听卡'**
  String get simFilterTitle;

  /// No description provided for @simFilterDesc.
  ///
  /// In zh, this message translates to:
  /// **'同时作用于短信和电话'**
  String get simFilterDesc;

  /// No description provided for @simFilterSingleSim.
  ///
  /// In zh, this message translates to:
  /// **'当前设备仅检测到一张SIM卡，无需选择'**
  String get simFilterSingleSim;

  /// No description provided for @simFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get simFilterAll;

  /// No description provided for @simFilterSim1.
  ///
  /// In zh, this message translates to:
  /// **'仅卡1'**
  String get simFilterSim1;

  /// No description provided for @simFilterSim2.
  ///
  /// In zh, this message translates to:
  /// **'仅卡2'**
  String get simFilterSim2;

  /// No description provided for @simFilterRemindTitle.
  ///
  /// In zh, this message translates to:
  /// **'部分短信可能无法识别所属卡'**
  String get simFilterRemindTitle;

  /// No description provided for @simFilterRemindMsg.
  ///
  /// In zh, this message translates to:
  /// **'由于小米等系统的限制，部分短信无法识别所属卡（通知栏兜底链路）。这些短信不受该设置影响，将照常推送。'**
  String get simFilterRemindMsg;

  /// No description provided for @codeMonitor.
  ///
  /// In zh, this message translates to:
  /// **'监听验证码'**
  String get codeMonitor;

  /// No description provided for @codeMonitorDesc.
  ///
  /// In zh, this message translates to:
  /// **'关闭后，包含验证码的短信将不会被推送'**
  String get codeMonitorDesc;

  /// No description provided for @widgetBrandCurrentDevice.
  ///
  /// In zh, this message translates to:
  /// **'当前设备'**
  String get widgetBrandCurrentDevice;

  /// No description provided for @statsToday.
  ///
  /// In zh, this message translates to:
  /// **'今日推送'**
  String get statsToday;

  /// No description provided for @statsTotal.
  ///
  /// In zh, this message translates to:
  /// **'总推送数'**
  String get statsTotal;

  /// No description provided for @statsApps.
  ///
  /// In zh, this message translates to:
  /// **'应用数'**
  String get statsApps;

  /// No description provided for @statsTrend.
  ///
  /// In zh, this message translates to:
  /// **'近7天推送趋势'**
  String get statsTrend;

  /// No description provided for @statsNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get statsNoData;

  /// No description provided for @statsRank.
  ///
  /// In zh, this message translates to:
  /// **'应用推送排行'**
  String get statsRank;

  /// No description provided for @deliverySuccess.
  ///
  /// In zh, this message translates to:
  /// **'推送成功'**
  String get deliverySuccess;

  /// No description provided for @deliveryFailed.
  ///
  /// In zh, this message translates to:
  /// **'推送失败'**
  String get deliveryFailed;

  /// No description provided for @deliveryPending.
  ///
  /// In zh, this message translates to:
  /// **'发送中'**
  String get deliveryPending;

  /// No description provided for @pushPausedByUser.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get pushPausedByUser;

  /// No description provided for @deliveryIntercepted.
  ///
  /// In zh, this message translates to:
  /// **'已拦截'**
  String get deliveryIntercepted;

  /// No description provided for @pushNow.
  ///
  /// In zh, this message translates to:
  /// **'现在推送'**
  String get pushNow;

  /// No description provided for @privacyOverviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策概述'**
  String get privacyOverviewTitle;

  /// No description provided for @privacyOverviewContent.
  ///
  /// In zh, this message translates to:
  /// **'通知推送助手（以下简称\"本应用\"）由幻念团队开发并运营。本应用高度重视您的个人信息与隐私保护，在您使用本应用前，请仔细阅读本隐私政策，了解我们如何收集、使用、存储和保护您的信息。\n\n本政策适用于本应用提供的所有服务。当您安装并使用本应用时，即表示您已阅读、理解并同意本政策的全部内容。'**
  String get privacyOverviewContent;

  /// No description provided for @privacyInfoTitle.
  ///
  /// In zh, this message translates to:
  /// **'我们收集的信息'**
  String get privacyInfoTitle;

  /// No description provided for @privacyInfoContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用遵循\"最小必要\"原则，仅收集实现核心功能所必需的信息：\n\n1. 通知内容（本地处理）\n   - 应用通过系统通知监听服务读取通知内容\n   - 所有通知内容仅在设备本地完成规则匹配、关键词过滤，并按您自行配置的 Webhook 或邮件地址转发\n   - 通知内容不会上传至除您指定目标以外的任何服务器\n\n2. 崩溃统计信息（腾讯 Bugly，默认关闭）\n   - 仅当你在「更多 → 崩溃上报」主动开启后，才收集应用崩溃时的堆栈信息、设备型号、系统版本、应用版本号、CPU 架构\n   - 未开启时 SDK 不初始化、数据不出网；开启后仅用于定位和修复崩溃问题，提升应用稳定性\n\n3. 推送统计与历史记录（本地存储）\n   - 通知记录、推送状态、每日统计等数据使用 AES-256 加密存储在本地数据库\n   - 这些数据仅保存在您的设备上，不会对外发送\n\n4. 延迟推送队列（本地存储）\n   - 规则引擎产生的延迟/定时推送任务持久化保存在本机，重启后不丢失\n\n5. 电池状态（本地监控）\n   - 电量及充电状态监控仅在本机采集，用于首页展示，不对外发送\n\n6. 已安装应用列表（本地使用）\n   - 用于规则引擎条件配置与应用过滤，仅在本机使用'**
  String get privacyInfoContent;

  /// No description provided for @privacyNoCollectTitle.
  ///
  /// In zh, this message translates to:
  /// **'我们不收集的信息'**
  String get privacyNoCollectTitle;

  /// No description provided for @privacyNoCollectContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用不会收集以下个人隐私信息：\n\n• 通讯录、短信内容（除非您主动授权用于短信通知识别）\n• 位置信息\n• 通话记录\n• 相册、文件内容\n• 麦克风、摄像头数据\n• 个人身份信息（姓名、身份证号、手机号等）\n\n当您不同意授权时，本应用的相关可选功能将不可用，但核心通知转发功能不受影响。'**
  String get privacyNoCollectContent;

  /// No description provided for @privacyShareTitle.
  ///
  /// In zh, this message translates to:
  /// **'信息共享与披露'**
  String get privacyShareTitle;

  /// No description provided for @privacyShareContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用不会出售、出租或交易您的个人信息。仅在以下情形中共享必要的信息：\n\n1. 您主动配置的转发目标\n   - 当您配置 Webhook（企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus）或 SMTP 邮件后，您选择转发的通知内容将发送至这些您指定的第三方平台\n   - 发送前需要您明确配置目标地址，未配置不会发生任何数据外发\n\n2. 第三方崩溃统计服务（腾讯 Bugly，默认关闭）\n   - 仅在你主动开启崩溃上报后，才共享崩溃堆栈及设备基础环境信息，用于修复问题\n\n3. 法律法规要求\n   - 依据法律、法规或有权机关的要求披露相关信息'**
  String get privacyShareContent;

  /// No description provided for @privacyStorageTitle.
  ///
  /// In zh, this message translates to:
  /// **'数据存储与安全'**
  String get privacyStorageTitle;

  /// No description provided for @privacyStorageContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用采用多层安全机制保护您的数据：\n\n1. 本地数据库加密\n   - 通知历史记录、推送统计使用 AES-256 加密存储（sqflite_sqlcipher）\n   - 加密密钥保存在 Android 系统密钥库（AndroidKeyStore）中\n   - 即使设备被他人获取，也无法直接读取数据库内容\n\n2. 敏感配置加密\n   - Webhook URL、SMTP 账号、TOTP 密钥等敏感配置使用 AndroidKeyStore / AES-256-GCM 加密存储\n   - 不会以明文形式保存在 SharedPreferences 中\n\n3. 网络传输安全\n   - 全站强制 HTTPS，禁止明文 HTTP 传输\n   - 管理后台 Token 仅通过 HTTP Header 传递，不出现在 URL 中\n\n4. 其他安全措施\n   - 管理后台二步验证（TOTP）\n   - 应用备份已禁用（allowBackup=false），防止数据通过云备份泄露\n   - 应用内广播接收器已加固，防止外部伪造通知数据\n\n5. 数据保留\n   - 您可随时在应用内清除全部或部分推送历史记录\n   - 卸载应用将清除全部本地数据'**
  String get privacyStorageContent;

  /// No description provided for @privacyThirdPartyTitle.
  ///
  /// In zh, this message translates to:
  /// **'第三方服务'**
  String get privacyThirdPartyTitle;

  /// No description provided for @privacyThirdPartyContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用使用以下第三方服务：\n\n腾讯 Bugly（崩溃统计，默认关闭）\n• 服务商：深圳市腾讯计算机系统有限公司\n• 用途：需你在「更多 → 崩溃上报」主动开启后才收集应用崩溃信息，帮助定位和修复问题；关闭后下次启动不再初始化\n• 隐私政策：https://privacy.qq.com/\n• 采集数据：崩溃堆栈、设备型号、系统版本、应用版本、CPU 架构\n\n用户主动配置的推送目标（非 SDK）\n• 企业微信、钉钉、飞书、Telegram、Bark、Server酱、PushPlus、SMTP 邮件服务器\n• 本应用仅向您自行配置的地址发送您选择转发的通知内容，不对第三方平台的数据处理行为负责\n• 涉及上述平台的隐私政策，请查阅对应平台官方文档'**
  String get privacyThirdPartyContent;

  /// No description provided for @privacyPermTitle.
  ///
  /// In zh, this message translates to:
  /// **'权限说明'**
  String get privacyPermTitle;

  /// No description provided for @privacyPermContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用遵循最小权限原则，以下为完整权限清单及用途说明：\n\n核心权限（必需）：\n• 通知使用权（Notification Listener）：读取通知内容，实现转发与规则引擎功能\n• 网络访问（INTERNET）：Webhook/邮件推送与版本更新检查\n• 前台服务（FOREGROUND_SERVICE 等）：保持通知监听服务常驻，确保消息及时推送\n• 开机自启动（RECEIVE_BOOT_COMPLETED）：设备重启后自动恢复通知监听服务\n• 通知发送（POST_NOTIFICATIONS）：发送本地通知提示\n• 唤醒锁（WAKE_LOCK）：延迟/定时推送到点唤醒设备\n\n辅助权限（可选）：\n• 电量优化白名单（REQUEST_IGNORE_BATTERY_OPTIMIZATIONS）：避免系统限制后台服务\n• 短信（RECEIVE_SMS/READ_SMS）：可选，用于短信通知识别与转发\n• 电话状态（READ_PHONE_STATE）：可选，用于来电通知识别\n• 存储（READ/WRITE_EXTERNAL_STORAGE）：导出推送历史 JSON、保存更新 APK\n• 安装未知应用（REQUEST_INSTALL_PACKAGES）：应用内在线更新时安装 APK\n• 查询已安装应用（QUERY_ALL_PACKAGES）：规则引擎条件配置与应用过滤\n• 振动（VIBRATE）：推送提示振动\n• 网络状态（ACCESS_NETWORK_STATE）：检测网络连接状态\n\n以上辅助权限均在您主动授权后使用，可随时在系统设置中关闭。'**
  String get privacyPermContent;

  /// No description provided for @privacyChildTitle.
  ///
  /// In zh, this message translates to:
  /// **'儿童隐私'**
  String get privacyChildTitle;

  /// No description provided for @privacyChildContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用面向一般用户，不针对 14 周岁以下儿童设计，也不会故意收集儿童的个人信息。若您是未成年人，请在监护人陪同下阅读本政策，并在监护人同意后使用本应用。'**
  String get privacyChildContent;

  /// No description provided for @privacyRightsTitle.
  ///
  /// In zh, this message translates to:
  /// **'您的权利'**
  String get privacyRightsTitle;

  /// No description provided for @privacyRightsContent.
  ///
  /// In zh, this message translates to:
  /// **'您对本应用所处理的本地数据享有以下权利：\n\n• 访问权：在应用内查看推送历史记录与统计信息\n• 删除权：随时清除全部或部分推送历史记录，卸载应用将删除全部本地数据\n• 撤回同意权：可在系统设置中关闭任何已授权的权限\n• 知情权：本政策将随应用功能变化及时更新并在应用内公示'**
  String get privacyRightsContent;

  /// No description provided for @privacyUpdateTitle.
  ///
  /// In zh, this message translates to:
  /// **'政策更新'**
  String get privacyUpdateTitle;

  /// No description provided for @privacyUpdateContent.
  ///
  /// In zh, this message translates to:
  /// **'本隐私政策可能会不定期更新。当政策发生变更时，我们将在应用内发布更新后的政策，并更新页面底部的\"最后更新\"日期。您继续使用本应用即表示您同意更新后的政策。'**
  String get privacyUpdateContent;

  /// No description provided for @privacyContactTitle.
  ///
  /// In zh, this message translates to:
  /// **'联系我们'**
  String get privacyContactTitle;

  /// No description provided for @privacyContactContent.
  ///
  /// In zh, this message translates to:
  /// **'如果您对本隐私政策或数据处理有任何疑问、意见或建议，可通过以下方式联系我们：\n\n• 在应用内「更多」页查看最新版本与更新说明\n• 通过 GitHub 仓库提交 Issue：https://github.com/fnthinklevi/noticeTransmit\n\n我们将在收到您的反馈后尽快予以回复。'**
  String get privacyContactContent;

  /// No description provided for @lastUpdate.
  ///
  /// In zh, this message translates to:
  /// **'最后更新：2026年8月15日'**
  String get lastUpdate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
