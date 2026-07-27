import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { system, zh, en }

class LocaleService {
  static const _keyLanguage = 'app_language';
  static const _keyLastSystemLang = 'last_system_lang';

  AppLanguage _language = AppLanguage.system;
  String? _lastSystemLang;

  AppLanguage get language => _language;
  bool get isSystem => _language == AppLanguage.system;

  Locale get currentLocale {
    switch (_language) {
      case AppLanguage.zh:
        return const Locale('zh');
      case AppLanguage.en:
        return const Locale('en');
      case AppLanguage.system:
        final sysLang = PlatformDispatcher.instance.locale.languageCode;
        return sysLang == 'zh' ? const Locale('zh') : const Locale('en');
    }
  }

  /// 当前系统语言是否与上次记录不同
  String get _currentSystemLang =>
      PlatformDispatcher.instance.locale.languageCode;

  bool get systemLanguageChanged {
    if (_lastSystemLang == null) return false;
    return _lastSystemLang != _currentSystemLang;
  }

  /// 是否应提示切换（仅 system 模式 + 语言变更时触发）
  bool get shouldPromptSwitch =>
      _language == AppLanguage.system && systemLanguageChanged;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyLanguage) ?? 'system';
    _language = AppLanguage.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => AppLanguage.system,
    );
    _lastSystemLang = prefs.getString(_keyLastSystemLang);
    // 首次启动记录当前系统语言
    if (_lastSystemLang == null) {
      _lastSystemLang = _currentSystemLang;
      await prefs.setString(_keyLastSystemLang, _lastSystemLang!);
    }
  }

  Future<void> setLanguage(AppLanguage lang) async {
    _language = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang.name);
  }

  /// 更新已记录的系统语言（切换后调用）
  Future<void> recordSystemLang() async {
    _lastSystemLang = _currentSystemLang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSystemLang, _lastSystemLang!);
  }

  String get languageLabel {
    switch (_language) {
      case AppLanguage.system:
        return '默认';
      case AppLanguage.zh:
        return '中文';
      case AppLanguage.en:
        return 'English';
    }
  }
}
