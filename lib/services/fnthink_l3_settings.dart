import 'package:fnthink_push/fnthink_push.dart';

/// L3 系统设置的**设备侧映射**（T51）。
///
/// 与 `server/lib/fnthink/l3settings.js` 是同一套设置项的两份实现，词表的唯一出处是
/// 契约 `capabilities.l3.settings`。两端各写一份是刻意的 —— 各自调本地的执行器，
/// **但"哪几项设置算数"必须同源**：一份名单存在两处时两处各自都对，
/// 而对面新加一项只有自己认得，表现是服务端把它收进队列、设备端在 apply 段判成
/// unknown —— 而 L3 恰好每次都要本地确认，用户看不出差别，只会觉得"点了没反应"。
///
/// 这一层只做纯解析，**不执行**。执行在 [FnthinkL3Executor] 那一层（碰 MethodChannel）。
///
/// ⚠ **2026-10-04 更新**（原来这段写的是"与服务端刻意不同"）：维护者删掉了「开启 L3 要过
/// 本机锁屏/生物认证」那一道（`grantableL3Level` 那一族随之删除），所以**服务端与设备侧
/// 现在判的是同一件事**了 —— 两边都只按 `confirmEveryTime` 要求"这一项要确认过"。
/// 那道本机认证的通道**从来没接过**（`unimplementedLocalAuthenticator` 永远回「没有认证器」，
/// android/ 侧也没有 `BiometricPrompt`），所以删掉它不改变任何一处的实际行为。
/// ⚠ L3 的安全度现在**只**由「对面在指令里带高级密钥或二步验证码」承担（见
/// `capabilities.remoteExecution.auth`），本机这一侧不再叠加任何本地认证。
sealed class FnthinkL3Parse {
  const FnthinkL3Parse();
}

class FnthinkL3Ok extends FnthinkL3Parse {
  const FnthinkL3Ok(this.setting);

  final FnthinkL3Setting setting;

  @override
  String toString() => 'FnthinkL3Ok($setting)';

  @override
  bool operator ==(Object other) =>
      other is FnthinkL3Ok && other.setting == setting;

  @override
  int get hashCode => setting.hashCode;
}

class FnthinkL3Rejected extends FnthinkL3Parse {
  const FnthinkL3Rejected(this.reason);

  final String reason;

  @override
  String toString() => 'FnthinkL3Rejected($reason)';

  @override
  bool operator ==(Object other) =>
      other is FnthinkL3Rejected && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// 把载荷里那个 `item` 读成设置项。纯函数：只读契约，不碰系统。
///
/// 四种拒的理由**刻意不合并** —— 合并之后界面只能说"这条不行"，
/// 而用户看到的是一个点了没反应的按钮，与"没权限"读起来一模一样
/// （T27/T28 那条「预授权失败只有一句话」在 L3 上的复刻）：
///  - `missing-item`      载荷里没有 item
///  - `unknown-setting:X` X 不在词表里
///  - `missing-grant:X`   这一项要先有对应授权才谈得上翻（契约 requiresExistingGrantFrom）
///  - `confirm-required`  这一项每次都要确认，而这一次没确认
///
/// [confirmedThisTime] 是**本机**那一次用户动作 —— 不许拿载荷里那个自称的标志替它
/// （那就是让发送方替接收端点"我确认了"，T30 那条红线）。
FnthinkL3Parse parseL3Item(
  FnthinkContract contract,
  String? item, {
  bool confirmedThisTime = false,
  Set<String> grantedKeys = const <String>{},
}) {
  if (item == null || item.isEmpty) {
    return const FnthinkL3Rejected('missing-item');
  }
  // ⚠ 拆 item 尾部那个目标值（契约 `l3.itemMayCarryTarget` / `itemTargetWords`）：
  //   `<key>` 收（沿用旧语义「读当前再翻」，**不幂等**），
  //   `<key>/on` 与 `<key>/off` 收且**幂等** —— 而投递是 at-least-once，
  //   不带目标值时重投一次就翻两次、回到原状。
  // ⚠ 词从契约读，不写死（那一层要透传回执、两端各拆一次）。
  var key = item;
  bool? target;
  final slash = item.lastIndexOf('/');
  if (slash > 0) {
    final words = contract.l3ItemTargetWords;
    final head = item.substring(0, slash);
    final tail = item.substring(slash + 1);
    final wantOn = words.contains('on');
    final wantOff = words.contains('off');
    if ((wantOn && tail == 'on') || (wantOff && tail == 'off')) {
      key = head;
      target = tail == 'on';
    }
    // ⚗ 不认识的尾部**不拆**：留成整串去查词表 ⇒ `unknown-setting:monitoring/on`
    //   而不是"猜它是别的东西"。而那正是契约 `itemTargetRejected` 说的
    //   **老设备**会报的那一句 —— 本机这一版拼错的尾部要能被看见，不能被吞掉。
  }
  final settings = contract.l3Settings;
  final base = settings[key];
  if (base == null) {
    return FnthinkL3Rejected('unknown-setting:$key');
  }
  final setting = target == null
      ? base
      : FnthinkL3Setting(
          key: base.key,
          mode: base.mode,
          native: base.native,
          targetValue: target,
        );
  // 每一项都要本地确认，且**没有免确认这条路**（契约 allowSkipConfirm: false）。
  if (contract.boolOf(const ['capabilities', 'l3', 'confirmEveryTime']) ==
          true &&
      !confirmedThisTime) {
    return const FnthinkL3Rejected('confirm-required');
  }
  if (contract.l3SettingsRequiringExistingGrant.contains(key) &&
      !grantedKeys.contains(key)) {
    return FnthinkL3Rejected('missing-grant:$key');
  }
  return FnthinkL3Ok(setting);
}

/// 设备侧执行某一项 L3 设置的那一层（真正碰系统的那一半）。
///
/// 拆成接口是为了让 [parseL3Item] 与执行分开可测：解析是纯函数、一行系统调用都没有，
/// 而执行要 MethodChannel 与 DB，混在一个类里就连"这项认不认得"都测不了。
///
/// ⚠ [grant] 一项返回**做不到**而不是"已开"：契约里那些 `grant` 项全部是
/// "跳设置页请用户自己点"（原生侧至今没有静默改系统设置的能力），
/// 所以"执行成功"的含义是**把用户送到了那一页**，不是"已经改好了"。
/// 两者混为一谈，表现是勾了之后界面上立刻显示已开启，而用户还得自己去点。
abstract class FnthinkL3Executor {
  /// 把用户送到那一项的设置页（`grant`）。返回 false = 这一台压根没有那一项的入口。
  Future<bool> grant(FnthinkL3Setting setting);

  /// 翻这台设备自己的一项开关（`toggle`）。已授权才有意义。
  Future<bool> toggle(FnthinkL3Setting setting);
}

/// 执行一项 L3 设置的结果。
class FnthinkL3Result {
  const FnthinkL3Result.ok() : reason = null;
  const FnthinkL3Result.failed(this.reason);

  /// 失败原因。**只进留痕**（T53），不进对外回执。
  final String? reason;

  bool get ok => reason == null;

  String receipt(FnthinkContract contract) =>
      ok ? 'delivered' : contract.l3SettingsReceipt;
}

/// 把一个已解析的设置项派到执行器上。纯转发，**action → 方法**的映射只有这一处。
///
/// `grant` 与 `toggle` 走的是两个不同的方法 —— 这一层存在的全部理由就是别让它们混成
/// 一个 `apply(setting)`：混了之后，"这一项能不能被直接改"这件事就没人判了。
Future<FnthinkL3Result> dispatchL3Setting(
  FnthinkContract contract,
  FnthinkL3Executor executor,
  FnthinkL3Setting setting,
) async {
  try {
    final done = setting.isToggle
        ? await executor.toggle(setting)
        : await executor.grant(setting);
    if (done) return const FnthinkL3Result.ok();
    return FnthinkL3Result.failed('not-applied:${setting.key}');
  } catch (e) {
    // 抛异常也要记成"做失败了"而不是让整轮收货停在这里 ——
    // 账已经报出去了（本机记忆里），本机这一次的执行失败不该拖垮后面的消息。
    return FnthinkL3Result.failed('threw:${setting.key}');
  }
}

/// 契约词表与设备侧映射是否同步。守卫用例调它，改契约时红的就是这一条。
bool l3SettingsCoveredByDevice(FnthinkContract contract) {
  final modes = contract.l3SettingModes.toSet();
  if (modes.isEmpty) return false;
  final settings = contract.l3Settings;
  if (settings.isEmpty) return false;
  return settings.values.every(
    (s) => modes.contains(s.mode) && s.native.isNotEmpty,
  );
}
