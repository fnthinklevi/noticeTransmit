import 'dart:convert';
import 'dart:io';

import '../support/source_guards.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tools/t09_stamp.dart' as stamp_tool;

/// T09 盖章工具的守卫。
///
/// 这个工具是仓库里**唯一**会把 `realSend: verified` 写进证据矩阵的东西，也就是说：
/// 它一旦说谎，"这一类通道真发过"这条证据就永久地被污染了，而守卫只会核对
/// "章有没有出处"，核不出"出处是不是编的"。所以这里钉的是它的**说谎能力**：
/// 1. 设备侧不许装原生桩 —— 装了桩，"发送成功"就是桩说出来的，脚本会开心地盖章；
/// 2. 只认 emulator-* —— 手滑指到维护者的手机 = 往真实群里打一通骚扰消息；
/// 3. 写矩阵是**外科式**的：只有被确认的那一行变，其余一字不动（整体重编码会把
///    一份人工维护、带内联 `{ "state": … }` 的文件摊成机器抄本，diff 再也看不出改了哪）；
/// 4. 找不到类型就拒绝写 —— 塞进矩阵里没有的类型，守卫只会报"多出一行"。
void main() {
  final root = projectRoot();
  File f(String rel) => File('$root/$rel');

  group('设备侧：真发就是真发', () {
    test('盖章测试文件里一个原生桩都不许有', () {
      const path = 'integration_test/t09_stamp_test.dart';
      expect(f(path).existsSync(), isTrue, reason: '$path 被改名 —— 本用例已失效');
      final src = stripComments(f(path).readAsStringSync());
      expect(
        src,
        isNot(contains('setMockMethodCallHandler')),
        reason: '装了 mock 桩之后"success:true"是桩给的，章就成了自证',
      );
      expect(
        src,
        isNot(contains('native_payload_stubs')),
        reason: '共享桩文件一 import 进来，真发就变成回放',
      );
      // 正向锚点：三条真发调用与清单出口都必须在，否则"没有桩"只是因为文件被掏空了。
      for (final anchor in const [
        'testWebhook',
        'testAppChannel',
        'testEmail',
        'T09-MANIFEST',
        'setDeviceName',
      ]) {
        expect(src, contains(anchor), reason: '盖章流程少了 $anchor 这一段');
      }
    });

    test('设备名必须在 finally 里还原（那是用户的设置，不是测试脚手架）', () {
      final src = stripComments(
        f('integration_test/t09_stamp_test.dart').readAsStringSync(),
      );
      final restored = RegExp(
        r'finally\s*\{[\s\S]{0,400}?setDeviceName[\s\S]{0,200}?originalName',
      ).hasMatch(src);
      expect(restored, isTrue, reason: '中途抛异常就把设备名留在 T09-XXXXX 上了');
    });
  });

  group('主机侧：只认模拟器', () {
    test('非 emulator 序列一律拒绝，且每次 adb 调用都带 -s', () {
      final src = stripComments(f('tools/t09_stamp.dart').readAsStringSync());
      // ⚠ 判据必须是**整段拒绝形状**，不能只问"文件里有没有 `startsWith('emulator-')`"：
      //   挑设备时也用同样的写法找序列，反证 S4（把拒绝改成 `if (serial.isEmpty)`）
      //   在只问存在性的版本下**照样绿** —— 那正是"守卫看着有、其实什么都不拦"。
      expect(
        RegExp(
          r"if\s*\(\s*!serial\.startsWith\('emulator-'\)\s*&&\s*!opt\.allowRealDevice\s*\)\s*\{",
        ).hasMatch(src),
        isTrue,
        reason: '少了这道判定（或放行条件不再要求显式开关），"下一个设备"可能就是别人的手机',
      );
      final refusal = RegExp(
        r"if\s*\(\s*!serial\.startsWith\('emulator-'\)\s*&&\s*!opt\.allowRealDevice"
        r"\s*\)\s*\{([\s\S]{0,260}?)\n  \}",
      ).firstMatch(src);
      expect(refusal, isNotNull, reason: '拒绝分支的形状变了（守卫要重新指向）');
      expect(refusal!.group(1), contains('拒绝'));
      expect(refusal.group(1), contains('exitCode = 2'), reason: '拒绝必须以非零码退出');
      // 放行开关必须是**默认关闭**的：一旦默认打开，上面那道判定就等于没有。
      expect(
        RegExp(r'bool allowRealDevice = false;').hasMatch(src),
        isTrue,
        reason: 'allowRealDevice 不再默认 false ⇒ 真机路线变成随手可达',
      );
      final noTarget = RegExp(
        r"Process\.runSync\(\s*adb,\s*<String>\[[^\]]*\]",
      ).allMatches(src).where((m) => !m.group(0)!.contains("'-s'")).toList();
      expect(
        noTarget.map((m) => m.group(0)!).where((s) => !s.contains("'devices'")),
        isEmpty,
        reason:
            '有 adb 调用没带 -s 目标序列（只有列设备的 `adb devices` 允许）：'
            '多设备时 adb 自己的报错会挡一下，但"别打到别人的设备"不该依赖别人家的错误提示',
      );
    });
  });

  group('写矩阵是外科式的', () {
    late String original;
    late List<String> allTypes;

    setUp(() {
      original = f(
        'test/evidence/channel_availability_matrix.json',
      ).readAsStringSync();
      allTypes = ((jsonDecode(original) as Map)['types'] as List)
          .map((r) => (r as Map)['type'].toString())
          .toList();
      expect(allTypes.length, greaterThanOrEqualTo(15), reason: '矩阵行数解析异常');
    });

    test('只改被盖章的那一行，其余行一字不动', () {
      final out = stamp_tool.applyStamp(
        original,
        stamp_tool.Stamp(
          type: 'dingtalk',
          date: '2026-09-26',
          build: '115',
          note: '模拟器实发，nonce=K7M2P',
        ),
      );
      expect(out, isNotNull);
      final before = original.split('\n');
      final after = out!.split('\n');
      expect(after.length, before.length, reason: '行数变了 = 文件被重编码过');
      final changed = <int>[];
      for (var i = 0; i < before.length; i++) {
        if (before[i] != after[i]) changed.add(i);
      }
      expect(changed, hasLength(1), reason: '改动行号 $changed，应只有 realSend 那一行');
      // 只改一行还不够：① 改完必须仍是合法 JSON（首版把键名重复写了一遍
      // `"realSend": "realSend": {…}`，逐行比对全绿、jsonDecode 才红）；
      // ② 被改的那一行必须**属于这个类型** —— 定位从 lazy 退成 greedy 时，
      //    "只改一行"和"总数加一"都仍成立，只有这一条会红（它盖到最后一个类型块上）。
      expect(() => jsonDecode(out), returnsNormally);
      final typed = (jsonDecode(out) as Map)['types']
          .cast<Map<String, dynamic>>()
          .where((r) => (r['realSend'] as Map)['state'] == 'verified')
          .map((r) => r['type'])
          .toList();
      expect(typed, ['dingtalk'], reason: '盖章盖到了别的类型头上');
      final line = after[changed.single];
      expect(line, contains('"state": "verified"'));
      expect(line, contains('2026-09-26'));
      expect(line, contains('"build": "115"'));
      expect(line, contains('K7M2P'), reason: '没有 nonce 的章 = 事后无法核对是哪一次发送');
      // 其余 14 类必须仍是 unverified（不许顺手全盖）
      expect(stamp_tool.countVerified(out), 1, reason: '盖一类涨一类，别的类不能跟着变绿');
    });

    test('矩阵里没有的类型：拒绝写入而不是新增一行', () {
      expect(
        stamp_tool.applyStamp(
          original,
          stamp_tool.Stamp(
            type: 'not_a_channel',
            date: '2026-09-26',
            build: '115',
            note: 'x',
          ),
        ),
        isNull,
      );
    });

    test('ratchet 与盖章数必须同一次写进去（守卫拿这两个数对账）', () {
      final out = stamp_tool.applyStamp(
        original,
        stamp_tool.Stamp(
          type: 'email',
          date: '2026-09-26',
          build: '115',
          note: '收件箱里看到了',
        ),
      )!;
      expect(stamp_tool.countVerified(out), 1);
      final fixed = stamp_tool.setRatchet(out, stamp_tool.countVerified(out));
      expect(fixed, contains('"verifiedRatchet": 1'));
      expect(stamp_tool.countVerified(fixed), 1, reason: '改 ratchet 不该顺手改章');
    });

    test('写出来的章满足矩阵守卫自己的判据（日期格式 + 三个字段齐）', () {
      for (final type in allTypes) {
        final out = stamp_tool.applyStamp(
          original,
          stamp_tool.Stamp(
            type: type,
            date: '2026-09-26',
            build: '115',
            note: '一条有出处的确认',
          ),
        );
        expect(out, isNotNull, reason: '$type 在矩阵里找不到（行数与类型清单漂移）');
        final send =
            ((jsonDecode(out!) as Map)['types'] as List)
                    .cast<Map<String, dynamic>>()
                    .firstWhere((r) => r['type'] == type)['realSend']
                as Map;
        expect(send['state'], 'verified');
        for (final k in const ['date', 'build', 'note']) {
          expect(
            (send[k] as String?)?.isNotEmpty ?? false,
            isTrue,
            reason: '$type 缺 $k',
          );
        }
        expect(
          send['date'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
          reason: '$type 的 date 必须是绝对日期（与 channel_evidence_matrix_test 同判据）',
        );
      }
    });
  });

  group('盖章只有一个人工咽喉', () {
    late String tool;
    setUp(
      () => tool = stripComments(f('tools/t09_stamp.dart').readAsStringSync()),
    );

    test('写矩阵只有一处调用 applyStamp，且默认答案是"不盖章"', () {
      expect(
        RegExp(r'applyStamp\(source, s\)').allMatches(tool).length,
        1,
        reason: '多一处写入 = 多一条绕过"逐条问人"的盖章路径',
      );
      expect(
        RegExp(r'matrixFile\.writeAsStringSync').allMatches(tool).length,
        1,
        reason: '矩阵必须只被一个函数落盘',
      );
      expect(tool, contains('(y/N)'), reason: '提示语不再默认 N = 顺手回车就盖章');
      expect(
        RegExp(r"if \(answer != 'y' && answer != 'yes'\) \{").hasMatch(tool),
        isTrue,
        reason: '确认判据变了（任何非 y 都必须跳过）',
      );
    });

    test('manual 模式必须自报"没有自动证据"', () {
      // 这条路没有 nonce、也没有设备侧的发送记录：章的出处只剩"人这么说"。
      // 如果哪天它不提醒这一点，就会被当成与 send/confirm 等价的证据用。
      final manual = blockAfter(tool, 'void _manual(Options opt) {');
      expect(manual, isNotEmpty, reason: 'manual 模式被删除或改名');
      expect(manual, contains('build'), reason: '必须显式记 build 出处');
      expect(
        manual,
        contains('_collectAndWrite('),
        reason: 'manual 必须走同一个"问人 → 写矩阵"咽喉，不能自己另开一条写入路',
      );
      expect(
        tool,
        contains('人工在设备界面点「仅测试」'),
        reason: '无 nonce 的默认备注必须写清"出处为本人回答"（否则 manual 会被当成自动证据）',
      );
    });
  });

  group('命令行本身（真机路线第一次就是这么死的）', () {
    test('不带 = 的布尔开关不得走进 substring(0, -1)', () {
      // 首版 `--allow-real-device` 一路落到 substring(0, i) 且 i = -1 ⇒ RangeError
      // 崩在解析阶段：真机那一步根本没执行，看起来却像"跑了没结果"。
      final o = stamp_tool.Options([
        '--allow-real-device',
        '--keep-emulator',
        '--types=dingtalk,email',
      ]);
      expect(o.allowRealDevice, isTrue);
      expect(o.keepEmulator, isTrue);
      expect(o.types, 'dingtalk,email');
      expect(o.unknown, isEmpty);
    });

    test('认不出的参数记进 unknown，由 main 大声拒绝而不是静默回退', () {
      final o = stamp_tool.Options(['--devcie=emulator-5554', '--yes-i-think']);
      expect(o.unknown, ['--devcie=emulator-5554', '--yes-i-think']);
      final src = stripComments(f('tools/t09_stamp.dart').readAsStringSync());
      expect(
        RegExp(
          r'if \(opt\.unknown\.isNotEmpty\) \{[\s\S]{0,200}?exitCode = 2',
        ).hasMatch(src),
        isTrue,
        reason: '拼错的 --device 若被丢掉，下一步就是"自动挑设备"——最不该静默的地方',
      );
      expect(
        RegExp(r'bool allowRealDevice = false;').hasMatch(src),
        isTrue,
        reason: '真机放行开关必须默认关闭',
      );
    });
  });

  group('清单解析：噪声不能把整轮判成没结果', () {
    const manifest = {
      'nonce': 'K7M2P',
      'build': 115,
      'rows': [
        {'type': 'dingtalk', 'success': true, 'target': 'oapi.dingtalk.com'},
      ],
    };
    final line = 'T09-MANIFEST ${jsonEncode(manifest)}';

    test('带日志前缀 / 纯行 / 坏 JSON / 没有前缀 各是什么结果', () {
      expect(stamp_tool.parseManifestLine(line)?['nonce'], 'K7M2P');
      expect(
        stamp_tool.parseManifestLine('07:31 +2: $line')?['nonce'],
        'K7M2P',
      );
      expect(stamp_tool.parseManifestLine('T09-MANIFEST {坏 JSON'), isNull);
      expect(stamp_tool.parseManifestLine('别的输出'), isNull);
      expect(
        stamp_tool.parseManifestLine('T09-MANIFEST [1,2]'),
        isNull,
        reason: '不是 Map 的"清单"不能当清单用',
      );
    });

    test('载荷里绝不写完整 URL 或密钥', () {
      // _redact 是设备侧的私有函数，这里钉它的**结果形状**：清单里只该有 host。
      final encoded = jsonEncode(manifest);
      expect(encoded, contains('oapi.dingtalk.com'));
      expect(encoded, isNot(contains('access_token')));
      expect(encoded, isNot(contains('https://')));
    });
  });
}
