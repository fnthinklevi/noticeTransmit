import 'dart:convert';
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

    test('CI 脚本里不许有 bash 专有写法（T64 根因）', () {
      // `android-emulator-runner` 用 `child_process.exec` 执行 script，Linux 上
      // 默认 shell 是 /bin/sh（dash），**不是 bash**。`${PIPESTATUS[0]}` 是 bash 数组，
      // dash 在**解析期**就 exit 2 ⇒ `set +e` 还没生效，整段脚本一次都没跑过，
      // 而 CI 上看到的是"集成测试红了"（2026-09-23 引入，09-22 之后一次都没真跑过）。
      //
      // 只查**非注释行**：注释里必须能提到这个词（那正是讲清"为什么不能这么写"的地方）。
      final src = read('.github/workflows/integration_test.yml');
      const banned = {
        r'${PIPESTATUS': 'bash 数组（取管道左侧退出码）—— dash 解析期 exit 2',
        'set -o pipefail': r'bash 专有；POSIX 做法是「重定向到文件 → $?」',
        '[[ ': 'bash 专有；POSIX 是单个 [',
      };
      for (final entry in banned.entries) {
        final hits = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('#'))
            .where((l) => l.contains(entry.key))
            .toList();
        expect(
          hits,
          isEmpty,
          reason:
              'CI 脚本里出现 ${entry.key}（${entry.value}）\n'
              '第 ${hits.length} 处：${hits.isEmpty ? '' : hits.first.trim()}',
        );
      }
      // 正向锚点：改成 POSIX 形状之后，"重定向到文件 → $? → cat" 必须真的在，
      // 否则这条判据可能在判据失效时照样通过（本组踩过两次"提取退化成空集"）。
      expect(
        RegExp(r'>\s*test_report/smoke\.log 2>&1').hasMatch(src),
        isTrue,
        reason: '冒烟那一步没有「重定向到文件」⇒ 取退出码的写法被删了，判红回到 tee 上',
      );
      expect(
        RegExp(r'smoke_status=\$\?').hasMatch(src),
        isTrue,
        reason: r'smoke_status 必须来自真实的 $?，不是别处算出来的数',
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
        '规则约束',
        '设备名称',
        '设备状态快照',
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
      // T23：骨架页上那枚「设备态告警也接受约束」开关也要被真点过。
      // 不钉这条的话，开关被挪走/改形状时闸门只会"找不到就跳过"，绿着失去覆盖面。
      final flatEngine = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flatEngine,
        contains(
          "of: find.byType(NotificationEnginePage), "
          "matching: find.byType(CupertinoSwitch)",
        ),
        reason: '闸门不再点 T23 的约束开关 ⇒ 那一节静默退出闸门覆盖面',
      );
      // T25：温度「试一次」也必须被真点过，并断言弹层有内容。
      // 这一步特别值得钉：求值在原生，Dart 只是渲染 —— 两侧键名/形状脱钩时，
      // 页面不会崩，只会弹一个空框，人眼看才发现。
      expect(
        flatEngine,
        contains("_in(TemperaturePage, find.byIcon(Icons.science_outlined))"),
        reason: '闸门不再点温度页右上的「试一次」⇒ 试跑这条链退出闸门',
      );
      expect(
        flatEngine,
        contains("ValueKey('temp-preview-body')"),
        reason: '点了却没看结果 ⇒ "空弹层"这种失败仍然看不见',
      );
      expect(
        RegExp('deviceAlertsRespectConstraints').allMatches(src).length,
        greaterThanOrEqualTo(3),
        reason: '点了还要看服务跟不跟、并且切回去还原（少于 3 处 = 只点不验或留在改过的状态）',
      );
    });

    test('T24 设备状态告警那一节：加两条 → 验族 → 停 → 删 都在闸门里', () {
      final src = walkSrc();
      final flat = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        RegExp("_openEngineRow\\(tester, '设备状态告警'\\)").hasMatch(src),
        isTrue,
        reason: '「设备状态告警」入口不再被点开 ⇒ T24 这一族静默退出闸门覆盖面',
      );
      // 两种触发源都得真点过：亮度型带滑杆、网络型没有 —— 只测一种，另一种的
      // "值/无值"分支就从闸门上消失了，而它正是最容易被顺手写成同一条路径的地方。
      for (final chip in const ['亮度低于', '断网时']) {
        expect(
          flat,
          // T90 片14：这枚阈值框换成了共享外壳 `IosFormDialog`（Cupertino 那件）⇒ 期望串跟着走。
          // ⚠ 这不是放宽：断的还是「闸门真的把那两种触发源各点了一遍」，只是那一层的型变了。
          //   同一条断言若哪天又指回 `AlertDialog`，红的应该是闸门那一步找不到弹层，而不是这条。
          contains("_in(CupertinoAlertDialog, find.text('$chip'))"),
          reason: '规则类型「$chip」不再被选 ⇒ 只测了另一半，形状分叉看不见',
        );
      }
      // 三族的落点是一张表按 family 分列：写错族 = 界面上一切正常而原生永远取不到。
      expect(
        flat,
        contains("isNot(contains('闸门亮度规则'))"),
        reason: '不再核对"设备状态规则没串到别的族里" ⇒ 族名写错这一类静默失效失去唯一现场',
      );
      // 镜像键**从服务源码里取**，再要求闸门读同一把。写死字面量的守卫会连自己写错的前缀
      // 一起钉住 —— 闸门第一轮就红在这：Dart 侧 SharedPreferences 用逻辑键，
      // `flutter.` 前缀是插件写原生 XML 时才加的，照着文件名写就会永远读到 null。
      final svc = stripComments(read('lib/services/device_state_service.dart'));
      final mirrorKey = RegExp(
        "prefsKey:\\s*'([^']+)'",
      ).firstMatch(svc)!.group(1);
      expect(
        flat,
        contains("prefs.getString('$mirrorKey')"),
        reason: '不再核对 prefs 镜像 ⇒ DB 写了而镜像没写（原生读的还是旧列表）测不出来',
      );
      expect(
        flat,
        isNot(contains("prefs.getString('flutter.")),
        reason:
            "闸门按带 `flutter.` 前缀的键读 prefs：读到的恒为 null，"
            '断言会红在"镜像没写"上而真因是键名',
      );
      // 尾控件的开关与长按删除都要按**那一行**的 key 定位（按标题找在改名/同名时会打中两个）
      expect(
        RegExp(
          r"find\.byKey\(ValueKey\('device-state-row-\$\{brightness\['id'\]\}'\)\)",
        ).allMatches(flat).length,
        greaterThanOrEqualTo(2),
        reason: '开关与长按删除不再各自定位到那一行 ⇒ "删一条顺带没了另一条"这类缺陷看不见',
      );
      expect(
        flat,
        contains("_confirmDelete(tester, '设备状态规则行')"),
        reason: '这一族的删除绕开了 T06 的确认咽喉 ⇒ 点一下就没',
      );
      // 闸门钉的 key 必须真是页面里的形状，否则两边一起改错也照样绿
      final page = stripComments(read('lib/pages/device_state_page.dart'));
      expect(
        RegExp(r"ValueKey\('device-state-row-\$id'\)").hasMatch(page),
        isTrue,
        reason: '页面里没有闸门用的那个行 key ⇒ 两边各写各的，定位断言成了摆设',
      );
    });

    test('T18 设备状态页：入口被点开、每一项都被核对、推送按钮被真按', () {
      final src = walkSrc();
      final flat = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        RegExp("_openMoreRow\\(tester, '设备状态快照'\\)").hasMatch(src),
        isTrue,
        reason: '「设备状态」入口不再被点开 ⇒ T17 那份快照没有消费者，闸门也管不到这一页',
      );
      expect(
        flat,
        contains('_onPage(tester, DeviceSnapshotPage,'),
        reason: '点了没确认落到哪一页 ⇒ "进去是空白也算过"',
      );
      expect(
        flat,
        contains("find.byKey(const ValueKey('device-status-push'))"),
        reason: '不点「推送设备信息」⇒ 先落库再补推那条链在设备上从没被走过',
      );
      expect(
        flat,
        contains("r.title == '设备状态快照'"),
        reason: '点了不看历史里真有一条 ⇒ 送达结果没有落点也照样绿',
      );

      // **每一项**都要被核对：页面加了新行而闸门没跟上时，这一条红（不靠人记得）
      final page = stripComments(
        File(
          '${projectRoot()}/lib/pages/device_snapshot_page.dart',
        ).readAsStringSync(),
      );
      final labelGetters = RegExp(
        r"\(\s*'[a-zA-Z]+',\s*l10n\.(\w+),",
      ).allMatches(page).map((m) => m.group(1)!).toSet();
      expect(
        labelGetters.length,
        greaterThanOrEqualTo(10),
        reason: '提取失效 = 空守卫',
      );
      final arb =
          jsonDecode(
                File(
                  '${projectRoot()}/lib/l10n/arb/app_zh.arb',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      // ⚠ 只在 5.14 那一节的源码里找标签：`'电池温度'` 在温度页那几步里也是 chip 文案，
      // 全文搜索会让"这一项不再核对"绿着过关（反证 G1 实测撞到的）。
      final sectionStart = src.indexOf('5.14 设备状态页');
      final sectionEnd = src.indexOf('── 6. 通知引擎', sectionStart);
      expect(sectionStart, greaterThan(-1), reason: '闸门里没有 5.14 设备状态页那一节');
      expect(sectionEnd, greaterThan(sectionStart), reason: '取不到那一节的结尾');
      final section = src.substring(sectionStart, sectionEnd);
      for (final getter in labelGetters) {
        final zh = arb[getter];
        expect(zh, isA<String>(), reason: 'ARB 里没有 $getter ⇒ 提取或词条命名漂了');
        expect(
          section,
          contains("'${(zh as String).split(RegExp('[：:{（(]')).first}'"),
          reason: '页面有「$zh」这一项，而 5.14 不核对它 ⇒ 项目丢了也测不出来',
        );
      }
    });

    test('影子差异出口：闸门打一行，发版脚本接住它（T72 第一步）', () {
      // ① 闸门末尾必须打这一行，且**无条件**（n=0 也是一种答复；缺行才说明出口坏了）
      final src = walkSrc();
      final at = src.indexOf("EngineRuleDiffLog().read()");
      expect(at, greaterThan(-1), reason: '闸门不再读影子差异环 ⇒ 「差异清零才切主路径」又变成一句空话');
      final between = src.substring(at, at + 400);
      // 标记名从"闸门实际打出来的那个字符串"里取，不在下面重打一遍字面量：
      // 两侧各写一份、朝同一个方向写错，正是本项目撞过的那类"守卫自己成了第二份拷贝"。
      final printed = RegExp(
        r"'(GATE-DIFF-[A-Z]+)",
      ).firstMatch(between)?.group(1);
      expect(
        printed,
        isNotNull,
        reason: '读了环，却没打出以 GATE-DIFF-* 开头的字符串 ⇒ 报告里看不见这一行',
      );
      expect(
        RegExp(
          r'\bif\s*\(',
        ).hasMatch(between.substring(0, between.indexOf(printed!))),
        isFalse,
        reason: '打印被 if 包住（典型是"有差异才打"）⇒ 清零与出口失效在报告里长得一样',
      );

      // ② 发版脚本必须 grep 的正是 ① 打出来的那个标记，并且"缺行"要判红
      final sh = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      expect(
        sh.contains('grep -a "$printed"'),
        isTrue,
        reason: '闸门打 $printed，脚本却 grep 别的字面量 ⇒ 两边对不上，等于没有出口',
      );
      expect(
        RegExp('fail "闸门没有打印 $printed').hasMatch(sh),
        isTrue,
        reason: '缺这一行必须是红：静默放行就等于把"没人打印"当成"清零了"',
      );
      expect(
        sh.contains(r'${N:-0}'),
        isTrue,
        reason: 'n>0 要单独提示（那是切换门槛未满足的证据），且必须带 :- 兜底防 set -u',
      );
      expect(
        RegExp("sed -n 's/.*$printed").hasMatch(sh),
        isTrue,
        reason:
            '取 n 必须锚在这个标记上。写成贪婪的 .*n= 会抓到差异明细里的 '
            '"库=n=55 镜像=3" —— 报告里的 n 与真实差异条数对不上，而人看不出来',
      );
      expect(
        sh.indexOf('grep -a "$printed"') < sh.indexOf(r'exit $RC'),
        isTrue,
        reason: '出口写在 exit 之后 ⇒ 报告里永远不会出现这一行',
      );
    });

    test('每一节都留下痕迹，且痕迹要覆盖到裸段（挂住的运行也要能定位）', () {
      final src = walkSrc();
      final helper = blockAfter(src, 'Future<void> _step(');
      expect(
        helper,
        contains("GATE-STEP-BEGIN"),
        reason:
            '只有 FAIL 一行时，"卡在某一节"在日志里长得和"还没跑到"一模一样 —— '
            '两轮 GATE_RC=124 都是这么浪费掉的',
      );
      expect(helper, contains('GATE-STEP-FAIL'));
      // 挂住之后同一用例剩下的节必须**记账跳过**（第 21 轮实测：它们一节节吃满用例级 7 分钟，
      // 把"挂住才重试一次"的资格都挤掉了），而"跳过"不许长得像"通过" ⇒ 必须写进同一本账。
      expect(
        helper,
        contains('GATE-STEP-SKIP'),
        reason: '挂住之后还在一节一节跑 ⇒ 用例级超时先说话，重试机会被吃掉',
      );
      expect(
        RegExp(r"failures\[name\] =\s*'已跳过[^\n]*").hasMatch(helper),
        isTrue,
        reason: '跳过只打印不记账 ⇒ 报告里那一节看着像绿了（本仓库反复撞过的"静默通过"）',
      );
      expect(
        helper.indexOf('GATE-STEP-SKIP') <
            helper.indexOf("debugPrint('GATE-STEP-BEGIN"),
        isTrue,
        reason: '跳过判断必须**在 BEGIN 之前**：先打 BEGIN 再跳过，日志里就分不清"跑过"与"没跑"',
      );
      // 有 BEGIN/FAIL 两行还不够：整轮挂住时这两行都证明"能留痕"，却没人给挂住的那节兜底。
      // 三轮 GATE_RC=124 的代价是 28 分钟换一个"不知道卡在哪"。
      expect(
        helper,
        contains('.timeout('),
        reason: '没有节内预算 ⇒ 一节挂住就是整轮 124，其余几十节的红一个都拿不回来',
      );
      expect(
        helper,
        contains('_stepBudget'),
        reason: '预算必须是同一个常量；别处再写一个数字就是两份口径，改一处漏一处',
      );
      final tryAt = helper.indexOf('try {');
      final toAt = helper.indexOf('.timeout(');
      final catchAt = helper.indexOf('} catch');
      expect(
        tryAt > -1 && tryAt < toAt && toAt < catchAt,
        isTrue,
        reason: '超时若落在 try 之外 ⇒ 它掀掉的是整轮，而不是记成"这一节红"',
      );
      // 「谁先说话」是契约而不是巧合：㊼ 把用例级超时从 18 放宽到 30 的时候，节内预算还不存在。
      // 拆开之后"用例级超时"有**四条**（每条用例一个），所以判据取逐条比较而不是抓第一条：
      // 任何一条短到兜不住两次节内挂住，先说话的就不是"哪一节挂住"而是"这条用例没结论"。
      final whole = read('integration_test/release_walkthrough_test.dart');
      final budget = RegExp(
        r'const _stepBudget = Duration\(minutes: (\d+)\)',
      ).firstMatch(whole);
      expect(budget, isNotNull, reason: '节内预算的形状变了 ⇒ 这条判据要跟着改，别让它静默失效');
      final caseBudgets = RegExp(
        r'const _case([A-Z])Budget = Duration\(minutes: (\d+)\)',
      ).allMatches(whole);
      final stepMinutes = int.parse(budget!.group(1)!);
      expect(
        caseBudgets.length,
        greaterThanOrEqualTo(4),
        reason:
            '取不到四条用例各自的超时常量 ⇒ "谁先说话"这条契约无从计算。'
            '常量名 `_case<X>Budget` 本身就是契约的一部分（写死数字就是两份口径）',
      );
      for (final m in caseBudgets) {
        expect(
          int.parse(m.group(2)!),
          greaterThanOrEqualTo(stepMinutes * 2),
          reason:
              '用例 ${m.group(1)} 的超时兜不住"两节各挂一次" ⇒ 那条用例里的挂住只会报'
              '"整条超时"，节内预算的点名能力白给（第 10 轮之前就是这个形状）',
        );
      }
      // ── 同一串顺序的下面几环：闸门现在按用例**分独立调用**跑（第 16 轮实测：一条挂住
      // 会带走同一 isolate 里后面的用例，它们全死在 `binding.dart '!inTest'`）。
      // 于是口径多了一层"单次调用的回退上限"，而它必须由测试文件派生出的用例名驱动。
      final sh2 = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      expect(
        sh2.contains('timeout "\$GATE_TEST_TIMEOUT" flutter test'),
        isTrue,
        reason: '整轮超时没写进脚本 ⇒ 它只存在于某人手敲的命令行里，每次都要重新猜一遍',
      );
      expect(
        RegExp(
          r'run_case "\$case_name" "\$walk_file" --plain-name "\$case_name"',
        ).hasMatch(sh2),
        isTrue,
        reason:
            '闸门不再逐条用例独立调用 ⇒ 回到"一个进程跑完四条"：那条挂住之后，'
            '后面的用例连一条断言都执行不到（第 16 轮的 3/4、4/4 就是这个形状）',
      );
      // 8.14：拆开跑的范围从"只有 walkthrough"扩到**每个文件**。第 27 轮的红正是这个差别：
      // smoke 四个 case 一次调用，3/4 挂住把 4/4 一起带走了，而逐条重试根本覆盖不到它。
      expect(
        sh2.contains(r'for gate_file in $FILES'),
        isTrue,
        reason: '逐条隔离又只服务某一个文件了 ⇒ 其它文件的挂住照样污染整档（第 27 轮的形状）',
      );
      expect(
        sh2.contains(r'gate_declared=$(grep -c "testWidgets("') &&
            sh2.contains(r'[ "$gate_found" -eq "$gate_declared" ]'),
        isTrue,
        reason:
            '防退化守卫不在了 ⇒ 用例改名/漏了编号前缀时，"从测试文件派生用例名"会安静地少数几条，'
            '脚本看起来照常跑完，实际退化成整档一次（这正是本文件反复拦的那类空转）',
      );
      expect(
        sh2.contains('grep -oE'),
        isTrue,
        reason: '用例清单必须由测试文件 grep 派生，不许在脚本里再抄一份写死的名字',
      );
      expect(
        sh2.contains(r'[0-9]+/[0-9]+') &&
            sh2.contains('闸门') &&
            sh2.contains('冒烟'),
        isTrue,
        reason:
            '派生用的模式不在了 ⇒ 数出来的可能是别的东西，逐条隔离就没有对齐测试文件'
            '（8.14 起两个前缀都要在：闸门 与 冒烟）',
      );
      expect(
        RegExp(r'--plain-name "闸门 \d/\d"').hasMatch(sh2),
        isFalse,
        reason: '脚本里出现写死的某一条用例名 ⇒ 改名之后那一档会静默跑空（--plain-name 匹配不到 = 0 条）',
      );
      expect(
        RegExp(r'(数不到|只数到)[\s\S]{0,140}?用例名[\s\S]{0,220}?exit 1').hasMatch(sh2),
        isTrue,
        reason:
            '派生不到用例名时必须判红（"数不到"与"只数到 k/n"两种说法都算，但紧跟的必须是 exit 1）。'
            '静默退回"整档一次"是假绿：脚本照样绿，'
            '隔离却已经没了，而下一次挂住又会带走一整段',
      );
      final wholeRun = RegExp(r'GATE_TEST_TIMEOUT:-(\d+)').firstMatch(sh2);
      expect(
        wholeRun,
        isNotNull,
        reason: '取不到整档兜底那档的超时 ⇒ 这条顺序契约失效（8.14 起它只在 GATE_FILES 调试路径上用）',
      );
      final caseRun = RegExp(r'GATE_CASE_TIMEOUT:-(\d+)').firstMatch(sh2);
      expect(
        caseRun,
        isNotNull,
        reason: '取不到单次调用的回退上限 ⇒ "谁先说话"少了一环（它兜的是"连 test zone 都没了"）',
      );
      final caseRunSec = int.parse(caseRun!.group(1)!);
      final maxCase = caseBudgets.fold<int>(
        0,
        (m, e) => int.parse(e.group(2)!) > m ? int.parse(e.group(2)!) : m,
      );
      expect(
        caseRunSec,
        greaterThanOrEqualTo(maxCase * 60 + 240),
        reason:
            '单次回退上限兜不住"最重那条用例挂满自己的超时（$maxCase′）+ 重装与启动" ⇒ '
            '说话的是 timeout 124 而不是用例级超时，报告里又只剩一个数字',
      );
      // 最上面一环：闸门 job 的预算。钉的是**现实形状**（正常一轮 + 一条挂满 + 构建），
      // 不是"四条同时挂满"那种病态叠加 —— 那种情况 job 会先掐，这是**已知并被接受的**：
      // 每条调用的结论都已逐条写进 LOG，且 test_report 步骤 `if: always()` 照样上传，
      // 所以不再退化成"一个 124 换一片空白"。
      final gateJob = RegExp(
        r'name: 发版全功能点击闸门[\s\S]*?timeout-minutes:\s*(\d+)',
      ).firstMatch(read('.github/workflows/integration_test.yml'));
      expect(
        gateJob,
        isNotNull,
        reason: '找不到闸门 job 的 timeout-minutes ⇒ job 改名了，这条顺序契约要跟着改',
      );
      expect(
        int.parse(gateJob!.group(1)!) * 60,
        greaterThanOrEqualTo(caseRunSec + 900 + 900),
        reason:
            'job 容不下"一条挂满单次回退 + 正常一轮 + 构建/装机" ⇒ 说话的是 job 而不是'
            '用例级超时，日志连"哪一条用例"都不会留下',
      );
      expect(
        blockAfter(src, 'void _mark('),
        contains('GATE-MARK'),
        reason: '_mark 是给"没被 _step 包住的裸段"用的里程碑，它自己不打印就等于没有',
      );

      // 上一条只证明"_step 里会打两行"，**不证明每一段都被 _step 包住**。
      // 实测就栽在这里：主用例从 testWidgets 起有 500 多行裸代码（5.1 webhook 两百多行、
      // 5.2 邮件、5.3 自建应用都没进 _step），连着三轮 GATE_RC=124 日志里一个 BEGIN 都没有
      // —— 存在性守卫全绿，定位能力却为零。所以判据必须是**覆盖**：任意一段"平级裸码"都不许超过 20 条语句。
      // 拆成四条用例之后这件事按**每一条**算：装配、种子、出口都是各条自己的裸代码，
      // 挂住的运行同样会停在那些地方（"整轮只有一条用例"时那种"挂在第一条后面就全瞎"不成立了）。
      final lines = src.split('\n');
      final headers = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('testWidgets(')) headers.add(i);
      }
      expect(
        headers.length,
        greaterThanOrEqualTo(4),
        reason: '闸门又被合回一条用例 ⇒ 一次挂住吃掉整轮，其余各节的结论全废（㊻ 拆分的理由）',
      );
      const maxBlind = 20; // 单位：平级语句条数（不是行距，见下面循环里的说明）
      // 会打印痕迹的东西：节内 BEGIN/FAIL、裸段的 _mark、装配与种子（各自末尾都有一行 _mark）、
      // 以及影子差异出口那行 debugPrint。少认一种 = 把有痕迹的区段误判成盲区（假红），
      // 多认一种（比如把普通 debugPrint 也算上）= 真盲区被放过（假绿），所以逐个点名。
      bool leavesMark(String l) =>
          l.contains('_mark(') ||
          l.contains('await _step(') ||
          l.contains('await _assemble(tester') ||
          l.contains('await _seed') ||
          l.contains("'GATE-DIFF-RING");
      // 盲区的度量单位是**用例自己那一层的语句**，不是文件行数：`_step` 的函数体本来就几百行
      // 长（5.1 两百多行），但它整段在预算保护里 ⇒ 不是盲区。缩进比 `_step(` 调用更深的行
      // 一律算"在某一节里面"，只有平级的那些行才是"没人管的裸码"。
      // （为什么不数括号：闸门里的 reason 文案有半角括号不配对的（实测 `'…只点不改)"'`），
      // 数括号会把守卫自己带偏 —— 这是本项目撞过的那类"守卫比被测代码更脆"。）
      final mainEnd = lines.indexOf('}', headers.first);
      final blindSpans = <String>[];
      final noStep = <int>[];
      for (var c = 0; c < headers.length; c++) {
        final from = headers[c];
        final to = c + 1 < headers.length
            ? headers[c + 1]
            : (mainEnd > from ? mainEnd : lines.length);
        final firstCall = lines.indexWhere(
          (l) => l.contains('await _step('),
          from,
        );
        final callIndent = firstCall < 0 || firstCall >= to
            ? 4
            : lines[firstCall].length - lines[firstCall].trimLeft().length;
        var blind = 0;
        var runStart = from;
        for (var i = from; i < to; i++) {
          final trimmed = lines[i].trim();
          if (trimmed.isEmpty) continue;
          final indent = lines[i].length - trimmed.length;
          if (indent > callIndent) continue; // 在某一节里面 ⇒ 整段受节内预算保护，不计
          if (leavesMark(lines[i])) {
            blind = 0;
            runStart = i;
            continue;
          }
          // 数的是**平级语句条数**，不是行距：`_step(...)` 那一条调用与它的收尾 `);`
          // 之间隔着两百行函数体，行距会把整节误判成盲区（第一版就是这么红的）。
          if (blind == 0) runStart = i;
          blind++;
          if (blind > maxBlind) {
            blindSpans.add(
              '第 ${runStart + 1}–${i + 1} 行（连续 $blind 条平级语句没有任何痕迹）',
            );
            blind = 0; // 一段长裸码只报一次
          }
        }
        final firstStep = lines.indexWhere(
          (l) => l.contains('await _step('),
          from,
        );
        if (firstStep < 0 || firstStep >= to) noStep.add(c + 1);
      }
      expect(
        noStep,
        isEmpty,
        reason: '第 ${noStep.join("/")} 条用例里一个 `_step` 都没有 ⇒ 它那些节既没有节内预算也不会单独记红',
      );
      expect(
        blindSpans,
        isEmpty,
        reason:
            '这些区段没有任何痕迹 ⇒ 挂在这里时日志里一个线索都没有，整轮只能重跑赌运气。'
            '补一行 _mark(\'几.几 在做什么\') 即可（判据：每条用例内连续平级裸码不超 $maxBlind 条）',
      );
      // 光有"盲区不超 20 条"还是太弱：mark 能给出位置，却给不出**预算保护**。
      // 第 10 轮实测：挂在裸段时节内 3 分钟预算完全用不上，只能等 18 分钟用例超时，
      // 且其余各节结论全废。所以每个分节都必须是一个 `_step`（有 BEGIN 痕迹 + 节内预算
      // + 一节红不吞其余），这件事只能直接钉节名。
      const requiredSections = [
        '1 通知页',
        '2 权限设置页',
        '3 短信监听页',
        '4 推送历史页',
        '5.1',
        '5.2 邮件通道',
        '5.3 自建应用',
      ];
      final stepNames = RegExp(
        r"await _step\(\s*tester,\s*gateFailures,\s*'([^']+)'",
      ).allMatches(src).map((m) => m.group(1)!).toList();
      final naked = requiredSections
          .where((s) => !stepNames.any((n) => n.startsWith(s)))
          .toList();
      expect(
        naked,
        isEmpty,
        reason:
            '这些分节没有被任何 _step 包住 ⇒ 挂在那里时没有节内预算、也不会单独记红：'
            '$naked（第 10 轮就是挂在 5.1 的裸段里，白等 18 分钟）',
      );
      // 24 节一条不许少：拆用例时最容易"搬着搬着某一节没了"，而上面那七条只钉得住
      // 我事先点名的几节。所以再加一条计数下限（拆完之后是 24，历史上最少的那几轮也是 24）。
      expect(
        stepNames.length,
        greaterThanOrEqualTo(24),
        reason:
            '闸门分节数掉到 ${stepNames.length} ⇒ 有分节在搬迁中丢了。'
            '每一条都对应"一个页面/一条 CRUD 在真机上点过一遍"，掉一条就是那一类永远没测',
      );
    });

    test('闸门拆成的每条用例都能自己跑（不共享上一步留下的现场）', () {
      // ㊼ 对 smoke 做过的同一判据。只把"用例边界"切开不算拆分：真正的前提是每条用例
      // 自己装配、自己灌数据 —— 否则 `--plain-name "闸门 3/4"` 单跑必然假红，而 2/4 挂住时
      // 3/4 也会在没有 webhook 的现场上找按钮（4/4 更是会在"备份里没有那一族"的机器上测恢复）。
      final src = walkSrc();
      expect(
        RegExp(r"testWidgets\(\s*'闸门 \d/4").allMatches(src).length,
        greaterThanOrEqualTo(4),
        reason: '用例名不再是一、二、三、四编号 ⇒ 拆分结构被合回去了：红的时候又只剩"那条用例失败"',
      );
      expect(
        RegExp(r"await _assemble\(tester").allMatches(src).length,
        greaterThanOrEqualTo(4),
        reason: '有用例不自己装配 ⇒ 它跑的是上一条留下的现场（挂住/超时之后单跑它没有意义）',
      );
      expect(
        RegExp(r'await _verdict\(tester, gateFailures').allMatches(src).length,
        greaterThanOrEqualTo(4),
        reason: '有用例不结自己的账 ⇒ 它那些节的失败被 `_step` 收进 Map 却没人判红（静默放行）',
      );
      final assemble = blockAfter(src, 'Future<void> _assemble(');
      expect(
        RegExp(r'await GetIt\.instance\.reset\(\);').hasMatch(assemble),
        isTrue,
        reason:
            '不 await reset ⇒ 注册还落在上一条用例的 Service 实例上（本项目的 Windows 备忘里'
            '记着"GetIt.reset() 必须 await"这一条，装配是每次都要过的）',
      );
      expect(
        assemble.indexOf('allowReassignment'),
        lessThan(assemble.indexOf('setupLocator()')),
        reason:
            'allowReassignment 必须开在 setupLocator **之前** ⇒ 第二次装配当场抛 already registered',
      );
      // 需要现场的用例必须自己灌，而且灌的必须是断言读的那几样
      expect(
        RegExp(r'await _assemble\(tester, _seed').allMatches(src).length,
        greaterThanOrEqualTo(2),
        reason:
            '3/4（通道状态页）与 4/4（备份往返）不再把现场交给 `_assemble` 在 pump **之前**灌 ⇒ '
            '单跑必然假红（拆开之前这份现场是 2/4 建出来的）',
      );
      // 灌的**时机**也是契约：pump 之后再改配置，等于在装配中途动用户设置 ——
      // 页面重建与通道探测会掺进来（第 17 轮两处挂住都紧跟在"装配完 + 种子写完"之后）。
      expect(
        assemble.indexOf('await seed()'),
        lessThan(assemble.indexOf('pumpWidget')),
        reason: '种子改到 pump 之后灌 ⇒ 闸门跑的是"启动中途被改了配置"那条路径，不是"带着配置启动"',
      );
      final seed = blockAfter(src, 'Future<void> _seedBackupFixtures(');
      for (final needed in [
        '_seedWebhookChannel()',
        'saveWhitelistKeywords',
        'TemperatureService>().restoreSettings',
        'DeviceStateService>().restoreSettings',
      ]) {
        expect(
          seed,
          contains(needed),
          reason: '4/4 的种子不再包含「$needed」这一项 ⇒ 备份往返是在测残留现场，不是测恢复',
        );
      }
      // 出口的位置：**最后一条**用例里，且只有一处。放在中间某条 ⇒ 那条被用例级超时掐掉时
      // 出口跟着一起消失，脚本的"缺行判红"会把"没跑到出口"说成"出口自己坏了"。
      final outletAt = src.indexOf("'GATE-DIFF-RING");
      expect(outletAt, greaterThan(-1), reason: '闸门不再打印差异出口 ⇒ 见上一条测试的说明');
      expect(
        RegExp(r"'GATE-DIFF-RING").allMatches(src).length,
        1,
        reason: '出口打了多处 ⇒ 报告里 `tail -1` 取到的那一条不再确定是谁打的',
      );
      expect(
        outletAt,
        greaterThan(src.lastIndexOf('testWidgets(')),
        reason: '出口不在最后一条用例里 ⇒ 前面某条挂满超时就可能永远走不到它',
      );
    });

    test('挂住可以重试一次，功能红永远不重试；重试前必须先清设备', () {
      // 口径由维护者 2026-09-27 定：本机每轮总有一两处 `TimeoutException`（不是断言失败），
      // 拆成独立用例之后允许"只把挂住的那一条重跑一次"，换取一轮里四条用例都有结论。
      // 这条判据同时是最危险的一处：判据写歪一面的方向是**把真功能红洗成绿**。
      // 所以这里只钉形状，真正的方向性检查在行为探针 `outputs/_retry_probe.sh`
      // （五组假日志 + 两条把判据改坏的反证）。
      final sh = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      expect(
        RegExp(r'case_hang_only\(\)').hasMatch(sh),
        isTrue,
        reason: '重试判据必须是**一个函数**：散在循环里就没法喂假日志做行为探针（本仓库的 bash 判据老毛病）',
      );
      expect(
        sh.contains('TimeoutException\\|Guarded function conflict'),
        isTrue,
        reason:
            '挂住的两种形状都要算挂住：`TimeoutException` 是那节自己超时，'
            '`Guarded function conflict.` 是它留下的 body 抢后面各节 —— 后者不是功能红',
      );
      expect(
        RegExp(r'\[ "\$\{funcs:-0\}" -eq 0 \]').hasMatch(sh),
        isTrue,
        reason: '"这条用例里没有别的红"那一半判据不在了 ⇒ 真功能红也会被重跑洗成绿',
      );
      // "跳过"（挂住的连带后果）既不算功能红，也不该被当成挂住本身：两个 grep 都只数
      // `GATE-STEP-FAIL` 行 ⇒ 写成宽松的 `GATE-STEP` 就会把 SKIP/别的行卷进来，判据走形。
      expect(
        RegExp("grep -a 'GATE-STEP-FAIL'").hasMatch(sh),
        isTrue,
        reason:
            '功能红计数必须锚在 `GATE-STEP-FAIL` 上。锚点放宽到 `GATE-STEP` 就把「跳过」「BEGIN」'
            '一起算成红 ⇒ 挂住永远不许重试，重试机制形同不存在',
      );
      // 重试的门必须同时是三件事：已经红了、还没用尽次数、且**只有挂住**。
      // 少任一件就会出现"绿的重跑"或"功能红被洗掉"。分三条 substring 断言：
      // 这条 while 在脚本里是折行的，用一条正则去捏它只会让守卫比被测代码更脆。
      expect(
        sh,
        allOf(
          contains(r'[ "$case_rc" -ne 0 ]'),
          contains(r'"$attempt" -lt "$GATE_HANG_RETRIES"'),
          contains(r'&& case_hang_only "$case_name"'),
        ),
        reason: '重试的门缺了任意一半（红过 / 次数未用尽 / 只有挂住）⇒ 行为会漂移到不可信',
      );
      expect(
        RegExp(
          r'run_case "\$case_name 重跑\$attempt" "\$walk_file" --plain-name "\$case_name"',
        ).hasMatch(sh),
        isTrue,
        reason: '重跑必须跑**同一条**用例（换成正则或整档，等于用别的覆盖顶掉这一条的结论）',
      );
      expect(
        RegExp(r'GATE_HANG_RETRIES=\$\{GATE_HANG_RETRIES:-1\}').hasMatch(sh),
        isTrue,
        reason: '重试次数要显式可读、默认为 1（这是定下的口径）；偷偷改成 2 等于把一轮时长再翻一倍',
      );
      expect(
        sh.contains('重跑这一条一次'),
        isTrue,
        reason: '重试必须在报告里看得见一条 warn —— 悄悄重跑等于把"这一条跑了几次"藏起来',
      );
      // 重试前必须清设备：挂住的那条是在跑的中途被打断的，它已建好的规则留在库里，
      // 而 `_assemble` 只擦三族通道与历史记录 ⇒ 重跑 3/4 时 5.4a 的 `hasLength(2)`
      // 会数到上一趟留下的两条，报出一条**假的"功能红"**（比不重试更坏：它会挡住洗红判据）。
      final runCase = blockAfter(sh, 'run_case() {');
      expect(
        runCase,
        contains('clear_app_data'),
        reason: '每次独立调用之前都要 `pm clear`（重试尤其需要，否则重跑面对的是半成品数据）',
      );
      expect(
        runCase.indexOf('clear_app_data'),
        lessThan(runCase.indexOf('flutter test')),
        reason: '清数据晚一步等于没清',
      );
      // 清不掉必须**上抛**，不许 `|| true`：静默失败等于"这一步没做成"而报告里看不见。
      //（曾把 v1.5.76 第一趟 smoke 的红归因成"上一档残留没清"，那条归因已被否证 ——
      //  `flutter test` 每次跑完会卸载应用 ⇒ 跨档残留没有通道，见发版脚本同处的注释。）
      expect(
        RegExp(r'clear_app_data\(\) \{[\s\S]{0,900}?return 9').hasMatch(sh),
        isTrue,
        reason: 'clear_app_data 不区分"没装"与"清不掉" ⇒ 干净起点是否成立无人知道，报告里也看不见',
      );
      expect(
        RegExp(r'clear_app_data \|\| return 1').hasMatch(sh),
        isTrue,
        reason:
            '每一次独立调用前都要清得下来。8.14 起没有"整档 smoke"那一支了：清不掉时这条'
            '**不写收尾行**，于是被上面的「跑没跑到」计数逮住 —— 而不是"没跑"长得像"跑了且绿"',
      );
      // ⚠ `< /dev/null` 是被实测逼出来的：`adb shell` 与 `flutter test` 都从 stdin 读，
      // 而用例循环是 `while read` —— 第 20 轮它们把循环剩下的三个用例名吃掉了，
      // 整轮"成功地跑完"却只执行了 1/4，看起来像全绿。
      expect(
        runCase,
        contains('< /dev/null'),
        reason: 'run_case 不重定向 stdin ⇒ 它一跑就把后面几条用例从循环的输入里抹掉',
      );
      expect(
        blockAfter(sh, 'clear_app_data() {'),
        contains('< /dev/null'),
        reason: '同上：`adb shell` 也会吃 stdin',
      );
      // 光有重定向还不够：还要**数**跑了几条。少一条就是少一份覆盖，而红/绿看不出来。
      expect(
        sh.contains("grep -av '重跑'"),
        isTrue,
        reason: '数覆盖时必须排掉重跑那一次，否则"1/4 没跑 + 3/4 跑两遍"会凑成四条',
      );
      expect(
        RegExp(r'只跑了 \$ran/\$planned 条用例').hasMatch(sh),
        isTrue,
        reason: '用例没跑全必须判红：那种轮次的"绿"是循环提前退出给的，不是被测代码给的',
      );
    });

    test('备份往返真的擦掉并恢复了引擎规则两族（#95）', () {
      final flat = walkSrc().replaceAll(RegExp(r'\s+'), ' ');
      // 只断言"恢复后规则还在"是不够的：备份缺这一族时，恢复走"缺键 ⇒ 不动本机"，
      // 数量照样对 ⇒ 绿着放行。必须钉"导出之后、导入之前确实被擦过"。
      for (final svc in ['TemperatureService', 'DeviceStateService']) {
        expect(
          RegExp(
            r"GetIt\.instance<" +
                svc +
                r">\(\)\s*\.\s*restoreSettings\(\s*rules:\s*const \[\]",
          ).hasMatch(walkSrc()),
          isTrue,
          reason: '闸门不再擦除 $svc 的本机规则 ⇒ 这一节的断言退化成"测本机残留"',
        );
      }
      expect(
        flat,
        contains("contains('battery_temp_above')"),
        reason: '恢复后不再核对温度规则回来了 ⇒ 温度族退出备份覆盖面',
      );
      // ⚠ 锚点必须带上"这一条属于恢复后的核对"：`contains('闸门断网规则')` 在 5.4a 的
      // 镜像核对里也出现一次，光看字面量会绿着放行"第 7 节那条被删了"（反证 F 实测撞到）。
      expect(
        flat,
        contains("restoredState.map((r) => r['title']), contains('闸门断网规则')"),
        reason: '恢复后不再核对设备状态规则回来了 ⇒ 设备状态族退出备份覆盖面',
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
      // helper 两类对话框都要认：`askConfirm` 自 T90 片3 起是 `CupertinoDialogAction`，
      // 而台账里那些历史 Material 确认框仍是 `TextButton`。只认一种 ⇒ 另一种形状的删除
      // 在闸门上"找不到确认框"，红的是判据自己而不是被漏掉的咽喉。
      for (final kind in const ['CupertinoDialogAction', 'TextButton']) {
        expect(
          helper,
          contains("widgetWithText($kind, '删除')"),
          reason: '确认框 helper 少了 $kind 这一类 ⇒ 该形状的删除会被当成"没弹框"',
        );
      }
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
  group('自己改设备状态的测试不进闸门', () {
    test('闸门默认清单必须排除盖章与覆盖升级两个测试', () {
      final src = stripShellComments(
        read('.github/scripts/release_emulator.sh'),
      );
      // 反向锚点：被排除的文件都还在，否则"排除"是在排一个不存在的东西（恒真）。
      for (final f in const ['t09_stamp_test', 't22_upgrade_test']) {
        expect(
          File('$root/integration_test/$f.dart').existsSync(),
          isTrue,
          reason: '$f.dart 已不在 —— 排除清单要重新核',
        );
        expect(
          src,
          contains(f),
          reason: '$f 被默认清单收进来 = 每次发版往真实群发一轮消息 / 卸载重装设备',
        );
      }
      final filesLine = RegExp(r'FILES=\$\{GATE_FILES:.*').firstMatch(src);
      expect(filesLine, isNotNull, reason: '闸门默认清单写法变了，守卫要重新指向');
      expect(
        filesLine!.group(0),
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
