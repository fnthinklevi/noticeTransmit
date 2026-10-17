/// L3 两枚 toggle 的「本机能力在位」**唯一读口**（T134 尾巴，维护者 2026-10-17 拍：
/// `missing-grant` 改指本机状态、不删）。
///
/// 契约 `capabilities.l3.requiresExistingGrantFrom = [monitoring, collect_inbox]`
/// 答的是「这台**自己**先把这一项立在位上，对面才谈得上翻」。此前这一格读的是
/// **对端清单**（与判定层第四道 `rejectBySenderGrant` 读同一份东西，判不出任何新东西）；
/// 现在改读本机事实，对端授权那一维由第四道独家负责：
///
/// - `monitoring`（转发监听，native = `setMonitoringEnabledPref`）：
///   监听服务在位（`NotificationService.serviceRunning` —— T74 既有那族读数，
///   不新造第二份）。
/// - `collect_inbox`（收件采集，native = `settings.receiveEnabled`）：
///   服务地址已配 + 中转同意在位。同意被撤销 ⇒ 对面翻不动这一枚；
///   服务地址有首启缺省，但读不出来（校验抛）一律按不在位（fail-closed）。
///
/// 词表外的 key **fail-closed 回 false**：调用方只在 `requiresExistingGrantFrom`
/// 命中时来问，走到这里还是不认得 ⇒ 不放行。守卫钉住契约那一表与本类的
/// `case` 集合一致（`test/architecture/fnthink_l3_local_state_guard_test.dart`），
/// 契约新加一项而这里没接时，表现是那一项恒拒（看得见），不是静默放行。
class FnthinkL3LocalState {
  const FnthinkL3LocalState({
    required this.monitoringInPlace,
    required this.collectInboxInPlace,
  });

  /// 转发监听此刻在不在位（生产 = `NotificationService.serviceRunning`）。
  final Future<bool> Function() monitoringInPlace;

  /// 收件采集此刻在不在位（生产 = 服务地址已配 + 中转同意）。
  final Future<bool> Function() collectInboxInPlace;

  Future<bool> inPlace(String key) {
    switch (key) {
      case 'monitoring':
        return monitoringInPlace();
      case 'collect_inbox':
        return collectInboxInPlace();
      default:
        return Future<bool>.value(false);
    }
  }
}
