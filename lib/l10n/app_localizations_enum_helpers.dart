import '../models/notification_rule.dart';
import 'app_localizations.dart';

/// 规则引擎枚举 → 本地化文案的委托方法（R2 迁移自手写 AppLocalizations）。
///
/// 这些方法不来自 ARB 字符串表，而是按枚举值映射到表内词条，
/// 因此以扩展形式保留，避免 gen-l10n 覆盖。
extension AppLocalizationsEnumHelpers on AppLocalizations {
  String conditionTypeLabel(ConditionType type) => switch (type) {
    ConditionType.packageName => condPackage,
    ConditionType.titleContains => condTitleContains,
    ConditionType.titleNotContains => condTitleNotContains,
    ConditionType.contentContains => condContentContains,
    ConditionType.contentNotContains => condContentNotContains,
    ConditionType.priority => condPriority,
    ConditionType.timeRange => condTimeRange,
    ConditionType.regexMatch => condRegex,
    ConditionType.chargingState => condChargingState,
    ConditionType.networkType => condNetworkType,
    ConditionType.unknown => condUnknown,
  };

  String conditionTypeHint(ConditionType type) => switch (type) {
    ConditionType.packageName => hintPackage,
    ConditionType.titleContains => hintKeyword,
    ConditionType.titleNotContains => hintKeyword,
    ConditionType.contentContains => hintKeyword,
    ConditionType.contentNotContains => hintKeyword,
    ConditionType.priority => hintPriority,
    ConditionType.timeRange => hintTimeRange,
    ConditionType.regexMatch => hintRegex,
    // 设备态两型的值域**由模型里那两份词表现取**（不在 ARB 里抄一份）：
    // 用户在这里看到的串就是求值真正比的串，加一档只改 `chargingStateValues`／
    // `networkTypeValues` 一处，文案自动跟着走。
    ConditionType.chargingState => hintAllowedValues(
      chargingStateValues.join(' / '),
    ),
    ConditionType.networkType => hintAllowedValues(
      networkTypeValues.join(' / '),
    ),
    ConditionType.unknown => hintUnknown,
  };

  String actionTypeLabel(ActionType type) => switch (type) {
    ActionType.push => actionPush,
    ActionType.silent => actionSilent,
    ActionType.delay => actionDelay,
    ActionType.merge => actionMerge,
    ActionType.record => actionRecord,
  };

  String actionTypeDesc(ActionType type) => switch (type) {
    ActionType.push => actionPushDesc,
    ActionType.silent => actionSilentDesc,
    ActionType.delay => actionDelayDesc,
    ActionType.merge => actionMergeDesc,
    ActionType.record => actionRecordDesc,
  };

  String logicLabel(LogicOperator op) => switch (op) {
    LogicOperator.and => logicAnd,
    LogicOperator.or => logicOr,
  };
}
