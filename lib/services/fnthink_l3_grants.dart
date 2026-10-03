import 'package:fnthink_push/fnthink_push.dart';

/// 一项 L3 系统设置在**这一台设备上**的四种下场。
///
/// ⚠ 这四态是本文件存在的全部理由。合成两态（「有 / 没有」）就是本仓修过一次的老 bug
/// 的形状 —— 权限页恒显「已授予」：把「不知道」显示成「有」，用户再也不会去查那一格。
/// 反过来把「读不到」显示成「未授权」也一样假：那要修的是代码，不是用户。
enum FnthinkL3GrantState {
  /// 已经给了，这一台现在就能用。
  granted,

  /// 读得到，且读数是「没给」—— **要用户自己去系统里开**。
  missing,

  /// 这条通道压根没有读数（方法在这个 Android 版本上没实现、少注册了一个读法）——
  /// **要修的是代码**。与 `missing` 混起来，就会让人为一个不存在的问题去设置里找。
  unreadable,

  /// 契约里有这一项，但这台设备没有它（厂商裁掉了 / 系统版本不认）—— **换一台就变了**。
  /// 与 `missing` 混起来，用户会为一个换台手机就不存在的问题反复找开关。
  unsupported,
}

/// L3 那一档「这台设备给了哪些授权」的**纯读模型**（T52）。
///
/// 它回答的是权限引导页要展示的那一件事：**契约里那几项设置，这一台现在各自是哪一态**。
/// 页面拿它渲染那一列 —— 不在别处再读一遍授权状态。
///
/// ⚠ **为什么这一层存在，而不是让页面自己去问**：契约里那六项的当前状态分别来自四个地方，
/// 形状还各不相同（`PermissionService` 的三个缓存字段、它的 `canScheduleExactAlarms()`、
/// 原生 `isMonitoringEnabled()`（经 `isServiceRunning` 通道）、`FnthinkSettings.receiveEnabled` 纯 prefs）。
/// 页面里各写一遍就是**七处会各自漂移的地方** —— 而它们漂移的表现是「某一项永远显示已开启」。
/// 这里把各处读法**收成一种**，读数由调用方注入。
///
/// ⚠ 这一层**不含任何文案**：四态各自说什么话是界面的事（要走 ARB，本应用有中英两套）。
/// 把「这台没有」与「用户没开」写成两个中文字符串放在服务层，等于允许它们在英文界面下漏出中文。
class FnthinkL3GrantRow {
  const FnthinkL3GrantRow({
    required this.key,
    required this.mode,
    required this.native,
    required this.state,
    this.note = '',
  });

  /// 契约里的设置项 key（如 `exact_alarm`）。
  final String key;

  /// `grant` / `toggle`（契约 `capabilities.l3.modes`）。
  final String mode;

  /// 契约里记的那个落点（原生函数名或 Dart 侧属性名）。
  final String native;

  final FnthinkL3GrantState state;

  /// 界面另外要补的那一句说明（例如「不开这一项，收不到任何通知」）。
  ///
  /// ⚠ **只在没给的时候留**：已经给了还在旁边写一句"你还没给"是自相矛盾的。
  final String note;

  bool get granted => state == FnthinkL3GrantState.granted;

  /// 这一项要不要用户动手（只有 `missing` 要 —— `unreadable` 要的是修代码，
  /// `unsupported` 要的是换一台设备）。
  bool get needsUserAction => state == FnthinkL3GrantState.missing;

  bool get unreadable => state == FnthinkL3GrantState.unreadable;

  bool get thisDeviceLacksIt => state == FnthinkL3GrantState.unsupported;

  /// 这一项能不能被**直接改**（`toggle`），还是只能**请用户去系统里开**（`grant`）。
  ///
  /// 界面上这两种承诺强度不同：前者勾了就成了，后者点了只是把人送到设置页。
  bool get directlyToggleable => mode == 'toggle';

  @override
  String toString() => 'FnthinkL3GrantRow($key, $mode, $state)';
}

/// 按 [rows] 汇总出这一台还差哪几项。
///
/// 排序口径**只在这里**：按契约词表里的次序（`rows` 传进来就是这个序），
/// 不按"哪些没给"重新排 —— 页面里再排一次就会出现两份，而两份迟早不一样。
List<FnthinkL3GrantRow> outstandingL3Grants(List<FnthinkL3GrantRow> rows) =>
    List<FnthinkL3GrantRow>.unmodifiable(rows.where((r) => r.needsUserAction));

/// 契约词表 → 读模型。纯函数，不碰系统：**状态由调用方注入**。
///
/// ⚠ [state] 刻意是「一个入参」而不是「在这里去查」：这一层若自己去查，
/// 就等于在纯函数里发起 MethodChannel 调用，于是 widget 测试里它永远拿不到值 ——
/// 而那正好是「显示成没给」的方向，与「显示成已给」一样是假的。
FnthinkL3GrantRow l3GrantRow(
  FnthinkContract contract,
  String key, {
  required FnthinkL3GrantState state,
  String note = '',
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
    state: state,
    note: state == FnthinkL3GrantState.granted ? '' : note,
  );
}

/// 契约里有、但这一台不支持的项 —— **如实返回，不悄悄藏起来**。
List<FnthinkL3GrantRow> unsupportedL3Grants(
  FnthinkContract contract,
  Set<String> supportedKeys,
) => List<FnthinkL3GrantRow>.unmodifiable(
  contract.l3Settings.keys
      .where((k) => !supportedKeys.contains(k))
      .map(
        (k) => l3GrantRow(contract, k, state: FnthinkL3GrantState.unsupported),
      ),
);

/// 生产那一份 `readers` 的**合成**（装配处只许经这里，不许自己写 map 字面量）。
///
/// ⚠ 为什么单独抽出来：`Map` 字面量少写一个键，编译器不喊、页面也不红 ——
/// 那一格只会显示成「读不到这台设备的状态」，**看起来像设备的问题，其实是我们的漏接**。
/// 抽成函数之后，「键集 == 契约词表」与「每枚参数落在自己的键上」才第一次可断。
///
/// 参数按契约的键名命名（不叫 `a`/`b`）：这样"接错线"至少还要过一道类型 + 一条用例。
Map<String, bool?> l3ReadersFrom({
  required bool notification,
  required bool batteryOptimization,
  bool? exactAlarm,
  bool? autostart,
  bool? monitoring,
  bool? collectInbox,
}) => <String, bool?>{
  'notification': notification,
  'exact_alarm': exactAlarm,
  'battery_optimization': batteryOptimization,
  'autostart': autostart,
  'monitoring': monitoring,
  'collect_inbox': collectInbox,
};

/// 各处读法收成一处：**按契约词表的次序**产出 [FnthinkL3GrantRow]。
///
/// ⚠ [readers] 的取值口径就是这四态（`true` / `false` / `null`）：
/// **`null`（含"键都没有"）落在 [FnthinkL3GrantState.unreadable]，不降级成 `missing`** ——
/// 读不到与「读到了 false」合成一种的话，设备上少一个方法通道时界面会说「未授权」，
/// 而真相是「没查到」，用户会为一个状态不明的东西去设置里找。
///
/// ⚠ **没有"过滤掉哪些"这个入参**：未授权项是置灰而不是隐藏，产出行数恒等于契约项数。
/// 「还差哪几项」是另一个问题，由 [outstandingL3Grants] 答。
///
/// ⚠ **次序取自契约**（`contract.l3Settings.keys`），不在这里重排 —— 见
/// [outstandingL3Grants] 那条同源的纪律。
List<FnthinkL3GrantRow> collectL3GrantRows(
  FnthinkContract contract, {
  required Map<String, bool?> readers,
  Map<String, String> notes = const <String, String>{},
}) {
  final rows = <FnthinkL3GrantRow>[];
  for (final key in contract.l3Settings.keys) {
    final read = readers[key];
    final state = switch (read) {
      // ⚠ 三档穷尽由编译器把关：`bool?` 只有 true / false / null 三个值，少写一档
      // 这里就编译不过 —— 这一层不允许「没判」那一格存在。
      true => FnthinkL3GrantState.granted,
      false => FnthinkL3GrantState.missing,
      null => FnthinkL3GrantState.unreadable,
    };
    rows.add(l3GrantRow(contract, key, state: state, note: notes[key] ?? ''));
  }
  return List<FnthinkL3GrantRow>.unmodifiable(rows);
}
