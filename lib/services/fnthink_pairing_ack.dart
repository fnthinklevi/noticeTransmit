/// 「把配对口令挂到服务器上」那一发的三态结论 —— 措辞与格子的 key 的**唯一作者**（T126 片2）。
///
/// ## 为什么要有这一处
/// 这一发有三种落点：服务器认了、服务器没认（本机仍记着那串码）、根本没问过。
/// 原来这三句写在页面的三个 `if` 分支里，于是"当场弹一次"（维护者 2026-10-10 第 1 条：
/// 「刚才你显示的密钥失效…很不起眼」）若要复用同一句，只能把那三个分支**再抄一遍** ——
/// 而抄的那一份会漂：弹层说"服务器已收到"、格子里那句还是旧的，用户读到的是两个结论。
///
/// ## key 也从这里出
/// `fnthink-pairing-acked` / `-local-only` / `-unknown` 这三枚 key 是测试与排查的抓手
/// （`fnthink_settings_page_test` 按 key 断"哪一态在场、哪一态不许在"）。把 key 的映射与
/// 措辞的映射放在同一处，状态换名字时两件事一起换，不会出现"格子还在、句子已经改了"。
///
/// ## ⚠ `acked == null` 不是 false
/// "没问过服务器"与"问过而没成"是两种不同的用户动作（等一等 vs 重来一次），合并成一档
/// 就等于让第三种人做多余的那一步。所以这里收的是 `bool?`，不是 `bool`。
library;

import '../l10n/app_localizations.dart';

/// 这一态说哪句话。[note] 是失败原因（内核原话），只在"问过而没成"那一档进句子。
String fnthinkPairingAckText(
  AppLocalizations l10n, {
  required bool? acked,
  required String? note,
}) {
  if (acked == true) return l10n.fnthinkPairingAcked;
  if (acked == false) return l10n.fnthinkPairingLocalOnly(note ?? '');
  return l10n.fnthinkPairingAckUnknown;
}

/// 这一态挂哪枚 key（拼在 `'fnthink-pairing-'` 后面）。与 [fnthinkPairingAckText] 同一份三档。
String fnthinkPairingAckKey(bool? acked) {
  if (acked == true) return 'acked';
  if (acked == false) return 'local-only';
  return 'unknown';
}
