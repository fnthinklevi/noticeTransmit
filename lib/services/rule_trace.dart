import '../models/notification_rule.dart';
import 'filter_service.dart';

/// F1 规则测试器的命中链路追踪引擎（纯函数，无 Flutter 依赖，可单测）。
///
/// **语义对齐**（逐条镜像原生，勿单独修改一端）：
/// - 过滤阶段 = `FilterEngine.filter`（Kotlin）：黑名单关键词 > 白名单关键词 >
///   应用过滤（仅 notification）> 默认放行；关键词标准化 = `FilterService.normalizeForMatch`
///   （与原生 `FilterEngine.normalize` 同源），支持 `re:` 前缀正则（>200 字符拒绝）。
/// - 规则阶段 = `RuleEngine.decide`（Kotlin）：按优先级降序、命中第一条即停止、
///   跳过禁用规则、跳过「排除应用」命中的规则（`excludedPackages`）、无命中 → 默认推送。
/// - 动作阶段 = `RuleEngine.decideAction`（Kotlin）：silent(短路) > delay > merge > record > push；
///   merge 窗口 `windowSeconds` > 0 时 `max(秒×1000, 5000ms)`，未配置 60000ms；
///   delay 未配置或已过期 → `now + 60000ms`。
class RuleTraceStep {
  /// filter / rule / action
  final String stage;
  final bool passed;
  final String detail;

  const RuleTraceStep({
    required this.stage,
    required this.passed,
    required this.detail,
  });
}

/// 过滤阶段来源
enum TraceFilterSource { blacklist, whitelist, appFilter, defaultPass }

/// 规则评估的逐条结果标记
enum TraceRuleMark { hit, missed, disabled, excluded }

class TraceRuleEntry {
  final NotificationRule rule;
  final TraceRuleMark mark;

  const TraceRuleEntry({required this.rule, required this.mark});
}

/// 最终动作类型
enum TraceActionKind { push, record, delay, merge, silent }

class RuleTraceResult {
  final bool allowed;
  final TraceFilterSource filterSource;
  final String filterKeyword;
  final List<TraceRuleEntry> ruleEntries;
  final NotificationRule? hitRule;
  final TraceActionKind action;
  final int? mergeWindowSeconds;
  final int? delayFireAtMs;
  final List<RuleTraceStep> steps;

  const RuleTraceResult({
    required this.allowed,
    required this.filterSource,
    required this.filterKeyword,
    required this.ruleEntries,
    required this.hitRule,
    required this.action,
    this.mergeWindowSeconds,
    this.delayFireAtMs,
    required this.steps,
  });

  /// 是否发生了「延迟/聚合/静默/仅记录」这类非直推动作
  bool get hasSpecialAction => action != TraceActionKind.push;
}

class RuleTracer {
  /// 原生常量对齐（RuleEngine.kt companion）
  static const int defaultDelayMs = 60000;
  static const int defaultMergeWindowMs = 60000;
  static const int minMergeWindowMs = 5000;
  static const int maxRegexKeywordLength = 200;

  /// 关键词匹配：镜像 `FilterEngine.matchKeyword`（标准化由调用方先做）
  /// 支持 `re:` 前缀正则（大小写不敏感，超长拒绝防灾难性回溯）
  static bool matchKeyword(String normalizedText, String rawKeyword) {
    final keyword = FilterService.normalizeForMatch(rawKeyword);
    if (keyword.isEmpty) return false;
    if (keyword.startsWith('re:')) {
      final pattern = keyword.substring(3);
      if (pattern.isEmpty) return false;
      if (pattern.length > maxRegexKeywordLength) return false;
      try {
        return RegExp(pattern, caseSensitive: false).hasMatch(normalizedText);
      } catch (_) {
        return false;
      }
    }
    return normalizedText.contains(keyword);
  }

  /// 追踪一条模拟通知的完整命中链路。
  ///
  /// [notifyPriority]：0=低 / 1=中 / 2=高（与原生 `NotificationInfo.priority` 同口径）。
  /// [sourceType]：notification / sms / call（sms、call 不走应用过滤，与原生一致）。
  static RuleTraceResult trace(
    FilterService filter, {
    required String packageName,
    required String title,
    required String content,
    int notifyPriority = 1,
    String subText = '',
    String sourceType = 'notification',
    DateTime? now,
  }) {
    final steps = <RuleTraceStep>[];
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;

    // ── ① 过滤阶段（FilterEngine.filter）──
    final fullText = FilterService.normalizeForMatch(
      '$title $content $subText',
    );

    String filterKeyword = '';
    var source = TraceFilterSource.defaultPass;
    var allowed = true;

    for (final raw in filter.blacklistKeywords) {
      if (raw.trim().isEmpty) continue;
      if (matchKeyword(fullText, raw)) {
        allowed = false;
        source = TraceFilterSource.blacklist;
        filterKeyword = raw;
        break;
      }
    }
    if (allowed) {
      for (final raw in filter.whitelistKeywords) {
        if (raw.trim().isEmpty) continue;
        if (matchKeyword(fullText, raw)) {
          source = TraceFilterSource.whitelist;
          filterKeyword = raw;
          break;
        }
      }
    }
    if (allowed &&
        source == TraceFilterSource.defaultPass &&
        sourceType == 'notification') {
      if (filter.appFilterMode == 'block') {
        if (filter.enabledPackages.contains(packageName)) {
          allowed = false;
          source = TraceFilterSource.appFilter;
        }
      } else {
        if (filter.enabledPackages.isNotEmpty &&
            !filter.enabledPackages.contains(packageName)) {
          allowed = false;
          source = TraceFilterSource.appFilter;
        }
      }
    }

    steps.add(
      RuleTraceStep(
        stage: 'filter',
        passed: allowed,
        detail: switch (source) {
          TraceFilterSource.blacklist => 'blacklist:$filterKeyword',
          TraceFilterSource.whitelist => 'whitelist:$filterKeyword',
          TraceFilterSource.appFilter => 'appFilter',
          TraceFilterSource.defaultPass => 'defaultPass',
        },
      ),
    );

    // ── ② 规则阶段（RuleEngine.decide）──
    final ruleEntries = <TraceRuleEntry>[];
    final sorted = [...filter.notificationRules]
      ..sort((a, b) => b.priority.compareTo(a.priority));

    NotificationRule? hitRule;
    if (allowed) {
      for (final rule in sorted) {
        if (!rule.enabled) {
          ruleEntries.add(
            TraceRuleEntry(rule: rule, mark: TraceRuleMark.disabled),
          );
          continue;
        }
        if (rule.excludedPackages.contains(packageName)) {
          ruleEntries.add(
            TraceRuleEntry(rule: rule, mark: TraceRuleMark.excluded),
          );
          continue;
        }
        final matched = filter.evaluateRule(rule, {
          'packageName': packageName,
          'title': title,
          'content': content,
          'time': _formatTime(now ?? DateTime.now()),
          'priority': notifyPriority,
        });
        if (matched) {
          ruleEntries.add(TraceRuleEntry(rule: rule, mark: TraceRuleMark.hit));
          hitRule = rule;
          break; // 命中第一条即停止（原生同语义）
        }
        ruleEntries.add(TraceRuleEntry(rule: rule, mark: TraceRuleMark.missed));
      }
    }

    // ── ③ 动作阶段（RuleEngine.decideAction）──
    var action = TraceActionKind.push;
    int? mergeWindowSeconds;
    int? delayFireAtMs;

    if (hitRule != null) {
      var recordOnly = false;
      var silent = false;
      for (final a in hitRule.actions) {
        switch (a.type) {
          case ActionType.silent:
            silent = true;
            break;
          case ActionType.record:
            recordOnly = true;
            break;
          case ActionType.delay:
            final t = _computeFireAt(a.params, nowMs);
            delayFireAtMs = (t != null && t > nowMs)
                ? t
                : nowMs + defaultDelayMs;
            break;
          case ActionType.merge:
            if (mergeWindowSeconds == null) {
              final seconds = a.params['windowSeconds'];
              final s = seconds is int ? seconds : -1;
              mergeWindowSeconds = s > 0
                  ? ((s * 1000) < minMergeWindowMs ? 5 : s)
                  : defaultMergeWindowMs ~/ 1000;
            }
            break;
          case ActionType.push:
            break;
        }
      }
      if (silent) {
        action = TraceActionKind
            .silent; // silent 短路（原生 decideAction 立即 return Block）
      } else if (delayFireAtMs != null) {
        action = TraceActionKind.delay;
      } else if (mergeWindowSeconds != null) {
        action = TraceActionKind.merge;
      } else if (recordOnly) {
        action = TraceActionKind.record;
      } else {
        action = TraceActionKind.push;
      }
    }

    steps.add(
      RuleTraceStep(
        stage: 'action',
        passed:
            action == TraceActionKind.push || action == TraceActionKind.record,
        detail: switch (action) {
          TraceActionKind.silent => 'silent',
          TraceActionKind.delay => 'delay:${delayFireAtMs ?? 0}',
          TraceActionKind.merge => 'merge:${mergeWindowSeconds ?? 60}',
          TraceActionKind.record => 'record',
          TraceActionKind.push => 'push',
        },
      ),
    );

    return RuleTraceResult(
      allowed: allowed,
      filterSource: source,
      filterKeyword: filterKeyword,
      ruleEntries: ruleEntries,
      hitRule: hitRule,
      action: action,
      mergeWindowSeconds: mergeWindowSeconds,
      delayFireAtMs: delayFireAtMs,
      steps: steps,
    );
  }

  /// 镜像 `RuleEngine.computeFireAt`：delaySeconds > 0 → now+n；否则 scheduleTime "HH:mm"
  /// （当日该时刻，已过顺延次日）；均未配置 → null
  static int? _computeFireAt(Map<String, dynamic> params, int nowMs) {
    final delaySeconds = params['delaySeconds'];
    if (delaySeconds is int && delaySeconds > 0) {
      return nowMs + delaySeconds * 1000;
    }
    final scheduleTime = (params['scheduleTime']?.toString() ?? '').trim();
    if (scheduleTime.isNotEmpty) {
      final parts = scheduleTime.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59) {
          final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
          var fire = DateTime(now.year, now.month, now.day, hour, minute);
          if (!fire.isAfter(now)) {
            fire = fire.add(const Duration(days: 1));
          }
          return fire.millisecondsSinceEpoch;
        }
      }
    }
    return null;
  }

  /// 与原生 NotificationInfo.time 同格式（HH:mm:ss），供时间范围条件评估
  static String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
