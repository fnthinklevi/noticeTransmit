import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T22 覆盖升级脚本自身的守卫。
///
/// 为什么要有：这个脚本是"升级会不会改用户设置"这条不变量的**唯一**真机形状证据来源，
/// 而它自己就是竞态的现场。第三轮它红过一次——旧构建的 START_STICKY 服务在
/// "灌完种子 → flutter test 编 gradle"那个分钟级窗口里被拉起来，把缺 `enabled` 的那条
/// 按原生默认值坐实成 false。修法是顺序，而顺序是脚本里最容易被人"顺手挪一下"的东西。
///
/// ⚠ 全部判据先剥 shell 注释：本仓库实测过"把现役代码注释掉，守卫照样绿"（见
/// [stripShellComments] 的文档）。这里大量判据是 `contains` / `indexOf` 型，不剥注释
/// 就等于给"注释掉即失守"留了后门。
void main() {
  final root = projectRoot();
  String script() =>
      stripShellComments(read('$root/tools/t22_overlay_upgrade.sh'));

  group('顺序：竞态窗口必须被留在断言之外', () {
    test('编包在灌种子之前，覆盖安装与断言在种子之后', () {
      final src = script();
      final buildAt = src.indexOf('build apk --debug --target-platform');
      final seedAt = src.indexOf('<string name="flutter.battery_rules">');
      final installAt = src.indexOf('install -r "\$NEW_APK"');
      final preMigAt = src.indexOf('_t22_prefs_before_migration.xml');
      final testAt = src.indexOf('integration_test/t22_upgrade_test.dart');
      for (final entry in {
        '编当前包': buildAt,
        '灌种子': seedAt,
        '覆盖安装': installAt,
        '迁移前核实': preMigAt,
        '跑断言': testAt,
      }.entries) {
        expect(
          entry.value,
          greaterThan(0),
          reason: '${entry.key} 这一步在脚本里不见了 ⇒ 顺序判据全部失去对象',
        );
      }
      expect(
        buildAt < seedAt,
        isTrue,
        reason:
            '编包挪到灌种子之后 = 把分钟级 gradle 窗口留在旧构建还装着的时段，'
            '它的服务一旦被拉起，种子就被原生默认值改写（第三轮红的就是这个）',
      );
      expect(
        seedAt < installAt && installAt < testAt,
        isTrue,
        reason: '覆盖安装必须发生在灌种子之后、跑断言之前，否则测的不是升级',
      );
      expect(
        installAt < preMigAt && preMigAt < testAt,
        isTrue,
        reason: '迁移前的最后一次核实必须夹在"安装完"与"启动新包"之间',
      );
      // 反证：把现役那行编包注释掉（旧写法就是"根本没有这一步"），锚点必须随之消失。
      // ⚠ 不能只在 src 前面拼一行假注释就指望它判假——真出现处还在，判据仍为真，
      //   那样这条反证自己是摆设（第一版写成了这种形状，被自己的反证逮住）。
      final commented = read('$root/tools/t22_overlay_upgrade.sh')
          .split('\n')
          .map(
            (l) =>
                l.contains('build apk --debug --target-platform') ? '# $l' : l,
          )
          .join('\n');
      expect(
        stripShellComments(
          commented,
        ).contains('build apk --debug --target-platform'),
        isFalse,
        reason: '注释掉的编包仍被当成现役代码 ⇒ 把这一步改成注释，守卫还是绿的（假绿）',
      );
      // 编包必须是无条件的一步：`if [ ! -f "$NEW_APK" ]` 式的"文件在就沿用"会让
      // 装到设备上的其实是上一次（可能是 T20 之前）编的包 —— 那这句话就是假的。
      final buildLines = src
          .split('\n')
          .where((l) => l.contains('build apk --debug --target-platform'))
          .toList();
      expect(buildLines, hasLength(1), reason: '编包出现两处 ⇒ 其中一处多半在条件分支里');
      expect(
        buildLines.single.startsWith('('),
        isTrue,
        reason: '编包这一步被缩进 = 被包进了某个 if；沿用旧包的形状会悄悄回来',
      );
      // 反证：同一行只要缩进过，上面那条就该判假。
      expect(
        r'  (cd "$ROOT" && run_flutter build apk --debug)'.startsWith('('),
        isFalse,
        reason: '缩进过的同一行仍能通过 ⇒ 上面那条判据是摆设',
      );
    });

    test('种子核实有两处：灌完一次、启动新包前再一次，且都判红不停就退出', () {
      final src = script();
      const anchor = '"charging","type":"charging","value":0,"title"';
      final hits = RegExp(RegExp.escape(anchor)).allMatches(src).length;
      expect(
        hits,
        greaterThanOrEqualTo(2),
        reason:
            '只在灌完种子后核实一次，就看不见"旧代码在窗口里回写"这件事 ⇒ '
            '缺 enabled 的那条被坐实成 false 时，红的会是最后的断言而不是原因',
      );
      // 两处核实都必须"没命中就停"，不能只 warn。
      expect(
        RegExp('grep -q \'$anchor\'[\\s\\S]{0,160}?exit 1').hasMatch(src),
        isTrue,
        reason: '核实失败只 warn ⇒ 拿假种子做比对，结论是反的还说"通过了"',
      );
    });

    test('旧进程必须被证明真的死了才开始迁移', () {
      final src = script();
      final installAt = src.indexOf('install -r "\$NEW_APK"');
      final pidofAt = src.indexOf('shell pidof "\$APP_ID"');
      expect(
        pidofAt,
        greaterThan(installAt),
        reason: '没有 pidof 判据 = 只靠 force-stop + sleep 赌旧进程没被拉起',
      );
      expect(
        RegExp(r'pidof "\$APP_ID"[\s\S]{0,400}?exit 1').hasMatch(src),
        isTrue,
        reason: '杀不掉就继续跑 ⇒ 拿"随时会被旧代码改写"的现场做比对',
      );
      expect(
        src.lastIndexOf('am force-stop "\$APP_ID"', pidofAt),
        lessThan(pidofAt),
        reason: 'pidof 之前没有 force-stop ⇒ 判据查的是一个从没被要求退出的进程',
      );
      // 反向锚点：被减掉的文件必须还在，否则"排除"是在排一个不存在的东西（恒真）。
      for (final f in const [
        '_t22_prefs_before_migration.xml',
        'FlutterSharedPreferences.xml',
      ]) {
        expect(src.contains(f), isTrue, reason: '$f 已不在脚本里 ⇒ 下面这条顺序判据失去对象');
      }
      expect(
        src.indexOf('_t22_prefs_before_migration.xml'),
        greaterThan(src.lastIndexOf('FlutterSharedPreferences.xml')),
        reason: '最后一次读设备镜像必须发生在启动新构建之前，晚一步读到的就是迁移后的了',
      );
    });
  });

  group('设备与写入：这个脚本会卸载、会改数据', () {
    test('只认 emulator-*，不认识的参数宁可停', () {
      final src = script();
      expect(
        src.contains(r'emulator-*)'),
        isTrue,
        reason: '缺少"设备必须是模拟器"的判定 = 有误清别人手机的风险',
      );
      expect(
        RegExp(r'目标不是模拟器').hasMatch(src) &&
            RegExp(r'\*.*?\bfail\b[\s\S]{0,120}?exit 2').hasMatch(src),
        isTrue,
        reason: '非模拟器序列必须停住（exit 2），不能降级继续',
      );
      expect(
        RegExp(r'不认识的参数[\s\S]{0,120}?exit 2').hasMatch(src),
        isTrue,
        reason: '拼错的参数被忽略后脚本会回退去自动挑设备 ⇒ 可能挑到真机',
      );
    });

    test('模拟器由 trap 收尾，boot 失败也不许留在后台', () {
      final src = script();
      expect(
        RegExp(r'^trap cleanup EXIT', multiLine: true).hasMatch(src),
        isTrue,
        reason: '只在末尾 emu kill ⇒ 中途失败会把模拟器挂在后台（维护者明确要求）',
      );
      // 反证：注释掉的 trap 必须判假。
      expect(
        RegExp(
          r'^trap cleanup EXIT',
          multiLine: true,
        ).hasMatch(stripShellComments('# trap cleanup EXIT INT TERM\n')),
        isFalse,
        reason: '注释里的 trap 也算命中 ⇒ 守卫是摆设',
      );
      expect(
        RegExp(r'emu kill').allMatches(src).length,
        1,
        reason: '第二处 emu kill 会掩盖第一处不在 trap 里的事实',
      );
    });

    test('灌 prefs 的 helper：建目录 + 回读非空，写失败直接停', () {
      // 第一版就是在这里静默失败的：cat 重定向不建 shared_prefs/，而 `|| warn` 让它无害。
      final src = script();
      final helper = src.substring(
        src.indexOf('xml() {'),
        src.indexOf('xml \'<?xml'),
      );
      expect(
        helper,
        contains('mkdir -p'),
        reason: '刚装完时 shared_prefs/ 不存在 ⇒ 写入落空，后面全是空结论',
      );
      expect(
        RegExp(r'回读为空[\s\S]{0,80}?exit 1').hasMatch(helper),
        isTrue,
        reason: '写完不回读 = "灌进去了"这件事没人证明过',
      );
      expect(
        RegExp(r'灌 prefs 失败[\s\S]{0,80}?exit 1').hasMatch(helper),
        isTrue,
        reason: '写失败只 warn ⇒ 拿一个空的 prefs 去做升级比对',
      );
    });

    test('旧构建没建出加密库就停（没库就没有"迁移"这回事）', () {
      final src = script();
      expect(
        RegExp(
          r'notice_transmit_encrypted\.db[\s\S]{0,200}?exit 1',
        ).hasMatch(src),
        isTrue,
        reason: '旧构建没建库还继续跑，比对的其实是"新装"',
      );
      expect(
        src.contains('ls -i /data/data/'),
        isTrue,
        reason: 'inode 留痕没了 ⇒ "是不是同一个库文件被升级"只剩日志里的一句话都没有',
      );
    });
  });

  group('判据归属：设备侧结论不能写在会被卸载之后', () {
    test('flutter test 之后不许再读设备', () {
      final src = script();
      final testAt = src.indexOf('integration_test/t22_upgrade_test.dart');
      expect(
        src.lastIndexOf('run-as'),
        lessThan(testAt),
        reason:
            '`flutter test` 收尾会连数据一起卸载，之后再 run-as 只会拿到 '
            '`unknown package`（第二轮就是这么"红"的）',
      );
    });

    test('"同一个库文件被升级"的判据确实在 Dart 测试里', () {
      final dart = stripComments(
        read('$root/integration_test/t22_upgrade_test.dart'),
      );
      expect(
        dart,
        contains('.corrupt'),
        reason: '没有 .corrupt 判据 ⇒ "打不开就重建空库"也可能看起来规则还在',
      );
      expect(
        dart,
        contains('PRAGMA user_version'),
        reason: '不核对 user_version，就不知道迁移是不是真落在这个库上',
      );
      expect(
        dart,
        contains('notice_transmit_encrypted.db'),
        reason: '没有"库文件确实存在"这条，同库升级无从谈起',
      );
    });
  });

  group('set -u：未定义变量会让脚本半路退出', () {
    test('每个裸用的大写变量都在脚本里被赋值过', () {
      // 踩过的形状：`[ ! -f "$NEW_APK" ] || [ "$BUILD_NEW" = "1" ]` —— 前者为真时才会
      // 求值后者，于是"没定义"这个 bug 只在**不需要重编**的路径上炸，`set -u` 直接退出，
      // 表现成"脚本半路没了"，比红更难查。
      expect(
        undefinedShellVars(
          read('$root/tools/t22_overlay_upgrade.sh').split('\n'),
        ),
        isEmpty,
        reason: '未赋值就裸用 ⇒ set -u 下这条路径会半路退出（看起来像"脚本没跑完"）',
      );
    });

    test('扫描器自己对每种形状都敏感（否则上面那条是摆设）', () {
      // ⚠ 逐行传，且一律 raw 字符串：`"$NOPE"` 写进普通 Dart 字符串会被当成插值，
      //   测的就不再是 shell 的那种写法了（这一版先是把 `\\$` 写成了普通字符串，编译就红）。
      // 1. 裸用未定义必须报（正向敏感）。
      expect(undefinedShellVars([r'X="$NOPE"']), {'NOPE'});
      // 2. 有定义就不报（顺带保证判据不是"永远返回非空"的单向装置）。
      expect(undefinedShellVars(['NOPE=1', r'echo "$NOPE"']), isEmpty);
      // 3. 自带兜底的写法不会炸，不该误报。
      expect(undefinedShellVars([r'X="${NOPE:-d}"']), isEmpty);
      expect(undefinedShellVars([r'X="${NOPE:+y}"']), isEmpty);
      // 4. `\$NOPE` 是打印给人看的字面美元号，不是变量引用。
      expect(undefinedShellVars([r'echo "set \$NOPE first"']), isEmpty);
      // 5. 注释里的定义**不算**定义（否则"把定义注释掉"仍是绿的）。
      expect(undefinedShellVars(['# NOPE=1', r'X="$NOPE"']), {'NOPE'});
      // 6. 函数体里赋值也算（缩进不影响判定）。
      expect(
        undefinedShellVars(['f() {', '  NOPE=1', '}', r'X="$NOPE"']),
        isEmpty,
      );
    });
  });
}

String read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// shell 在 `set -u` 下会炸的变量：裸用 `$NAME` / `${NAME}` 而整个脚本里没有赋值语句。
///
/// 为什么要扫这个而不是靠肉眼看：`[ -f "$A" ] || [ "$B" = 1 ]` 这种短路写法，未定义的
/// `$B` 只在**其中一条路径**上求值，测试覆盖不到时它会表现成"脚本半路退出"而不是明确的红
/// （本脚本的 BUILD_NEW 就是这个形状）。注释先剥掉（注释里的定义不算定义）；
/// `${NAME:-…}` / `:+` / `:=` 自带兜底不会炸；`\$NAME` 是打印给人看的字面美元号。
Set<String> undefinedShellVars(List<String> lines) {
  final src = stripShellComments('${lines.join('\n')}\n');
  final assigned = RegExp(
    r'(?:^|\n)[ \t]*([A-Z][A-Z0-9_]*)=',
  ).allMatches(src).map((m) => m.group(1)!).toSet();
  final out = <String>{};
  for (final m in RegExp(r'(?<!\\)\$\{?([A-Z][A-Z0-9_]*)\b').allMatches(src)) {
    final rest = src.substring(m.end);
    if (rest.startsWith(':-') ||
        rest.startsWith(':+') ||
        rest.startsWith(':=')) {
      continue;
    }
    final name = m.group(1)!;
    if (!assigned.contains(name)) out.add(name);
  }
  return out;
}
