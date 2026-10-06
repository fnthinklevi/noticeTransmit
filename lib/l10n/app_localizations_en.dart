// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'NoticeTransmit';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get duplicate => 'Duplicate';

  @override
  String copyOfName(String name) {
    return '$name copy';
  }

  @override
  String get add => 'Add';

  @override
  String get test => 'Test';

  @override
  String get send => 'Send';

  @override
  String get close => 'Close';

  @override
  String get ok => 'OK';

  @override
  String get goSettings => 'Settings';

  @override
  String get unknown => 'Unknown';

  @override
  String get notSet => 'Not Set';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get tabHome => 'Home';

  @override
  String get tabNotificationEngine => 'Alerts';

  @override
  String get tabMore => 'More';

  @override
  String get notificationEngineTitle => 'Notification Engine';

  @override
  String get notificationEngineShort =>
      'Alerts when the device itself reaches a state: battery, temperature. Whether to forward a notification is set under More -> Filters & rules.';

  @override
  String get notificationEngineScopeTitle =>
      'What this page covers, and what it does not';

  @override
  String get notificationEngineDesc =>
      'Alerts the device raises about itself: battery and temperature. Whether an incoming notification gets forwarded is set under More → Filter & Rules.';

  @override
  String get engineBatteryEntry => 'Battery Alerts';

  @override
  String get engineTemperatureEntry => 'Temperature Alerts';

  @override
  String get serviceRunning => 'Notification service is running, tap to stop';

  @override
  String get serviceStopped => 'Notification service is stopped, tap to start';

  @override
  String get running => 'Running';

  @override
  String get stopped => 'Stopped';

  @override
  String get currentChannels => 'Push Channels';

  @override
  String get noChannels => 'No channels configured';

  @override
  String get statusOk => 'Normal';

  @override
  String get statusError => 'Abnormal';

  @override
  String get statusUnknown => 'Unknown';

  @override
  String get channelStatusTitle => 'Channel Status';

  @override
  String get channelStatusGuide =>
      'Every enabled channel with its latest probe result and address. Tap any row to open that channel\'s settings.';

  @override
  String get channelStatusNeverProbed => 'Never probed';

  @override
  String get mainBackupSettings => 'Primary & Backup';

  @override
  String get mainBackupHint =>
      'Primary channels always receive the notification. Backup channels are used only when every primary channel is unavailable — a notification is never sent to both.';

  @override
  String get mainBackupRecommend =>
      'Keep primary channels at 5 or fewer. More are allowed, but fan-out and failure detection get slower.';

  @override
  String get rolePrimary => 'Primary';

  @override
  String get roleBackup => 'Backup';

  @override
  String get roleNone => 'Excluded';

  @override
  String get mainBackupExcluded =>
      'Excluded channels keep their configuration but receive nothing until re-assigned.';

  @override
  String get roleUnset => 'Unset';

  @override
  String get mainBackupUnsetNotice =>
      '\"Unset\" is where a newly added channel starts: it never duplicates a primary send, and it is used only when no channel is marked Primary. Set your everyday channel to \"Primary\".';

  @override
  String get roleGuideTitle => 'Split channels into primary and backup';

  @override
  String roleGuideBody(Object n) {
    return '$n of your channels need a primary/backup role. While all of them stay Primary, one notification is sent $n times; mark the less critical ones as Backup and they only take over when every Primary channel is unavailable.';
  }

  @override
  String get roleGuideAction => 'Set up';

  @override
  String get roleGuideLater => 'Later';

  @override
  String get mainBackupChannelGone =>
      'That channel is gone; the change was not saved.';

  @override
  String get backupModeBanner =>
      'Pushing via backup channels: the app fell back automatically and will not switch back by itself. Confirm the primary channels are healthy, then tap \"Switch to primary\".';

  @override
  String get backupModeSwitchBack => 'Switch to primary';

  @override
  String get permSettings => 'Permissions';

  @override
  String get permSettingsDesc =>
      'Configure notification, battery, background permissions';

  @override
  String get pushHistory => 'Push History';

  @override
  String recordCount(int n) {
    return '$n records';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get pushChannels => 'Push Channels';

  @override
  String get filterRules => 'Filter Rules';

  @override
  String get webhookChannel => 'Webhook Channels';

  @override
  String get webhookNotConfigured => 'Not configured';

  @override
  String webhookConfigured(int n, int m) {
    return '$n configured · $m enabled';
  }

  @override
  String get emailChannel => 'Email Forwarding';

  @override
  String get emailChannelDesc => 'SMTP email notifications';

  @override
  String get appFilter => 'App Filter';

  @override
  String appFilterBlocked(int n) {
    return '$n apps blocked';
  }

  @override
  String appFilterSelected(int n) {
    return '$n apps selected';
  }

  @override
  String get appFilterAll => 'All apps push';

  @override
  String get keywordFilter => 'Keyword Filter';

  @override
  String keywordWhitelistBlacklist(int n, int m) {
    return 'Whitelist $n · Blacklist $m';
  }

  @override
  String get ruleEngine => 'Rule Constraints';

  @override
  String ruleCount(int n) {
    return '$n rules';
  }

  @override
  String get ruleEmpty => 'Tap to add rule';

  @override
  String get device => 'Device';

  @override
  String get deviceName => 'Device Name';

  @override
  String get widgetGuide => 'Push Toggle';

  @override
  String get widgetGuideDesc => 'One-tap start/pause push from home screen';

  @override
  String get widgetGuideIntro =>
      'After adding the \"Push Toggle\" widget to your home screen, you can start or pause push with one tap without opening the app.';

  @override
  String get widgetGuideStep1 =>
      '1. Long-press an empty area of the home screen';

  @override
  String get widgetGuideStep2 => '2. Tap \"Widgets\" (小部件 / 插件)';

  @override
  String get widgetGuideStep3 =>
      '3. Find \"NoticeTransmit\" and drag \"Push Toggle\" to the home screen';

  @override
  String get widgetGuideBrand => 'Add widget by brand';

  @override
  String get widgetBrandXiaomi =>
      'Xiaomi / Redmi: long-press home screen → Add widgets → NoticeTransmit';

  @override
  String get widgetBrandHuawei =>
      'Huawei / Honor: pinch or long-press home screen → Widgets → NoticeTransmit';

  @override
  String get widgetBrandOppo =>
      'OPPO / realme / OnePlus: long-press home screen → Add widgets → NoticeTransmit';

  @override
  String get widgetBrandVivo =>
      'vivo / iQOO: long-press home screen → Widgets → NoticeTransmit';

  @override
  String get widgetBrandSamsung =>
      'Samsung: long-press home screen → Widgets → NoticeTransmit';

  @override
  String get widgetBrandOthers =>
      'Other brands (Stock / Pixel / Motorola / Sony, etc.): long-press home screen → Widgets → NoticeTransmit';

  @override
  String get widgetTipsTitle => 'Tips';

  @override
  String get widgetTip1 => 'Tap the widget to toggle push (Active ⇄ Paused)';

  @override
  String get widgetTip2 =>
      'While paused, monitoring continues but messages are not sent';

  @override
  String get widgetTip3 =>
      'Some brands require autostart permission for the widget to refresh in real time';

  @override
  String get widgetTip4 =>
      'If the widget is not listed, open the app once or restart the launcher';

  @override
  String get widgetPinTitle => 'Quick Add (Recommended)';

  @override
  String get widgetPinDesc =>
      'Tap below and confirm in the system dialog to place the 2×2 push toggle widget on your home screen, no dragging needed.';

  @override
  String get widgetPinAction => 'Add 2×2 widget';

  @override
  String get widgetPinWideAction => 'Add 4×2 wide widget';

  @override
  String get widgetPinSuccess =>
      'Request sent, place the widget on the home screen';

  @override
  String get widgetPinUnsupported =>
      'This launcher does not support quick-add. Long-press an empty area of the home screen to add manually';

  @override
  String get widgetPinLowApi =>
      'Quick-add requires Android 8.0+. Long-press an empty area of the home screen to add manually';

  @override
  String get widgetPin2x2 =>
      '2×2 round toggle: title + status circle + tap hint';

  @override
  String get widgetPin4x2 =>
      '4×2 wide bar: title + status circle + daily pushed count';

  @override
  String get pushStats => 'Push Statistics';

  @override
  String get pushStatsDesc => 'View push data statistics';

  @override
  String get aboutUpdate => 'About & Update';

  @override
  String get checkUpdate => 'Check Update';

  @override
  String get checking => 'Checking...';

  @override
  String get clickToCheck => 'Tap to check for updates';

  @override
  String get privacyPolicyTitle => 'Privacy Policy';

  @override
  String get privacyPolicyDesc => 'Data collection and privacy';

  @override
  String get crashReport => 'Crash Reporting';

  @override
  String get crashReportDesc =>
      'Off by default; when enabled, crash logs are uploaded to Tencent Bugly for diagnostics';

  @override
  String get crashReportOffHint =>
      'Disabled; takes full effect after next launch';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutDesc => 'Version info and author';

  @override
  String get followSystem => 'Follow System';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get language => 'Language';

  @override
  String get langDefault => 'Default';

  @override
  String get langChinese => '中文';

  @override
  String get langEnglish => 'English';

  @override
  String get switchLangTitle => 'Switch Language';

  @override
  String switchLangMsg(String lang) {
    return 'System language changed to $lang. Switch app language?';
  }

  @override
  String get switchBtn => 'Switch';

  @override
  String get notNow => 'Not Now';

  @override
  String get privacyTitle => 'Privacy Policy';

  @override
  String get privacyWelcome => 'Welcome to NoticeTransmit!';

  @override
  String get privacyBody =>
      '• Notification content is matched and filtered on-device, and forwarded only to the Webhook, email address, or Fnthink device you configure\n• Fnthink Push messages are relayed through the server you choose; if you never use Fnthink Push, notification content never leaves this device\n• Push history is AES-256 encrypted and stored in a local database\n• Channel credentials (Webhook/email) are encrypted with AndroidKeyStore\n• Crash reporting (Tencent Bugly) is off by default; it only collects necessary crash logs for fixing issues after you enable it in settings, and no personal information is collected';

  @override
  String get privacyGateLinkAfter =>
      ' (the full text is available before you agree). Tapping \"Agree\" confirms you have read and accepted it.';

  @override
  String get privacyPolicyLink => 'Privacy Policy';

  @override
  String get privacyGateLinkBefore => 'Please read the ';

  @override
  String get disagree => 'Disagree';

  @override
  String get agree => 'Agree';

  @override
  String get privacyWarnTitle => 'Notice';

  @override
  String get privacyWarnBody =>
      'You must agree to the privacy policy to use this app.\n\nIf you disagree, the app will exit.\n\nAre you sure you want to exit?';

  @override
  String get returnAgree => 'Go Back';

  @override
  String get confirmExit => 'Exit';

  @override
  String get latestVersion => 'You are on the latest version';

  @override
  String get fileSize => 'File size: ';

  @override
  String get updateNow => 'Update now';

  @override
  String get ignore => 'Ignore';

  @override
  String get update => 'Update';

  @override
  String get enable => 'Enable';

  @override
  String get confirmExport => 'Confirm Export';

  @override
  String get exportBtn => 'Export';

  @override
  String get exportCancelled => 'Cancelled';

  @override
  String get exportError => 'Export error';

  @override
  String historyTitle(int n) {
    return 'History ($n)';
  }

  @override
  String get exportJson => 'Export JSON';

  @override
  String get clearRecords => 'Clear Records';

  @override
  String get clearToday => 'Clear Today';

  @override
  String get clearLast10 => 'Clear Last 10';

  @override
  String get clearLast50 => 'Clear Last 50';

  @override
  String get clearAll => 'Clear All';

  @override
  String get confirmClear => 'Confirm Clear';

  @override
  String clearConfirmMsg(int n) {
    return 'Clear all $n records?';
  }

  @override
  String clearedN(int n) {
    return '$n records cleared';
  }

  @override
  String get searchHint => 'Search title/content/app';

  @override
  String searchResultCount(int n) {
    return 'Results ($n)';
  }

  @override
  String get clearSearchFilter => 'Clear Filters';

  @override
  String get filterTitle => 'Filters';

  @override
  String get filterTimeAll => 'All Time';

  @override
  String get filterToday => 'Today';

  @override
  String get filterYesterday => 'Yesterday';

  @override
  String get filterLast7Days => 'Last 7 Days';

  @override
  String get filterLast30Days => 'Last 30 Days';

  @override
  String get filterCustomRange => 'Custom';

  @override
  String get filterDateRange => 'Date Range';

  @override
  String get filterAppName => 'App Name (contains)';

  @override
  String get filterPackageName => 'Package Name (contains)';

  @override
  String get filterDeliveryStatus => 'Delivery Status';

  @override
  String get deliveryAll => 'All';

  @override
  String get deliverySuccessOnly => 'Success Only';

  @override
  String get deliveryFailedOnly => 'Failed Only';

  @override
  String get filterApply => 'Apply Filters';

  @override
  String get filterReset => 'Reset';

  @override
  String get loadMoreHint => 'Pull up to load more';

  @override
  String get noRecords => 'No records yet';

  @override
  String get noMatchRecords => 'No matching records';

  @override
  String get notificationDetail => 'Notification Detail';

  @override
  String get detailInfo => 'Details';

  @override
  String get noTitle => '(No title)';

  @override
  String get emailSettingsTitle => 'Email Forwarding';

  @override
  String get noEmailChannels => 'No email channels';

  @override
  String get clickToAdd => 'Tap the button below to add';

  @override
  String get addEmailChannel => 'Add Email Channel';

  @override
  String get editEmailChannel => 'Edit Email Channel';

  @override
  String get testAndSave => 'Test & Save';

  @override
  String get testOnly => 'Test only';

  @override
  String get turnOn => 'Turn On';

  @override
  String get turnOff => 'Turn Off';

  @override
  String get fieldRequired => 'Required';

  @override
  String fillRequiredFieldsNamed(String fields) {
    return 'Save failed: please fill in $fields';
  }

  @override
  String get channelName => 'Channel Name';

  @override
  String get confirmDelete => 'Confirm delete';

  @override
  String deleteChannelConfirm(String name) {
    return 'Delete channel \"$name\"? Its credentials and health record are removed; records already pushed are unaffected.';
  }

  @override
  String deleteKeywordConfirm(String keyword) {
    return 'Delete keyword \"$keyword\"? It stops taking part in filtering right away.';
  }

  @override
  String get autoSavePath => 'Auto-save Path';

  @override
  String get autoSavePathDesc =>
      'Where daily archived notification history JSON files are saved';

  @override
  String get archivePathDefault => 'Default (app-private directory)';

  @override
  String get chooseFolder => 'Choose Custom Folder';

  @override
  String get resetToDefault => 'Reset to Default';

  @override
  String get archivePathUpdated => 'Auto-save path updated';

  @override
  String get archivePathReset => 'Auto-save path reset to default';

  @override
  String get testPassed => '✅ Verified';

  @override
  String get testFailed => '❌ Verification Failed';

  @override
  String get testPassedSaved => 'Test passed, config saved';

  @override
  String verifyFailed(String msg) {
    return 'Verification failed: $msg';
  }

  @override
  String get testing => 'Testing...';

  @override
  String get channelNameHint => 'e.g. QQ Mail';

  @override
  String get smtpHost => 'SMTP Server';

  @override
  String get smtpPort => 'Port';

  @override
  String get smtpAccount => 'SMTP Account';

  @override
  String get smtpPassword => 'Password / Auth Code';

  @override
  String get fromEmail => 'From';

  @override
  String get toEmail => 'To';

  @override
  String get useSSL => 'SSL';

  @override
  String get subjectTemplate => 'Subject Template (optional)';

  @override
  String get bodyTemplate => 'Body Template (optional)';

  @override
  String get presetDefault => 'Default';

  @override
  String get presetSimple => 'Simple';

  @override
  String get presetDetailed => 'Detailed';

  @override
  String get presetTime => 'Time';

  @override
  String get presetCode => 'Code';

  @override
  String get presetDevice => 'Device';

  @override
  String get presetStandard => 'Standard';

  @override
  String get presetComplete => 'Complete';

  @override
  String get presetMinimal => 'Minimal';

  @override
  String availableVars(String vars) {
    return 'Variables: $vars';
  }

  @override
  String get webhookSettingsTitle => 'Webhook Channels';

  @override
  String get webhookUrlRequired => 'Please enter a Webhook URL first';

  @override
  String get webhookChannelNewTitle => 'New webhook channel';

  @override
  String get noWebhookChannels => 'No webhook channels yet';

  @override
  String get channelUntitled => 'Untitled channel';

  @override
  String get saveFailedPrefix => 'Save failed: ';

  @override
  String get webhookErrUrlRequired => 'Save failed: a Webhook URL is required';

  @override
  String get webhookErrUrlInvalid =>
      'Save failed: the Webhook URL must start with http(s)://';

  @override
  String get webhookErrSecretRequired =>
      'Save failed: this platform requires a credential (signing secret or token) - requests would be rejected';

  @override
  String get addChannel => 'Add Channel';

  @override
  String get webhookDesc1 =>
      'Support multiple Webhook channels with independent switches';

  @override
  String get webhookDesc2 => 'Auto-detect WeCom, DingTalk, Feishu formats';

  @override
  String get webhookDesc3 => 'Newly added channels are enabled by default';

  @override
  String get channelNameOptional => 'Channel name (optional)';

  @override
  String get webhookUrlPlaceholder => 'https://example.com/webhook';

  @override
  String get webhookSecretLabel => 'Signing Secret (optional)';

  @override
  String get webhookSigned => 'Signed';

  @override
  String get webhookTemplateLabel => 'Push Template (optional)';

  @override
  String get webhookFormatLabel => 'Message Format';

  @override
  String get feishuMarkdownDowngradeHint =>
      'Feishu custom bots do not support markdown. It will be sent as plain text (markdown symbols shown as-is). Consider using text format.';

  @override
  String get webhookTemplateHint =>
      'Leave empty to use preset; supported variables:';

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
  String get platformGeneric => 'Generic JSON';

  @override
  String get platformWechatDesc => 'Text format push';

  @override
  String get platformGenericDesc => 'Custom JSON format';

  @override
  String get channelTypeLabel => 'Channel Type';

  @override
  String get channelTypeAuto => 'Auto Detect';

  @override
  String channelTypeAutoWith(String type) {
    return 'Auto Detect ($type)';
  }

  @override
  String get selectChannelType => 'Select Channel Type';

  @override
  String get channelTypeWechat => 'WeCom Bot';

  @override
  String get channelTypeDingtalk => 'DingTalk Bot';

  @override
  String get channelTypeFeishu => 'Feishu Bot';

  @override
  String get channelTypeTelegram => 'Telegram';

  @override
  String get channelTypeBark => 'Bark';

  @override
  String get channelTypeServerChan => 'ServerChan';

  @override
  String get channelTypePushPlus => 'PushPlus';

  @override
  String get channelTypeGeneric => 'Generic Webhook';

  @override
  String get signingHintWechat =>
      'Secret generated after enabling signature verification for WeCom bot';

  @override
  String get signingHintDingtalk =>
      'Secret generated after enabling sign verification for DingTalk bot (starts with SEC)';

  @override
  String get signingHintFeishu =>
      'Secret generated after enabling signature verification for Feishu custom bot';

  @override
  String get signingHintTelegram =>
      'Telegram uses Bot Token auth, no signing secret needed';

  @override
  String get signingHintBark =>
      'Bark uses device Key auth, no signing secret needed';

  @override
  String get signingHintServerChan =>
      'ServerChan uses SendKey auth, no signing secret needed';

  @override
  String get signingHintPushPlus =>
      'PushPlus uses Token auth, no signing secret needed';

  @override
  String get signingHintGeneric =>
      'Secret for your server to verify the signature (sent via X-Signature header)';

  @override
  String get msgFormatDefault => 'Default Format';

  @override
  String get msgFormatText => 'Plain Text';

  @override
  String get urlEmpty => 'Empty';

  @override
  String get urlPlaceholder => 'Enter Webhook URL';

  @override
  String get permSettingsTitle => 'Permissions';

  @override
  String get essentialPerms => 'Essential Permissions';

  @override
  String get notifAccessPerm => 'Notification Access';

  @override
  String get allowNotifications => 'Allow Notifications';

  @override
  String get ignoreBatteryOpt => 'Ignore Battery Optimization';

  @override
  String get vendorBgSettings => 'Vendor Background Settings';

  @override
  String get xiaomiAutoStart => 'Xiaomi Auto-start';

  @override
  String get meizuBgRun => 'Meizu Background';

  @override
  String get huaweiProtected => 'Huawei Protected Apps';

  @override
  String get oppoAutoStart => 'OPPO Auto-start';

  @override
  String get vivoBgStart => 'vivo Background Start';

  @override
  String get samsungSettings => 'Samsung Settings';

  @override
  String get nativeAndroid => 'Native Android Settings';

  @override
  String get optionalPerms => 'Optional Permissions';

  @override
  String get smsPerm => 'SMS Permission';

  @override
  String get smsPermDesc => 'Read SMS sender and content';

  @override
  String get phonePerm => 'Phone Permission';

  @override
  String get phonePermDesc => 'Get call number and status';

  @override
  String get appListPerm => 'App List Permission';

  @override
  String get appListPermDesc => 'Improves accuracy of specific features';

  @override
  String get appListPermTitle => 'App List Permission Required';

  @override
  String get appListPermMsg =>
      'This permission is needed to get installed apps list for app filtering.\n\nTap \"Allow\" to go to system settings and enable it manually.';

  @override
  String get appListPermExtra =>
      'Used to get installed apps list for app-based notification filtering';

  @override
  String get appListPermUnknown =>
      'This system version reports no explicit state; readability is decided by whether the app list can actually be read';

  @override
  String get clickToSettings => 'Tap to open settings';

  @override
  String get samsungSmartManagerDesc =>
      'Add this app to auto-start whitelist in Smart Manager';

  @override
  String get nativeBatteryOptDesc =>
      'Confirm battery optimization is disabled in system settings';

  @override
  String get exactAlarmTitle => 'Exact Alarm (On-time Push)';

  @override
  String get exactAlarmDesc =>
      'Delayed/scheduled pushes fire on time; requires system grant on Android 12+';

  @override
  String get exactAlarmGranted => 'Granted';

  @override
  String get exactAlarmNeedGrant => 'Tap to grant';

  @override
  String get keepAliveGuideTitle => 'Keep-alive Guide';

  @override
  String get keepAliveGuideDesc =>
      'Some systems restrict background services and may miss notifications. Follow these steps:';

  @override
  String get keepAliveStep1 => 'Set battery optimization to Unrestricted';

  @override
  String get keepAliveStep2 => 'Allow auto-start';

  @override
  String get keepAliveStep3 => 'Keep running in background (task lock)';

  @override
  String get keepAliveStep4 => 'Confirm notification access is enabled';

  @override
  String get notes => 'Notes';

  @override
  String get allow => 'Allow';

  @override
  String get reject => 'Reject';

  @override
  String get batteryTitle => 'Battery';

  @override
  String get addRule => 'Add Rule';

  @override
  String get charging => 'Charging';

  @override
  String get notCharging => 'Not Charging';

  @override
  String get reminderSettings => 'Reminder Settings';

  @override
  String get batteryNotifToggle => 'Battery Notification Master Switch';

  @override
  String get notifToggleDesc => 'Reminders below only work when enabled';

  @override
  String get notifRules => 'Notification Rules';

  @override
  String get batteryNotes1 =>
      'Low battery alerts only trigger when not charging';

  @override
  String get batteryNotes2 => 'Alert resets when battery rises above threshold';

  @override
  String get batteryNotes3 =>
      'Battery notification runs with the notification listener service';

  @override
  String get batteryNotes4 => 'Tap to edit, swipe or long-press to delete';

  @override
  String get closeBatteryOpt => 'Close Battery Optimization';

  @override
  String get batteryOptDesc =>
      'System may restrict background running when screen off';

  @override
  String get ruleStartCharging => 'Push when charger connected';

  @override
  String get ruleStopCharging => 'Push when charger disconnected';

  @override
  String ruleAboveThreshold(int n) {
    return 'Push when battery reaches $n%';
  }

  @override
  String ruleBelowThreshold(int n) {
    return 'Push when battery below $n%';
  }

  @override
  String ruleEqualThreshold(int n) {
    return 'Push when battery equals $n%';
  }

  @override
  String get ruleUnknown => 'Unknown rule type';

  @override
  String get confirmDeleteRule => 'Confirm Delete';

  @override
  String confirmDeleteRuleMsg(String title) {
    return 'Delete rule \"$title\"?';
  }

  @override
  String get editRule => 'Edit Rule';

  @override
  String get ruleType => 'Rule Type';

  @override
  String get startCharging => 'Start Charging';

  @override
  String get stopCharging => 'Stop Charging';

  @override
  String get belowValue => 'Below Value';

  @override
  String get aboveValue => 'Above Value';

  @override
  String get equalValue => 'Equal Value';

  @override
  String get threshold => 'Threshold (%)';

  @override
  String get customTitle => 'Custom Title (optional)';

  @override
  String get customTitleHint => 'Leave empty for default title';

  @override
  String get batteryReminder => 'Battery Reminder';

  @override
  String get setDeviceName => 'Set Device Name';

  @override
  String get deviceNameLabel => 'Device Name';

  @override
  String get author => 'Author: fnthinklevi';

  @override
  String get ruleListTitle => 'Rule Management';

  @override
  String get ruleNew => 'New Rule';

  @override
  String get ruleNoCondition => 'No conditions';

  @override
  String get ruleNoAction => 'No actions';

  @override
  String get ruleListEmpty => 'No rules yet';

  @override
  String get ruleAddFirst => 'Add Your First Rule';

  @override
  String rulePriorityBadge(int n) {
    return 'Priority $n';
  }

  @override
  String get ruleGuideTitle => 'Rule Constraints Intro';

  @override
  String get ruleGuideAdd => 'Add Rule';

  @override
  String get ruleGuideAddDesc =>
      'Tap \"+\" in the top bar or the FAB to create a new rule';

  @override
  String get ruleGuideCondition => 'Set Conditions';

  @override
  String get ruleGuideConditionDesc =>
      'Configure the IF conditions (app package, keyword, time, etc.)';

  @override
  String get ruleGuideAction => 'Add Actions';

  @override
  String get ruleGuideActionDesc =>
      'Configure the THEN actions (push notification, silent ignore, etc.)';

  @override
  String get ruleGuideEnable => 'Enable Rule';

  @override
  String get ruleGuideEnableDesc =>
      'Toggle to control whether the rule takes effect; disabled rules won\'t run';

  @override
  String get ruleGuideTip =>
      'Tip: rules run by priority; execution stops after the first match. Edit a rule to adjust priority.';

  @override
  String get ruleGuideGotIt => 'Got It';

  @override
  String get ruleHelp => 'Help';

  @override
  String get ruleAddTooltip => 'Add Rule';

  @override
  String ruleDeleteMsg(String name) {
    return 'Delete rule \"$name\"?';
  }

  @override
  String get ruleEditTitle => 'Edit Rule';

  @override
  String get ruleName => 'Rule Name';

  @override
  String get ruleNameHint => 'Enter rule name';

  @override
  String get ruleDescription => 'Description';

  @override
  String get ruleDescriptionHint => 'Optional';

  @override
  String get ruleConditions => 'Conditions (IF)';

  @override
  String get ruleActions => 'Actions (THEN)';

  @override
  String get ruleAddCondition => 'Add Condition';

  @override
  String get ruleAddAction => 'Add Action';

  @override
  String get rulePriority => 'Rule Priority';

  @override
  String get rulePriorityNote =>
      'Higher priority runs first; equal priority runs in add order';

  @override
  String get rulePDefault => 'Default (0)';

  @override
  String get rulePLow => 'Low (50)';

  @override
  String get rulePMedium => 'Medium (100)';

  @override
  String get rulePHigh => 'High (200)';

  @override
  String get rulePHighest => 'Highest (500)';

  @override
  String get rulePriorityCustom => 'Custom…';

  @override
  String get rulePriorityCustomTitle => 'Custom Priority';

  @override
  String get rulePriorityCustomHint => 'Integer from 0 to 500';

  @override
  String get rulePriorityCustomInvalid => 'Enter an integer between 0 and 500';

  @override
  String get ruleAppScope => 'Applicable Apps';

  @override
  String get ruleAppScopeAll => 'All apps';

  @override
  String ruleAppScopeExcluded(int n) {
    return '$n apps excluded';
  }

  @override
  String get ruleAppScopeDesc => 'Excluded apps won\'t match this rule';

  @override
  String get ruleAppPickTitle => 'Select Applicable Apps';

  @override
  String get ruleAppNoPermission => 'No permission to read the app list';

  @override
  String get ruleMergeWindowRow => 'Merge wait duration';

  @override
  String ruleMergeWindowSummary(int n) {
    return 'Wait ${n}s';
  }

  @override
  String get ruleMergeWindowPresets => 'Presets (tap to fill):';

  @override
  String get ruleMergeWindowInvalid =>
      'Enter an integer between 5 and 86400 (minimum 5s)';

  @override
  String get historyActionBlockApp => 'Block notifications from this app';

  @override
  String get historyActionBlockAppShort => 'Block app';

  @override
  String get historyActionBlockAppDescAllow =>
      'Allow mode: remove this app from the push allowlist';

  @override
  String get historyActionBlockAppDescBlock =>
      'Block mode: add this app to the blocked list';

  @override
  String get historyActionBlockAppDescAlreadyExcluded =>
      'This app is currently not in the push scope';

  @override
  String get historyActionBlockAppDescAlreadyBlocked =>
      'This app is already in the blocked list';

  @override
  String get historyActionBlockContent =>
      'Block notifications containing this text';

  @override
  String get historyActionBlockContentShort => 'Block text';

  @override
  String get historyBlockContentDialogTitle => 'Add blacklist keyword';

  @override
  String get historyBlockContentEditHint =>
      'Editable; notifications containing this text will be blocked';

  @override
  String get historyBlockContentSuccess => 'Keyword added to blacklist';

  @override
  String get historyBlockContentDuplicate => 'Keyword already in the blacklist';

  @override
  String historyBlockAppRemoved(String app) {
    return 'Removed \"$app\" from the push allowlist';
  }

  @override
  String historyBlockAppAdded(String app) {
    return 'Added \"$app\" to the blocked list';
  }

  @override
  String historyBlockAppAlreadyBlocked(String app) {
    return '\"$app\" is already in the blocked list';
  }

  @override
  String get historyBlockNoAppName =>
      'This record has no app info; cannot block';

  @override
  String get historyBlockNoText => 'This record has no text to block';

  @override
  String get ruleSelect => 'Please select';

  @override
  String get ruleEditCondition => 'Edit Condition';

  @override
  String get ruleAddConditionTitle => 'Add Condition';

  @override
  String get ruleConditionType => 'Condition Type';

  @override
  String get ruleConditionValue => 'Value';

  @override
  String get ruleLogic => 'Logic Operator';

  @override
  String get ruleEditAction => 'Edit Action';

  @override
  String get ruleAddActionTitle => 'Add Action';

  @override
  String get ruleActionType => 'Action Type';

  @override
  String get ruleDelayTitle => 'Delayed Push Params (fill at least one)';

  @override
  String get ruleDelaySeconds => 'Delay (seconds)';

  @override
  String get ruleDelaySecondsHint => 'e.g. 60 = 1 minute';

  @override
  String get ruleScheduleTime => 'Schedule Time';

  @override
  String get ruleScheduleTimeHint => 'e.g. 22:00 (push when due)';

  @override
  String get ruleBasicInfo => 'Basic Info';

  @override
  String get ruleEnableRule => 'Enable Rule';

  @override
  String get ruleEmptyConditions => 'No conditions yet, tap to add';

  @override
  String get ruleEmptyActions => 'No actions yet, tap to add';

  @override
  String ruleDelayMinute(int n) {
    return 'Delay $n min';
  }

  @override
  String ruleDelaySecond(int n) {
    return 'Delay $n s';
  }

  @override
  String ruleScheduleAt(String t) {
    return 'Scheduled $t';
  }

  @override
  String get condPackage => 'App Package';

  @override
  String get condTitleContains => 'Title Contains';

  @override
  String get condTitleNotContains => 'Title Not Contains';

  @override
  String get condContentContains => 'Content Contains';

  @override
  String get condContentNotContains => 'Content Not Contains';

  @override
  String get condPriority => 'Priority';

  @override
  String get mergeWindowSeconds => 'Merge Window (seconds)';

  @override
  String get mergeWindowHint =>
      'Default 60. Notifications from the same app within this window are merged into one push';

  @override
  String get condTimeRange => 'Time Range';

  @override
  String get condRegex => 'Regex';

  @override
  String get hintPackage => 'e.g. com.example.app';

  @override
  String get hintKeyword => 'Enter keyword';

  @override
  String get hintPriority => 'High/Medium/Low';

  @override
  String get hintTimeRange => '09:00-18:00';

  @override
  String get hintRegex => 'Regex';

  @override
  String get actionPush => 'Push Notification';

  @override
  String get actionSilent => 'Silent Ignore';

  @override
  String get actionDelay => 'Delayed Push';

  @override
  String get actionMerge => 'Merge Push';

  @override
  String get actionRecord => 'Record Only';

  @override
  String get actionPushDesc => 'Push to configured channels';

  @override
  String get actionSilentDesc => 'Don\'t push, process silently';

  @override
  String get actionDelayDesc => 'Push after a delay';

  @override
  String get actionMergeDesc => 'Merge notifications from the same app';

  @override
  String get actionRecordDesc => 'Record to history only, no push';

  @override
  String get logicAnd => 'And';

  @override
  String get logicOr => 'Or';

  @override
  String get keywordTitle => 'Keyword Filter';

  @override
  String get keywordWhitelist => 'Whitelist';

  @override
  String get keywordBlacklist => 'Blacklist';

  @override
  String get keywordWhitelistHint => 'Enter whitelist keyword';

  @override
  String get keywordBlacklistHint => 'Enter blacklist keyword';

  @override
  String get keywordWhitelistDesc =>
      'Whitelist: notification containing any keyword is pushed even if the app is not selected (highest priority)';

  @override
  String get keywordBlacklistDesc =>
      'Blacklist: notification containing any keyword won\'t be pushed even if the app is selected';

  @override
  String get keywordWhitelistEmpty => 'No whitelist keywords';

  @override
  String get keywordBlacklistEmpty => 'No blacklist keywords';

  @override
  String get initializing => 'Initializing...';

  @override
  String get loadWebhook => 'Loading Webhook config...';

  @override
  String get loadBattery => 'Loading battery config...';

  @override
  String get loadRecords => 'Loading notification records...';

  @override
  String get loadFilter => 'Loading filter config...';

  @override
  String get initUpdate => 'Initializing update service...';

  @override
  String get initComplete => 'Initialization complete';

  @override
  String get initFailed => 'App startup failed';

  @override
  String get initFailedMsg =>
      'DI initialization failed, please restart the app';

  @override
  String get retry => 'Retry';

  @override
  String pageInitFailed(String e) {
    return 'Page init failed: $e';
  }

  @override
  String get unknownError => 'Unknown error';

  @override
  String testFailedMsg(String e) {
    return 'Test failed: $e';
  }

  @override
  String get iconDefault => 'Default';

  @override
  String get iconBlue => 'Blue';

  @override
  String get iconCyan => 'Cyan';

  @override
  String get iconTeal => 'Teal';

  @override
  String get iconMint => 'Mint';

  @override
  String get iconGreen => 'Green';

  @override
  String get iconYellow => 'Yellow';

  @override
  String get iconOrange => 'Orange';

  @override
  String get iconRed => 'Red';

  @override
  String get iconPink => 'Pink';

  @override
  String get iconRose => 'Rose';

  @override
  String get iconPurple => 'Purple';

  @override
  String get iconIndigo => 'Indigo';

  @override
  String get iconBrown => 'Brown';

  @override
  String get iconGray => 'Gray';

  @override
  String get iconGraphite => 'Graphite';

  @override
  String get iconBlack => 'Black';

  @override
  String get appIconTitle => 'App Icon';

  @override
  String currentIcon(String label) {
    return 'Current: $label';
  }

  @override
  String iconSwitched(String label) {
    return 'Switched to \"$label\", home screen will refresh soon';
  }

  @override
  String get iconSwitchFailed => 'Switch failed';

  @override
  String get done => 'Done';

  @override
  String get refreshAppList => 'Refresh App List';

  @override
  String get appFilterBlockModeInfo =>
      'Mode: Block — when none selected, all app notifications are pushed';

  @override
  String appFilterBlockModeSelected(int n) {
    return '$n app(s) selected — notifications from these apps will NOT be pushed';
  }

  @override
  String get appFilterAllowModeInfo =>
      'Mode: Allow — when none selected, all app notifications are pushed (default)';

  @override
  String appFilterAllowModeSelected(int n) {
    return '$n app(s) selected — only notifications from these apps will be pushed';
  }

  @override
  String get filterNotifyApps => 'Notify Apps';

  @override
  String get filterBlockApps => 'Block Apps';

  @override
  String get searchAppHint => 'Search app name or package';

  @override
  String get showSystemApps => 'Show System Apps';

  @override
  String get selectAll => 'Select All';

  @override
  String get deselectAll => 'Clear All';

  @override
  String get invertSelection => 'Invert';

  @override
  String selectedCount(int n) {
    return 'Selected $n';
  }

  @override
  String unselectedCount(int n) {
    return 'Unselected $n';
  }

  @override
  String get noAppsFound => 'No apps found';

  @override
  String refreshFailed(String e) {
    return 'Refresh failed: $e';
  }

  @override
  String get appFilterNoPermPrompt =>
      'No permission to read the app list, app filtering is unavailable.\nTap here to grant the \"read app list\" permission';

  @override
  String get smsMonitor => 'SMS Monitoring';

  @override
  String get smsMonitorDesc =>
      'Control whether received SMS are monitored and pushed';

  @override
  String get smsMonitorSettings => 'SMS Monitor Settings';

  @override
  String get smsMonitorTotalDesc =>
      'When off, no SMS will be monitored or pushed';

  @override
  String get simFilterTitle => 'SIM to Monitor';

  @override
  String get simFilterDesc => 'Applies to both SMS and calls';

  @override
  String get simFilterSingleSim =>
      'Only one SIM detected on this device — no selection needed';

  @override
  String get simFilterAll => 'All';

  @override
  String get simFilterSim1 => 'SIM 1 only';

  @override
  String get simFilterSim2 => 'SIM 2 only';

  @override
  String get simFilterRemindTitle => 'Some SMS may not be identifiable by SIM';

  @override
  String get simFilterRemindMsg =>
      'Due to system limitations (e.g. Xiaomi/HyperOS), some SMS cannot be attributed to a SIM card (notification fallback link). These SMS are not affected by this setting and will still be pushed.';

  @override
  String get codeMonitor => 'Monitor Verification Codes';

  @override
  String get codeMonitorDesc =>
      'When off, SMS containing verification codes will not be pushed';

  @override
  String get widgetBrandCurrentDevice => 'Your device';

  @override
  String get statsToday => 'Today';

  @override
  String get statsTotal => 'Total';

  @override
  String get statsApps => 'Apps';

  @override
  String get statsTrend => 'Last 7 Days Trend';

  @override
  String get statsNoData => 'No data';

  @override
  String get statsRank => 'App Push Ranking';

  @override
  String get deliverySuccess => 'Sent';

  @override
  String get deliveryFailed => 'Failed';

  @override
  String get deliveryPending => 'Sending';

  @override
  String get pushPausedByUser => 'Paused by user';

  @override
  String get deliveryIntercepted => 'Blocked';

  @override
  String get deliveryViaBackupTag => 'Backup';

  @override
  String get pushNow => 'Push Now';

  @override
  String get privacyOverviewTitle => 'Privacy Policy Overview';

  @override
  String get privacyOverviewContent =>
      'NoticeTransmit (hereinafter referred to as \"this App\") is developed and operated by the Fnthink team. This App takes your privacy seriously. Please read this Privacy Policy carefully before using this App to understand how we collect, use, store, and protect your information.\n\nThis Policy applies to all services provided by this App. By installing and using this App, you acknowledge that you have read, understood, and agreed to this Policy.';

  @override
  String get privacyInfoTitle => 'Information We Collect';

  @override
  String get privacyInfoContent =>
      'This App follows the principle of \"minimum necessary\" and only collects information required for core functionality:\n\n1. Notification Content (Local Processing)\n   - The app reads notification content through the system notification listener service\n   - Notification content is matched against rules and filtered by keywords on-device, then forwarded only to the targets you configure: a Webhook, an email address, or an Fnthink device\n   - Apart from those targets you specify, notification content is never uploaded to any other server; the Fnthink device route is delivered through a relay server you choose - see section 7\n\n2. Crash Statistics (Tencent Bugly, off by default)\n   - Collected only after you explicitly enable \"Crash Reporting\" under More → settings\n   - The SDK is not initialized and no data leaves the device until enabled; used solely to locate and fix crash issues and improve app stability\n\n3. Push Statistics & History (Local Storage)\n   - Notification records, delivery status, and daily statistics are AES-256 encrypted and stored in a local database\n   - These data stay on your device and are never transmitted externally\n\n4. Delayed Push Queue (Local Storage)\n   - Delay/scheduled push tasks from the rule constraints are persisted locally and survive reboots\n\n5. Battery Status (Local Monitoring)\n   - Battery level and charging status are monitored locally for the home page display only\n\n6. Installed App List (Local Use)\n   - Used for rule constraint condition configuration and app filtering, on-device only\n\n7. Fnthink Push (device-to-device, or a third party pushing to your phone via an endpoint — requires your explicit consent)\n   - Only after you use Fnthink Push and give a one-time, explicit in-app consent are messages relayed through the server you choose to reach the target device; if you do not use it or do not consent, notification content never leaves this device\n   - While undelivered, the message body is encrypted and stored on the server for at most 7 days, then deleted immediately upon delivery or expiry\n   - Pairing codes and the identity private key are never uploaded; the server and audit logs keep only the metadata needed for delivery (no message bodies)\n   - If you self-host the Fnthink Push server, the above relay and retention rules are enforced by your own server, and the data stays within infrastructure you control\n   - ⚠ If the instance is run by someone else: that server encrypts stored bodies with its own key, so \'no plaintext body on the server\' describes the storage form, not what its operator can read — delivery metadata and operations logs are in their hands too. This is the same kind of decision as configuring a webhook target: only connect to instances you trust';

  @override
  String get privacyNoCollectTitle => 'Information We Do Not Collect';

  @override
  String get privacyNoCollectContent =>
      'This App does NOT collect the following personal privacy information:\n\n• Contacts, or SMS content (unless you explicitly authorize SMS notification recognition)\n• Location information\n• Call logs\n• Photos, or file contents\n• Microphone or camera data\n• Personally identifiable information (name, ID number, phone number, etc.)\n\nIf you decline authorization, the related optional features will be unavailable, but core notification forwarding remains unaffected.';

  @override
  String get privacyShareTitle => 'Information Sharing & Disclosure';

  @override
  String get privacyShareContent =>
      'This App never sells, rents, or trades your personal information. Information is only shared in the following circumstances:\n\n1. Forwarding Targets You Configure\n   - Once you configure Webhook (WeCom, DingTalk, Feishu, Telegram, Bark, ServerChan, PushPlus) or SMTP email, the notification content you choose to forward is sent to these third-party platforms you specified\n   - No data is transmitted externally until you explicitly configure a target address\n\n2. Third-Party Crash Statistics (Tencent Bugly, off by default)\n   - Crash stack traces and basic device environment info are shared only after you opt in, for issue fixing\n\n3. Legal Requirements\n   - Information may be disclosed as required by laws, regulations, or competent authorities';

  @override
  String get privacyStorageTitle => 'Data Storage & Security';

  @override
  String get privacyStorageContent =>
      'This App uses multi-layer security mechanisms to protect your data:\n\n1. Local Database Encryption\n   - Notification history and push statistics are AES-256 encrypted (sqflite_sqlcipher)\n   - Encryption keys are stored in the Android system KeyStore (AndroidKeyStore)\n   - Even if the device is obtained by others, the database content cannot be read directly\n\n2. Sensitive Configuration Encryption\n   - Webhook URLs, SMTP credentials, and TOTP secrets are encrypted with AndroidKeyStore / AES-256-GCM\n   - Never stored in plain text in SharedPreferences\n\n3. Network Transport Security\n   - HTTPS is enforced site-wide; plain HTTP transmission is prohibited\n   - Admin backend tokens are only passed via HTTP headers, never in URLs\n\n4. Other Security Measures\n   - Admin backend two-step verification (TOTP)\n   - App backup is disabled (allowBackup=false) to prevent data leakage via cloud backup\n   - In-app broadcast receivers are hardened against forged notification data\n\n5. Data Retention\n   - You may clear all or part of the push history at any time in the app\n   - Uninstalling the app deletes all local data';

  @override
  String get privacyThirdPartyTitle => 'Third-Party Services';

  @override
  String get privacyThirdPartyContent =>
      'This App uses the following third-party services:\n\nTencent Bugly (Crash Statistics, off by default)\n• Provider: Shenzhen Tencent Computer Systems Co., Ltd.\n• Purpose: Collects app crash information for issue diagnosis and fixing only after you explicitly enable \"Crash Reporting\" under More → settings; the SDK stays uninitialized while disabled\n• Privacy Policy: https://privacy.qq.com/\n• Data Collected: Crash stack traces, device model, system version, app version, CPU architecture\n\nForwarding Targets You Configure (Not SDKs)\n• WeCom, DingTalk, Feishu, Telegram, Bark, ServerChan, PushPlus, SMTP email servers\n• This App only sends the notification content you choose to forward to addresses you configured and is not responsible for how third parties process data\n• Refer to the official documentation of the corresponding platform for its privacy policy';

  @override
  String get privacyPermTitle => 'Permission Notes';

  @override
  String get privacyPermContent =>
      'This App follows the principle of least privilege. The complete permission list and purposes are as follows:\n\nCore Permissions (Required):\n• Notification Listener: Read notification content for forwarding and the rule constraints\n• Internet (INTERNET): Webhook/email push and update checks\n• Foreground Service (FOREGROUND_SERVICE, etc.): Keeps the notification listener alive for timely delivery\n• Boot Completed (RECEIVE_BOOT_COMPLETED): Automatically restores the listener after reboot\n• Post Notifications (POST_NOTIFICATIONS): Sends local notification prompts\n• Wake Lock (WAKE_LOCK): Wakes the device for delayed/scheduled pushes\n\nAuxiliary Permissions (Optional):\n• Battery Optimization Whitelist (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS): Prevents the system from restricting background services\n• SMS (RECEIVE_SMS/READ_SMS): Optional, for SMS notification recognition and forwarding\n• Phone State (READ_PHONE_STATE): Optional, for incoming call notification recognition\n• Storage (READ/WRITE_EXTERNAL_STORAGE): Export push history JSON and save update APKs\n• Install Unknown Apps (REQUEST_INSTALL_PACKAGES): Installs APKs for in-app updates\n• Query All Packages (QUERY_ALL_PACKAGES): Rule constraint condition configuration and app filtering\n• Vibrate (VIBRATE): Vibration for push prompts\n• Network State (ACCESS_NETWORK_STATE): Detects network connectivity\n\nAuxiliary permissions are only used after your explicit authorization and can be revoked anytime in system settings.';

  @override
  String get privacyChildTitle => 'Children\'s Privacy';

  @override
  String get privacyChildContent =>
      'This App is designed for the general public, is not intended for children under 14, and does not knowingly collect children\'s personal information. If you are a minor, please read this Policy with a guardian and use this App only with their consent.';

  @override
  String get privacyRightsTitle => 'Your Rights';

  @override
  String get privacyRightsContent =>
      'You have the following rights regarding the local data processed by this App:\n\n• Access: View push history and statistics in the app\n• Deletion: Clear all or part of the push history at any time; uninstalling the app deletes all local data\n• Withdraw Consent: Disable any authorized permission in system settings at any time\n• Right to Know: This Policy is updated as features change and is published in the app';

  @override
  String get privacyUpdateTitle => 'Policy Updates';

  @override
  String get privacyUpdateContent =>
      'This Privacy Policy may be updated from time to time. When changes occur, the updated policy will be published in the app and the \"Last updated\" date at the bottom of this page will be refreshed. Your continued use of this App signifies your agreement to the updated policy.';

  @override
  String get privacyContactTitle => 'Contact Us';

  @override
  String get privacyContactContent =>
      'If you have any questions, comments, or suggestions about this Privacy Policy or data processing, you can reach us through:\n\n• Check the latest version and release notes on the \"More\" page in the app\n• Submit an Issue on GitHub: https://github.com/fnthinklevi/noticeTransmit\n\nWe will respond to your feedback as soon as possible.';

  @override
  String get lastUpdate => 'Last updated: October 6, 2026';

  @override
  String get deliveryLogTitle => 'Delivery Log';

  @override
  String get deliveryLogEmpty =>
      'No delivery log yet (older than the 30-day retention, or this notification predates the feature)';

  @override
  String get backupRestoreTitle => 'Backup & Restore';

  @override
  String get backupSectionTitle => 'Backup Configuration';

  @override
  String get backupSectionDesc =>
      'Pack all your settings into a single file so you can restore them in one step after switching phones or reinstalling.\n\nIncludes: Webhook and email channels (with credentials), notification rules, SMS monitoring toggle, app filter and keyword lists.\nExcludes: notification history that has already been pushed.\n\nThe file is password-protected — you will need the same password to restore, so keep it safe.';

  @override
  String get restoreSectionTitle => 'Restore Configuration';

  @override
  String get restoreSectionDesc =>
      'Pick a .nbackup file and enter its password to restore. When existing configuration is detected, you can choose to overwrite or fill gaps only.';

  @override
  String get backupCreate => 'Create Backup File';

  @override
  String get restorePick => 'Choose Backup File';

  @override
  String get backupPasswordTitle => 'Set Backup Password';

  @override
  String get backupPasswordHint =>
      'Password (min 8 chars; unrecoverable if lost)';

  @override
  String get restorePasswordTitle => 'Enter Backup Password';

  @override
  String get backupTooShort => 'Password must be at least 8 characters';

  @override
  String get backupOk => 'Backup created and saved';

  @override
  String get backupFailed => 'Backup failed: ';

  @override
  String get restoreWrongPassword => 'Wrong password or corrupted file';

  @override
  String get restoreInvalidFile => 'Not a valid backup file';

  @override
  String get restoreConfirmTitle => 'Existing Configuration Detected';

  @override
  String get restoreConflictMsg =>
      'Some configuration already exists. Overwrite replaces everything in the matching categories; Fill gaps keeps existing configuration untouched.';

  @override
  String get restoreOverwriteAll => 'Overwrite All';

  @override
  String get restoreFillGaps => 'Fill Gaps Only';

  @override
  String get restoreDoneReTest =>
      'Restore completed. Please re-test channels with credentials (Webhook/email).';

  @override
  String get restoreFailed => 'Restore failed: ';

  @override
  String restoreSkippedInvalid(int n) {
    return 'Skipped $n webhook channels with invalid URLs';
  }

  @override
  String get restorePartialFailed =>
      'Some settings were not restored — please check each settings page';

  @override
  String get backupRestoreSubtitle =>
      'Encrypted backup of channels, rules and settings, restorable on a new device';

  @override
  String get developerDiagEnabled =>
      'Developer diagnostics enabled (rule/merge logs in logcat)';

  @override
  String get developerDiagDisabled => 'Developer diagnostics disabled';

  @override
  String get ruleTesterTitle => 'Rule Tester';

  @override
  String get ruleTesterTooltip =>
      'Rule tester (trace a simulated notification)';

  @override
  String get testerHint =>
      'Enter a simulated notification to see the full trace (filter → rules → action, aligned with the native engine)';

  @override
  String get testerInputSection => 'Simulated notification';

  @override
  String get testerAppPackage => 'App package';

  @override
  String get testerPickApp => 'Pick app';

  @override
  String get testerTitleField => 'Notification title';

  @override
  String get testerContentField => 'Notification content';

  @override
  String get testerPriorityLabel => 'Notify priority';

  @override
  String get testerPriorityHigh => 'High';

  @override
  String get testerPriorityMid => 'Medium';

  @override
  String get testerPriorityLow => 'Low';

  @override
  String get testerStageFilter => '① Filter stage';

  @override
  String get testerStageRules => '② Rule matching';

  @override
  String get testerStageAction => '③ Final action';

  @override
  String get testerAllowed => 'Allowed';

  @override
  String get testerBlocked => 'Blocked';

  @override
  String get testerSrcAppFilter =>
      'Blocked by app filter (app not selected / selected, per current mode)';

  @override
  String get testerSrcDefault => 'Default pass (no keyword or app-filter hit)';

  @override
  String get testerNoRules => 'No rule matched → push immediately by default';

  @override
  String get testerRuleHit => 'hit';

  @override
  String get testerRuleMissed => 'miss';

  @override
  String get testerRuleDisabled => 'disabled';

  @override
  String get testerRuleExcluded => 'excluded (app excluded)';

  @override
  String get testerActionPush => 'Push immediately';

  @override
  String get testerActionSilent => 'Silently ignore';

  @override
  String get testerActionRecord => 'Record only (no push)';

  @override
  String get testerFilteredNote =>
      'This notification is filtered out before the rule constraints';

  @override
  String get engineConstraintEntry =>
      'Apply keyword constraints to device alerts';

  @override
  String get engineConstraintTitle =>
      'Which constraints apply to device-state alerts, and what happens when one is blocked';

  @override
  String get engineConstraintShort =>
      'When on, battery and temperature alerts also pass the keyword allow/block lists before being pushed.';

  @override
  String get engineConstraintDesc =>
      'When on, battery/temperature alerts also pass the keyword allow/block lists before sending; app filtering does not apply (these alerts originate on this device). Suppressed alerts are recorded in push history with the reason.';

  @override
  String get tempTestEntry => 'Test once';

  @override
  String get tempTestTitle => 'Temperature alert preview';

  @override
  String get tempTestReadings => 'Current readings: ';

  @override
  String get tempTestSteps => 'Walk: ';

  @override
  String get tempTestFired => 'Would fire: ';

  @override
  String get tempTestSilent => 'Would not fire: ';

  @override
  String get tempTestFailed =>
      'Preview failed (not measured — does not mean it would not fire)';

  @override
  String get tempTestNoDims =>
      'No temperature dimension is readable on this device';

  @override
  String get tempOutcomeFire => 'fire';

  @override
  String get tempSilenceNoRules => 'no enabled temperature rules';

  @override
  String get tempSilenceNoReading =>
      'this dimension has no reading on this device';

  @override
  String get tempSilenceNotTriggered => 'threshold not reached';

  @override
  String get tempSilenceNotCrossing =>
      'no crossing (previous sample was already above the threshold)';

  @override
  String get tempSilenceBaseline => 'first sample only records the baseline';

  @override
  String get tempSilenceInCooldown => 'in cooldown';

  @override
  String get tempSilenceDisabled => 'temperature alerts are off';

  @override
  String get deviceStateEntry => 'Device state alerts';

  @override
  String get deviceStateDesc =>
      'Screen brightness and network changes can also trigger alerts. Only the moment of crossing counts (staying below the threshold will not repeat), and the same kind will not alert again within 30 minutes.';

  @override
  String brightnessPercentOnly(int percent) {
    return '$percent%';
  }

  @override
  String networkCaption(Object network) {
    return 'Network: $network';
  }

  @override
  String get temperatureNotes1 =>
      'Thresholds run 30-90C: only the moment a threshold is crossed counts, so staying above it does not re-alert.';

  @override
  String get temperatureNotes2 =>
      'After an alert fires, the same dimension stays silent for 30 minutes.';

  @override
  String get temperatureNotes3 =>
      'Battery / device / screen temperature are judged independently; a dimension this device cannot read is stated plainly in \"Try once\".';

  @override
  String get deviceStateNotes2 =>
      'Brightness is judged by percentage; network rules only react to \"lost\" and \"reconnected\" and need no threshold.';

  @override
  String get deviceStateNotifyEnabled => 'Device state alert push';

  @override
  String get brightnessBelow => 'Brightness below';

  @override
  String get brightnessAbove => 'Brightness above';

  @override
  String get networkConnected => 'When back online';

  @override
  String get networkDisconnected => 'When offline';

  @override
  String get deviceStateValueLabel => 'Brightness threshold (%)';

  @override
  String get deviceStateNoValue => 'Network triggers need no threshold';

  @override
  String get noDeviceStateRules =>
      'No device state rules yet — tap + to add one';

  @override
  String get deviceStatusEntry => 'Device status snapshot';

  @override
  String deviceStatusBrief(String model, int level) {
    return '$model · battery $level%';
  }

  @override
  String deviceStatusBriefCharging(String model, int level) {
    return '$model · battery $level% · charging';
  }

  @override
  String deviceStatusBriefNoReading(String model) {
    return '$model · no battery reading yet';
  }

  @override
  String get deviceStatusDesc =>
      'Every line below comes from the same reading. \"Not readable on this device\" means the system API is unavailable here — it is not a value of 0.';

  @override
  String get deviceStatusSnapshotFailed =>
      'No device snapshot (the native channel did not reply)';

  @override
  String get deviceStatusRefresh => 'Read again';

  @override
  String snapshotCapturedAt(String time) {
    return 'Read at $time';
  }

  @override
  String get snapshotModel => 'Model';

  @override
  String get snapshotManufacturer => 'Manufacturer';

  @override
  String get snapshotBrand => 'Brand';

  @override
  String get snapshotSystemVersion => 'System version';

  @override
  String snapshotSystemVersionValue(String version, int sdk) {
    return 'Android $version (API $sdk)';
  }

  @override
  String get snapshotNetwork => 'Network';

  @override
  String get netWifi => 'Wi-Fi';

  @override
  String get netCellular => 'Cellular';

  @override
  String get netVpn => 'VPN';

  @override
  String get netEthernet => 'Ethernet';

  @override
  String get netNone => 'Offline';

  @override
  String get netOther => 'Other network';

  @override
  String get snapshotBattery => 'Battery';

  @override
  String snapshotBatteryValue(int level, String state) {
    return '$level% ($state)';
  }

  @override
  String get batteryChargingState => 'charging';

  @override
  String get batteryDischargingState => 'not charging';

  @override
  String get snapshotBatteryTemp => 'Battery temperature';

  @override
  String snapshotBatteryTempValue(String value) {
    return '$value°C';
  }

  @override
  String get snapshotStorage => 'Storage';

  @override
  String snapshotStorageValue(String used, String total) {
    return '$used GB used of $total GB';
  }

  @override
  String get snapshotMemory => 'Memory';

  @override
  String snapshotMemoryValue(String available, String total) {
    return '$available GB free of $total GB';
  }

  @override
  String get snapshotBrightness => 'Screen brightness';

  @override
  String snapshotBrightnessValue(int percent, String mode) {
    return '$percent% ($mode)';
  }

  @override
  String get brightnessModeAuto => 'auto';

  @override
  String get brightnessModeManual => 'manual';

  @override
  String get snapshotUptime => 'Uptime';

  @override
  String snapshotUptimeValue(int days, int hours, int minutes) {
    return '$days d $hours h $minutes m';
  }

  @override
  String get unreadableField => 'Not readable on this device';

  @override
  String get pushDeviceInfo => 'Push device info';

  @override
  String get pushDeviceInfoDesc =>
      'Sends this snapshot to your enabled channels as one notification. It goes through the same delivery chain as alerts, so results show up in push history.';

  @override
  String get pushDeviceInfoSent => 'Handed to your channels — see push history';

  @override
  String get pushDeviceInfoBusy => 'Pushing…';

  @override
  String testerSrcBlacklist(String kw) {
    return 'Blacklist keyword hit: $kw';
  }

  @override
  String testerSrcWhitelist(String kw) {
    return 'Whitelist keyword hit: $kw';
  }

  @override
  String testerActionDelay(String when) {
    return 'Delayed push ($when)';
  }

  @override
  String testerActionMerge(int n) {
    return 'Merged push (window ${n}s)';
  }

  @override
  String get batchPushEntry => 'Batch re-push';

  @override
  String get batchPushNoFailed =>
      'No failed records to re-push in the current list';

  @override
  String batchSelectedCount(int n) {
    return '$n selected';
  }

  @override
  String get batchSelectAll => 'Select all failed';

  @override
  String get batchSelectNone => 'Clear selection';

  @override
  String batchPushAction(int n) {
    return 'Re-push $n';
  }

  @override
  String get batchPushConfirmTitle => 'Confirm re-push';

  @override
  String batchPushConfirmMsg(int n) {
    return 'Will re-push $n failed records; the actual delivery result is reflected by record status.';
  }

  @override
  String batchPushRunning(int done, int total) {
    return 'Re-pushing $done/$total';
  }

  @override
  String batchPushDone(int n) {
    return 'Submitted $n re-pushes';
  }

  @override
  String get batchPushUnsupported => 'Re-push is unavailable on this page';

  @override
  String get mergeMaxItemsLabel => 'Flush early at N items';

  @override
  String get mergeMaxItemsHint =>
      'Push as soon as this many items arrive; 0 or empty = wait for the window (optional)';

  @override
  String get mergeGroupByTitleLabel => 'Group by conversation';

  @override
  String get mergeGroupByTitleDesc =>
      'Aggregate per conversation title (contact/group) instead of per app';

  @override
  String ruleMergeMaxItemsSummary(int n) {
    return 'flush at $n';
  }

  @override
  String get ruleMergeGroupByTitleSummary => 'by conversation';

  @override
  String get historyActionBlockAppDescSelf =>
      'This app\'s own notifications (battery alerts) are governed by battery rules — app blocking does not apply';

  @override
  String get historyBlockAppSelfToast =>
      'This app\'s own notifications are governed by battery rules — adjust them in battery settings';

  @override
  String get exportConfirmDesc =>
      'Records will be exported as a JSON file containing notification content and device info. Choose a save location and keep the file safe or delete it promptly.';

  @override
  String get historyMoreActions => 'More actions';

  @override
  String get updateAlreadyLatest => 'You\'re on the latest version';

  @override
  String get updateCheckFailed =>
      'Update check failed. Check your network connection.';

  @override
  String updateCheckFailedWithError(String error) {
    return 'Update check failed: $error';
  }

  @override
  String updateDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get updateForceBadge => 'Important update';

  @override
  String get updateForceRequired => 'Update required to continue';

  @override
  String get updateFoundNew => 'New version available';

  @override
  String get updateLatestVersionLabel => 'Latest version: ';

  @override
  String get updateCurrentVersionLabel => 'Current version: ';

  @override
  String get updateFileSizeLabel => 'File size: ';

  @override
  String get updateChangelogTitle => 'What\'s new';

  @override
  String get updateIgnore => 'Ignore';

  @override
  String get updateLater => 'Later';

  @override
  String get updateButton => 'Update';

  @override
  String get updateDownloading => 'Downloading update';

  @override
  String get webhookConfigSaved => 'Webhook config saved';

  @override
  String get emailConfigSaved => 'Email channel config saved';

  @override
  String get notificationPermOffMsg =>
      'Notification access is off, so the app cannot read device notifications.\n\nEnable it in \"Permission settings\" first, then start the service.';

  @override
  String get historyBlockAppWhitelistNote =>
      'Blocked as requested. Note: whitelist keyword hits will still push this app — consider removing related whitelist keywords.';

  @override
  String get channelTypeNtfy => 'ntfy Push';

  @override
  String get channelTypeGotify => 'Gotify Push';

  @override
  String get channelTypeSlack => 'Slack Notification';

  @override
  String get channelTypeDiscord => 'Discord Notification';

  @override
  String get platformNtfyDesc =>
      'Push to an ntfy topic; official or self-hosted servers supported (optional access token)';

  @override
  String get platformGotifyDesc =>
      'Push to a self-hosted Gotify server, authenticated with an application token (in the secret field)';

  @override
  String get platformSlackDesc => 'Send messages via a Slack Incoming Webhook';

  @override
  String get platformDiscordDesc =>
      'Send messages via a Discord Webhook; content limited to 2000 chars';

  @override
  String get platformDingtalkDesc =>
      'Signed URL (timestamp + sign); Markdown supported';

  @override
  String get platformFeishuDesc =>
      'Signature goes in the request body; content is sent as plain text (Markdown downgrades)';

  @override
  String get platformTelegramDesc =>
      'Bot token and chat_id come from the URL; plain text, 4096-character limit';

  @override
  String get platformBarkDesc =>
      'Device key comes from the URL path; title and body sent as JSON, no signing secret';

  @override
  String get platformServerChanDesc =>
      'SendKey comes from the URL path; content posted as form fields (title/desp), no signing';

  @override
  String get platformPushPlusDesc =>
      'Token taken from the URL is written into the body; plain-text template, no signing secret';

  @override
  String get signingHintNtfy =>
      'Optional: ntfy access token (Bearer), required if your server has auth enabled';

  @override
  String get signingHintGotify =>
      'Required: Gotify application token (client tokens cannot push)';

  @override
  String get signingHintSlack =>
      'Slack authenticates via the Incoming Webhook URL; no signing key needed';

  @override
  String get signingHintDiscord =>
      'Discord authenticates via the Webhook URL; no signing key needed';

  @override
  String get historyActionBlockAppDescAllowAll =>
      'All apps are currently pushed. Tapping switches to blocklist mode and blocks this app; other apps are unaffected';

  @override
  String historyBlockAppSwitchedToBlock(String app) {
    return 'Blocked \"$app\"; filter mode switched to blocklist (other apps unaffected)';
  }

  @override
  String ruleAppGroupApplied(int n) {
    return 'Applied · $n';
  }

  @override
  String ruleAppGroupExcludedN(int n) {
    return 'Excluded · $n';
  }

  @override
  String get ruleAppQuickSelect => 'Quick Select';

  @override
  String get ruleAppQuickComm => 'Messaging';

  @override
  String get ruleAppQuickMail => 'Email';

  @override
  String get ruleAppQuickSms => 'SMS';

  @override
  String get ruleAppQuickPhone => 'Phone';

  @override
  String get ruleAppQuickSmsSub => 'System messaging apps';

  @override
  String get ruleAppQuickPhoneSub => 'System phone & call apps';

  @override
  String ruleAppGroupOthersN(int n) {
    return 'Other Apps · $n';
  }

  @override
  String get channelTypeWecomApp => 'WeCom App (self-built)';

  @override
  String get ruleTemplateTitle => 'Rule Templates';

  @override
  String get ruleTemplatePreset => 'Preset Templates';

  @override
  String get ruleTemplateMine => 'My Templates';

  @override
  String get ruleTemplateMineEmpty =>
      'No custom templates yet; tap \"Save as Template\" on a rule card to create one';

  @override
  String get ruleTemplateSaveAs => 'Save as Template';

  @override
  String ruleTemplateSavedToast(String app) {
    return '\"$app\" saved as template';
  }

  @override
  String get ruleTemplateImport => 'Import File';

  @override
  String get ruleTemplateExport => 'Export & Share';

  @override
  String get ruleTemplateImportPasswordTitle => 'Template File Password';

  @override
  String get ruleTemplateImportPasswordHint =>
      'This file is encrypted; enter the password set at export time';

  @override
  String get ruleTemplateExportPasswordTitle => 'Export Password (optional)';

  @override
  String get ruleTemplateExportPasswordHint =>
      'Leave empty for plain export; with a password the file is AES-256 encrypted';

  @override
  String get ruleTemplateImportEmpty => 'No templates in the file';

  @override
  String get ruleTemplateInvalidFile => 'Not a valid template file';

  @override
  String get ruleTemplateExportOk => 'Templates exported';

  @override
  String get statsDeliveryHealth => 'Delivery Health';

  @override
  String get statsChannelSuccess => 'Channel Success Rate';

  @override
  String get statsFailureTop => 'Top Failure Reasons';

  @override
  String get statsHourly => 'Peak Hours';

  @override
  String get statsRange7 => '7 days';

  @override
  String get statsRange30 => '30 days';

  @override
  String get statsNoDeliveryData => 'No delivery records in this range';

  @override
  String get statsFailNetwork => 'Network / connection failure';

  @override
  String statsFailCount(int n) {
    return '$n times';
  }

  @override
  String healthReachable(int n) {
    return 'Reachable · $n ms';
  }

  @override
  String get healthUnreachable => 'Connection failed';

  @override
  String healthProbedMinutes(int n) {
    return 'probed $n min ago';
  }

  @override
  String healthProbedHours(int n) {
    return 'probed $n h ago';
  }

  @override
  String get appChannelTitle => 'App Channels';

  @override
  String get appChannelNewTitle => 'New app channel';

  @override
  String get noAppChannels => 'No app channels yet';

  @override
  String get appChannelPageTitle =>
      'How a custom-app channel actually gets a message out';

  @override
  String get appChannelPageShort =>
      'WeCom and Feishu custom apps: trade credentials for a token, then post to the message endpoint. Secrets are stored encrypted.';

  @override
  String get appChannelPageDesc =>
      'App channels use a two-phase API (credential → token → message endpoint), distinct from webhooks. Supports WeCom self-built apps and Feishu self-built apps; secrets are encrypted; delivery results and failure retries match webhook channels.';

  @override
  String appChannelConfigured(int n, int m) {
    return '$n configured · $m enabled';
  }

  @override
  String get appChannelNotConfigured => 'Not configured';

  @override
  String get appChannelNameLabel => 'Channel name';

  @override
  String get appChannelBaseUrlHint =>
      'API base URL (leave empty for the official endpoint; self-hosted deployments supported — must be HTTPS with a system-trusted certificate)';

  @override
  String get appChannelSecretWecomHint =>
      'corpsecret (exchanges for access_token)';

  @override
  String get appChannelSecretFeishuHint =>
      'app_secret (exchanges for tenant_access_token)';

  @override
  String get appChannelCorpidLabel => 'Corp ID (corpid)';

  @override
  String get appChannelAgentidLabel => 'App agentid (numeric)';

  @override
  String get appChannelTouserLabel =>
      'Receiver touser (optional, @all; | separated)';

  @override
  String get appChannelAppidLabel => 'App app_id';

  @override
  String get appChannelReceiveIdTypeLabel =>
      'Receive ID type (chat_id or open_id)';

  @override
  String get appChannelReceiveIdLabel => 'Receiver receive_id';

  @override
  String get appChannelDeleteHint =>
      'Deletions take effect after tapping Save.';

  @override
  String get appChannelTestFailed => 'Test failed: ';

  @override
  String get appChannelSaveOk => 'App channels saved and synced';

  @override
  String get appChannelErrNameRequired =>
      'Save failed: channel name is required';

  @override
  String get appChannelErrBaseUrlRequired =>
      'Save failed: API address is required';

  @override
  String appChannelErrFieldsRequired(String fields) {
    return 'Save failed: required fields are empty ($fields)';
  }

  @override
  String get priorityBadgeHigh => 'High';

  @override
  String get priorityBadgeLow => 'Low';

  @override
  String get channelBadgeFallback => 'C';

  @override
  String storageRootPath(String path) {
    return 'Storage root $path';
  }

  @override
  String get recordTypeSms => 'SMS';

  @override
  String get recordTypeCallIncoming => 'Incoming call';

  @override
  String get recordTypeCallAnswered => 'Answered';

  @override
  String get recordTypeCallEnded => 'Call ended';

  @override
  String get recordTypeWechat => 'WeChat';

  @override
  String get recordTypeQq => 'QQ';

  @override
  String get recordTypeAlipay => 'Alipay';

  @override
  String get recordTypeSystem => 'System';

  @override
  String get recordTypeTest => 'Test';

  @override
  String get recordTypeCharging => 'Charging';

  @override
  String get recordTypeFull => 'Fully charged';

  @override
  String get recordTypeLow30 => 'Low battery 30%';

  @override
  String get recordTypeLow20 => 'Low battery 20%';

  @override
  String get recordTypeNotification => 'Notification';

  @override
  String get emailHintPort => '465 (SSL) or 587 (STARTTLS)';

  @override
  String get emailHintPassword =>
      'SMTP authorization code (not your mailbox password)';

  @override
  String get emailHintRecipients => 'Separate multiple addresses with commas';

  @override
  String get emailHintHostExample => 'smtp.qq.com';

  @override
  String get emailHintAddressExample => 'your@email.com';

  @override
  String get emailMetaUnavailable =>
      'Channel metadata is not ready yet, try again later (no configuration was changed)';

  @override
  String get testUnknownResult => 'Unknown result';

  @override
  String get emailHintSubject =>
      'Leave empty for the default subject (app name + title)';

  @override
  String get emailHintBody =>
      'Leave empty for the default body (app / title / content / package / time / device)';

  @override
  String get emailPresetSubjectDefault => '🔔 %appName% — %title%';

  @override
  String get emailPresetSubjectSimple => '%appName% — %title%';

  @override
  String get emailPresetSubjectDetailed =>
      '%appName% — %title%\nContent: %content%';

  @override
  String get emailPresetSubjectTime => '%time% %appName% — %title%';

  @override
  String get emailPresetSubjectCode =>
      '[%appName%] verification code — %title%';

  @override
  String get emailPresetSubjectDevice => '[%deviceName%] %appName% — %title%';

  @override
  String get emailPresetBodyStandard =>
      'App: %appName%\nTitle: %title%\nContent: %content%\nTime: %time%\nDevice: %deviceName%';

  @override
  String get emailPresetBodyComplete =>
      'App: %appName%\nTitle: %title%\nContent: %content%\nSub-text: %subText%\nPackage: %packageName%\nTime: %time%\nDevice: %deviceName%';

  @override
  String get emailPresetBodyCode =>
      'Code: %content%\nFrom: %appName% (%packageName%)\nTime: %time%';

  @override
  String get emailPresetBodyMinimal => '%appName%: %title%\n%content%';

  @override
  String get channelTypeFeishuApp => 'Feishu App (self-built)';

  @override
  String get appChannelGuideEntry =>
      'First time? Tap the \"?\" at the top-right of a card to see how to get each parameter';

  @override
  String get appChannelGuideOpen => 'Setup steps';

  @override
  String get appChannelGuideTitleWecom => 'WeCom Self-built App · Setup Steps';

  @override
  String get appChannelGuideTitleFeishu =>
      'Feishu Self-built App · Setup Steps';

  @override
  String get appChannelGuidePrepWecom =>
      'Prerequisite: WeCom admin (or app admin) access, and a self-built app created in the admin console.';

  @override
  String get appChannelGuidePrepFeishu =>
      'Prerequisite: Feishu Open Platform developer access. Publishing a version requires admin approval.';

  @override
  String get appChannelGuideWecomS1 => 'Get the Corp ID (corpid)';

  @override
  String get appChannelGuideWecomS1Desc =>
      'Admin console (work.weixin.qq.com) → \"My Enterprise\" → \"Enterprise Info\" → scroll to the bottom and copy the Enterprise ID.';

  @override
  String get appChannelGuideWecomS2 => 'Create a self-built app';

  @override
  String get appChannelGuideWecomS2Desc =>
      '\"App Management\" → \"Apps\" → \"Self-built\" → \"Create App\"; fill in the name and icon.';

  @override
  String get appChannelGuideWecomS3 => 'Get AgentId and Secret';

  @override
  String get appChannelGuideWecomS3Desc =>
      'Open the app you just created: the AgentId (digits only) is shown at the top; click \"View\" next to Secret, send the prompt to WeCom, then copy the secret (this is the corpsecret / Secret field in this app).';

  @override
  String get appChannelGuideWecomS4 => 'Set visible range (recipients)';

  @override
  String get appChannelGuideWecomS4Desc =>
      'App details → \"Visible Range\": add the members/departments that should receive pushes. Leave the Recipient field empty to push to all visible members (@all); multiple user IDs can be separated by |.';

  @override
  String get appChannelGuideWecomS5 => '(Optional) Configure trusted IP';

  @override
  String get appChannelGuideWecomS5Desc =>
      'If the enterprise enforces \"Trusted IP\": app details → \"Developer Interface\" → \"Trusted IP\" and add the phone\'s egress IP; otherwise skip.';

  @override
  String get appChannelGuideWecomS6 => 'Fill in and test';

  @override
  String get appChannelGuideWecomS6Desc =>
      'Enter the Corp ID / AgentId / Secret, tap the card\'s \"Test\" button to confirm delivery, then save.';

  @override
  String get appChannelGuideFeishuS1 => 'Create an enterprise self-built app';

  @override
  String get appChannelGuideFeishuS1Desc =>
      'Open the Feishu Developer Console (open.feishu.cn) → \"Create Enterprise Self-built App\"; fill in name, description and icon.';

  @override
  String get appChannelGuideFeishuS2 => 'Get App ID and App Secret';

  @override
  String get appChannelGuideFeishuS2Desc =>
      'App details → \"Credentials & Basic Info\" → copy the App ID and App Secret.';

  @override
  String get appChannelGuideFeishuS3 => 'Enable message permissions';

  @override
  String get appChannelGuideFeishuS3Desc =>
      'In \"Permissions\", search for and enable im:message (send single chat messages) and im:message:send_as_bot (send as the app).';

  @override
  String get appChannelGuideFeishuS4 => 'Create a version and publish';

  @override
  String get appChannelGuideFeishuS4Desc =>
      '\"Version Management & Release\" → \"Create Version\" → request release. Permissions take effect only after admin approval (pushes fail before that).';

  @override
  String get appChannelGuideFeishuS5 => 'Get the recipient ID';

  @override
  String get appChannelGuideFeishuS5Desc =>
      'Set receive_id_type to chat_id (group) or open_id (user). Use the API Explorer with im/v1/chats to get a chat_id; open_id can be found in contact details or via the explorer.';

  @override
  String get appChannelGuideFeishuS6 => 'Fill in and test';

  @override
  String get appChannelGuideFeishuS6Desc =>
      'Enter App ID / App Secret / recipient type / recipient ID, tap the card\'s \"Test\" button to confirm delivery, then save.';

  @override
  String get appChannelGuideNoteTitle => 'Notes';

  @override
  String get appChannelGuideNote1 =>
      'The secret is usually only visible at creation time — keep it safe; it is stored encrypted in this app.';

  @override
  String get appChannelGuideNote2 =>
      'Self-hosted deployment: replace the API base URL with your own (leave empty to use the official one).';

  @override
  String get appChannelGuideNote3 =>
      'Common causes of push failure: permissions not granted / app version not published / recipient not in the visible range / wrong Secret or recipient ID.';

  @override
  String get appChannelGuideNote4 =>
      'App channels and Webhook channels are independent and can be enabled together; delivery results and retries behave the same as Webhook channels.';

  @override
  String get appChannelGuideClose => 'Got it';

  @override
  String get appChannelGuideNote5 =>
      'A custom API base URL must use HTTPS (plain http is rejected by the system); self-signed certificates are not trusted and will fail to connect — use a proper certificate, or leave it empty to use the official endpoint.';

  @override
  String get textMenuCopy => 'Copy';

  @override
  String get textMenuPaste => 'Paste';

  @override
  String get textMenuCut => 'Cut';

  @override
  String get textMenuSelectAll => 'Select all';

  @override
  String get batteryTempAbove => 'Battery temp';

  @override
  String get deviceTempAbove => 'Device temp';

  @override
  String get screenTempAbove => 'Screen temp';

  @override
  String ruleBatteryTempAbove(int value) {
    return 'Battery temperature reached $value°C';
  }

  @override
  String ruleDeviceTempAbove(int value) {
    return 'Device temperature reached $value°C';
  }

  @override
  String ruleScreenTempAbove(int value) {
    return 'Screen temperature reached $value°C';
  }

  @override
  String get tempThreshold => 'Temperature threshold (°C)';

  @override
  String get temperatureTitle => 'Temperature Push';

  @override
  String get noRules => 'No temperature rules yet. Tap + to add one';

  @override
  String get disable => 'Disable';

  @override
  String get temperatureNotifyEnabled => 'Temperature push notification';

  @override
  String get textMenuShare => 'Share';

  @override
  String offlineCacheDropped(int n) {
    return 'Offline cache was full — $n oldest notifications never reached history';
  }

  @override
  String get fnthinkPush => 'Fnthink Push';

  @override
  String get fnthinkReceive => 'Receive pushes';

  @override
  String get fnthinkReceiveDesc =>
      'Messages are only fetched while this is on; off means neither sending nor receiving';

  @override
  String get fnthinkConsentTitle =>
      'Allow notification content to be relayed through the server?';

  @override
  String get fnthinkConsentMsg =>
      '① Not using push: everything runs on this device; notification content never touches a server.\n② Only forwarding notifications locally: same — the server collects no notification content at all.\n③ Using push: messages must be relayed through the server to reach this phone. Until delivered, the body is encrypted and stored on the server for at most 7 days and is deleted immediately on delivery or expiry; pairing codes and the identity private key are never uploaded, and audits keep metadata only (no bodies).';

  @override
  String get fnthinkConsentAgree => 'I understand and agree';

  @override
  String get fnthinkConsentGranted =>
      'Content relay through the server is allowed';

  @override
  String get fnthinkConsentPending =>
      'Relay not allowed yet — everything that goes through the server stays off';

  @override
  String get fnthinkConsentNotGranted =>
      'This device has not allowed relaying content through the server, so nothing was sent';

  @override
  String get fnthinkHealthNever => 'Nothing has been sent to this server yet';

  @override
  String get fnthinkHealthReachable => 'The last send reached the server';

  @override
  String get fnthinkHealthUnreachable =>
      'The last send could not reach the server';

  @override
  String get fnthinkStatusRunning => 'Receiving';

  @override
  String get fnthinkStatusIdle => 'Not running';

  @override
  String get fnthinkReceiveNow => 'Receive now';

  @override
  String get fnthinkReceiveDisabled => 'Receiving is off, so this did nothing';

  @override
  String get fnthinkReceiveSkipped =>
      'A round is still in flight - its result shows up shortly';

  @override
  String get fnthinkIdentitySection => 'This device';

  @override
  String get fnthinkAddressCode => 'Address code';

  @override
  String get fnthinkAddressCodeNone =>
      'Not created yet (created on first pairing code or when receiving starts)';

  @override
  String get fnthinkCopy => 'Copy';

  @override
  String get fnthinkCopied => 'Copied to clipboard';

  @override
  String get fnthinkResetCode => 'Reset address code';

  @override
  String get fnthinkResetCodeTitle => 'Replace the address code?';

  @override
  String get fnthinkResetCodeMsg =>
      'The code in every peer\'s allowlist stops pointing at this device right away. All pairings must be redone.';

  @override
  String get fnthinkPairingCode => 'Pairing code';

  @override
  String get fnthinkPairingNone => 'No pairing code is issued';

  @override
  String get fnthinkRevokePairing => 'Revoke code';

  @override
  String get fnthinkArmPairing => 'Issue a new code';

  @override
  String fnthinkPairingHeld(String n) {
    return 'Issued $n ago';
  }

  @override
  String get fnthinkPairingExpireNote =>
      'The server decides expiry and whether it was used; this phone only puts it out there';

  @override
  String get fnthinkIdentityKey => 'Identity key';

  @override
  String get fnthinkKeystoreOn => 'Held by the system keystore';

  @override
  String get fnthinkKeystoreOff =>
      'Stored in app files only (no keystore on this device)';

  @override
  String get fnthinkKeystoreUnknown =>
      'Identity unavailable - an identity problem, not the network';

  @override
  String get fnthinkServerSection => 'Server';

  @override
  String get fnthinkHost => 'Server address';

  @override
  String get fnthinkHostEditTitle => 'Change server address';

  @override
  String get fnthinkHostDesc =>
      'Host name only (port allowed); the scheme comes from the protocol, do not type https://';

  @override
  String get fnthinkHostReset => 'Restore default';

  @override
  String get fnthinkHostSwitch => 'Switch service';

  @override
  String get fnthinkHostRegionInternational => 'Overseas (Los Angeles)';

  @override
  String get fnthinkHostRegionMainland => 'Mainland China (Chengdu)';

  @override
  String get fnthinkHostNoCandidates =>
      'The contract declares no selectable service address';

  @override
  String fnthinkHostUpdateNote(String host) {
    return 'Update checks always go to $host, regardless of this setting.';
  }

  @override
  String get fnthinkBoundary =>
      'With receiving on, message content passes through the server, which can then read the body and metadata.';

  @override
  String fnthinkContractUnavailable(String reason) {
    return 'The bundled protocol contract cannot be read, so nothing here can be changed yet: $reason';
  }

  @override
  String get fnthinkDirForwarded => 'Forwarded';

  @override
  String get fnthinkDirInbox => 'Received (Fnthink)';

  @override
  String get fnthinkInboxEmpty => 'No messages received yet';

  @override
  String get fnthinkMessageGoneFromHistory =>
      'This message is no longer in this device\'s inbox history (it may have been pruned)';

  @override
  String get fnthinkInboxEntry => 'Fnthink inbox';

  @override
  String fnthinkInboxUnread(int n) {
    return '$n unread';
  }

  @override
  String get fnthinkPairingAcked =>
      'The server took this code — a peer can pair with it now';

  @override
  String fnthinkPairingLocalOnly(String reason) {
    return 'Only this device stored the code; the server has not taken it ($reason). A peer pairing now will fail';
  }

  @override
  String get fnthinkPairingAckUnknown =>
      'This device never asked the server — re-arm the code to confirm';

  @override
  String get fnthinkPairRequests => 'Pairing requests waiting for you';

  @override
  String fnthinkPairRequestLine(String peer, String level) {
    return '$peer asks to pair with you, requesting $level';
  }

  @override
  String fnthinkPairWillGrant(String level) {
    return 'This device can only grant $level: anything higher must be confirmed locally on it';
  }

  @override
  String fnthinkPairUnknownLevel(String level) {
    return 'The level \"$level\" is not in the table this device knows ⇒ approving is not possible, only denying';
  }

  @override
  String get fnthinkPairApprove => 'Approve';

  @override
  String get fnthinkPairDeny => 'Deny';

  @override
  String get fnthinkPairAskTitle => 'Approve this pairing?';

  @override
  String fnthinkPairAskMsg(String peer, String level) {
    return 'Adds $peer to this device\'s list and grants $level. Once approved it can push notifications to this device.';
  }

  @override
  String fnthinkPairApproved(String peer, String level) {
    return 'Approved $peer; the server recorded it at $level';
  }

  @override
  String fnthinkPairDenied(String peer) {
    return 'Denied $peer';
  }

  @override
  String fnthinkPairKeySwapped(String peer) {
    return '$peer presented a different public key for the same address code; nothing was changed — either it rebuilt its identity or someone is spoofing that code';
  }

  @override
  String fnthinkPairFailed(String reason) {
    return 'Not approved: $reason';
  }

  @override
  String get fnthinkPairNoGrantedLevel =>
      'The server accepted this one but did not say which level it recorded ⇒ nothing written to the local list';

  @override
  String get fnthinkPeerStoreUnavailable =>
      'The server accepted this one but no peer store is wired on this device ⇒ nothing written to the local list';

  @override
  String get fnthinkPeerWriteFailed =>
      'The server accepted this one but writing the local list failed ⇒ nothing written';

  @override
  String get fnthinkPeersTitle => 'Paired devices';

  @override
  String get fnthinkHubTitle => 'Fnthink Push';

  @override
  String get fnthinkHubDesc =>
      'Where to send: paired devices, sending a notice and receiving settings live here.';

  @override
  String get fnthinkHubPeersDesc =>
      'Which devices are paired, send one to them, or revoke one of them.';

  @override
  String get fnthinkHubReceiveDesc =>
      'Receiving, how often to ask for messages, and what the sender may make this device do (remote execution) live here.';

  @override
  String get fnthinkChannelTitle => 'Fnthink channels';

  @override
  String get fnthinkChannelDesc =>
      'Where this device forwards to as a sender: notifications it receives go out through these.';

  @override
  String get fnthinkPushChannel => 'Fnthink Push Channels';

  @override
  String get fnthinkChannelSettingsEntry => 'Push and receive settings';

  @override
  String get fnthinkChannelNote =>
      'The badge line records the last time this channel was tested, not an automatic probe: a Fnthink channel has no way to ask \"is it reachable\" without disturbing the other end.';

  @override
  String get fnthinkHubChannelsDesc =>
      'Where this device forwards to as a sender.';

  @override
  String get fnthinkChannelEmpty =>
      'No Fnthink channel yet. Add one and this device will forward the notifications it receives.';

  @override
  String get fnthinkChannelDeleteAskTitle => 'Delete this channel?';

  @override
  String fnthinkChannelDeleteAskMsg(Object name) {
    return 'After deleting it, this device stops forwarding to “$name”.';
  }

  @override
  String get fnthinkChannelDeleted => 'Channel deleted';

  @override
  String get fnthinkChannelName => 'Name';

  @override
  String get fnthinkChannelNameHint => 'Name this channel';

  @override
  String get fnthinkChannelNameEmpty => 'The name cannot be empty';

  @override
  String get fnthinkChannelTargetKind => 'Where to';

  @override
  String get fnthinkChannelTargetKindDevice => 'A checked device';

  @override
  String get fnthinkChannelTargetKindWebhook => 'A webhook URL';

  @override
  String get fnthinkChannelTarget => 'Target';

  @override
  String get fnthinkChannelTargetEmpty => 'The target cannot be empty';

  @override
  String get fnthinkChannelTargetBadScheme =>
      'A webhook target must start with https://';

  @override
  String get fnthinkChannelNoTargetPicked =>
      'No device is checked yet — check one under Paired devices first.';

  @override
  String get fnthinkChannelTargetNotChecked =>
      'This device is not checked as a forwarding target';

  @override
  String get fnthinkChannelEnabled => 'Enable this channel';

  @override
  String get fnthinkChannelRole => 'Primary or backup';

  @override
  String get fnthinkChannelSave => 'Save';

  @override
  String get fnthinkChannelSaved => 'Saved';

  @override
  String get fnthinkChannelNewTitle => 'New Fnthink channel';

  @override
  String fnthinkChannelSaveFailed(Object reason) {
    return 'Not saved: $reason';
  }

  @override
  String get fnthinkPeerForwardToggle => 'Use as an Fnthink channel target';

  @override
  String get fnthinkPeerForwardHint =>
      'Check it so notifications this device receives are forwarded to it.';

  @override
  String get fnthinkReceiveGo => 'Open receiving and remote execution';

  @override
  String get fnthinkPeersGo => 'Manage paired devices';

  @override
  String get fnthinkPushPeersDesc =>
      'Pairing, sending and revoking are set up under Notification Engine → Fnthink Push; this page is about this device itself.';

  @override
  String fnthinkPeerLine(String peer, String level, String at) {
    return '$peer · granted $level · $at';
  }

  @override
  String get fnthinkPeersEmpty => 'Nothing has been paired yet';

  @override
  String fnthinkPeersError(String reason) {
    return 'The list could not be read ($reason) — an unreadable cell is not the same as no devices';
  }

  @override
  String get fnthinkPeersBoundary =>
      'This cell records who this device has approved. Revoking first takes the grant back on the server, then this row disappears here; notifications already received are not deleted. The grant the other device gave you is its own to revoke.';

  @override
  String get fnthinkPeerRevoke => 'Revoke';

  @override
  String get fnthinkPeerSend => 'Send';

  @override
  String get fnthinkPairPeer => 'Pair with another device';

  @override
  String get fnthinkPairPeerTitle => 'Start pairing with that device';

  @override
  String get fnthinkPairPeerTargetHint =>
      'Counterpart address code (the one shown on that device)';

  @override
  String get fnthinkPairPeerCodeHint =>
      'The one-time pairing code it just armed';

  @override
  String get fnthinkPairPeerCodeNote =>
      'That code lives only inside this one input: this device keeps no copy, writes no log, stores nothing. Close this sheet and the other device has to arm a new one.';

  @override
  String fnthinkPairPeerLevelNote(String level) {
    return 'Only up to $level is listed here: anything higher must be confirmed locally on that device (lock screen or biometrics), and requesting it remotely is rejected outright.';
  }

  @override
  String get fnthinkPairPeerSubmit => 'Send it';

  @override
  String get fnthinkPairPeerIncomplete =>
      'Fill in both the address code and the code first';

  @override
  String get fnthinkPairPeerPendingNote =>
      'Sending it only adds a pending request on the other device: it decides whether to approve, and this device\'s peer list only shows the row after the next round of receiving.';

  @override
  String fnthinkPairPeerSubmitted(String id, String status) {
    return 'Submitted (request $id, status $status). Now that device has to approve it — this one holds no grant yet.';
  }

  @override
  String get fnthinkPairPeerNotConsented =>
      'This device never consented to \"notification content relayed through the server\", so not a byte left it — flip the consent cell above first';

  @override
  String get fnthinkPairPeerNoSignature =>
      'This one cannot be signed (no identity key on this device), not a byte left it — reset the three credentials above';

  @override
  String get fnthinkPairPeerTransportError =>
      'No reply from the server: this attempt may never have arrived, or it arrived and the answer was lost. Check the pending list on that device before resending — one code is good for one pairing';

  @override
  String get fnthinkPairPeerUnsigned =>
      'The server did not accept this signature: this device is not registered, or its public key is no longer the one on record';

  @override
  String get fnthinkPairPeerRateLimited =>
      'Asked too often, this attempt was pushed back — try once more later, tapping again will not make it faster';

  @override
  String get fnthinkPairPeerReplayed =>
      'This attempt looked like a duplicate (nonce collision) — have the other device arm a new code';

  @override
  String get fnthinkPairPeerNeedsCalibration =>
      'This device\'s clock is too far from the server\'s — press \"receive now\" once to calibrate, then send';

  @override
  String fnthinkPairPeerFailed(String reason) {
    return 'Not submitted: $reason';
  }

  @override
  String get fnthinkPairPeerPrefilled =>
      'These two fields came from the link you just opened, not from your typing — check that is the device you mean to pair with';

  @override
  String get fnthinkPairLinkRejected =>
      'This device cannot use that link: it is not a fnthink pairing link, or the protocol version does not match. Go back to the other device, arm a new code and open it again';

  @override
  String fnthinkSendSheetTitle(String peer) {
    return 'Send to $peer';
  }

  @override
  String get fnthinkSendTitleHint => 'Title (optional)';

  @override
  String get fnthinkSendBodyHint => 'Message';

  @override
  String get fnthinkSendEnvelopeNote =>
      'On the device path the title travels inside the message envelope: the signed bytes have no separate title field, only the endpoint forms do. What the recipient shows as a title comes from this body.';

  @override
  String get fnthinkSendEmptyBody =>
      'Nothing to send — the other side would only get an empty line';

  @override
  String get fnthinkSendSubmit => 'Send';

  @override
  String fnthinkSendSent(String id) {
    return 'Queued on the server ($id). Delivery is proven only by that device\'s ack.';
  }

  @override
  String fnthinkSendEvicted(int count) {
    return '$count older message(s) were dropped to stay under the per-device cap.';
  }

  @override
  String get fnthinkSendRejectedUnsigned =>
      'Signature not recognised: this device\'s identity does not match on the server side (it may need re-pairing)';

  @override
  String get fnthinkSendRejectedCapability =>
      'The other side did not grant this level, or you are not paired yet';

  @override
  String get fnthinkSendReplayed =>
      'Hit the de-duplication window: wait a moment, don\'t tap twice';

  @override
  String get fnthinkSendNeedsCalibration =>
      'Clock not calibrated: tap Receive now once, then send';

  @override
  String fnthinkSendRateLimited(int seconds) {
    return 'Too many this minute — try again in $seconds seconds';
  }

  @override
  String get fnthinkSendTransportError =>
      'The server could not be reached; this message was not sent';

  @override
  String get fnthinkSendSigningUnavailable =>
      'This device cannot sign: reset the credential triple above, or pair again';

  @override
  String fnthinkSendPrecondition(String reason) {
    return 'This device is not ready: $reason';
  }

  @override
  String get fnthinkSendBadInput =>
      'The text contains a character that cannot be sent';

  @override
  String get fnthinkSendUnparseable =>
      'The server accepted it without an id, so this message cannot be tracked';

  @override
  String get fnthinkSendBoundary =>
      'Send uses the signed device path and only goes to a device on your list; it is not proof of delivery — only that device\'s ack is.';

  @override
  String get fnthinkRevokeAskTitle => 'Revoke this device\'s push permission?';

  @override
  String fnthinkRevokeAskMsg(String peer) {
    return 'After revoking, $peer can no longer push to this device; notifications already received stay. This step needs the server, so it cannot be done offline.';
  }

  @override
  String fnthinkRevoked(String peer) {
    return 'Revoked $peer: it can no longer push to this device';
  }

  @override
  String fnthinkRevokeAlreadyGone(String peer) {
    return 'The server no longer holds a grant for $peer (revoking is idempotent: the goal is already met)';
  }

  @override
  String get fnthinkRevokeStoreUnavailable =>
      'The server revoked it, but this device has no row-deletion wiring, so this row stays';

  @override
  String get fnthinkRevokeRowRemains =>
      'The server revoked it, but deleting this row failed, so the row stays';

  @override
  String fnthinkRevokeFailed(String reason) {
    return 'Revoking failed ($reason) — the row stays in the list, which is the truth right now';
  }

  @override
  String get fnthinkEndpointTitle => 'Ingress endpoints (for NAS / scripts)';

  @override
  String get fnthinkEndpointWhy =>
      'A long-lived token third-party platforms use to push to this device. The server stores only a digest; the token below is shown this once — close the page and it is gone.';

  @override
  String fnthinkEndpointCap(int max) {
    return 'This device can hold up to $max; at the cap new ones are refused and none in use is displaced.';
  }

  @override
  String get fnthinkEndpointCreate => 'Create an endpoint';

  @override
  String get fnthinkEndpointDefaultName => 'Created in-app';

  @override
  String fnthinkEndpointId(String id) {
    return 'Ingress id: $id';
  }

  @override
  String fnthinkEndpointSecret(String secret) {
    return 'Token: $secret';
  }

  @override
  String get fnthinkEndpointOnce =>
      'This token appears only once — copy it now; afterwards you can only create a new one (nobody can hand back the old).';

  @override
  String get fnthinkEndpointTutorial => 'How to call this one';

  @override
  String get fnthinkEndpointPostWhy =>
      'The token goes into the request header, not the URL, so it never lands in the reverse proxy\'s access log — this one you can copy whole.';

  @override
  String get fnthinkEndpointGetWarning =>
      'The GET form is shown as a shape only: it puts the token in the URL path, so it does land in the reverse proxy\'s access log. Until log redaction is configured on this server, this branch gives no copyable real token — use the POST above if you need it working now.';

  @override
  String fnthinkEndpointFieldAlias(String title, String body) {
    return 'Field names differ per platform; the first non-empty one wins. Title: $title. Body: $body. Extra fields are ignored. A request cannot pick the delivery target — this endpoint only delivers to this device.';
  }

  @override
  String get fnthinkEndpointCopyId => 'Copy endpoint id';

  @override
  String get fnthinkEndpointCopySecret => 'Copy token';

  @override
  String get fnthinkEndpointCopyCommand => 'Copy the whole command';

  @override
  String get fnthinkEndpointCopyHint =>
      'One-tap copy works only for a while right after you create (or rotate) one: the token lives just in this page\'s memory, and once you leave the page it can no longer be filled in — rotate to copy again.';

  @override
  String fnthinkEndpointFailed(String reason) {
    return 'Endpoint not created ($reason) — no token came back either, so there is no \'created but uncopiable\' state.';
  }

  @override
  String get fnthinkEndpointListPending =>
      'This device has not been asked which endpoints it owns. \'None\' and \'haven\'t looked\' are different sentences, so nothing is listed here and no claim is made.';

  @override
  String get fnthinkEndpointListRead => 'Read the endpoints I created';

  @override
  String fnthinkEndpointRowNamed(String name, String id) {
    return '\"$name\" · $id';
  }

  @override
  String fnthinkEndpointRowUnnamed(String id) {
    return 'Unnamed · $id';
  }

  @override
  String get fnthinkEndpointUsable => 'still accepting pushes';

  @override
  String fnthinkEndpointNotUsable(String status) {
    return 'no longer accepting pushes (the server records it as \"$status\")';
  }

  @override
  String get fnthinkEndpointNone =>
      'Read successfully: this device owns no endpoints. Use the button above to create one.';

  @override
  String fnthinkEndpointListFailed(String reason) {
    return 'Could not read this time ($reason) — \'could not read\' is not \'none\', so nothing is listed and no claim is made.';
  }

  @override
  String get fnthinkEndpointRevoke => 'Close this one';

  @override
  String get fnthinkEndpointRevokeAskTitle => 'Close this endpoint?';

  @override
  String fnthinkEndpointRevokeAskMsg(String id) {
    return 'After $id is closed, whatever holds that token starts getting refused immediately. The token cannot be recovered: the server stores only a digest, so reuse means creating a new one.';
  }

  @override
  String fnthinkEndpointRevoked(String id) {
    return 'Closed $id: that one no longer accepts pushes. The record stays, and the list shows it stopped.';
  }

  @override
  String fnthinkEndpointRevokeAlreadyGone(String id) {
    return '$id was already not accepting pushes — that is a goal reached, not a failure.';
  }

  @override
  String fnthinkEndpointRevokeFailed(String reason) {
    return 'This one was not closed ($reason) — it still accepts pushes, and the list shows the server\'s copy.';
  }

  @override
  String get fnthinkEndpointRotate => 'Rotate this token';

  @override
  String get fnthinkEndpointRotateAskTitle => 'Rotate this endpoint\'s token?';

  @override
  String get fnthinkEndpointRotateAskMsg =>
      'Rotating gives you a new token, shown exactly once. The old one keeps working until the grace period ends (the line below says when); after that, whatever holds it starts getting refused.';

  @override
  String fnthinkEndpointRotated(String id) {
    return 'Rotated the token of $id — the new one is shown above exactly once.';
  }

  @override
  String fnthinkEndpointRotateGrace(String until) {
    return 'The old token keeps working until $until.';
  }

  @override
  String fnthinkEndpointRotateNotRotated(String id) {
    return '$id already accepts no pushes, so no token was rotated — rotating does not resurrect an endpoint; create a new one instead.';
  }

  @override
  String fnthinkEndpointRotateFailed(String reason) {
    return 'Token not rotated ($reason)';
  }

  @override
  String fnthinkPresenceNext(String time, int seconds) {
    return 'Next wake-up: $time (every ${seconds}s)';
  }

  @override
  String fnthinkPresenceNextNoCadence(String time) {
    return 'Next wake-up: $time (interval unknown)';
  }

  @override
  String get fnthinkPresenceAsleep =>
      'Not waking on its own right now (switch off, or not armed yet)';

  @override
  String get fnthinkPollIntervalTitle => 'Poll interval';

  @override
  String fnthinkPollIntervalUsingDefault(int seconds) {
    return 'Asks every ${seconds}s (the protocol default)';
  }

  @override
  String fnthinkPollIntervalChosen(int seconds) {
    return 'Asks every ${seconds}s (your choice)';
  }

  @override
  String fnthinkPollIntervalRange(int min, int max) {
    return 'Allowed range $min–${max}s, set by the protocol, not a local preference';
  }

  @override
  String get fnthinkPollIntervalShort =>
      'Shorter: messages arrive sooner, battery drains faster. Longer: saves power, but a new message can wait a whole interval.';

  @override
  String get fnthinkPollIntervalTradeoffTitle =>
      'What each end of this slider costs';

  @override
  String get fnthinkPollIntervalTradeoff =>
      'Shorter: messages arrive sooner, but every extra poll costs battery. Longer saves power and pays twice at once — the worst-case delay before you even see a new message is one full interval (the server only polls faster while it already has something queued for you, which does not help the very first discovery), and the \'are you online\' answer other devices see goes stale by the same number. Under battery saver the OS merges wake-ups, so these are approximations: even the shortest interval the protocol allows does not guarantee a poll exactly that often.';

  @override
  String get fnthinkPollIntervalReset => 'Use the protocol default';

  @override
  String fnthinkPollIntervalInvalid(String reason) {
    return 'Poll interval not applied: $reason';
  }

  @override
  String get fnthinkReply => 'Reply';

  @override
  String get fnthinkResend => 'Resend';

  @override
  String fnthinkReplyTitle(String title) {
    return 'Reply: $title';
  }

  @override
  String get fnthinkDirSent => 'Sent (fnthink)';

  @override
  String get fnthinkDirAll => 'All';

  @override
  String get fnthinkTagForwarded => 'Fwd';

  @override
  String get fnthinkTagInbox => 'In';

  @override
  String get fnthinkTagSent => 'Out';

  @override
  String get fnthinkAllScopeNote =>
      'All lines the three sources up side by side; it does not merge them into one timeline. Search and filters apply to the Forwarded section only — inbox and sent rows live in another table with different paging, so a merged timeline would show a row twice or not at all.';

  @override
  String get fnthinkSentEmpty =>
      'Nothing sent yet. This tab only lists what this device sent.';

  @override
  String get fnthinkRecipient => 'Recipient';

  @override
  String get l3SettingsSectionTitle => 'System settings a peer can request';

  @override
  String get l3SettingsSectionDesc =>
      'Each item here needs a confirmation you make on this device. Items you have not granted stay listed - greyed out, with the reason.';

  @override
  String get l3StateMissing => 'Not granted on this device yet';

  @override
  String get l3StateUnreadable => 'This device does not report a state';

  @override
  String get l3StateUnsupported => 'Not available on this device';

  @override
  String get l3ItemAutostart => 'Auto-start (per vendor)';

  @override
  String get l3ItemMonitoring => 'Notification forwarding listener';

  @override
  String get l3ItemCollectInbox => 'Fnthink inbox switch';

  @override
  String get l3NoteAutostart =>
      'Android exposes per-vendor entry points only - there is no unified reading';

  @override
  String get l3NoteLivesInFnthinkPage =>
      'This switch lives on the Fnthink Push page';

  @override
  String get updateBlockIntegrityFailed =>
      'Update package verification failed. Installation blocked.';

  @override
  String get updateBlockChecksumMismatch =>
      'Update package integrity check failed (checksum mismatch). Installation blocked.';

  @override
  String get updateBlockUnverifiable =>
      'Cannot verify the update package. Installation blocked.';

  @override
  String get updateFailAllUrls => 'Every download address failed.';

  @override
  String get updateFailDownloaderStart => 'Cannot start the system downloader.';

  @override
  String get updateFailProgressQuery => 'Failed to read the download progress.';

  @override
  String updateFailDownloader(String detail) {
    return 'System downloader failed$detail.';
  }

  @override
  String updateFailHttpStatus(int code) {
    return 'Download failed: HTTP $code.';
  }

  @override
  String get updateSizeUnknown => 'Unknown';

  @override
  String get updateNotificationTitle => 'Notification Forwarder Update';

  @override
  String get remoteExecSection => 'Remote execution';

  @override
  String get remoteExecWhyTitle =>
      'What actually decides how safe remote execution is';

  @override
  String get remoteExecShort =>
      'Others can make this device act. Off by default — an upgrade will not turn it on for you.';

  @override
  String get remoteExecWhy =>
      'Others can make this device act. Safety comes from two things: the channel it arrives on, and whether a credential comes with it. The switch is off by default — an upgrade never makes that decision for you.';

  @override
  String get remoteExecEnabledOn => 'On';

  @override
  String get remoteExecEnabledOff => 'Off';

  @override
  String get remoteExecNeedsCredential =>
      'On but no credential set ⇒ nothing at the high-risk level (L3) can get in.';

  @override
  String get remoteExecOpenSettings => 'Remote execution settings';

  @override
  String get remoteExecSendPage => 'Send a remote command';

  @override
  String get remoteExecHistory => 'Remote execution history';

  @override
  String get remoteExecDelayTitle => 'Cancel window';

  @override
  String remoteExecDelayUsingDefault(int seconds) {
    return 'It runs automatically ${seconds}s later (the protocol default)';
  }

  @override
  String remoteExecDelayChosen(int seconds) {
    return 'It runs automatically ${seconds}s later (your choice)';
  }

  @override
  String remoteExecDelayRange(int min, int max) {
    return 'Allowed range $min–${max}s, set by the protocol, not a local preference';
  }

  @override
  String get remoteExecDelayReset => 'Use protocol default';

  @override
  String remoteExecDelayInvalid(String reason) {
    return 'This cancel window is not in effect: $reason';
  }

  @override
  String remoteExecPendingBanner(String item, int seconds) {
    return 'Remote command 「$item」 runs in ${seconds}s unless you cancel';
  }

  @override
  String get remoteExecCancel => 'Cancel';

  @override
  String get remoteExecCancelled => 'Cancelled — that command will not run';

  @override
  String get remoteExecCancelTooLate =>
      'It already started, so it cannot be undone (the action may be half done)';

  @override
  String get remoteCredWhyTitle =>
      'Why the credential and the device identity are two different keys';

  @override
  String get remoteCredShort =>
      'This key authorizes others to make this device act — it is not the key that proves this device is who it says it is.';

  @override
  String get remoteCredWhy =>
      'A credential authorizes one remote command, and it is a different key from your device identity: one proves which device this is, the other authorizes someone to make it act.';

  @override
  String get remoteCredKeySection => 'Advanced key';

  @override
  String get remoteCredKeyNone => 'Not set yet';

  @override
  String get remoteCredKeySetNoFingerprint =>
      'One is set (this device has no fingerprint for it, so you cannot tell which one)';

  @override
  String remoteCredKeySet(String fingerprint) {
    return 'One is set, fingerprint $fingerprint';
  }

  @override
  String remoteCredKeyMin(int min) {
    return 'At least $min characters, set by the protocol';
  }

  @override
  String get remoteCredKeyGenerate => 'Generate one';

  @override
  String get remoteCredKeyCustom => 'Set my own';

  @override
  String get remoteCredKeyOnce =>
      'This string appears exactly once: copy it somewhere you keep yourself right now (or hand it to the other device in person). Once you close this page only the hash stays on this device, and nobody — including you — can read the string back.';

  @override
  String get remoteCredKeyReset => 'Remove this key';

  @override
  String get remoteCredKeyResetAsk =>
      'Once removed, the other side\'s copy stops working at once — you will have to generate another and hand it over in person.';

  @override
  String get remoteCredTotpSection => 'Two-step code (TOTP)';

  @override
  String get remoteCredTotpNone => 'Not set yet';

  @override
  String get remoteCredTotpSet => 'One is set';

  @override
  String get remoteCredTotpGenerate => 'Generate one';

  @override
  String get remoteCredTotpLink => 'Link to add to your authenticator app';

  @override
  String get remoteCredTotpSecret =>
      'Secret string (your authenticator app can also take it by hand)';

  @override
  String get remoteCredTotpOnce =>
      'This appears exactly once and exists only on the receiving device: enter it into the other device\'s authenticator app now (or hand it over in person to be entered there). After that the authenticator keeps it, no server ever sees it, and once you close this page only the seed remains here.';

  @override
  String get remoteCredTotpClear => 'Remove this one';

  @override
  String remoteCredProblem(String reason) {
    return 'The credential stored on this device is unusable: $reason';
  }

  @override
  String get remoteCredResetAll => 'Reset everything';

  @override
  String get remoteCredResetAllAsk =>
      'After a full reset, both the advanced key and the code seed the other side holds stop working at once. To keep remote execution going you must generate new ones and hand them over in person.';

  @override
  String get remoteSendTitle => 'Send a remote command';

  @override
  String get remoteSendPickPeer => 'Send to which device';

  @override
  String get remoteSendLevel => 'Send at which level';

  @override
  String get remoteSendLevelL1 =>
      'Low risk: runs directly, or can be triggered by a chosen app\'s notification';

  @override
  String get remoteSendLevelL2 =>
      'Medium risk: only via push; a credential is optional';

  @override
  String get remoteSendLevelL3 =>
      'High risk: push only, and it must carry a key or a two-step code';

  @override
  String get remoteSendAction => 'What it should do';

  @override
  String get remoteSendArgument => 'Argument (target channel id)';

  @override
  String get remoteSendKeyOptional => 'Advanced key (optional)';

  @override
  String get remoteSendTotpOptional => 'Two-step code (optional)';

  @override
  String get remoteSendKeyRequired => 'Advanced key (required at this level)';

  @override
  String get remoteSendTotpRequired => 'Two-step code (required at this level)';

  @override
  String get remoteSendSubmit => 'Send it';

  @override
  String get remoteSendCancelNote =>
      'Cancel ⇒ not one byte is sent. The credential you just typed would ride along with it.';

  @override
  String get remoteSendNeedsCredential =>
      'This level needs an advanced key or a two-step code — with both empty there is nothing to send.';

  @override
  String get remoteSendNeedsArgument =>
      'This one needs an argument (the target channel id); it cannot be sent empty.';

  @override
  String get remoteSendStartedNote =>
      'Sent. Wait for the other device to send back two receipts — “executing” and “execution_done” — they will show up in the remote execution history.';

  @override
  String remoteSendFailed(String reason) {
    return 'It did not go out: $reason';
  }

  @override
  String remoteSendLevelUnknown(String level) {
    return 'This level ($level) is not in the protocol vocabulary — nothing sent.';
  }

  @override
  String get remoteHistoryIn => 'Commands received';

  @override
  String get remoteHistoryOut => 'Commands sent';

  @override
  String get remoteHistoryAll => 'All';

  @override
  String get remoteHistoryEmpty => 'No remote execution yet.';

  @override
  String get remoteHistoryPending => 'Waiting';

  @override
  String get remoteHistoryExecuting => 'Executing';

  @override
  String get remoteHistoryDone => 'Done';

  @override
  String get remoteHistoryFailed => 'Failed';

  @override
  String get remoteHistoryCancelled => 'Cancelled';

  @override
  String remoteHistoryStateUnknown(String state) {
    return 'Unrecognised execution state ($state)';
  }

  @override
  String remoteHistoryFromPeer(String peer) {
    return 'From $peer';
  }

  @override
  String remoteHistoryToPeer(String peer) {
    return 'To $peer';
  }

  @override
  String get remoteHistoryLocalTrigger =>
      'Triggered by this device\'s own app notification (no remote sender)';

  @override
  String get remoteHistoryCancel => 'Cancel this one';

  @override
  String get remoteHistoryCancelNote =>
      'Cancelling only works before execution starts; one already running is past that window.';

  @override
  String get remoteHistoryRemoved =>
      'This entry is now gone from this device\'s history.';

  @override
  String get remoteHistoryBoundary =>
      'This history is this device\'s own record: both received and sent. Credentials and command text never enter it — they ride inside that message\'s encrypted body, while receipts and audit rows each keep their own copy.';
}
