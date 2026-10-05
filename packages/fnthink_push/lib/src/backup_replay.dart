/// 补推与补发的**二选一裁决**（T46）· Dart 这一半。
///
/// 与 `server/lib/fnthink/backupReplay.js` 是同一套规则的两份实现，两边都只从契约
/// `waitingOnline` / `limits` 段读词与读数，共读 `protocol/fnthink-vectors-v1.json`
/// 的 `backupReplay` 组各断言一遍。
///
/// 为什么要有这个函数：`DeliveryStep.resend` 只回答"**该走哪条路**"（T34 定的），
/// 拿到那个路线词之后的三件事今天没有第二份答案 —— 这条消息能不能再补推一次
/// （幂等键 `waitingOnline.backupReplayIdempotencyKey`）、最多补推几次
/// （`limits.backupReplayMax`）、以及这一发在记录上叫什么
/// （`waitingOnline.backupReplayLabel`）。三样都写在契约里，于是三样都从这里读。
///
/// ⚠ **互斥是靠"只返回一个 action"兑现的**，不是靠调用方自觉：两条路径并存的后果是
/// 同一条消息提醒两次（产品不变量里点名的那一件）。所以 [BackupReplayAction.queueResend]
/// 与 [BackupReplayAction.backupReplay] 互斥且穷尽，调用方拿到的永远只有一条路。
library;

import 'contract.dart';

/// 这一条走哪条路。三个取值里只有两个是"动作"，第三个数什么都不做。
enum BackupReplayAction {
  /// 走备用渠道补推（契约 `waitingOnline.withBackupChannel` 那条路）。
  backupReplay,

  /// 交给服务端排队补发（契约 `waitingOnline.withoutBackupChannel` 那条路）。
  /// 发送端**不动作** —— 这一档存在的意义就是让"没配备用渠道"这件事有个正面说法，
  /// 而不是让调用方靠 `hasBackupChannel == false` 自己推一遍（那是第二份判据）。
  queueResend,

  /// 什么都不做：已经补推过（幂等）或补推次数用满（上限）。
  none,
}

class BackupReplayDecision {
  const BackupReplayDecision({
    required this.action,
    this.route,
    this.label,
    this.dedupeKey,
    this.max = 0,
    this.limitReason,
  });

  const BackupReplayDecision._queueResend(this.route)
    : action = BackupReplayAction.queueResend,
      label = null,
      dedupeKey = null,
      max = 0,
      limitReason = null;

  const BackupReplayDecision._none(String this.limitReason)
    : action = BackupReplayAction.none,
      route = null,
      label = null,
      dedupeKey = null,
      max = 0;

  final BackupReplayAction action;

  /// 这一条走的**契约路线词**（`waitingOnline.withBackupChannel` 或
  /// `withoutBackupChannel` 原样），什么都不做时为 null。
  ///
  /// 为什么要单独带一个它而不是让调用方拿 [action] 去配词：枚举名是代码里的名字
  /// （`queueResend`），路线词是契约里的名字（`queue_resend`），两份词表各写一遍时
  /// 改名的那一天两边悄悄对不上，而对不上的表现是"这一档从来没被走到过"。
  /// 记录与向量表比的都是路线词，所以这里给的就是路线词。
  final String? route;

  /// 记录上要标的字（契约 `waitingOnline.backupReplayLabel`）。只有补推那一档有。
  final String? label;

  /// 这一发的去重键（契约说的键名对应的值）。**同一条消息不许补推两次**
  /// （幂等键在契约里写死的是 `message_id`）。
  final String? dedupeKey;

  /// 还允许补推几次（`limits.backupReplayMax`）。调用方记完这一次要减一。
  final int max;

  /// `none` 的原因：`already-replayed`（幂等）还是 `cap-reached`（上限）。
  /// 分开是因为这两种"没做"在运维眼里不是同一件事：前者是重复触发，后者是这条消息
  /// 已经把备用渠道的机会用完了。
  final String? limitReason;

  bool get replays => action == BackupReplayAction.backupReplay;

  @override
  String toString() =>
      'BackupReplayDecision($action, route=$route, label=$label, '
      'dedupeKey=$dedupeKey, max=$max, limitReason=$limitReason)';
}

/// 补推次数上限（`limits.backupReplayMax`）。取不到就抛，不退回 0：
/// 退回 0 意味着"备用补推这条路今天不存在"，而这个函数正是那条路唯一的判据 ——
/// 静默退 0 的表现是界面上补推那一格永远不亮，没有任何报错。
int backupReplayMax(FnthinkContract contract) {
  final max = contract.intOf(const ['limits', 'backupReplayMax']);
  if (max == null || max <= 0) {
    throw StateError(
      '契约缺 limits.backupReplayMax（正整数）：备用补推有几条路可走是这一段的唯一判据，'
      '退回 0 等于把这条路悄悄关掉',
    );
  }
  return max;
}

/// 幂等键的字段名（`waitingOnline.backupReplayIdempotencyKey`）。
///
/// **本实现只兑现 `message_id`**：契约点名了别的键名时照抛，不静默拿 `message_id` 顶替 ——
/// 顶替之后去重仍然"看着在跑"，而实际上契约要求按另一个字段去重，那正是重复补推的入口。
String backupReplayIdempotencyKeyName(FnthinkContract contract) {
  final key = contract.str(const [
    'waitingOnline',
    'backupReplayIdempotencyKey',
  ]);
  if (key == null || key.isEmpty) {
    throw StateError('契约缺 waitingOnline.backupReplayIdempotencyKey');
  }
  if (key != _supportedIdempotencyKey) {
    throw StateError(
      'waitingOnline.backupReplayIdempotencyKey 是「$key」，而本实现只兑现「$_supportedIdempotencyKey」：'
      '换一个键名就换了一套去重口径，悄悄拿旧键顶替会让重复补推重新变成可能',
    );
  }
  return key;
}

const String _supportedIdempotencyKey = 'message_id';

/// 裁决：这条已经进了 `waiting_online`，接下来怎么办。
///
/// [route] 是状态机给出的那一条路线词（`DeliveryStep.resend`）；两个必填事实由调用方从
/// 本机账里查出来 —— [alreadyReplayed]（这个去重键是不是已经补推过）与 [replayCount]
/// （已经补推过几次）。把后两个留成参数而不是函数自己去查账，是为了让它保持纯函数：
/// 账在设备本地（Dart 这半）与服务端（JS 那半）不是同一份，两个实现自己去查就会各查各的。
BackupReplayDecision decideBackupReplay(
  FnthinkContract contract, {
  required String route,
  required bool alreadyReplayed,
  required int replayCount,
  String? messageId,
}) {
  final section =
      contract.str(const ['delivery', 'resendDecisionFrom']) ?? 'waitingOnline';
  final table = contract.map([section]) ?? const {};
  final withBackup = table['withBackupChannel'] as String?;
  final withoutBackup = table['withoutBackupChannel'] as String?;
  if (route != withBackup) {
    // 路线词不属于这两条之一 = 契约改了而这里没跟上。抛，不猜：猜错的方向是"当成排队补发"
    // （于是和备用补推并存 = 提醒两次），另一头是"当成备用补推"（没备用渠道时用户什么都收不到）。
    if (route != withoutBackup) {
      throw ArgumentError.value(
        route,
        'route',
        '不是契约 $section 里的两条补发路线：$withBackup / $withoutBackup',
      );
    }
    return BackupReplayDecision._queueResend(withoutBackup);
  }
  if (alreadyReplayed) {
    return const BackupReplayDecision._none('already-replayed');
  }
  final max = backupReplayMax(contract);
  if (replayCount >= max) {
    return const BackupReplayDecision._none('cap-reached');
  }
  final keyName = backupReplayIdempotencyKeyName(contract);
  final dedupeKey = messageId ?? '';
  if (dedupeKey.isEmpty) {
    throw ArgumentError.value(
      messageId,
      'messageId',
      '补推要按「$keyName」去重，而它没给出来：拿空键去重等于没去重',
    );
  }
  final label = contract.str(const ['waitingOnline', 'backupReplayLabel']);
  if (label == null || label.isEmpty) {
    throw StateError('契约缺 waitingOnline.backupReplayLabel：补推那一发在记录上叫什么');
  }
  return BackupReplayDecision(
    action: BackupReplayAction.backupReplay,
    route: withBackup,
    label: label,
    dedupeKey: dedupeKey,
    max: max,
  );
}
