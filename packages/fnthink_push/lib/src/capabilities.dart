import 'contract.dart';

/// 能力清单（T30）的纯裁决层：**一条已经证明身份的消息，这台设备准不准它做**。
///
/// 这一层刻意不碰存储、UI 与网络 —— 它只回答一个会被两端各写一遍的问题：
/// 签名验过之后，`type` 与逐条勾选的清单合不合并。写歪一次的表现不是报错，
/// 而是"同一把已配对的钥匙，在 Dart 侧只能发通知、在 Node 侧却能触发设置"。
///
/// 三条规则都来自契约（`capabilities` 段），这里一个数值都不重复定义：
/// ① `type` 的取值表闭合，认不出就拒；② 从 [FnthinkContract.itemRequiredFromLevel] 起
/// 光有级别不够，还要 `item` 在这台设备勾选过的清单里；③ L3 每次都要本地确认。
class FnthinkGrant {
  FnthinkGrant({
    required this.maxLevel,
    this.items = const [],
    this.revision = 0,
    this.grantedAt,
  });

  /// 该发送方被允许的最高级别（L1/L2/L3）。
  final String maxLevel;

  /// 逐条勾选过的项目 id（动作、设置）。**没有"通配"**：清单里没写就是没给。
  final List<String> items;

  /// 第几版授权。变更必须重新确认，所以它只增不减（给"对端拿旧版来签"留判据）。
  final int revision;

  final int? grantedAt;

  /// 从设备/端点记录里读（记录形如 `{grant: {...}}`）。
  static FnthinkGrant fromRecord(
    FnthinkContract contract,
    Map<String, Object?>? record,
  ) => fromNode(contract, record?['grant']);

  /// 从**授权节点本身**读。读不到就按契约的缺省档（fail-closed），**不是**按"全给"；
  /// `items` 不是数组也按空清单算，同样不放开。
  static FnthinkGrant fromNode(FnthinkContract contract, Object? node) {
    if (node is! Map) {
      return FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel);
    }
    // 形状不认识就按空清单，**不用 as**：`as List` 在拿到字符串时是抛，
    // 而这里要的是"判不过"，不是"读记录读出一个 500"。
    final rawItems = node['items'];
    final items = rawItems is List
        ? rawItems.map((e) => '$e').where((e) => e.isNotEmpty).toList()
        : const <String>[];
    final rawRevision = node['revision'];
    final rawGrantedAt = node['grantedAt'];
    return FnthinkGrant(
      maxLevel: '${node['maxLevel'] ?? contract.grantDefaultMaxLevel}',
      items: items,
      revision: rawRevision is num ? rawRevision.toInt() : 0,
      grantedAt: rawGrantedAt is num ? rawGrantedAt.toInt() : null,
    );
  }

  Map<String, Object?> toMap() => {
    'maxLevel': maxLevel,
    'items': items,
    'revision': revision,
    if (grantedAt != null) 'grantedAt': grantedAt,
  };
}

/// 裁决走哪一段。**没有默认值**：两条路径判的不完全是同一件事，
/// 让调用方不必说清自己是哪一段，就等于允许服务端拿"对端自称已确认"当确认用。
enum CapabilityStage {
  /// 服务端收单：只判 词表 / 档位 / 逐条清单。判不了"每次本地确认"（那发生在设备上），
  /// 到最高档时放行并带 [CapabilityDecision.requiresLocalConfirm]。
  intake,

  /// 设备落地之前：四条全判，其中确认取自**本机**那一次用户动作。
  apply,
}

/// 裁决结果。**原因只进日志与留痕，不改变对外形状**（能力拒绝发生在身份已证明之后，
/// 所以它可以被说清楚 —— 与 T27/T28 那条"预授权失败只有一句话"是两回事）。
class CapabilityDecision {
  const CapabilityDecision._(this.reason, this.requiresLocalConfirm);

  static const CapabilityDecision allow = CapabilityDecision._(null, false);
  static const CapabilityDecision allowNeedConfirm = CapabilityDecision._(
    null,
    true,
  );
  static CapabilityDecision unknownType(String type) =>
      CapabilityDecision._('unknown-type:$type', false);
  static CapabilityDecision levelNotGranted(String need) =>
      CapabilityDecision._('level:$need', false);
  static CapabilityDecision itemNotGranted(String item) =>
      CapabilityDecision._('item:$item', false);
  static const CapabilityDecision itemMissing = CapabilityDecision._(
    'missing-item',
    false,
  );
  static const CapabilityDecision confirmRequired = CapabilityDecision._(
    'confirm-required',
    true,
  );

  /// 闭集：向量的期望值只能取这些形状（新增一种却不补向量 ⇒ 守卫红）。
  static final RegExp reasonPattern = RegExp(
    r'^(unknown-type:.+|level:L\d|item:.+|missing-item|confirm-required)$',
  );

  final String? reason;

  /// 这一条要不要在落到用户眼前时**再确认一次**（契约 `capabilities.l3.confirmEveryTime`）。
  /// intake 那一段它只是"提醒"，apply 那一段它是判据。
  final bool requiresLocalConfirm;

  bool get allowed => reason == null;
}

/// 端点（长期口令、无签名）那一侧的授权：**只有档位，没有逐条清单**。
/// 走同一个裁决函数，不在别处再写一份"端点不许发动作"。
FnthinkGrant endpointGrant(FnthinkContract contract) =>
    FnthinkGrant(maxLevel: contract.endpointMaxLevel);

/// 能不能发这一条。纯函数：不查库、不弹框、不猜时钟。
///
/// [item] 由载荷带（如 `app:<包名>/<动作>`、`setting:<键>`），且**必须来自签过名的部分**
/// （服务端那道 `unsigned-item` 检查钉的就是这个）。契约里 `itemRequiredFromLevel`
/// 那一档及以上才要求它。
CapabilityDecision decideCapability(
  FnthinkContract contract, {
  required CapabilityStage stage,
  FnthinkGrant? grant,
  required String type,
  String? item,
  bool confirmedThisTime = false,
}) {
  final need = contract.messageTypeLevels[type];
  // 认不出的 type 一律拒，且不往任何一侧兜底：兜底等于把词表的解释权交给对端。
  if (need == null || need.isEmpty) {
    return CapabilityDecision.unknownType(type);
  }
  final effective =
      grant ?? FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel);
  if (contract.levelRank(need) > contract.levelRank(effective.maxLevel)) {
    return CapabilityDecision.levelNotGranted(need);
  }
  if (contract.levelRank(need) >=
      contract.levelRank(contract.itemRequiredFromLevel)) {
    if (item == null || item.isEmpty) {
      return CapabilityDecision.itemMissing;
    }
    if (!effective.items.contains(item)) {
      return CapabilityDecision.itemNotGranted(item);
    }
  }
  // "每次都要本地确认"绑的是**最高那一档**（契约里那块就叫 l3，且 validate 保证
  // levels 按权限升序）。这里不写死 'L3'：哪天加一档，写死的会静默失效。
  final levels = contract.capabilityLevels;
  final topLevel = levels.isEmpty ? '' : levels.last;
  final needsConfirm =
      need == topLevel &&
      contract.boolOf(const ['capabilities', 'l3', 'confirmEveryTime']) == true;
  if (!needsConfirm) return CapabilityDecision.allow;
  if (stage == CapabilityStage.intake) {
    // 收单这段判不了确认，也**不许拿请求里那个自称的标志替设备判** —— 交给 apply。
    return CapabilityDecision.allowNeedConfirm;
  }
  if (!confirmedThisTime) return CapabilityDecision.confirmRequired;
  return CapabilityDecision.allowNeedConfirm;
}

/// 「把 L3 开起来」这一次本地认证的结论。**三值**：设备根本没装锁屏/生物识别、
/// 用户按了取消、以及平台通道本身还没接上，三者在这一层是同一个形状 —— **不许开**。
///
/// 为什么不能是 `bool`：把"没认证器"读成"通过"或读成"失败"都说得通，于是实现里
/// 两种都会长出来 —— 一种把 L3 开给了没有锁屏的设备，另一种让用户永远开不了。
/// 判据是**三态各自有用**：只有 `authenticated` 能开，另外两态的处置不同
/// （去设置页开锁屏 / 告诉用户没配认证器）。
enum LocalAuthOutcome {
  /// 用户刚才真的过了一关（指纹、面容、锁屏密码）。
  authenticated,

  /// 这一台压根没有认证器（`KeyguardManager.isDeviceSecure` 为假）——
  /// 要请用户先去系统里设一个，不是"他拒绝了"。
  unavailable,

  /// 有认证器，用户没通过（取消、输错、超时）。原样可以重试。
  rejected,
}

/// 开启 L3 的那一次本地认证在本设备上的实现。
///
/// 平台通道（锁屏 / 生物识别）今天还没接 —— 这是 T49 之后那一片的事。接上之前给
/// [unimplementedLocalAuthenticator]：它回"没有认证器"，于是**默认关着**而不是默认开着。
/// ⚠ 默认回 [LocalAuthOutcome.unavailable] 而不是 `authenticated` 是这一条存在的全部理由。
typedef LocalAuthenticator =
    Future<LocalAuthResult> Function({required String reason});

/// 一次本地认证的结果：**过没过**（[LocalAuthOutcome]）与**过的哪一关**（[mechanism]）是
/// 两件事，合成一个字段就会出现下面这个坑 ——
/// 契约 `capabilities.l3.enableRequiresLocalAuth` 列的是**手段**（`lockScreen` /
/// `biometric`），不是"通过"这个词。把结论的名字直接拿去与那张表比，读出来永远是空表，
/// 于是每一次判都是"开不了"，而用户看到的是"这功能坏了"。
class LocalAuthResult {
  const LocalAuthResult({required this.mechanism, required this.outcome});

  /// 用的哪一关。取值须来自 [FnthinkContract.l3EnableRequiresLocalAuth]；表外的形状
  /// 按"开不了"处置（平台通道与契约各说各话时，放行等于把授权交给谁都读不懂的那种结论）。
  final String mechanism;

  final LocalAuthOutcome outcome;

  bool get authenticated => outcome == LocalAuthOutcome.authenticated;

  @override
  String toString() => 'LocalAuthResult($mechanism, ${outcome.name})';
}

/// 还没接平台通道时的实现：永远"这台没有认证器"。
/// 与"用户拒了"分开 —— 前者要请用户去设置，后者在界面上只是没开成，可以原样重试。
/// 机制词仍填契约那张表的首项：判据核的是"用的手段在不在词表里"，
/// 而这里根本没走到那一步（`outcome` 已经把这件事说清了）。
Future<LocalAuthResult> unimplementedLocalAuthenticator({
  required String reason,
}) async => LocalAuthResult(
  mechanism: 'lockScreen',
  outcome: LocalAuthOutcome.unavailable,
);

/// 能不能把 L3 开起来。纯函数：只判认证结果与词表，不弹框、不查系统。
///
/// 返回**最终要写进授权的那一档**，或者 null（不开）。⚠ 这里不是"校验通过就放行"，
/// 是一道**改档**：拿到 L2 授权时调用它，写回去的是最高档；而授权变更本身还要
/// 重新确认（契约 `capabilities.grantChangeRequiresConfirmation`），那一步在界面上。
String? grantableL3Level(
  FnthinkContract contract,
  FnthinkGrant current, {
  required LocalAuthResult result,
}) {
  final levels = contract.capabilityLevels;
  final top = levels.isEmpty ? null : levels.last;
  if (top == null) return null;
  if (!contract.l3EnableRequiresLocalAuth.contains(result.mechanism))
    return null;
  if (!result.authenticated) return null;
  return top;
}

/// L3 熔断器：**一分钟内连续失败达到契约那条线，就把这一对发送方降回 L1**。
///
/// 三件事写在这里，别处再写一遍就会各自算各自的窗口：
///  ① 失败的时刻按到达顺序倒序记，超过一分钟的旧记录先丢（"一分钟内连续"就是这个意思）；
///  ② 成功一次就把窗口**清空**（连续 ⇒ 失败之间不许插成功）；
///  ③ 降级是**有方向的**：降到契约写的那一档就停，不会一路降到最低档。
///
/// 时钟由调用方注入：这一层判"一分钟内失败几次"，判错的表现是正常负载下熔断或
/// 对端一直在打失败却永远不熔断，而测试里没法靠真等一分钟来复现其中任何一种。
class L3CircuitBreaker {
  L3CircuitBreaker({
    required FnthinkContract contract,
    required int Function() nowMs,
  }) : _contract = contract,
       _now = nowMs;

  final FnthinkContract _contract;
  final int Function() _now;

  /// 失败到达的时刻，**新的在后面**。只留窗口内的。
  final List<int> _failures = <int>[];

  int get threshold => _contract.l3CircuitBreakerFailuresPerMinute;

  String get downgradeTo => _contract.l3CircuitBreakerDowngradeTo;

  /// 窗口内失败了几次（已丢弃过期记录）。
  int get failuresInWindow {
    _trim();
    return _failures.length;
  }

  /// 现在该不该降级 —— 只读，**不自己动手**：降级要写授权，是调用方的动作。
  bool get tripped => failuresInWindow >= threshold;

  /// 记一次失败，落这一发带来的动作**没能完成**（判据在裁决层之外）：
  /// 已达到阈值就回要降到的档，否则回 null（继续按现状）。
  String? recordFailure() {
    _failures.add(_now());
    _trim();
    return tripped ? downgradeTo : null;
  }

  /// 记一次成功并清空窗口（"连续"要求失败之间没有成功）。
  void recordSuccess() => _failures.clear();

  /// 丢掉窗口外的记录。⚠ 这一步不是可选的整理：不丢的话一个每分钟失败一次的对端
  /// 会把计数攒到阈值，而契约写的是"一分钟内连续" —— 表现是某天毫无征兆地降级。
  ///
  /// 窗口是**半开的** `[now - 60s, now)`：恰好整一分钟前的那次失败不算"一分钟内"。
  /// 用 `t < floor` 判会把它留下，于是"第 5 次"与"第 6 次"之间差整整一分钟时，
  /// 两种读法能给出相反的结论 —— 而这一条的全部作用就是那个结论。
  void _trim() {
    final floor = _now() - windowMs;
    _failures.removeWhere((t) => t <= floor);
  }

  /// 窗口宽度就是一分钟，这个数写在这里是因为它要与 [threshold] 同源 ——
  /// 契约那条线说的是"每分钟"，两个数分开写就会出现"3 次/周"那种读数。
  static const int windowMs = 60000;
}
