enum BatteryRuleType {
  charging,
  discharging,
  levelAbove,
  levelBelow,
  levelEquals,
}

extension BatteryRuleTypeExtension on BatteryRuleType {
  String get value {
    switch (this) {
      case BatteryRuleType.charging:
        return 'charging';
      case BatteryRuleType.discharging:
        return 'discharging';
      case BatteryRuleType.levelAbove:
        return 'level_above';
      case BatteryRuleType.levelBelow:
        return 'level_below';
      case BatteryRuleType.levelEquals:
        return 'level_equals';
    }
  }

  String get label {
    switch (this) {
      case BatteryRuleType.charging:
        return '开始充电';
      case BatteryRuleType.discharging:
        return '断开充电';
      case BatteryRuleType.levelAbove:
        return '高于某值';
      case BatteryRuleType.levelBelow:
        return '低于某值';
      case BatteryRuleType.levelEquals:
        return '等于某值';
    }
  }

  static BatteryRuleType fromValue(String value) {
    switch (value) {
      case 'charging':
        return BatteryRuleType.charging;
      case 'discharging':
        return BatteryRuleType.discharging;
      case 'level_above':
        return BatteryRuleType.levelAbove;
      case 'level_below':
        return BatteryRuleType.levelBelow;
      case 'level_equals':
        return BatteryRuleType.levelEquals;
      default:
        return BatteryRuleType.charging;
    }
  }

  bool get hasValue {
    switch (this) {
      case BatteryRuleType.charging:
      case BatteryRuleType.discharging:
        return false;
      case BatteryRuleType.levelAbove:
      case BatteryRuleType.levelBelow:
      case BatteryRuleType.levelEquals:
        return true;
    }
  }
}

class BatteryRule {
  final String id;
  final BatteryRuleType type;
  final int value;
  final bool enabled;
  final String title;
  final String content;

  BatteryRule({
    required this.id,
    required this.type,
    this.value = 0,
    this.enabled = true,
    this.title = '',
    this.content = '',
  });

  factory BatteryRule.fromMap(Map<String, dynamic> map) {
    return BatteryRule(
      id: map['id'] as String? ?? '',
      type: BatteryRuleTypeExtension.fromValue(
        map['type'] as String? ?? 'charging',
      ),
      value: map['value'] as int? ?? 0,
      enabled: map['enabled'] as bool? ?? true,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'value': value,
      'enabled': enabled,
      'title': title,
      'content': content,
    };
  }

  BatteryRule copyWith({
    String? id,
    BatteryRuleType? type,
    int? value,
    bool? enabled,
    String? title,
    String? content,
  }) {
    return BatteryRule(
      id: id ?? this.id,
      type: type ?? this.type,
      value: value ?? this.value,
      enabled: enabled ?? this.enabled,
      title: title ?? this.title,
      content: content ?? this.content,
    );
  }

  static List<BatteryRule> defaultRules() {
    return [
      BatteryRule(
        id: 'charging',
        type: BatteryRuleType.charging,
        enabled: true,
        title: '开始充电',
      ),
      BatteryRule(
        id: 'full',
        type: BatteryRuleType.levelAbove,
        value: 100,
        enabled: true,
        title: '电量充满',
      ),
      BatteryRule(
        id: 'low30',
        type: BatteryRuleType.levelBelow,
        value: 30,
        enabled: true,
        title: '电量低于30%',
      ),
      BatteryRule(
        id: 'low20',
        type: BatteryRuleType.levelBelow,
        value: 20,
        enabled: true,
        title: '电量低于20%',
      ),
      BatteryRule(
        id: 'discharging',
        type: BatteryRuleType.discharging,
        enabled: false,
        title: '断开充电',
      ),
    ];
  }
}
