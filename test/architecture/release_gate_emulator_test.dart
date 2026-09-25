import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// ㊻ 「闸门的闸门」：发版必须包含模拟器全功能点击 + 备份导入导出这一步，
/// 而且它不能被人不知不觉地拆掉或改成静默跳过。
///
/// 为什么要有这条：本仓库已经发生过两次"闸门其实不存在"——
/// `build-apk.yml` 调用的纯净度脚本长期只躺在 gitignore 的本地目录里（㉙），
/// `dart_code_metrics` 那一步每次崩溃却被 `set +e` 吞掉（㊶）。
/// 所以这道新闸门的上岗本身也要有测试钉住。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  group('发版脚本必须挂上模拟器全功能闸门', () {
    test('release_local.sh 调用 release_emulator.sh，且失败判红不吞', () {
      final src = read('.github/scripts/release_local.sh');
      expect(
        src.contains('bash .github/scripts/release_emulator.sh'),
        isTrue,
        reason: '发版脚本不再调用模拟器闸门 = 步骤 6.7 名存实亡',
      );
      // 必须"失败即 FAIL"，不能像 dart_code_metrics 那样被静默吞掉
      expect(
        RegExp(
          r"bash \.github/scripts/release_emulator\.sh.*?\n.*?ok .*?\n.*?fail ",
          dotAll: true,
        ).hasMatch(src),
        isTrue,
        reason: '闸门结果没有 ok/fail 两个分支 ⇒ 可能出现"红了但发版继续"',
      );
    });

    test('闸门脚本只允许跑在模拟器上', () {
      final src = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      expect(
        src.contains(r'emulator-*)'),
        isTrue,
        reason: '缺少"设备必须是 emulator-*"的判定 = 有误删真机数据的风险',
      );
      expect(
        src.contains('running_serial_for'),
        isTrue,
        reason: 'AVD 与 adb serial 的对应必须走 `adb emu avd name`（serial 不含 AVD 名）',
      );
    });

    test('模拟器由 EXIT trap 收尾，失败或中断也不许留在后台', () {
      final src = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      expect(
        RegExp(
          r'^trap\s+cleanup_emulator\s+EXIT',
          multiLine: true,
        ).hasMatch(src),
        isTrue,
        reason:
            '只在脚本末尾 emu kill ⇒ boot 超时、测试失败、Ctrl-C 这些出口都会把模拟器'
            '留在后台吃内存（维护者 2026-09-25 明确要求：用完必须关）',
      );
      // 反证 1：旧写法（无 trap，只在末尾收尾）必须判假
      expect(
        RegExp(r'^trap\s+cleanup_emulator\s+EXIT', multiLine: true).hasMatch(
          'STARTED_BY_US=1\nflutter test\n'
          'if [ "\$STARTED_BY_US" = "1" ]; then "\$ADB" emu kill; fi\n',
        ),
        isFalse,
        reason: '守卫对"无 trap 的旧写法"不敏感 ⇒ 它是摆设',
      );
      // 反证 2：注释掉的 trap 必须判假（实测踩过：不加剥注释这一步时它是绿的，闸门是空的）
      expect(
        RegExp(r'^trap\s+cleanup_emulator\s+EXIT', multiLine: true).hasMatch(
          stripShellComments('# trap cleanup_emulator EXIT\nflutter test\n'),
        ),
        isFalse,
        reason: '注释里的 trap 也算命中 ⇒ 把闸门注释掉，守卫仍然绿（假绿）',
      );
      // 关闭动作只允许一处，且必须先确认 serial 是 emulator-*（不能误伤真机）
      expect(
        RegExp(r'emu kill').allMatches(src).length,
        1,
        reason: '出现第二处 emu kill ⇒ 两处收尾会互相掩盖，其中一处可能不在 trap 里',
      );
      final cleanup = src.substring(
        src.indexOf('cleanup_emulator()'),
        src.indexOf('trap cleanup_emulator EXIT'),
      );
      expect(
        RegExp(r'emulator-\*\)\s*:').hasMatch(cleanup) &&
            RegExp(r'case "\$\{SERIAL:-\}"').hasMatch(cleanup),
        isTrue,
        reason: 'trap 里没有 serial 画像判定 ⇒ 中断路径上可能对真机执行 emu kill',
      );
    });

    test('CI 两个集成文件都在跑，且各自占一个 job', () {
      final src = read('.github/workflows/integration_test.yml');
      expect(
        src.contains('integration_test/smoke_test.dart'),
        isTrue,
        reason: '冒烟 job 被摘掉',
      );
      expect(
        src.contains('integration_test/release_walkthrough_test.dart'),
        isTrue,
        reason: '全功能点击闸门没进 CI ⇒ 只有本机会跑到',
      );
      expect(
        src.contains(r'walk_status'),
        isTrue,
        reason: 'walkthrough 的退出码必须参与 job 成败判定，不能只 tee 不看',
      );
      // ㊼：原来三条链挤在一个 job 里共用一个 timeout-minutes，"慢的把预算吃掉、
      // 快的没跑到就没结论"。拆成两个 job 是这次改进的实质，被合回去就等于回滚。
      final smokeJob = src.indexOf('integration_test/smoke_test.dart');
      final walkJob = src.indexOf(
        'integration_test/release_walkthrough_test.dart',
      );
      expect(
        smokeJob >= 0 && walkJob >= 0 && _differentJobs(src, smokeJob, walkJob),
        isTrue,
        reason: '冒烟与全功能闸门必须分属不同 job（否则又会互相顶掉结论）',
      );
    });

    test('每个 job 都有显式超时预算，且失败会在 run 页面留痕', () {
      final src = read('.github/workflows/integration_test.yml');
      // 只在 jobs: 段里数（on: 下也有两空格缩进的键，会混进来）
      final jobs = src.substring(src.indexOf('\njobs:\n'));
      expect(
        RegExp(r'^  [A-Za-z0-9_-]+:$', multiLine: true).allMatches(jobs).length,
        greaterThanOrEqualTo(2),
        reason: 'job 数量少于 2 ⇒ 又并回一个 job 了',
      );
      expect(
        RegExp(r'timeout-minutes:\s*\d+').allMatches(jobs).length,
        greaterThanOrEqualTo(2),
        reason: '每个 job 都要有自己的超时预算（共用一个就会互相顶掉）',
      );
      expect(
        src.contains('::error::'),
        isTrue,
        reason: '失败必须写注解：以前红的时候 run 页面没有任何 annotation，只能下日志',
      );
      expect(
        RegExp(r'if:\s*always\(\)').hasMatch(src),
        isTrue,
        reason: 'test_report 必须**无论成败**上传 —— 绿的时候也要能证明它真跑过',
      );
    });
  });

  group('冒烟测试必须保持"红在第几步"可读', () {
    final src = read('integration_test/smoke_test.dart');

    // ⚠ 这里的匹配一律按**语句片段**数，不要按 `testWidgets('名字'` 整行匹配：
    //   dart format 会把长签名折行（本文件写完就被折过一次），整行正则会静默漏数，
    //   守卫于是既会假红也会假绿。名字字面量与 timeout: 片段是稳定的。
    test('按步拆成多条用例，而不是一个大 testWidgets 串到底', () {
      final n = RegExp(r"'冒烟 \d+/\d+").allMatches(src).length;
      expect(
        n,
        greaterThanOrEqualTo(4),
        reason:
            '冒烟被合回单条用例 ⇒ 任一中间步失败只会报"那条用例红了"，'
            'CI 上又得翻日志找断在第几步（㊼ 拆开的全部意义）',
      );
    });

    test('每条用例都有自己的超时', () {
      final cases = RegExp(r"'冒烟 \d+/\d+").allMatches(src).length;
      final timeouts = RegExp(
        r'timeout: const Timeout\(',
      ).allMatches(src).length;
      expect(
        timeouts,
        greaterThanOrEqualTo(cases),
        reason:
            '用例数 $cases、超时数 $timeouts ⇒ 有卡住不吃帧的用例时会吃满整个 job 预算，'
            '后面的步骤根本没有结论',
      );
    });

    test('用例之间互不依赖（各自 launchApp 装配）', () {
      // 拆分的真正前提是每条用例自己能灌数据；否则只有 1/4 单独跑得动
      expect(
        RegExp(r"await launchApp\(tester\)").allMatches(src).length,
        greaterThanOrEqualTo(4),
        reason: '出现共享"上一步留下的现场"的写法 ⇒ 单跑某一步会假红',
      );
      expect(
        src.contains('GetIt.instance.reset()'),
        isTrue,
        reason: '不 reset GetIt ⇒ 上一条用例的 Service 实例会漏进下一条（假绿）',
      );
    });
  });

  group('闸门测试自身不得被静默削弱', () {
    final src = read('integration_test/release_walkthrough_test.dart');

    test('没有 skip / 空跑标记', () {
      for (final marker in const ['skip:', 'skip: true', 'markTestSkipped']) {
        expect(src.contains(marker), isFalse, reason: '出现 $marker ⇒ 闸门变成了摆设');
      }
    });

    test('备份导出与导入两端都真的被点到', () {
      // 只点"生成备份文件"而不点恢复，等于没验往返（1.5.74 事故就在恢复侧）
      expect(src.contains("find.text('生成备份文件')"), isTrue);
      expect(src.contains("find.text('选择备份文件恢复')"), isTrue);
      expect(src.contains("find.text('覆盖全部')"), isTrue);
      expect(
        src.contains('FilePicker.platform'),
        isTrue,
        reason: '恢复必须走页面的读盘路径（注入 FilePicker 返回真实文件）',
      );
    });

    test('每个设置页入口都被点过', () {
      for (final entry in const [
        'Webhook 推送通道',
        '邮件转发通道',
        '自建应用通道',
        '温度推送',
        '应用筛选',
        '关键词过滤',
        '规则引擎',
        '设备名称',
        '深色模式',
        '语言',
        '推送开关',
        '推送统计',
        '隐私政策',
        '备份与恢复',
      ]) {
        expect(
          src.contains("'$entry'"),
          isTrue,
          reason: '更多页入口「$entry」不再被点击 ⇒ 覆盖面缩水',
        );
      }
      // 三个 tab（T13 起：首页 / 通知引擎 / 更多）与两条 tab 内入口。
      // ⚠ tab 名一改这里必须同步：闸门是按文案点 tab 的，漏改的后果不是红，
      //   而是"找不到就跳过"——覆盖面静默缩水（本条存在的唯一理由）。
      //   电量作为 tab 没了，但电量页仍在中间那一格（通知引擎），点它=点这一格。
      for (final entry in const ['权限设置', '短信监听', '推送历史', '首页', '通知引擎', '更多']) {
        expect(
          src.contains("'$entry'"),
          isTrue,
          reason: '主链路入口「$entry」不再被点击 ⇒ 覆盖面缩水',
        );
      }
    });
  });
}

/// 判断 workflow 文本里两个偏移量是否落在**不同 job** 下。
///
/// 为什么要这条：CI 的红从"整条链一个 job"改成"每类一个 job"才是这次改进的实质
/// （冒烟不必再等全功能闸门把预算跑完）。合回一个 job 时两个偏移会同属一个块。
bool _differentJobs(String src, int a, int b) {
  String jobOf(int offset) {
    final head = src.substring(0, offset);
    final matches = RegExp(
      r'^  [A-Za-z0-9_-]+:$',
      multiLine: true,
    ).allMatches(head).toList();
    return matches.isEmpty ? '' : matches.last.group(0)!;
  }

  return jobOf(a) != jobOf(b);
}
