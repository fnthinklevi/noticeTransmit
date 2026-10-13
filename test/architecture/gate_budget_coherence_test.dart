import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 闸门那份文件里有自己的 `main()`，所以必须带前缀导入：这里要的只是它那把**公开的**
// 预算钳函数 —— 判据打在真实现上，不在守卫里再抄一份算法（抄一份就是下一个漂移点）。
import '../../integration_test/release_walkthrough_test.dart' as gate;
import '../support/source_guards.dart';

/// 闸门预算的**自洽**（2026-10-13 立）。
///
/// ## 量出来的事
/// 为排查 2/4 的挂住，把慢机旋钮 `--dart-define=GATE_STEP_BUDGET_SEC=420` 放大之后，
/// 先 firing 的**不是**节内预算（那时是 420s），而是测试级 6 分钟硬超时（360s）——
/// 于是整份日志只剩一句 `TimeoutException after 0:06:00`，既没有 `GATE-STEP-FAIL`
/// 也没有「最后动作」。**旋钮本身把这一发要拿的读数吞掉了**：放大保护 = 失去点名。
///
/// ## 这本账的牙（四条各钉一件事，合成一条就会有一维看不见）
/// ① 纯函数不变量：只要 override>0，返回的用例预算必须**晚于**节预算，且不许比默认档小；
///    override==0 时逐字返回 base ⇒ CI 与既有那条四分不等式一字不改。
/// ② 四处用例超时**全部**走那把钳，且钳只有一个定义处（绕回裸常量／再抄一份都是两份口径）。
/// ③ 尺认得合成样本（②全绿时"全都合规"与"提取器一枚都没认出来"同形 —— 本仓栽过多次）。
/// ④ `_tap` 那把「最后动作」路标必须落在**每一句**之前：只写一次就只能指到"哪一次点击"，
///    指不到那一次里的哪一句在等一个永远不回来的东西（本轮 5.1 就卡在这个信息缺口上）。
void main() {
  final root = projectRoot();
  const gatePath = 'integration_test/release_walkthrough_test.dart';

  /// ②的尺：给定**剥注释后**的闸门源码，返回预算那一层的问题清单（空 = 合规）。
  List<String> budgetProblems(String src) {
    final problems = <String>[];
    final clamped = RegExp(
      r'timeout:\s*Timeout\(\s*gateCaseBudgetFor\(\s*_case[A-Z]Budget\s*\)\s*\)',
    ).allMatches(src).length;
    final raw = RegExp(
      r'timeout:\s*const\s+Timeout\(\s*_case[A-Z]Budget',
    ).allMatches(src).length;
    final declared = RegExp(
      r'const\s+_case[A-Z]Budget\s*=\s*Duration\(',
    ).allMatches(src).length;
    final defs = RegExp(
      r'Duration\s+gateCaseBudgetFor\s*\(',
    ).allMatches(src).length;
    // 反向自证：常量声明与 timeout 使用点都还在 —— 否则这条判据拦的是已经不存在的事，
    // 而"全都合规"与"这段代码被人删光了"在尺上是同一个绿。
    if (declared < 4) {
      problems.add('取不到四条 `_case<X>Budget` 声明 ⇒ 无从计算（改名要一起改这本账）');
    }
    if (clamped != declared || raw > 0) {
      problems.add(
        '用例超时走钳的有 $clamped 处、裸常量 $raw 处、声明 $declared 处 ⇒ '
        '三者必须相等且裸常量为 0：任何一处绕过钳，放大旋钮时那一层就会先掐掉点名',
      );
    }
    if (defs != 1) {
      problems.add('`gateCaseBudgetFor` 有 $defs 个定义处 ⇒ 预算口径只能有一份作者');
    }
    return problems;
  }

  test('① 自洽钳的不变量：旋钮一生效，用例预算必须晚于节预算（默认档逐字不变）', () {
    for (final baseMin in const [6, 7]) {
      final base = Duration(minutes: baseMin);
      expect(
        gate.gateCaseBudgetFor(base, overrideSec: 0),
        base,
        reason: '不设旋钮时不许动任何数字 —— CI 与那条四分不等式按默认值算',
      );
      for (final sec in const [
        1,
        60,
        179,
        180,
        359,
        360,
        420,
        600,
        900,
        3600,
      ]) {
        final step = Duration(seconds: sec);
        final got = gate.gateCaseBudgetFor(base, overrideSec: sec);
        expect(
          got > step,
          isTrue,
          reason:
              'base=${base.inMinutes}min、override=${sec}s ⇒ 用例预算 $got 不晚于节预算 $step '
              '⇒ 先说话的是测试级硬超时，日志里不会有 GATE-STEP-FAIL、不会有「最后动作」'
              '（2026-10-13 实测：420s 的旋钮就是这么把 2/4 那一发的读数整个吞掉的）',
        );
        expect(
          got >= base,
          isTrue,
          reason: '钳只许往上让，不许把默认档改小（改小就是拿排查旋钮换掉一轮正常跑）',
        );
      }
    }
    Duration? prev;
    for (final sec in const [0, 60, 360, 420, 900, 1800]) {
      final got = gate.gateCaseBudgetFor(
        const Duration(minutes: 6),
        overrideSec: sec,
      );
      if (prev != null) {
        expect(
          got >= prev,
          isTrue,
          reason: '旋钮越放大而用例预算越缩 ⇒ 两层看门狗的顺序会反过来，点名再次被吞',
        );
      }
      prev = got;
    }
  });

  test('② 四处用例超时全部走那把钳，且钳只有一个定义处', () {
    final src = stripComments(File('$root/$gatePath').readAsStringSync());
    expect(budgetProblems(src), isEmpty, reason: '闸门预算不自洽 ⇒ 放大旋钮等于放弃点名');
  });

  test('③ 尺认得合成样本（防② 退化成"一处都没认出来＝恒绿"）', () {
    const compliant = '''
const _caseABudget = Duration(minutes: 6);
const _caseBBudget = Duration(minutes: 6);
const _caseCBudget = Duration(minutes: 7);
const _caseDBudget = Duration(minutes: 6);
Duration gateCaseBudgetFor(Duration base, {int overrideSec = 0}) => base;
void main() {
  testWidgets('a', (t) async {}, timeout: Timeout(gateCaseBudgetFor(_caseABudget)));
  testWidgets('b', (t) async {}, timeout: Timeout(gateCaseBudgetFor(_caseBBudget)));
  testWidgets('c', (t) async {}, timeout: Timeout(gateCaseBudgetFor(_caseCBudget)));
  testWidgets('d', (t) async {}, timeout: Timeout(gateCaseBudgetFor(_caseDBudget)));
}
''';
    expect(
      budgetProblems(compliant),
      isEmpty,
      reason: '合规写法被判成问题 ⇒ ② 红得没有信息量，下次没人再读它',
    );

    // 坏法一：一处绕回裸常量（正是本轮之前那个形状 —— 它不会红，只会在挂住时少一半信息）。
    final oneRaw = compliant.replaceFirst(
      'timeout: Timeout(gateCaseBudgetFor(_caseBBudget))',
      'timeout: const Timeout(_caseBBudget)',
    );
    expect(
      budgetProblems(oneRaw),
      isNotEmpty,
      reason: '有一处用例超时绕过钳都抓不到 ⇒ ② 那条绿只说明尺没量到',
    );

    // 坏法二：钳被抄了第二份（两处定义＝两份口径，改一处漏一处）。
    const twoDefs =
        '$compliant\nDuration gateCaseBudgetFor(Duration b) => b;\n';
    expect(
      budgetProblems(twoDefs),
      isNotEmpty,
      reason: '两处定义抓不到 ⇒ 下一次放大的是哪一份，没人说得清',
    );

    // 坏法三：四条常量整块被删（"没有违规"与"这段代码不见了"必须不同形）。
    expect(
      budgetProblems('void main() {}'),
      isNotEmpty,
      reason: '取不到声明就当通过 ⇒ 这本账可以在一次重构里静默失效',
    );
  });

  test('④ `_tap` 的路标落在每一句之前（挂住要能指到那一句，不是那一次点击）', () {
    final src = stripComments(File('$root/$gatePath').readAsStringSync());
    final start = src.indexOf('Future<void> _tap(');
    expect(start, greaterThan(-1), reason: '认不出 `_tap` ⇒ 这条判据无从计算');
    final nextMember = RegExp(
      r'\nFuture<',
    ).firstMatch(src.substring(start + 5));
    final body = nextMember == null
        ? src.substring(start)
        : src.substring(start, start + 5 + nextMember.start);
    final markers = RegExp(r'_lastAction\s*=').allMatches(body).length;
    expect(
      markers,
      greaterThanOrEqualTo(4),
      reason:
          '一次点击里有 scrollUntil／ensureVisible／pump／tap／settle 五句会各自等东西，'
          '只写一次路标就只能指到"哪一次点击"，指不到那一次里的哪一句 —— '
          '本轮 5.1 挂住时日志停在 tap「底部 tab→更多」，正是这个信息缺口',
    );
    for (final word in const ['ensureVisible', 'pump', 'tap', 'settle']) {
      expect(
        RegExp('_lastAction\\s*=\\s*\'[^\']*·$word').hasMatch(body),
        isTrue,
        reason: '路标少了「·$word」那一档 ⇒ 挂在那一句上时日志又会退回只见点击不见句子',
      );
    }
    // 反向自证：被路标覆盖的那几句本身还在（否则这条守卫在拦一件已经没人做的事）。
    expect(
      body.contains('t.ensureVisible(') &&
          body.contains('t.pump(') &&
          body.contains('_settle(t,'),
      isTrue,
      reason: '那几句已经不在了 ⇒ 路标判据要跟着改，别让它绿着量一件不存在的事',
    );
  });
}
