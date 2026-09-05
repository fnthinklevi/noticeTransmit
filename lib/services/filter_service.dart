import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_rule.dart';
import 'platform_channel.dart';

class FilterService {
  static const _channel = AppChannels.notification;

  /// 与原生 FilterEngine.normalize 逐行对齐的文本归一化：
  /// trim + 全角转半角（\u3000 与 \uFF01-\uFF5E）+ 折叠连续空白 + 小写。
  /// 双端必须保持一致，否则同一规则在 Flutter 侧与原生侧匹配结果不同
  ///（对齐用例见 test/fixtures/rule_engine_golden.json）。
  static String normalizeForMatch(String raw) {
    if (raw.isEmpty) return raw;
    var s = raw.trim();
    final sb = StringBuffer();
    for (final code in s.codeUnits) {
      if (code == 0x3000) {
        sb.write(' '); // 全角空格
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        sb.writeCharCode(code - 0xFEE0); // 全角!-~ → 半角
      } else {
        sb.writeCharCode(code);
      }
    }
    s = sb.toString();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.toLowerCase();
  }

  Set<String> _enabledPackages = {};
  String _appFilterMode = 'allow'; // 'allow' = 仅通知选中；'block' = 屏蔽选中
  List<String> _blacklistKeywords = [];
  List<String> _whitelistKeywords = [];
  List<NotificationRule> _notificationRules = [];

  Set<String> get enabledPackages => _enabledPackages;
  String get appFilterMode => _appFilterMode;
  List<String> get blacklistKeywords => _blacklistKeywords;
  List<String> get whitelistKeywords => _whitelistKeywords;
  List<NotificationRule> get notificationRules => _notificationRules;

  bool evaluateRule(NotificationRule rule, Map<String, dynamic> notification) {
    if (!rule.enabled) return false;
    if (rule.conditions.isEmpty) return false;

    final packageName = notification['packageName'] as String? ?? '';
    final title = notification['title'] as String? ?? '';
    final content = notification['content'] as String? ?? '';
    final time = notification['time'] as String? ?? '';

    List<bool> andGroups = [];
    bool currentGroupResult = true;
    bool isFirstCondition = true;

    for (final condition in rule.conditions) {
      bool conditionMatch = false;
      // 对齐原生 RuleEngine.evaluateCondition：条件值先 trim；除包名外空值直接不匹配
      final value = condition.value.trim();
      if (value.isEmpty && condition.type != ConditionType.packageName) {
        conditionMatch = false;
      } else {
        switch (condition.type) {
          case ConditionType.packageName:
            conditionMatch = packageName == value;
            break;
          case ConditionType.titleContains:
            conditionMatch = FilterService.normalizeForMatch(
              title,
            ).contains(FilterService.normalizeForMatch(value));
            break;
          case ConditionType.titleNotContains:
            conditionMatch = !FilterService.normalizeForMatch(
              title,
            ).contains(FilterService.normalizeForMatch(value));
            break;
          case ConditionType.contentContains:
            conditionMatch = FilterService.normalizeForMatch(
              content,
            ).contains(FilterService.normalizeForMatch(value));
            break;
          case ConditionType.contentNotContains:
            conditionMatch = !FilterService.normalizeForMatch(
              content,
            ).contains(FilterService.normalizeForMatch(value));
            break;
          case ConditionType.priority:
            conditionMatch = _evaluatePriorityCondition(value, notification);
            break;
          case ConditionType.timeRange:
            conditionMatch = _evaluateTimeRangeCondition(value, time);
            break;
          case ConditionType.regexMatch:
            conditionMatch = _evaluateRegexCondition(value, title, content);
            break;
        }
      }

      if (isFirstCondition) {
        currentGroupResult = conditionMatch;
        isFirstCondition = false;
      } else if (condition.logic == LogicOperator.and) {
        currentGroupResult = currentGroupResult && conditionMatch;
      } else {
        andGroups.add(currentGroupResult);
        currentGroupResult = conditionMatch;
      }
    }

    andGroups.add(currentGroupResult);

    return andGroups.any((g) => g);
  }

  List<RuleAction> getMatchingActions(Map<String, dynamic> notification) {
    final sortedRules = List<NotificationRule>.from(_notificationRules)
      ..sort((a, b) => b.priority.compareTo(a.priority));

    for (final rule in sortedRules) {
      if (evaluateRule(rule, notification)) {
        return rule.actions;
      }
    }

    return [RuleAction(id: 'default', type: ActionType.push)];
  }

  bool _evaluatePriorityCondition(
    String value,
    Map<String, dynamic> notification,
  ) {
    final priority = notification['priority'] as int? ?? 0;
    switch (value.toLowerCase()) {
      case 'high':
        return priority >= 2;
      case 'medium':
        return priority >= 1 && priority < 2;
      case 'low':
        return priority < 1;
      default:
        return false;
    }
  }

  bool _evaluateTimeRangeCondition(String value, String time) {
    try {
      final parts = value.split('-');
      if (parts.length != 2) return false;

      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;

      final startTime = _parseTime(parts[0]);
      final endTime = _parseTime(parts[1]);

      if (startTime == null || endTime == null) return false;

      if (startTime <= endTime) {
        return currentMinutes >= startTime && currentMinutes <= endTime;
      } else {
        return currentMinutes >= startTime || currentMinutes <= endTime;
      }
    } catch (_) {
      return false;
    }
  }

  int? _parseTime(String timeStr) {
    try {
      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) return null;

      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);

      if (hour == null || minute == null) return null;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

      return hour * 60 + minute;
    } catch (_) {
      return null;
    }
  }

  bool _evaluateRegexCondition(String pattern, String title, String content) {
    // E1：超长正则直接拒绝，防灾难性回溯阻塞（与原生 RuleEngine/FilterEngine 一致）
    if (pattern.length > 200) return false;
    try {
      final regex = RegExp(pattern);
      return regex.hasMatch(title) || regex.hasMatch(content);
    } catch (_) {
      return false;
    }
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final List<dynamic> enabledPkgs = await _channel.invokeMethod(
        'getEnabledPackages',
      );
      _enabledPackages = Set<String>.from(enabledPkgs.map((e) => e.toString()));
    } catch (e) {
      final jsonStr = prefs.getString('enabled_packages');
      if (jsonStr != null) {
        try {
          final List<dynamic> list = jsonDecode(jsonStr);
          _enabledPackages = Set<String>.from(list.map((e) => e.toString()));
        } catch (_) {}
      }
    }

    try {
      final mode = await _channel.invokeMethod('getAppFilterMode') as String?;
      _appFilterMode = (mode == 'block') ? 'block' : 'allow';
    } catch (e) {
      final mode = prefs.getString('app_filter_mode');
      _appFilterMode = (mode == 'block') ? 'block' : 'allow';
    }

    try {
      final List<dynamic> blacklist = await _channel.invokeMethod(
        'getBlacklistKeywords',
      );
      _blacklistKeywords = blacklist.map((e) => e.toString()).toList();
    } catch (e) {
      final jsonStr = prefs.getString('blacklist_keywords');
      if (jsonStr != null) {
        try {
          final List<dynamic> list = jsonDecode(jsonStr);
          _blacklistKeywords = list.map((e) => e.toString()).toList();
        } catch (_) {}
      }
    }

    try {
      final List<dynamic> whitelist = await _channel.invokeMethod(
        'getWhitelistKeywords',
      );
      _whitelistKeywords = whitelist.map((e) => e.toString()).toList();
    } catch (e) {
      final jsonStr = prefs.getString('whitelist_keywords');
      if (jsonStr != null) {
        try {
          final List<dynamic> list = jsonDecode(jsonStr);
          _whitelistKeywords = list.map((e) => e.toString()).toList();
        } catch (_) {}
      }
    }

    _notificationRules = _loadNotificationRules(prefs);
  }

  Future<void> saveAppFilter(String mode, List<String> packages) async {
    _appFilterMode = (mode == 'block') ? 'block' : 'allow';
    _enabledPackages = Set<String>.from(packages);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_filter_mode', _appFilterMode);
    await prefs.setString('enabled_packages', jsonEncode(packages));

    try {
      await _channel.invokeMethod('setAppFilter', {
        'mode': _appFilterMode,
        'packages': packages,
      });
    } catch (e) {
      debugPrint('FilterService: 保存应用筛选失败: $e');
    }
  }

  Future<void> saveBlacklistKeywords(List<String> keywords) async {
    _blacklistKeywords = keywords;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('blacklist_keywords', jsonEncode(keywords));

    try {
      await _channel.invokeMethod('setBlacklistKeywords', {
        'keywords': keywords,
      });
    } catch (e) {
      debugPrint('FilterService: 保存黑名单失败: $e');
    }
  }

  Future<void> saveWhitelistKeywords(List<String> keywords) async {
    _whitelistKeywords = keywords;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('whitelist_keywords', jsonEncode(keywords));

    try {
      await _channel.invokeMethod('setWhitelistKeywords', {
        'keywords': keywords,
      });
    } catch (e) {
      debugPrint('FilterService: 保存白名单失败: $e');
    }
  }

  Future<void> saveNotificationRules(List<NotificationRule> rules) async {
    _notificationRules = rules;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'notification_rules',
      jsonEncode(_notificationRules.map((r) => r.toMap()).toList()),
    );

    try {
      await _channel.invokeMethod('setNotificationRules', {
        'rules': rules.map((r) => r.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('FilterService: 保存通知规则失败: $e');
    }
  }

  List<NotificationRule> _loadNotificationRules(SharedPreferences prefs) {
    final jsonStr = prefs.getString('notification_rules');
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list
            .map((e) => NotificationRule.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    return NotificationRule.defaultRules();
  }
}
