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
        return ActionType.push;
    }
  }
}

class RuleAction {
  final String id;
  final ActionType type;
  final Map<String, dynamic> params;

  RuleAction({required this.id, required this.type, this.params = const {}});

  factory RuleAction.fromMap(Map<String, dynamic> map) {
    return RuleAction(
      id: map['id'] as String? ?? '',
      type: ActionTypeExtension.fromValue(map['type'] as String? ?? 'push'),
      params: (map['params'] as Map<String, dynamic>?) ?? {},
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

  NotificationRule({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    this.priority = 0,
    this.conditions = const [],
    this.actions = const [],
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map) {
    final conditions = (map['conditions'] as List?) ?? [];
    final actions = (map['actions'] as List?) ?? [];

    return NotificationRule(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      enabled: map['enabled'] as bool? ?? true,
      priority: map['priority'] as int? ?? 0,
      conditions: conditions
          .map((e) => Condition.fromMap(e as Map<String, dynamic>))
          .toList(),
      actions: actions
          .map((e) => RuleAction.fromMap(e as Map<String, dynamic>))
          .toList(),
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
  }) {
    return NotificationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      conditions: conditions ?? this.conditions,
      actions: actions ?? this.actions,
    );
  }

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
}
