import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_rule.dart';

class FilterService {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  Set<String> _enabledPackages = {};
  List<String> _blacklistKeywords = [];
  List<String> _whitelistKeywords = [];
  List<NotificationRule> _notificationRules = [];

  Set<String> get enabledPackages => _enabledPackages;
  List<String> get blacklistKeywords => _blacklistKeywords;
  List<String> get whitelistKeywords => _whitelistKeywords;
  List<NotificationRule> get notificationRules => _notificationRules;

  bool evaluateRule(NotificationRule rule, Map<String, dynamic> notification) {
    if (!rule.enabled) return false;

    final packageName = notification['packageName'] as String? ?? '';
    final title = notification['title'] as String? ?? '';
    final content = notification['content'] as String? ?? '';
    final time = notification['time'] as String? ?? '';

    bool result = rule.conditions.isEmpty;

    for (var i = 0; i < rule.conditions.length; i++) {
      final condition = rule.conditions[i];
      bool conditionMatch = false;

      switch (condition.type) {
        case ConditionType.packageName:
          conditionMatch = packageName == condition.value;
          break;
        case ConditionType.titleContains:
          conditionMatch = title.toLowerCase().contains(
            condition.value.toLowerCase(),
          );
          break;
        case ConditionType.titleNotContains:
          conditionMatch = !title.toLowerCase().contains(
            condition.value.toLowerCase(),
          );
          break;
        case ConditionType.contentContains:
          conditionMatch = content.toLowerCase().contains(
            condition.value.toLowerCase(),
          );
          break;
        case ConditionType.contentNotContains:
          conditionMatch = !content.toLowerCase().contains(
            condition.value.toLowerCase(),
          );
          break;
        case ConditionType.priority:
          conditionMatch = _evaluatePriorityCondition(
            condition.value,
            notification,
          );
          break;
        case ConditionType.timeRange:
          conditionMatch = _evaluateTimeRangeCondition(condition.value, time);
          break;
        case ConditionType.regexMatch:
          conditionMatch = _evaluateRegexCondition(
            condition.value,
            title,
            content,
          );
          break;
      }

      if (i == 0) {
        result = conditionMatch;
      } else {
        if (condition.logic == LogicOperator.and) {
          result = result && conditionMatch;
        } else {
          result = result || conditionMatch;
        }
      }
    }

    return result;
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
      final List<dynamic> enabledPkgs = await platform.invokeMethod(
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
      final List<dynamic> blacklist = await platform.invokeMethod(
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
      final List<dynamic> whitelist = await platform.invokeMethod(
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

  Future<void> saveEnabledPackages(List<String> packages) async {
    _enabledPackages = Set<String>.from(packages);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('enabled_packages', jsonEncode(packages));

    try {
      await platform.invokeMethod('setEnabledPackages', {'packages': packages});
    } catch (e) {
      // ignore
    }
  }

  Future<void> saveBlacklistKeywords(List<String> keywords) async {
    _blacklistKeywords = keywords;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('blacklist_keywords', jsonEncode(keywords));

    try {
      await platform.invokeMethod('setBlacklistKeywords', {
        'keywords': keywords,
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> saveWhitelistKeywords(List<String> keywords) async {
    _whitelistKeywords = keywords;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('whitelist_keywords', jsonEncode(keywords));

    try {
      await platform.invokeMethod('setWhitelistKeywords', {
        'keywords': keywords,
      });
    } catch (e) {
      // ignore
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
      await platform.invokeMethod('setNotificationRules', {
        'rules': rules.map((r) => r.toMap()).toList(),
      });
    } catch (e) {
      // ignore
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
