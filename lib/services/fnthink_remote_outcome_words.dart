import '../l10n/app_localizations.dart';

/// 远程执行「本机**做成了什么**」那一列的唯一词表（T144 片2 格①，维护者 2026-10-12 第 2 条：
/// 失败**和成功都要有原因**）。
///
/// ## 这一列以前没有作者
/// 执行器成功时回的是 `(ok: true, reason: null)` —— 而落库那一行写的是
/// `result: result.reason ?? ''`（`fnthink_remote_runner.dart`），于是**做成的那一条两格全空**：
/// 状态是「执行完毕」，可"完毕"之后本机到底做了什么，界面上一个字都没有。
/// 同一行失败时那一串机器词又被**同时抄进 result 与 reason 两格**（两句一模一样）。
///
/// ## 这一层的规矩
/// 两列各管一件事：**`result` = 本机做成了哪一步**（只有成功那一档有值，词就是下面这三个），
/// **`reason` = 为什么没成、或为什么被拦**（判定层与执行器给的那些码，整族翻译属格②）。
/// 词表是封闭的：加一档成功形状要在这里加一词，`fnthink_remote_outcome_words_test.dart`
/// 按双向差集判 —— 只加常量不加词条、或只加词条不加常量，都会当场红。
///
/// ⚠ 这三个词描述的是**本机这一步**，不是"对面收到了"：回传那一路送不到时执行器整条算失败
/// （`report-not-sent`），所以不会出现「结果说送到了、其实没送」这种读数。
const String kFnthinkRemoteOutcomePerformed = 'performed';
const String kFnthinkRemoteOutcomeReported = 'reported';
const String kFnthinkRemoteOutcomeSet = 'set';

/// 封闭清单（守卫拿它做双向差集的那一边；页面不该读它）。
const List<String> kFnthinkRemoteOutcomeWords = <String>[
  kFnthinkRemoteOutcomePerformed,
  kFnthinkRemoteOutcomeReported,
  kFnthinkRemoteOutcomeSet,
];

/// 词 → 人话。存**取值函数**不存键名：少一条 ARB 词条就编译不过（与
/// `kFnthinkRemoteActionLabels` 同一写法，理由也同一 —— 别让"配了没有"等一条运行时用例去撞）。
final Map<String, String Function(AppLocalizations)>
kFnthinkRemoteOutcomeLabels = <String, String Function(AppLocalizations)>{
  kFnthinkRemoteOutcomePerformed: (l) => l.remoteOutcomePerformed,
  kFnthinkRemoteOutcomeReported: (l) => l.remoteOutcomeReported,
  kFnthinkRemoteOutcomeSet: (l) => l.remoteOutcomeSet,
};

/// 这一格给人看的那一句。词表外的读数**原样显示**（看得见的缺，不是编一句"已完成"盖住它 ——
/// 这一族最容易长的坏形状是"把读不出来说成做完了"，与状态那一格的 `不认得` 同一条纪律）。
String fnthinkRemoteOutcomeText(AppLocalizations l10n, String word) {
  final label = kFnthinkRemoteOutcomeLabels[word];
  return label == null ? word : label(l10n);
}

/// 这个词配了词条没有（守卫用它，页面不用它）。
bool hasFnthinkRemoteOutcomeLabel(String word) =>
    kFnthinkRemoteOutcomeLabels.containsKey(word);
