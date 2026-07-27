import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const Map<String, Map<String, String>> _localizedValues = {
    'zh': {
      'appTitle': '通知推送助手',
      'tabNotification': '通知',
      'tabBattery': '电量',
      'tabMore': '更多',
      'serviceRunning': '通知监听服务正在运行，点击可停止',
      'serviceStopped': '通知监听服务未启动，点击可启动',
      'currentChannels': '当前推送通道',
      'noChannels': '未配置推送通道',
      'statusOk': '状态正常',
      'statusError': '状态异常',
      'today': '今日',
      'thisMonth': '本月',
      'notificationCount': '通知数',
      'pushHistory': '推送历史',
      'clearRecords': '清空记录',
      'exportRecords': '导出记录',
      'noRecords': '暂无推送记录',
      'permissionSettings': '权限设置',
      'notificationPermission': '通知读取权限',
      'batteryPermission': '电池优化白名单',
      'webhookSettings': 'Webhook 推送通道',
      'emailSettings': '邮件转发通道',
      'appFilterSettings': '应用筛选设置',
      'keywordSettings': '关键词设置',
      'about': '关于',
      'version': '版本',
      'github': 'GitHub',
      'privacyPolicy': '隐私政策',
      'language': '语言',
      'languageDefault': '默认',
      'languageChinese': '中文',
      'languageEnglish': 'English',
      'switchLanguageTitle': '切换语言',
      'switchLanguageMessage': '检测到系统语言已变更，是否切换？',
      'switchYes': '切换',
      'switchNo': '暂不',
      'cancel': '取消',
      'confirm': '确定',
      'save': '保存',
      'delete': '删除',
      'edit': '编辑',
      'test': '测试',
      'send': '发送',
      'testSend': '测试发送',
      'testAndSave': '测试并保存',
      'testPassed': '验证通过',
      'testFailed': '验证失败',
      'smtpHost': 'SMTP 服务器',
      'smtpPort': '端口',
      'username': '账号',
      'password': '密码',
      'fromEmail': '发件人',
      'toEmail': '收件人',
      'useSSL': 'SSL 加密',
      'addEmailChannel': '添加邮件通道',
      'editEmailChannel': '编辑邮件通道',
      'webhookUrl': 'Webhook 地址',
      'channelName': '通道名称',
      'addWebhook': '添加 Webhook 通道',
      'remoteCommand': '远程命令',
      'exporting': '导出中...',
      'exportSuccess': '导出成功',
      'exportCancelled': '已取消',
      'clearConfirm': '确定要清空全部记录吗？',
      'clearToday': '清除今日',
      'clearLastN': '清除最近 {n} 条',
      'clearAll': '清除全部',
      'confirmClear': '确认清除',
      'updatedAt': '更新于',
    },
    'en': {
      'appTitle': 'NoticeTransmit',
      'tabNotification': 'Notifications',
      'tabBattery': 'Battery',
      'tabMore': 'More',
      'serviceRunning': 'Notification service is running, tap to stop',
      'serviceStopped': 'Notification service is stopped, tap to start',
      'currentChannels': 'Push Channels',
      'noChannels': 'No channels configured',
      'statusOk': 'Normal',
      'statusError': 'Abnormal',
      'today': 'Today',
      'thisMonth': 'This Month',
      'notificationCount': 'Notifications',
      'pushHistory': 'Push History',
      'clearRecords': 'Clear Records',
      'exportRecords': 'Export Records',
      'noRecords': 'No records yet',
      'permissionSettings': 'Permissions',
      'notificationPermission': 'Notification Access',
      'batteryPermission': 'Battery Optimization',
      'webhookSettings': 'Webhook Channels',
      'emailSettings': 'Email Forwarding',
      'appFilterSettings': 'App Filter',
      'keywordSettings': 'Keywords',
      'about': 'About',
      'version': 'Version',
      'github': 'GitHub',
      'privacyPolicy': 'Privacy Policy',
      'language': 'Language',
      'languageDefault': 'Default',
      'languageChinese': '中文',
      'languageEnglish': 'English',
      'switchLanguageTitle': 'Switch Language',
      'switchLanguageMessage':
          'System language has changed. Switch the app language?',
      'switchYes': 'Switch',
      'switchNo': 'Not Now',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'test': 'Test',
      'send': 'Send',
      'testSend': 'Test Send',
      'testAndSave': 'Test & Save',
      'testPassed': 'Verified',
      'testFailed': 'Verification Failed',
      'smtpHost': 'SMTP Server',
      'smtpPort': 'Port',
      'username': 'Username',
      'password': 'Password',
      'fromEmail': 'From',
      'toEmail': 'To',
      'useSSL': 'SSL',
      'addEmailChannel': 'Add Email Channel',
      'editEmailChannel': 'Edit Email Channel',
      'webhookUrl': 'Webhook URL',
      'channelName': 'Channel Name',
      'addWebhook': 'Add Webhook',
      'remoteCommand': 'Remote Command',
      'exporting': 'Exporting...',
      'exportSuccess': 'Export successful',
      'exportCancelled': 'Cancelled',
      'clearConfirm': 'Clear all records?',
      'clearToday': 'Clear Today',
      'clearLastN': 'Clear Last {n}',
      'clearAll': 'Clear All',
      'confirmClear': 'Confirm Clear',
      'updatedAt': 'Updated',
    },
  };

  String get appTitle =>
      _localizedValues[locale.languageCode]?['appTitle'] ??
      _localizedValues['en']!['appTitle']!;
  String get tabNotification => _get('tabNotification');
  String get tabBattery => _get('tabBattery');
  String get tabMore => _get('tabMore');
  String get serviceRunning => _get('serviceRunning');
  String get serviceStopped => _get('serviceStopped');
  String get currentChannels => _get('currentChannels');
  String get noChannels => _get('noChannels');
  String get statusOk => _get('statusOk');
  String get statusError => _get('statusError');
  String get today => _get('today');
  String get thisMonth => _get('thisMonth');
  String get notificationCount => _get('notificationCount');
  String get pushHistory => _get('pushHistory');
  String get clearRecords => _get('clearRecords');
  String get exportRecords => _get('exportRecords');
  String get noRecords => _get('noRecords');
  String get permissionSettings => _get('permissionSettings');
  String get notificationPermission => _get('notificationPermission');
  String get batteryPermission => _get('batteryPermission');
  String get webhookSettings => _get('webhookSettings');
  String get emailSettings => _get('emailSettings');
  String get appFilterSettings => _get('appFilterSettings');
  String get keywordSettings => _get('keywordSettings');
  String get about => _get('about');
  String get version => _get('version');
  String get github => _get('github');
  String get privacyPolicy => _get('privacyPolicy');
  String get language => _get('language');
  String get languageDefault => _get('languageDefault');
  String get languageChinese => _get('languageChinese');
  String get languageEnglish => _get('languageEnglish');
  String get switchLanguageTitle => _get('switchLanguageTitle');
  String get switchLanguageMessage => _get('switchLanguageMessage');
  String get switchYes => _get('switchYes');
  String get switchNo => _get('switchNo');
  String get cancel => _get('cancel');
  String get confirm => _get('confirm');
  String get save => _get('save');
  String get delete => _get('delete');
  String get edit => _get('edit');
  String get test => _get('test');
  String get send => _get('send');
  String get testSend => _get('testSend');
  String get testAndSave => _get('testAndSave');
  String get testPassed => _get('testPassed');
  String get testFailed => _get('testFailed');
  String get smtpHost => _get('smtpHost');
  String get smtpPort => _get('smtpPort');
  String get username => _get('username');
  String get password => _get('password');
  String get fromEmail => _get('fromEmail');
  String get toEmail => _get('toEmail');
  String get useSSL => _get('useSSL');
  String get addEmailChannel => _get('addEmailChannel');
  String get editEmailChannel => _get('editEmailChannel');
  String get webhookUrl => _get('webhookUrl');
  String get channelName => _get('channelName');
  String get addWebhook => _get('addWebhook');
  String get remoteCommand => _get('remoteCommand');
  String get exporting => _get('exporting');
  String get exportSuccess => _get('exportSuccess');
  String get exportCancelled => _get('exportCancelled');
  String get clearConfirm => _get('clearConfirm');
  String get clearToday => _get('clearToday');
  String clearLastN(int n) =>
      _get('clearLastN').replaceAll('{n}', n.toString());
  String get clearAll => _get('clearAll');
  String get confirmClear => _get('confirmClear');
  String get updatedAt => _get('updatedAt');

  String _get(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']![key]!;
  }
}
