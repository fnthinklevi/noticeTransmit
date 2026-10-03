import 'package:fnthink_push/fnthink_push.dart';

/// L3 那一档「这台设备给了哪些授权」的**纯读模型**（T52）。
///
/// 它回答的是权限引导页要展示的那一件事：**契约里那几项设置，这一台现在各自是 granted
/// 还是没给**。页面拿它渲染那一列 —— 不在别处再读一遍授权状态。
///
/// ⚠ **为什么这一层存在，而不是让页面自己去问**：`PermissionService` 里有
/// `isNotificationPermissionGranted` / `isPostNotificationPermissionGranted` /
/// `isIgnoringBatteryOptimizations` / `canScheduleExactAlarms` 四种读法，形状还各不相同
/// （有的回 bool、有的回 bool?），而 `monitoring` / `receiveEnabled` 又在
/// `MainActivity` 与 `FnthinkSettings` 另一头。**七项七种读法**，页面里各写一遍
/// 就是七处会各自漂移的地方 —— 而它们漂移的表现是「某一项永远显示已开启」，
/// 那正是本仓修过一次的老 bug（权限页恒显已授予）。这里把七种读法**收成一种**。
class FnthinkL3GrantRow {
  const FnthinkL3GrantRow({
    required this.key,
    required this.mode,
    required this.native,
    required this.granted,
    required this.detail,
  });

  /// 契约里的设置项 key（如 `exact_alarm`）。
  final String key;

  /// `grant` / `toggle`（契约 `capabilities.l3.modes`）。
  final String mode;

  /// 契约里记的那个落点（原生函数名或 Dart 侧属性名）。
  final String native;

  /// 这一台现在有没有给。
  final bool granted;

  /// **没给时的那一句解释**（`granted` 为 true 时为空串）。
  ///
  /// ⚠ 未授权项**置灰而不是隐藏** —— 隐藏的话用户看到的是一个少了一项的列表，
  /// 而"幻念推送要改哪些系统设置"这件事本该在点之前就说清楚。
  final String detail;

  bool get needsUserAction => !granted;

  /// 这一项能不能被**直接改**（`toggle`），还是只能**请用户去系统里开**（`grant`）。
  ///
  /// 界面上这两种承诺强度不同：前者勾了就成了，后者点了只是把人送到设置页。
  bool get directlyToggleable => mode == 'toggle';

  @override
  String toString() => 'FnthinkL3GrantRow($key, $mode, granted=$granted)';
}

/// 按 [rows] 汇总出这一台还差哪几项。
///
/// 排序口径**只在这里**：按契约词表里的次序（`rows` 传进来就是这个序），
/// 不按"哪些没给"重新排 —— 页面里再排一次就会出现两份，而两份迟早不一样。
List<FnthinkL3GrantRow> outstandingL3Grants(List<FnthinkL3GrantRow> rows) =>
    List<FnthinkL3GrantRow>.unmodifiable(rows.where((r) => r.needsUserAction));

/// 契约词表 → 读模型。纯函数，不碰系统：**读数由调用方注入**。
///
/// ⚠ [granted] 刻意是「一个回调」而不是「在这里去查」：这一层若自己去查，
/// 就等于在纯函数里发起 MethodChannel 调用，于是 widget 测试里它永远拿不到值 ——
/// 而那正好是「显示成没给」的方向，与「显示成已给」一样是假的。
FnthinkL3GrantRow l3GrantRow(
  FnthinkContract contract,
  String key, {
  required bool granted,
  required String detailWhenMissing,
}) {
  final setting = contract.l3Settings[key];
  if (setting == null) {
    throw StateError(
      '契约 capabilities.l3.settings 里没有 $key —— '
      '拿一个词表外的项去渲染，这一行就既不属于任何一档，也没人能给它填授权状态',
    );
  }
  return FnthinkL3GrantRow(
    key: key,
    mode: setting.mode,
    native: setting.native,
    granted: granted,
    // 解释只在没给时用得上：给了的时候再讲一遍"你还没给"是自相矛盾。
    detail: granted ? '' : detailWhenMissing,
  );
}

/// 契约里有、但这一台压根不支持的项 —— **如实返回，不悄悄藏起来**。
///
/// ⚠ 「这台系统没有这一项」与「用户还没去开」是两件事：前者是设备事实（换一台就变了），
/// 后者是要用户动手的。合成一种显示的话，用户会一直为一个换台手机就不存在的问题
/// 去设置里找 —— 而找不到。
List<FnthinkL3GrantRow> unsupportedL3Grants(
  FnthinkContract contract,
  Set<String> supportedKeys,
) => List<FnthinkL3GrantRow>.unmodifiable(
  contract.l3Settings.keys
      .where((k) => !supportedKeys.contains(k))
      .map(
        (k) => FnthinkL3GrantRow(
          key: k,
          mode: contract.l3Settings[k]!.mode,
          native: contract.l3Settings[k]!.native,
          granted: false,
          detail: unsupportedDetail,
        ),
      ),
);

/// 「这台不支持」那一句。
const String unsupportedDetail = '这台设备上没有这一项';

/// 七种读法收成一处：**按契约词表的次序**产出 [FnthinkL3GrantRow]。
///
/// ⚠ 这是 T52 的核心动作。契约里那七项，授权状态**分别**来自四个不同的地方：
/// `PermissionService` 的三个缓存字段（通知/电池优化）、它的 `canScheduleExactAlarms()`、
/// 原生的 `isMonitoringEnabled()`，以及 `FnthinkSettings.receiveEnabled`（纯 prefs）。
/// 页面里各写一遍就是**七处会各自漂移的地方** —— 而它们漂移的表现是
/// 「某一项永远显示已开启」，那正是本仓修过一次的老 bug（权限页恒显已授予）。
/// 所以：读法只在这里，读数由参数注入（[readers]），本文件不碰 MethodChannel 也不碰 DB。
///
/// ⚠ [readers] 缺一项时**不静默跳过**，而是给「这台读不到」那一档（`granted: false`
/// + [unreadableDetail]）：读不到与「读到了 false」合成一种的话，设备上少一个方法通道
/// 时界面会说「未授权」，而真相是「没查到」—— 用户会为一个状态不明的东西去设置里找。
///
/// ⚠ **次序取自契约**（`contract.l3Settings.keys`），不在这里重排 —— 见
/// [outstandingL3Grants] 那条同源的纪律。
List<FnthinkL3GrantRow> collectL3GrantRows(
  FnthinkContract contract, {
  required Map<String, bool?> readers,
  Map<String, String> details = const <String, String>{},
}) {
  final rows = <FnthinkL3GrantRow>[];
  for (final key in contract.l3Settings.keys) {
    final read = readers[key];
    if (read == null) {
      rows.add(
        FnthinkL3GrantRow(
          key: key,
          mode: contract.l3Settings[key]!.mode,
          native: contract.l3Settings[key]!.native,
          granted: false,
          detail: unreadableDetail,
        ),
      );
      continue;
    }
    rows.add(
      l3GrantRow(
        contract,
        key,
        granted: read,
        detailWhenMissing: details[key] ?? defaultDetail,
      ),
    );
  }
  return List<FnthinkL3GrantRow>.unmodifiable(rows);
}

/// 「这台读不到」那一句。与「未授权」**刻意不同**（见 [collectL3GrantRows]）。
const String unreadableDetail = '读不到这台设备的状态';

/// 没给时若没给一句专门的解释，就用它。
const String defaultDetail = '还没给这台设备授权';
