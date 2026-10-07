/// 远程执行那一行/那一页的**唯一**前置判定（T97 片C）。
///
/// 为什么要是纯函数：同一个判定有**两个**读者 —— 通知引擎 hub 那一行（决定灰不灰、说缺哪一条）
/// 与远程控制页自己（同一句话要能在页里再解释一遍），各写一份迟早一个说"缺同意"、一个说"缺开关"。
///
/// 顺序是**从外到内**：先问"这台愿不愿意收别人的通知"（接收开关），再问"愿意不愿意让内容经手
/// 第三方"（同意门），最后才是"允不允许别人指挥这台设备做事"（远程执行自己的开关）。
/// 拿最外层的那条作答 —— 三层都缺时报"接收没开"，用户照着修一层就能看到下一层。
///
/// ⚠ 与 `FnthinkRemoteSettings.enabled` 的关系：2026-10-07 维护者拍板，远程执行的前置挂**它自己**
/// 那枚开关（默认 false），不跟 `fnthink.receive_enabled` 共用一次同意 —— 收通知与"允许别人改我这台"
/// 风险不对等，合并之后关掉一件会连带关掉另一件。
library;

enum FnthinkRemoteGate {
  ready,

  /// 接收开关没开（最外层）。
  receiveOff,

  /// 同意门还没过（T56）。
  notConsented,

  /// 远程执行自己的开关关着（默认关）。
  switchOff,
}

FnthinkRemoteGate fnthinkRemoteGate({
  required bool receiveEnabled,
  required bool consented,
  required bool remoteEnabled,
}) {
  if (!receiveEnabled) return FnthinkRemoteGate.receiveOff;
  if (!consented) return FnthinkRemoteGate.notConsented;
  if (!remoteEnabled) return FnthinkRemoteGate.switchOff;
  return FnthinkRemoteGate.ready;
}
