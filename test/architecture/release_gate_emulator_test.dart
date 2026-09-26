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
      // 必须剥 shell 注释：一句"当初这里是 bash release_emulator.sh"的注释
      // 能让两条判据都为真，而脚本其实已经不跑闸门（同类事故见下条 trap 的反证 2）。
      final src = stripShellComments(read('.github/scripts/release_local.sh'));
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

    test('发版脚本必须重打 T09 证据矩阵的欠账（绿了也要看得见缺什么）', () {
      final src = stripShellComments(read('.github/scripts/release_local.sh'));
      expect(
        src,
        contains('channel_evidence_matrix_test.dart'),
        reason:
            '矩阵守卫的打印被全量 flutter test 的几百行输出淹没 ⇒ '
            '"15/15 没盖过章"这件事在交付报告里看不见，绿就等于没人欠账了',
      );
      expect(
        src,
        contains('T09 待人工盖章'),
        reason: '重打的那行必须来自守卫的打印口径；改了打印名要同步这里，否则只剩静默',
      );
    });

    test('闸门起跑前必须清掉被测应用的残留数据', () {
      // AVD 的 /data 跨启动保留，`flutter test` 只是覆盖安装 ⇒ 上一轮（或被掐断的那一轮）
      // 留下的通道还在库里。两面都坏：本轮"仅测试不许落库"会**假红**，
      // 而靠上一轮残留才点得动的分节会**假绿**（闸门测的已经不是这份代码）。
      final src = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      final clearAt = src.indexOf('pm clear com.fnthink.notice');
      expect(
        clearAt,
        greaterThan(0),
        reason: '没有清数据这一步：闸门的结论取决于上一轮跑没跑完（2026-09-26 实测假红过一次）',
      );
      expect(
        clearAt,
        lessThan(src.indexOf('flutter test')),
        reason: '清数据必须发生在跑测试之前，晚一步等于没清',
      );
      expect(
        src.lastIndexOf('emulator-*)', clearAt),
        greaterThan(0),
        reason: '这条 pm clear 必须落在 emulator-* 分支里：serial 不是模拟器就不许执行',
      );
      expect(
        src,
        contains('禁止对真机执行'),
        reason: 'default 分支必须显式 fail —— serial 为空/异常时宁可停，不能清到真机',
      );
      expect(
        src,
        matches(RegExp(r'pm clear com\.fnthink\.notice[\s\S]{0,220}?exit 1')),
        reason: '装过却清不掉必须**停下来**：只 warn 一句继续跑，等于把"本轮结论可能来自上一轮残留"咽下去',
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
    /// ⚠ 惰性 + 剥注释：写在 group 体里的 `read()` 若文件被改名，异常抛在用例之外 ⇒
    ///   整个文件加载失败（CI 表现为"这个文件没有用例"）；而不剥注释时，
    ///   一句提到 `testWidgets('冒烟 1/4 …'` 的注释就能让计数虚高。
    String smokeSrc() =>
        stripComments(read('integration_test/smoke_test.dart'));

    // ⚠ 这里的匹配一律按**语句片段**数，不要按 `testWidgets('名字'` 整行匹配：
    //   dart format 会把长签名折行（本文件写完就被折过一次），整行正则会静默漏数，
    //   守卫于是既会假红也会假绿。名字字面量与 timeout: 片段是稳定的。
    test('按步拆成多条用例，而不是一个大 testWidgets 串到底', () {
      final n = RegExp(r"'冒烟 \d+/\d+").allMatches(smokeSrc()).length;
      expect(
        n,
        greaterThanOrEqualTo(4),
        reason:
            '冒烟被合回单条用例 ⇒ 任一中间步失败只会报"那条用例红了"，'
            'CI 上又得翻日志找断在第几步（㊼ 拆开的全部意义）',
      );
    });

    test('每条用例都有自己的超时', () {
      final src = smokeSrc();
      final cases = RegExp(r"'冒烟 \d+/\d+").allMatches(src).length;
      final timeouts = RegExp(
        r'timeout: const Timeout\(',
      ).allMatches(src).length;
      // 正面锚点：cases 为 0 时下面这条不等式对任何 timeouts 都成立（空断言）。
      expect(cases, greaterThanOrEqualTo(4), reason: '没数到冒烟用例 ⇒ 计数正则已失效');
      expect(
        timeouts,
        greaterThanOrEqualTo(cases),
        reason:
            '用例数 $cases、超时数 $timeouts ⇒ 有卡住不吃帧的用例时会吃满整个 job 预算，'
            '后面的步骤根本没有结论',
      );
    });

    test('用例之间互不依赖（各自 launchApp 装配）', () {
      final src = smokeSrc();
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
    /// 同上：惰性读取，并且**剥注释** —— 本组全是 `src.contains('…')` 型判据，
    /// 一句"当初点这里"的注释就能让判据为真而闸门其实是空的（base.md（75）记的同类事故）。
    String walkSrc() =>
        stripComments(read('integration_test/release_walkthrough_test.dart'));

    test('没有 skip / 空跑标记', () {
      final src = walkSrc();
      for (final marker in const ['skip:', 'skip: true', 'markTestSkipped']) {
        expect(src.contains(marker), isFalse, reason: '出现 $marker ⇒ 闸门变成了摆设');
      }
    });

    test('备份导出与导入两端都真的被点到', () {
      final src = walkSrc();
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
      final src = walkSrc();
      for (final entry in const [
        'Webhook 推送通道',
        '邮件转发通道',
        '自建应用通道',
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
      for (final entry in const ['权限设置', '短信监听', '推送历史', '首页', '通知引擎', '更多']) {
        expect(
          src.contains("'$entry'"),
          isTrue,
          reason: '主链路入口「$entry」不再被点击 ⇒ 覆盖面缩水',
        );
      }
    });

    test('通知引擎 tab 的两类告警入口都被点过（T15）', () {
      final src = walkSrc();
      // 电量/温度从"独立 tab / 更多页入口"挪进骨架页 ⇒ 点法也换了 helper。
      // 只查字面量不够：文案可以只活在注释里。所以钉的是"确实经 _openEngineRow 点过"。
      for (final entry in const ['电量告警', '温度告警']) {
        expect(
          RegExp("_openEngineRow\\(tester, '$entry'\\)").hasMatch(src),
          isTrue,
          reason: '「$entry」不再经 `_openEngineRow` 被点开 ⇒ 骨架页换了文案而闸门静默失配',
        );
      }
      expect(
        src.contains('find.byType(NotificationEnginePage)'),
        isTrue,
        reason: '入口没有"限定在骨架页里找" ⇒ 首页卡片上的同名字样会被误点',
      );
    });

    test('删除的二次确认在闸门里被走通（T06）', () {
      final src = walkSrc();
      final flat = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains("_confirmDelete(tester, 'Webhook 行')"),
        reason: 'webhook 那条删除不再走确认框 ⇒ T06 的咽喉在闸门上失去覆盖（红的是"没弹框"）',
      );
      // 锚点必须带返回类型：光写 `_confirmDelete(` 会先命中调用点，blockAfter 于是截到
      // 调用点后面那个 lambda，断言的对象就错了一个函数（找不到时抛 StateError ⇒ 用例红，
      // 而不是静默通过，这点由 blockAfter 的语义保证）。
      final helper = blockAfter(src, 'Future<void> _confirmDelete(');
      expect(
        helper,
        contains('_must('),
        reason: '确认框缺失时必须当场红；静默继续 = 把"删除没有确认"这件事测不出来',
      );
    });

    test('两条测试动作都被真点过：仅测试 与 测试并保存（T04）', () {
      // 「仅测试」与「测试并保存」是两个按钮、两条不同路径（一条落库、一条不落库）。
      // 只钉字面量不够（文案可以只活在注释里 ⇒ walkSrc 已剥注释），也不许被 dart format
      // 的换行打断 ⇒ 先压平空白再匹配"确实经 _tap + _appBarText 点过"。
      final flat = walkSrc().replaceAll(RegExp(r'\s+'), ' ');
      for (final step in const ['Webhook→仅测试', '应用通道→仅测试']) {
        expect(
          flat,
          contains("_appBarText('仅测试'), '$step'"),
          reason: '「$step」不再被点 ⇒ 「仅测试」这条不落库的路径静默退出了闸门覆盖面',
        );
      }
      expect(
        flat,
        contains("_appBarText('测试并保存')"),
        reason: '「测试并保存」不再被点 ⇒ T04 的两条动作只剩一条还在被验证',
      );
    });

    test('两处长按弹层都被真点过，且都先滚到可见（T05）', () {
      // T05 把卡片动作表搬进共用组件（历史记录那一份原本是就地写的）。
      // 新入口一旦退出闸门覆盖面，红的是"没人点过"，而不是"点错了"——所以钉在这里。
      // ⚠ 长按与 _tap 有同一个坑：懒加载列表里"finder 命中 ≠ 已绘制"，而打不中
      // **只打印 warning 不抛异常** ⇒ 手势静默丢失（闸门第一轮就是这么红的）。
      // 因此这里钉的不只是"点了"，还有"点之前 ensureVisible 过"。
      final src = walkSrc();
      final flat = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        allOf(
          contains("_longPress(tester, appRow, '应用通道列表行')"),
          contains("_longPress(tester, find.text('闸门通知一'), '历史记录行')"),
        ),
        reason: '应用通道卡或历史记录卡的长按不再被点 ⇒ 共用组件失去真机覆盖',
      );
      // helper 自己的两条不变量：居中对齐（贴顶会被 AppBar 吃手势）+ 不用 pumpAndSettle。
      // walkSrc 已剥注释，所以解释"为什么不用 pumpAndSettle"的那句注释不会再让守卫
      // 在干净的树上红（不剥注释就错过不止一次，见 base.md（75））。
      final helper = blockAfter(src, 'Future<void> _longPress(');
      expect(
        helper,
        contains('alignment: 0.5'),
        reason: '长按目标又回到"贴视口上沿"⇒ 手势被 AppBar 吃掉，闸门只会说"菜单没出来"',
      );
      expect(
        helper,
        isNot(contains('pumpAndSettle')),
        reason: '刚输入过的 TextField 有光标动画 ⇒ helper 里用 pumpAndSettle 会永不收敛',
      );
      expect(
        flat,
        contains('tapAt(const Offset(10, 10))'),
        reason: '弹层只展开不收起 ⇒ 后面的分节会被模态遮罩挡死（也是用户被困住的形状）',
      );
    });
  });
  group('盖章测试不进闸门', () {
    test('闸门默认清单必须排除 t09_stamp_test.dart（它会真发消息）', () {
      final src = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      expect(
        File('$root/integration_test/t09_stamp_test.dart').existsSync(),
        isTrue,
        reason: '被排除的文件已经不在了 —— 下面那条"排除"就成了空断言',
      );
      final filesLine = RegExp(r'FILES=\$\{GATE_FILES:.*').firstMatch(src);
      expect(filesLine, isNotNull, reason: '闸门默认清单写法变了，守卫要重新指向');
      expect(
        filesLine!.group(0),
        contains('t09_stamp_test'),
        reason: '盖章测试被默认清单收进来 = 每次发版往用户的真实群/邮箱发一轮消息',
      );
      expect(
        filesLine.group(0),
        contains('grep -v'),
        reason: '"提到但没排除"不算排除：必须真的从清单里减掉',
      );
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
