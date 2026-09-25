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
  String get later => 'Later';

  @override
  String get goSettings => 'Settings';

  @override
  String get loading => 'Loading...';

  @override
  String get unknown => 'Unknown';

  @override
  String get notSet => 'Not Set';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get tabHome => 'Home';

  @override
  String get tabNotificationEngine => 'Alerts';

  @override
  String get tabMore => 'More';

  @override
  String get notificationEngineTitle => 'Notification Engine';

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
  String get notificationPermissionTitle => 'Notification Access Not Enabled';

  @override
  String get notificationPermissionMsg =>
      'Notification access is not enabled. The app cannot read device notifications.\n\nPlease go to Permissions and enable notification access before starting the service.';

  @override
  String get appearance => 'Appearance';

  @override
  String get pushSettings => 'Push Settings';

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
  String get ruleEngine => 'Rule Engine';

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
  String get widgetSection => 'Desktop Widget';

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
      'Please read our privacy policy before using this app.\n\n• All notifications are processed on-device and only forwarded to Webhook or email addresses you configure\n• Push history is AES-256 encrypted and stored in a local database\n• Crash reporting (Tencent Bugly) is off by default; it only collects necessary crash logs for fixing issues after you enable it in settings, and no personal information is collected\n• Channel credentials (Webhook/email) are encrypted with AndroidKeyStore\n\nBy tapping \"Agree\", you agree to our privacy policy.';

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
  String checkUpdateFailed(String e) {
    return 'Update check failed: $e';
  }

  @override
  String get checkUpdateNetworkError =>
      'Update check failed, please check your network';

  @override
  String get importantUpdate => 'Important Update';

  @override
  String get mustUpdate => 'You must update to continue using this app';

  @override
  String get newVersionFound => 'New Version Available';

  @override
  String get latestVer => 'Latest version: ';

  @override
  String get currentVer => 'Current version: ';

  @override
  String get fileSize => 'File size: ';

  @override
  String get updateContent => 'Changelog';

  @override
  String get updateNow => 'Update now';

  @override
  String get ignore => 'Ignore';

  @override
  String get update => 'Update';

  @override
  String get downloading => 'Downloading update';

  @override
  String downloadFailed(String e) {
    return 'Download failed: $e';
  }

  @override
  String get storagePermissionRequired => 'Storage Permission Required';

  @override
  String get storagePermissionMsg =>
      'Storage permission is needed to save the APK file. Please go to Settings to enable it.';

  @override
  String get noStoragePermission =>
      'Storage permission not granted, cannot download update';

  @override
  String get enable => 'Enable';

  @override
  String get confirmExport => 'Confirm Export';

  @override
  String get exportMsg =>
      'Notification records will be exported as a JSON file containing notification content and device info.\n\nChoose a save location. Please keep the file safe or delete it after use.\n\nExport now?';

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
  String channelN(int n) {
    return 'Channel $n';
  }

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
  String get webhookTemplateInsertVar => 'Insert Variable';

  @override
  String get webhookTemplatePreview => 'Preview';

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
  String get exactAlarmUnsupported => 'Requires Android 12+';

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
  String get batteryNotifToggleDesc => 'Reminders below only work when enabled';

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
  String get aboutDialogTitle => 'About';

  @override
  String get author => 'Author: fnthinklevi';

  @override
  String get appDesc => 'Listen to all notifications and push to Webhook';

  @override
  String get appFeatures => 'Supports: WeChat / QQ / SMS / Call / Battery';

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
  String get ruleGuideTitle => 'Rule Engine Intro';

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
  String get ruleAppPinnedSms => 'System SMS';

  @override
  String get ruleAppPinnedCall => 'Phone';

  @override
  String get ruleAppPinnedNote =>
      'System SMS and call notifications are forwarded via separate pipelines and never reach the rule engine; listed here for unified management.';

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
  String historyBlockAppAlreadyExcluded(String app) {
    return '\"$app\" is already excluded from pushes';
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
  String get initRetry => 'Initializing retry service...';

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
  String get webhookSaved => 'Webhook config saved';

  @override
  String get emailSaved => 'Email channel config saved';

  @override
  String get unknownError => 'Unknown error';

  @override
  String testFailedMsg(String e) {
    return 'Test failed: $e';
  }

  @override
  String get unknownResult => 'Unknown result';

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
  String get appListPermDesc2 =>
      'To filter apps for push notifications, please grant permission to read installed apps.';

  @override
  String get goEnablePermission => 'Go to Enable Permission';

  @override
  String get refreshRetry => 'Refresh & Retry';

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
      'This App follows the principle of \"minimum necessary\" and only collects information required for core functionality:\n\n1. Notification Content (Local Processing)\n   - The app reads notification content through the system notification listener service\n   - All notification content is matched against rules, filtered by keywords, and forwarded to Webhook or email addresses you configure, all on-device\n   - Notification content is never uploaded to any server other than the targets you specify\n\n2. Crash Statistics (Tencent Bugly, off by default)\n   - Collected only after you explicitly enable \"Crash Reporting\" under More → settings\n   - The SDK is not initialized and no data leaves the device until enabled; used solely to locate and fix crash issues and improve app stability\n\n3. Push Statistics & History (Local Storage)\n   - Notification records, delivery status, and daily statistics are AES-256 encrypted and stored in a local database\n   - These data stay on your device and are never transmitted externally\n\n4. Delayed Push Queue (Local Storage)\n   - Delay/scheduled push tasks from the rule engine are persisted locally and survive reboots\n\n5. Battery Status (Local Monitoring)\n   - Battery level and charging status are monitored locally for the home page display only\n\n6. Installed App List (Local Use)\n   - Used for rule engine condition configuration and app filtering, on-device only';

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
      'This App follows the principle of least privilege. The complete permission list and purposes are as follows:\n\nCore Permissions (Required):\n• Notification Listener: Read notification content for forwarding and the rule engine\n• Internet (INTERNET): Webhook/email push and update checks\n• Foreground Service (FOREGROUND_SERVICE, etc.): Keeps the notification listener alive for timely delivery\n• Boot Completed (RECEIVE_BOOT_COMPLETED): Automatically restores the listener after reboot\n• Post Notifications (POST_NOTIFICATIONS): Sends local notification prompts\n• Wake Lock (WAKE_LOCK): Wakes the device for delayed/scheduled pushes\n\nAuxiliary Permissions (Optional):\n• Battery Optimization Whitelist (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS): Prevents the system from restricting background services\n• SMS (RECEIVE_SMS/READ_SMS): Optional, for SMS notification recognition and forwarding\n• Phone State (READ_PHONE_STATE): Optional, for incoming call notification recognition\n• Storage (READ/WRITE_EXTERNAL_STORAGE): Export push history JSON and save update APKs\n• Install Unknown Apps (REQUEST_INSTALL_PACKAGES): Installs APKs for in-app updates\n• Query All Packages (QUERY_ALL_PACKAGES): Rule engine condition configuration and app filtering\n• Vibrate (VIBRATE): Vibration for push prompts\n• Network State (ACCESS_NETWORK_STATE): Detects network connectivity\n\nAuxiliary permissions are only used after your explicit authorization and can be revoked anytime in system settings.';

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
  String get lastUpdate => 'Last updated: August 15, 2026';

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
  String get backupCancelled => 'Cancelled';

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
      'This notification is filtered out before the rule engine';

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
  String get historyActionBlockAppDescAllowWhitelist =>
      'Already blocked by app filter, but whitelist keyword hits will still push — no action needed';

  @override
  String get historyBlockAppSelfToast =>
      'This app\'s own notifications are governed by battery rules — adjust them in battery settings';

  @override
  String get historyBlockAppAllowWhitelistToast =>
      'Already blocked by app filter, but whitelist keyword hits will still push';

  @override
  String get exportConfirmDesc =>
      'Records will be exported as a JSON file containing notification content and device info. Choose a save location and keep the file safe or delete it promptly.';

  @override
  String get historyMoreActions => 'More actions';

  @override
  String get ruleAppPickScanEmpty =>
      'No apps were scanned. Go back and retry; if still empty, make sure \"Query all packages\" is allowed in system settings.';

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
  String get platformWecomAppDesc =>
      'WeCom self-built app push (requires corpid/agentid/corpsecret), supports targeting users; content limited to 2048 bytes';

  @override
  String get signingHintWecomApp =>
      'Required: corpsecret (exchanges for access_token); also fill in corpid and agentid';

  @override
  String get wecomAppExtraTitle => 'WeCom App Parameters';

  @override
  String get wecomAppCorpidHint => 'Corp ID (corpid)';

  @override
  String get wecomAppAgentidHint => 'App agentid (numeric)';

  @override
  String get wecomAppTouserHint =>
      'Receiver touser (optional, default @all; separate users with |)';

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
  String get appChannelPageDesc =>
      'App channels use a two-phase API (credential → token → message endpoint), distinct from webhooks. Supports WeCom self-built apps and Feishu self-built apps; secrets are encrypted; delivery results and failure retries match webhook channels.';

  @override
  String appChannelConfigured(int n, int m) {
    return '$n configured · $m enabled';
  }

  @override
  String get appChannelNotConfigured => 'Not configured';

  @override
  String appChannelN(int n) {
    return 'App Channel $n';
  }

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
  String get channelStateEnabled => 'Enabled';

  @override
  String get channelStateDisabled => 'Disabled';

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
}
