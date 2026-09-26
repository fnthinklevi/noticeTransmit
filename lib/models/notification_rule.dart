import 'package:flutter/foundation.dart';

/// 规则里数值型 JSON 取值的**唯一口径**，与设备侧 `JSONObject.optInt` 必须一致。
///
/// 为什么单独收成一处：页面与影子链路原先各写各的 `v is int`，于是
/// `5.0`（别的工具导出的备份、手改的 JSON、模板里的实数）在界面上等于没配，
/// 设备上却照常用 —— 原生读的是 JSON，任何 `Number` 一律**截断**取整，数字串也认
/// （Android 的 org.json 会强制转换）。两侧对同一个文件值取到不同的数，表现就是
/// "我没设过延迟，它却延后推了"。旧写法还顺手用 `round()`，`100.7` 在 Dart 是 101、
/// 在设备是 100 —— 优先级排序因此也可能不同。
///
/// 这里只回答"这个值是多少"，不回答"没配时取什么默认"（缺省归调用方，两侧各自保留
/// 原有的 fallback 语义）。与 [ChannelConfigCodec.flag] 的区别是刻意的：那个是 DB 行
/// 读取器，故意不认字符串，以免脏数据混进 UI。
int? ruleParamInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  return int.tryParse(text) ?? double.tryParse(text)?.toInt();
}

/// 同上，布尔口径：只认 `Boolean` 与 `"true"/"false"`（大小写无关），
/// 与原生 `optBoolean` 一致 —— **数字不当真**（两侧都不把 1  coerce 成 true）。
bool ruleParamBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == 'true') return true;
    if (text == 'false') return false;
  }
  return fallback;
}

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

  /// 反序列化。⚠ 入参可能是**备份文件或规则模板**里的 Map，形状不受我们控制：
  /// 任何一处 `as String?` / `as int?` 硬转抛 TypeError，代价是整张规则表恢复不回来
  /// （备份恢复按类别串行执行，这一类失败会让用户的通知规则全部保持原样）。
  /// 因此这里一律宽松取值，缺省保持"启用"语义（老备份没写 enabled）。
  /// 与 [ChannelConfigCodec.flag] 的区别是刻意的：那个是 DB 行读取器，故意不认字符串，
  /// 以免脏数据混进 UI。
  factory Condition.fromMap(Map<String, dynamic> map) {
    return Condition(
      id: map['id']?.toString() ?? '',
      type: ConditionTypeExtension.fromValue(
        map['type']?.toString() ?? 'title_contains',
      ),
      value: map['value']?.toString() ?? '',
      logic: LogicOperatorExtension.fromValue(
        map['logic']?.toString() ?? 'and',
      ),
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
      id: map['id']?.toString() ?? '',
      type: ActionTypeExtension.fromValue(map['type']?.toString() ?? 'push'),
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
    // 子表按「是不是列表」取，非列表（文件被手改成对象/字符串）视为没有这一项：
    // 这一层抛 TypeError 的代价是整类配置恢复不回来（见上面的说明）。
    List<Map<String, dynamic>> asMaps(Object? value) => value is List
        ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const <Map<String, dynamic>>[];
    List<String> asTexts(Object? value) => value is List
        ? value.map((e) => e?.toString() ?? '').toList()
        : const <String>[];

    // ⚠ description 必须保留：saveNotificationRules 用 toMap() 落盘，
    // 丢掉它会让用户编辑任意规则后预制规则的说明文案（UI 上直接展示）永久消失。
    return NotificationRule(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      // ⚠ 这里**故意不用** ruleParamBool：原生 `optBoolean("enabled", true)` 对 `0` 这种
      // 形状没有布尔可转，会退回默认值"启用"，而那意味着"用户关掉的规则被一份文件读成开着"
      // —— 方向不可接受的错法。留着按值判（0/false 都算关），两侧到底怎么读 `0`
      // 需要一次真机实测才能定（JVM 侧用的是 org.json 参考实现，不是设备那份）。
      // 详见 base.md 的覆盖升级/恢复待核实清单。
      enabled: map['enabled'] != false && map['enabled'] != 0,
      priority: ruleParamInt(map['priority']) ?? 0,
      conditions: asMaps(map['conditions']).map(Condition.fromMap).toList(),
      actions: asMaps(map['actions']).map(RuleAction.fromMap).toList(),
      excludedPackages: asTexts(map['excludedPackages']),
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
