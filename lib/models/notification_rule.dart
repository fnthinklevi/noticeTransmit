import 'package:flutter/foundation.dart';

enum ConditionType {
  packageName,
  titleContains,
  titleNotContains,
  contentContains,
  contentNotContains,
  priority,
  timeRange,
  regexMatch,
}

extension ConditionTypeExtension on ConditionType {
  String get value {
    switch (this) {
      case ConditionType.packageName:
        return 'package_name';
      case ConditionType.titleContains:
        return 'title_contains';
      case ConditionType.titleNotContains:
        return 'title_not_contains';
      case ConditionType.contentContains:
        return 'content_contains';
      case ConditionType.contentNotContains:
        return 'content_not_contains';
      case ConditionType.priority:
        return 'priority';
      case ConditionType.timeRange:
        return 'time_range';
      case ConditionType.regexMatch:
        return 'regex_match';
    }
  }

  String get label {
    switch (this) {
      case ConditionType.packageName:
        return '应用包名';
      case ConditionType.titleContains:
        return '标题包含';
      case ConditionType.titleNotContains:
        return '标题不包含';
      case ConditionType.contentContains:
        return '内容包含';
      case ConditionType.contentNotContains:
        return '内容不包含';
      case ConditionType.priority:
        return '通知优先级';
      case ConditionType.timeRange:
        return '时间范围';
      case ConditionType.regexMatch:
        return '正则表达式';
    }
  }

  String get hint {
    switch (this) {
      case ConditionType.packageName:
        return '例如: com.example.app';
      case ConditionType.titleContains:
      case ConditionType.titleNotContains:
        return '输入关键词';
      case ConditionType.contentContains:
      case ConditionType.contentNotContains:
        return '输入关键词';
      case ConditionType.priority:
        return '高/中/低';
      case ConditionType.timeRange:
        return '09:00-18:00';
      case ConditionType.regexMatch:
        return '正则表达式';
    }
  }

  static ConditionType fromValue(String value) {
    switch (value) {
      case 'package_name':
        return ConditionType.packageName;
      case 'title_contains':
        return ConditionType.titleContains;
      case 'title_not_contains':
        return ConditionType.titleNotContains;
      case 'content_contains':
        return ConditionType.contentContains;
      case 'content_not_contains':
        return ConditionType.contentNotContains;
      case 'priority':
        return ConditionType.priority;
      case 'time_range':
        return ConditionType.timeRange;
      case 'regex_match':
        return ConditionType.regexMatch;
      default:
        debugPrint('警告：未知的 ConditionType 值: $value');
        return ConditionType.titleContains;
    }
  }
}

enum LogicOperator { and, or }

extension LogicOperatorExtension on LogicOperator {
  String get value {
    switch (this) {
      case LogicOperator.and:
        return 'and';
      case LogicOperator.or:
        return 'or';
    }
  }

  String get label {
    switch (this) {
      case LogicOperator.and:
        return '且';
      case LogicOperator.or:
        return '或';
    }
  }

  static LogicOperator fromValue(String value) {
    switch (value) {
      case 'and':
        return LogicOperator.and;
      case 'or':
        return LogicOperator.or;
      default:
        debugPrint('警告：未知的 LogicOperator 值: $value');
        return LogicOperator.and;
    }
  }
}

class Condition {
  final String id;
  final ConditionType type;
  final String value;
  final LogicOperator logic;

  Condition({
    required this.id,
    required this.type,
    required this.value,
    this.logic = LogicOperator.and,
  });

  factory Condition.fromMap(Map<String, dynamic> map) {
    return Condition(
      id: map['id'] as String? ?? '',
      type: ConditionTypeExtension.fromValue(
        map['type'] as String? ?? 'title_contains',
      ),
      value: map['value'] as String? ?? '',
      logic: LogicOperatorExtension.fromValue(map['logic'] as String? ?? 'and'),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'type': type.value, 'value': value, 'logic': logic.value};
  }

  Condition copyWith({
    String? id,
    ConditionType? type,
    String? value,
    LogicOperator? logic,
  }) {
    return Condition(
      id: id ?? this.id,
      type: type ?? this.type,
      value: value ?? this.value,
      logic: logic ?? this.logic,
    );
  }
}

enum ActionType { push, silent, delay, merge, record }

extension ActionTypeExtension on ActionType {
  String get value {
    switch (this) {
      case ActionType.push:
        return 'push';
      case ActionType.silent:
        return 'silent';
      case ActionType.delay:
        return 'delay';
      case ActionType.merge:
        return 'merge';
      case ActionType.record:
        return 'record';
    }
  }

  String get label {
    switch (this) {
      case ActionType.push:
        return '推送通知';
      case ActionType.silent:
        return '静默忽略';
      case ActionType.delay:
        return '延迟推送';
      case ActionType.merge:
        return '合并推送';
      case ActionType.record:
        return '仅记录';
    }
  }

  String get description {
    switch (this) {
      case ActionType.push:
        return '将通知推送到指定渠道';
      case ActionType.silent:
        return '不推送，静默处理';
      case ActionType.delay:
        return '延迟一段时间后推送';
      case ActionType.merge:
        return '合并同应用多条通知';
      case ActionType.record:
        return '仅记录到历史，不推送';
    }
  }

  static ActionType fromValue(String value) {
    switch (value) {
      case 'push':
        return ActionType.push;
      case 'silent':
        return ActionType.silent;
      case 'delay':
        return ActionType.delay;
      case 'merge':
        return ActionType.merge;
      case 'record':
        return ActionType.record;
      default:
        debugPrint('警告：未知的 ActionType 值: $value');
        return ActionType.push;
    }
  }
}

class RuleAction {
  final String id;
  final ActionType type;
  final Map<String, dynamic> params;

  RuleAction({required this.id, required this.type, this.params = const {}});

  /// 反序列化（含 `params`）。
  ///
  /// ⚠ `params` 的 cast 必须宽松，否则**整条规则解析抛 TypeError**：
  /// `jsonDecode` 产生的是 `_Map<String, dynamic>`，它同时满足
  /// `is Map<String, dynamic>` 与 `is Map<dynamic, dynamic>`，所以
  /// `map['params'] as Map<String, dynamic>?` 在**落盘读取**路径上是安全的；
  /// 但 `Map<dynamic, dynamic>`（`_Map<dynamic, dynamic>`）**不是**
  /// `Map<String, dynamic>` 的子类型，直接 cast 会抛：
  ///   `type '_Map<dynamic, dynamic>' is not a subtype of type 'Map<String, dynamic>?'`
  /// 而这些字面量来自 `NotificationRule.toMap()` 产生的
  /// `Map<String, Map<dynamic, dynamic>>`（`defaultRules()` 里
  /// `params: {'windowSeconds': 60}` 的推断类型）——即**代码内构造规则**的路径。
  /// 用 `is Map` 判断 + `Map<String, dynamic>.from` 拷贝可同时覆盖两种泛型。
  ///
  /// 另注：本方法**不能丢弃 params**——`saveNotificationRules` 用 `toMap()` 落盘，
  /// 丢字段会让 merge 的 `windowSeconds`、delay 的 `delaySeconds` / `scheduleTime`
  /// 在用户编辑规则后被静默清空（原生退回默认值）。回归用例见
  /// `test/models/notification_rule_test.dart` 的「落盘保真」一组。
  factory RuleAction.fromMap(Map<String, dynamic> map) {
    final rawParams = map['params'];
    return RuleAction(
      id: map['id'] as String? ?? '',
      type: ActionTypeExtension.fromValue(map['type'] as String? ?? 'push'),
      params: rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'type': type.value, 'params': params};
  }

  RuleAction copyWith({
    String? id,
    ActionType? type,
    Map<String, dynamic>? params,
  }) {
    return RuleAction(
      id: id ?? this.id,
      type: type ?? this.type,
      params: params ?? this.params,
    );
  }
}

class NotificationRule {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final int priority;
  final List<Condition> conditions;
  final List<RuleAction> actions;

  /// 规则级适用应用（**排除制**，P1-4）：为空 = 适用于全部应用（默认，兼容旧数据）；
  /// 非空 = 列表内的应用不适用本规则。双端评估语义一致
  /// （原生 RuleEngine.evaluate 读同名 JSON 字段，见 base.md §4.6.1）。
  final List<String> excludedPackages;

  NotificationRule({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    this.priority = 0,
    this.conditions = const [],
    this.actions = const [],
    this.excludedPackages = const [],
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map) {
    final conditions = (map['conditions'] as List?) ?? [];
    final actions = (map['actions'] as List?) ?? [];
    final excludedPackages = (map['excludedPackages'] as List?) ?? [];

    // ⚠ description 必须保留：saveNotificationRules 用 toMap() 落盘，
    // 丢掉它会让用户编辑任意规则后预制规则的说明文案（UI 上直接展示）永久消失。
    return NotificationRule(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      enabled: map['enabled'] as bool? ?? true,
      priority: map['priority'] as int? ?? 0,
      conditions: conditions
          .map((e) => Condition.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      actions: actions
          .map((e) => RuleAction.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      excludedPackages: excludedPackages.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'enabled': enabled,
      'priority': priority,
      'conditions': conditions.map((c) => c.toMap()).toList(),
      'actions': actions.map((a) => a.toMap()).toList(),
      'excludedPackages': excludedPackages,
    };
  }

  NotificationRule copyWith({
    String? id,
    String? name,
    String? description,
    bool? enabled,
    int? priority,
    List<Condition>? conditions,
    List<RuleAction>? actions,
    List<String>? excludedPackages,
  }) {
    return NotificationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      conditions: conditions ?? this.conditions,
      actions: actions ?? this.actions,
      excludedPackages: excludedPackages ?? this.excludedPackages,
    );
  }

  /// 预制规则列表（**默认全部开启**）。
  ///
  /// ⚠️ 新增/修改后需注意：默认规则必须真正下发给原生才生效——`FilterService.loadSettings`
  /// 在本地无 `notification_rules` 时会调用 `ensureDefaultRulesPersisted()` 把本列表
  /// 落盘并推给原生，否则原生 RuleEngine 拿到空规则表，全部走 Push。
  static List<NotificationRule> defaultRules() {
    return [
      NotificationRule(
        id: 'sms_code',
        name: '验证码短信优先推送',
        description: '标题或内容包含"验证码"、"验证码"的通知优先推送',
        enabled: true,
        priority: 100,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.contentContains,
            value: '验证码',
            logic: LogicOperator.or,
          ),
          Condition(
            id: 'c2',
            type: ConditionType.titleContains,
            value: '验证码',
            logic: LogicOperator.or,
          ),
        ],
        actions: [RuleAction(id: 'a1', type: ActionType.push)],
      ),
      NotificationRule(
        id: 'merge_burst',
        name: '应用通知聚合',
        description: '同一应用 60 秒内收到的多条通知合并为一条推送，避免连续打扰',
        enabled: true,
        // 优先级低于夜间免打扰(200)与验证码(100)：聚合是「降噪」而非「优先」，
        // 命中优先级更高的规则时按更高优先级规则处理。
        priority: 10,
        conditions: [
          // 聚合规则不筛应用：以「所有应用」为范围。规则引擎要求至少一个条件，
          // 用 packageName 通配 "*" 表达「任意应用」（见 FilterEngine/RuleEngine 的匹配实现）。
          Condition(
            id: 'c1',
            type: ConditionType.packageName,
            value: '*',
            logic: LogicOperator.and,
          ),
        ],
        actions: [
          RuleAction(
            id: 'a1',
            type: ActionType.merge,
            params: {'windowSeconds': 60},
          ),
        ],
      ),
      NotificationRule(
        id: 'marketing_block',
        name: '营销广告拦截',
        description: '拦截常见营销关键词的通知',
        enabled: true,
        priority: 50,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.contentContains,
            value: '优惠',
            logic: LogicOperator.or,
          ),
          Condition(
            id: 'c2',
            type: ConditionType.contentContains,
            value: '促销',
            logic: LogicOperator.or,
          ),
          Condition(
            id: 'c3',
            type: ConditionType.contentContains,
            value: '抢购',
            logic: LogicOperator.or,
          ),
        ],
        actions: [RuleAction(id: 'a1', type: ActionType.silent)],
      ),
      NotificationRule(
        id: 'night_dnd',
        name: '夜间免打扰',
        description: '22:00-07:00 之间的通知静默处理',
        enabled: true,
        priority: 200,
        conditions: [
          Condition(
            id: 'c1',
            type: ConditionType.timeRange,
            value: '22:00-07:00',
            logic: LogicOperator.and,
          ),
        ],
        actions: [RuleAction(id: 'a1', type: ActionType.silent)],
      ),
    ];
  }

  /// 需要补充进入既有规则表的预制规则（用于老用户升级补齐）。
  ///
  /// 按 [id] 与用户现有规则去重：用户已存在同 id 规则（含被手动关闭的）时不覆盖，
  /// 尊重用户「关掉它」的明确意图。返回空列表表示无需补充。
  static List<NotificationRule> missingDefaults(
    List<NotificationRule> existing,
  ) {
    final existingIds = existing.map((r) => r.id).toSet();
    return defaultRules()
        .where((r) => !existingIds.contains(r.id))
        .toList(growable: false);
  }
}
