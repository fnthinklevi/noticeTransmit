import 'notification_rule.dart' show ruleParamInt;

/// T25：温度规则试跑的结果（原生 `BatteryMonitor.previewTemperatureRules` 回的那份）。
///
/// 为什么求值在原生而不在这里：阈值迟滞、首轮基准、冷却截止的判据只有
/// `NotificationEngine` 一份 —— T21 整批的结论就是"判据抄第二份迟早分叉"，
/// 在 Dart 再实现一遍"会不会响"正是那种分叉（表现是测试器说不响、设备照样推）。
///
/// ⚠ 解析一律宽容（与 `notification_rule.dart` 同一口径）：这份 Map 来自平台通道，
/// 形状由原生那侧决定，任何 `as int` / `as String` 硬转抛异常，代价是用户点完
/// 「试一次」看到红屏而不是结果。
class TemperaturePreview {
  TemperaturePreview({
    required this.ok,
    required this.temps,
    required this.steps,
    required this.ruleCount,
    required this.fired,
    this.ruleId,
    this.type,
    this.threshold,
    this.temperatureC,
    this.title,
    this.content,
    this.silence,
    this.error,
  });

  factory TemperaturePreview.fromMap(Map<Object?, Object?> raw) {
    final temps = <String, double>{};
    final rawTemps = raw['temps'];
    if (rawTemps is Map) {
      rawTemps.forEach((key, value) {
        if (key is! String || value is! num) return;
        temps[key] = value.toDouble();
      });
    }
    final steps = <TemperaturePreviewStep>[];
    final rawSteps = raw['steps'];
    if (rawSteps is List) {
      for (final entry in rawSteps.whereType<Map>()) {
        final phase = entry['phase']?.toString();
        final outcome = entry['outcome']?.toString();
        if (phase == null || phase.isEmpty || outcome == null) continue;
        steps.add(TemperaturePreviewStep(phase: phase, outcome: outcome));
      }
    }
    return TemperaturePreview(
      // 缺键按"失败"处理：宁可显示"试跑失败"，也不要把读不到当成"不会触发"。
      ok: raw['ok'] == true,
      temps: temps,
      steps: steps,
      ruleCount: ruleParamInt(raw['ruleCount']) ?? 0,
      fired: raw['fired'] == true,
      ruleId: _text(raw['ruleId']),
      type: _text(raw['type']),
      threshold: ruleParamInt(raw['threshold']),
      temperatureC: raw['temperatureC'] is num
          ? (raw['temperatureC']! as num).toDouble()
          : null,
      title: _text(raw['title']),
      content: _text(raw['content']),
      silence: _text(raw['silence']),
      error: _text(raw['error']),
    );
  }

  final bool ok;

  /// 当前各维度读数（℃）。**缺键 = 这台设备读不到那个维度**（原生就不塞键，
  /// 不是 0）—— 与引擎 `?: continue` 同一条口径，界面必须说"读不到"而不是"没到阈值"。
  final Map<String, double> temps;

  /// 三步走查：`baseline` → `below` → `current`。只有最后一步是用户要的答案，
  /// 前两步是引擎的"跨越"语义要求的前置（新实例第一次必返 BASELINE）。
  final List<TemperaturePreviewStep> steps;

  final int ruleCount;
  final bool fired;
  final String? ruleId;
  final String? type;
  final int? threshold;
  final double? temperatureC;

  /// 命中时**真会推出去的**标题/正文（原生同一条渲染抄本，不是 Dart 拼的）。
  final String? title;
  final String? content;

  /// 未命中的原因（原生 `Silence` 枚举名）。
  final String? silence;
  final String? error;

  static String? _text(Object? value) {
    final s = value?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// 求值没跑成（原生抛异常或通道回 null）：界面必须与"不会触发"分开显示。
  bool get failed => !ok;
}

/// 一步走查的结果。[outcome] 是 `FIRE` 或原生 `Silence` 枚举名。
class TemperaturePreviewStep {
  const TemperaturePreviewStep({required this.phase, required this.outcome});

  final String phase;
  final String outcome;
}
