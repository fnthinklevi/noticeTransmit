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
