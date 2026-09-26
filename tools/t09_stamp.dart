#!/usr/bin/env dart
/// roadmap T09「真发一次」盖章工具（主机侧）。
///
/// 为什么要有它：那一列的证据只能由人眼给（守卫要 date/build/note，且盖章总数是显式
/// 数字），但**流程**里剩下的全是机械活 —— 起设备、按类型逐条真发、把结论写进矩阵、
/// 动 ratchet、别忘了在 base.md 记一句。手工做 15 次的代价是"每次都想跳过"，
/// 于是这一列永远空着。这里把一次盖章的成本压成：跑一遍、在收件端看一眼、回一个 y。
///
/// 三条不能让步的设计：
/// 1. **只认 emulator-* 序列**。真机上一旦跑起来就是往用户的真实群/邮箱发骚扰消息，
///    而且这台机器上还挂着维护者自己的手机（同 `release_emulator.sh` 的判定）。
/// 2. **设备侧不 mock 任何原生方法**（见 `integration_test/t09_stamp_test.dart`），
///    否则"发送成功"是桩说出来的，章就成了自证。
/// 3. **只有人答了 y 才写矩阵**；没答、答 n、发送失败的行一律原样不动。
///    nonce（一次性随机码，塞在设备名里跟着消息一起发出去）保证你确认的是**刚才那条**，
///    不是上周群里躺着的那条测试消息。
///
/// 用法：
///   dart tools/t09_stamp.dart list
///   dart tools/t09_stamp.dart send    [--types=dingtalk,email] [--device=emulator-5554]
///                                     [--avd=ci_api34_pixel6] [--keep-emulator]
///   dart tools/t09_stamp.dart confirm [--manifest=outputs/t09_stamp_manifest.json]
library;

import 'dart:convert';
import 'dart:io';

const _defaultMatrix = 'test/evidence/channel_availability_matrix.json';
const _defaultManifest = 'outputs/t09_stamp_manifest.json';

/// 一条待写入矩阵的章。
class Stamp {
  Stamp({
    required this.type,
    required this.date,
    required this.build,
    required this.note,
  });
  final String type;
  final String date;
  final String build;
  final String note;
}

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'help' : args.first;
  final opt = Options(args.skip(1).toList());
  if (opt.unknown.isNotEmpty) {
    stderr.writeln(
      '不认识的参数：${opt.unknown.join(' ')} —— 拼错的开关若被静默丢掉，'
      '下一步就是"自动挑设备"，而这正是最不能静默回退的地方。',
    );
    _usage();
    exitCode = 2;
    return;
  }
  switch (mode) {
    case 'list':
      _list(opt);
    case 'send':
      await _send(opt);
    case 'confirm':
      _confirm(opt);
    case 'manual':
      _manual(opt);
    default:
      _usage();
  }
}

void _usage() {
  stdout.write(
    '''
T09「真发一次」盖章工具

  list                       看现在哪些类型盖了章、哪些还欠着
  send   [--types=a,b]       在模拟器上逐类真发一条（nonce 挂在设备名里），存清单
         [--device=<serial>] 缺省时自动挑唯一的 emulator-* 序列；非 emulator-* 一律拒绝
         [--avd=<name>]      没有跑着的模拟器时，用这个 AVD 起一个（跑完默认关掉）
         [--keep-emulator]   跑完别关（连着 confirm 一起调试时用）
         [--allow-real-device]  明知是测试机、接受被清数据时才加；默认拒绝非 emulator-*
  confirm [--manifest=<f>]   按清单逐条问你"收件端看到那条了吗"，只把 y 的写进矩阵
  manual --types=a,b [--build=115]
                             没有清单时的人工盖章（你在设备界面手点「仅测试」）。
                             ⚠ 没有 nonce、没有发送记录，章的出处完全来自你的回答

典型一轮：
  dart tools/t09_stamp.dart send --types=dingtalk,email
  dart tools/t09_stamp.dart confirm
''',
  );
}

void _list(Options opt) {
  final matrix = File(opt.matrix);
  if (!matrix.existsSync()) {
    stderr.writeln('找不到矩阵：${opt.matrix}');
    exitCode = 1;
    return;
  }
  final decoded = jsonDecode(matrix.readAsStringSync()) as Map<String, dynamic>;
  final rows = (decoded['types'] as List).cast<Map<String, dynamic>>();
  final ratchet = decoded['verifiedRatchet'];
  final verified = <String>[];
  for (final r in rows) {
    final send = r['realSend'] as Map;
    if (send['state'] == 'verified') {
      verified.add('${r['type']}(${send['date']}/build ${send['build']})');
    }
  }
  stdout.writeln('矩阵共 ${rows.length} 类；已盖章 ${verified.length} 类，ratchet=$ratchet');
  for (final v in verified) {
    stdout.writeln('  ✅ $v');
  }
  final missing = rows
      .map((r) => r['type'].toString())
      .where((t) => !verified.any((v) => v.startsWith('$t(')))
      .toList();
  if (missing.isNotEmpty) {
    stdout.writeln('  ⚠ 未盖章：${missing.join('、')}');
  }
  if (verified.length != ratchet) {
    stdout.writeln(
      '  ❌ 盖章数与 verifiedRatchet 不一致 ⇒ 守卫现在就是红的，先改回同一个数',
    );
    exitCode = 1;
  }
}

Future<void> _send(Options opt) async {
  final adb = _tool(opt.adb, 'adb');
  final flutter = _tool(opt.flutter, 'flutter');
  if (adb == null) {
    stderr.writeln('找不到 adb：用 --adb=<路径> 或把它放进 PATH');
    exitCode = 1;
    return;
  }

  var serial = opt.device;
  var bootedHere = false;
  if (serial == null) {
    final found = _emulatorSerials(adb);
    if (found.length == 1) {
      serial = found.single;
    } else if (found.isEmpty || opt.avd != null) {
      serial = await _bootEmulator(adb, opt);
      if (serial == null) {
        exitCode = 1;
        return;
      }
      bootedHere = true;
    } else {
      stderr.writeln(
        '检测到 ${found.length} 台 emulator-* 设备，无法自己猜：用 --device= 指定。',
      );
      exitCode = 1;
      return;
    }
  }
  // ⚠ 这条判定是整个工具唯一挡住"往别人的设备上真发"的东西。默认拒绝；只有显式
  //   --allow-real-device 才放行，放行时也要把两件事念一遍：消息是真的、
  //   `flutter test` 会先装 debug 包 ⇒ 签名不合就 adb uninstall ⇒ 该设备上的
  //   通道配置与通知历史一起没（本仓库 2026-09-23 就在维护者的手机上撞过一次）。
  if (!serial.startsWith('emulator-') && !opt.allowRealDevice) {
    stderr.writeln(
      '拒绝在非模拟器设备（$serial）上真发。确认这是测试机、且接受"数据被清 + '
      '真消息发出去"，再加 --allow-real-device。',
    );
    exitCode = 2;
    return;
  }
  if (!serial.startsWith('emulator-')) {
    stderr.writeln('⚠ 真机模式（$serial）：这一步可能卸载设备上的现有安装，且发出的消息收得到。');
  }
  if (flutter == null) {
    stderr.writeln('找不到 flutter：用 --flutter=<路径> 或把它放进 PATH');
    exitCode = 1;
    return;
  }

  stdout.writeln('设备：$serial（每次 adb 调用都带 -s，绝不落到别的设备）');
  int? killed;
  if (bootedHere && !opt.keepEmulator) {
    killed = 0;  // 结束时关掉，别让 AVD 挂着（同 release_emulator.sh 的 trap 口径）
  }
  try {
    final defines = <String>['T09_TYPES=${opt.types ?? ''}'];
    stdout.writeln('开始逐类真发（这一步会真的把消息发出去）…');
    final run = wrap(
      flutter,
      <String>[
        'test',
        'integration_test/t09_stamp_test.dart',
        '-d',
        serial,
        for (final d in defines) '--dart-define=$d',
      ],
    );
    final r = Process.runSync(run.$1, run.$2);
    final out = '${r.stdout}\n${r.stderr}';
    final manifest = _parseManifest(out);
    if (manifest == null) {
      stderr.writeln(
        '没在输出里找到 T09-MANIFEST（退出码 ${r.exitCode}）。原始输出尾部：\n',
      );
      stderr.writeln(_tail(out, 40));
      exitCode = 1;
      return;
    }
    final file = File(opt.manifest)..createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
    stdout.writeln('清单已写入 ${file.path}');
    _printChecklist(manifest);
    stdout.writeln('\n下一步：dart tools/t09_stamp.dart confirm');
  } finally {
    if (killed != null) {
      stdout.writeln('关闭本工具启动的模拟器 $serial');
      Process.runSync(adb, <String>['-s', serial, 'emu', 'kill']);
    }
  }
}

void _printChecklist(Map<String, dynamic> manifest) {
  final rows = (manifest['rows'] as List).cast<Map<String, dynamic>>();
  stdout.writeln('');
  stdout.writeln(
    'nonce=${manifest['nonce']}  设备名当时被改成「T09-${manifest['nonce']}」  '
    'build=${manifest['build'] ?? '?'}',
  );
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    stdout.writeln(
      '  ${i + 1}. ${(r['type'] as String).padRight(14)} → ${r['target']}   '
      '${r['success'] == true ? '发送返回成功' : '发送失败：${r['message']}'}',
    );
  }
  stdout.writeln('请到这些收件端各找一条【设备名写着 T09-${manifest['nonce']}】的测试消息。');
}

void _confirm(Options opt) {
  final file = File(opt.manifest);
  if (!file.existsSync()) {
    stderr.writeln('找不到清单 ${file.path}：先跑 dart tools/t09_stamp.dart send');
    exitCode = 1;
    return;
  }
  final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final rows = (manifest['rows'] as List).cast<Map<String, dynamic>>();
  _collectAndWrite(
    opt,
    rows,
    build: (manifest['build'] ?? '?').toString(),
    nonce: manifest['nonce'].toString(),
  );
}

/// 没有清单时的人工盖章：你在**设备界面里手点「仅测试」**（release 包），
/// 然后坐在这里回答"哪几类真的收到了"。
///
/// ⚠ 这条路比 send/confirm 更弱：nonce 没有了，自动侧连"发过一次"都没有记录，
/// 章的出处**完全**来自你此刻的回答。所以 `--build` 必须填你实际点的那个构建号
/// （缺省读 pubspec，读错就等于给一个没验过的构建盖章）。
void _manual(Options opt) {
  final types = (opt.types ?? '')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (types.isEmpty) {
    stderr.writeln('manual 需要 --types=<逗号分隔的类型>（先看 dart tools/t09_stamp.dart list）');
    exitCode = 1;
    return;
  }
  final build = opt.build ?? _buildFromPubspec();
  stdout.writeln(
    '人工盖章：本轮没有任何自动记录，build 记为 **$build**。'
    '${opt.build == null ? '（build 取自 pubspec.yaml —— 不是你手点的那个包就用 --build= 指定）' : ''}\n',
  );
  _collectAndWrite(
    opt,
    [
      for (final t in types)
        {'type': t, 'target': '（人工填写）', 'success': true},
    ],
    build: build,
  );
}

/// 两条路共用同一个提问 + 写入咽喉：只有答 y 的行会变成章。
void _collectAndWrite(
  Options opt,
  List<Map<String, dynamic>> rows, {
  required String build,
  String? nonce,
}) {
  final matrixFile = File(opt.matrix);
  if (!matrixFile.existsSync()) {
    stderr.writeln('找不到矩阵：${opt.matrix}');
    exitCode = 1;
    return;
  }
  var source = matrixFile.readAsStringSync();
  final date = DateTime.now().toIso8601String().substring(0, 10);
  final stamps = <Stamp>[];

  stdout.writeln('每一条都要你在收件端**亲眼看到**那条消息才答 y。');
  stdout.writeln('没有对应平台账号 / 没收到 / 拿不准 —— 一律回车跳过（保持 unverified）。\n');
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final type = r['type'].toString();
    stdout.writeln('[${i + 1}/${rows.length}] $type → ${r['target']}');
    if (r['success'] != true) {
      stdout.writeln('    ⚠ 这一条原生返回的是失败：${r['message']}');
    }
    stdout.write(
      nonce == null
          ? '    你确实收到了这一类的一条测试消息吗？(y/N) '
          : '    收件端有没有一条内容里写着「T09-$nonce」的测试消息？(y/N) ',
    );
    final answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
    if (answer != 'y' && answer != 'yes') {
      stdout.writeln('    → 跳过（这一类仍然未盖章）');
      continue;
    }
    stdout.write('    备注（在哪看到的，回车用默认）：');
    final note = (stdin.readLineSync() ?? '').trim();
    stamps.add(
      Stamp(
        type: type,
        date: date,
        build: build,
        note: note.isNotEmpty
            ? note
            : nonce == null
            ? '人工在设备界面点「仅测试」，收件端确认可见（无 nonce，出处为本人回答）'
            : '模拟器实发，nonce=$nonce，收件端确认可见；收件端 ${r['target']}',
      ),
    );
    stdout.writeln('    → 记录盖章');
  }

  if (stamps.isEmpty) {
    stdout.writeln('\n一条都没确认，矩阵不动。');
    return;
  }
  for (final s in stamps) {
    final next = applyStamp(source, s);
    if (next == null) {
      stderr.writeln('矩阵里找不到类型 ${s.type} —— 拒绝写入（守卫会因为多出行判红）');
      exitCode = 1;
      return;
    }
    source = next;
  }
  final written = countVerified(source);
  source = setRatchet(source, written);
  matrixFile.writeAsStringSync(source);

  stdout.writeln('\n已写入矩阵：$written 类已盖章（verifiedRatchet 同步为 $written）。');
  stdout.writeln('记得跑一遍守卫确认没写坏：');
  stdout.writeln('  flutter test test/architecture/channel_evidence_matrix_test.dart');
  stdout.writeln('并给 base.md 补一句（谁在哪个构建上验了哪一类）：');
  final list = stamps.map((s) => '${s.type}（build ${s.build}，${s.date}）').join('、');
  stdout.writeln('  『T09 真发一次盖章：$list，由维护者实发后在收件端确认。』');
}

/// 当前源码的构建号（`version: 1.5.75+115` 里的 115）。
String _buildFromPubspec() {
  final f = File('pubspec.yaml');
  if (!f.existsSync()) return '?';
  final m = RegExp(r'^version:\s*\S*\+(\d+)', multiLine: true)
      .firstMatch(f.readAsStringSync());
  return m?.group(1) ?? '?';
}

/// 把一枚章写进矩阵源码。定位方式是**类型块内**的 realSend —— 用整体 JSON 重编码
/// 会把 `"realSend": { "state": … }` 这行摊成多行，一份人工维护的文件于是变成机器
/// 抄本，下次看 diff 谁也看不出改了哪。
String? applyStamp(String source, Stamp stamp) {
  // 锚在「本类型的 type → 它自己的 realSend」这一段：lazy 匹配停在**同一个类型块**里的
  // realSend，不会一路吃到下一个类型（那会改掉别的类型的章）。
  final re = RegExp(
    '("type":\\s*"${RegExp.escape(stamp.type)}"[\\s\\S]*?"realSend":\\s*)\\{[^}]*\\}',
  );
  // group(1) 已经把 `"realSend": ` 这个键名连同冒号一起捕获了，这里只补**值**。
  final stamped = '{ '
      '"state": "verified", '
      '"date": ${jsonEncode(stamp.date)}, '
      '"build": ${jsonEncode(stamp.build)}, '
      '"note": ${jsonEncode(stamp.note)} }';
  // replaceFirstMapped：函数返回的字符串**不再做 `$` 展开**（note 是人写的，里面可能有 $）。
  final out = source.replaceFirstMapped(re, (m) => '${m.group(1)}$stamped');
  return out == source ? null : out;
}

/// 当前已盖章的行数（守卫拿它与 verifiedRatchet 比对，两者必须同一次写进去）。
int countVerified(String source) => RegExp(
  '"state":\\s*"verified"',
).allMatches(source).length;

String setRatchet(String source, int value) {
  final re = RegExp('"verifiedRatchet":\\s*\\d+');
  if (!re.hasMatch(source)) {
    throw StateError('矩阵里没有 verifiedRatchet 字段，拒绝盲写');
  }
  return source.replaceFirst(re, '"verifiedRatchet": $value');
}

/// 从 flutter test 的输出里取出设备侧打印的那份清单。
/// 反向找：日志里可能有别的内容含同样的前缀（比如被重新打印的失败原因）。
Map<String, dynamic>? parseManifestLine(String line) {
  const prefix = 'T09-MANIFEST ';
  final idx = line.indexOf(prefix);
  if (idx < 0) return null;
  try {
    final decoded = jsonDecode(line.substring(idx + prefix.length).trim());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _parseManifest(String output) {
  Map<String, dynamic>? found;
  for (final line in const LineSplitter().convert(output)) {
    final m = parseManifestLine(line);
    if (m != null) found = m;
  }
  return found;
}

List<String> _emulatorSerials(String adb) {
  final r = Process.runSync(adb, <String>['devices']);
  return (const LineSplitter().convert('${r.stdout}'))
      .map((l) => l.trim().split(RegExp(r'\s+')).first)
      .where((s) => s.startsWith('emulator-'))
      .toList();
}

Future<String?> _bootEmulator(String adb, Options opt) async {
  final avd = opt.avd;
  if (avd == null) {
    stderr.writeln(
      '没有 emulator-* 设备在跑。启动一个：emulator -avd <AVD> -no-audio -no-boot-anim\n'
      '或给本工具加 --avd=<AVD> 让它代劳。',
    );
    return null;
  }
  final exe = _tool(null, 'emulator');
  if (exe == null) {
    stderr.writeln('找不到 emulator 可执行文件（--adb 同级的 emulator.exe）');
    return null;
  }
  stdout.writeln('启动模拟器 $avd（由本工具起的，跑完默认由本工具关掉），等待开机…');
  final proc = await Process.start(
    exe,
    <String>[
      '-avd',
      avd,
      '-no-audio',
      '-no-boot-anim',
      '-gpu',
      opt.gpu ?? 'swiftshader_indirect',
    ],
    mode: ProcessStartMode.detached,
  );
  stdout.writeln('  pid ${proc.pid}');
  final deadline = DateTime.now().add(const Duration(seconds: 240));
  while (DateTime.now().isBefore(deadline)) {
    final r = Process.runSync(adb, <String>['devices']);
    final serial = (const LineSplitter().convert('${r.stdout}'))
        .map((l) => l.trim().split(RegExp(r'\s+')).first)
        .firstWhere(
          (s) => s.startsWith('emulator-'),
          orElse: () => '',
        );
    if (serial.isNotEmpty) {
      final booted = Process.runSync(
        adb,
        <String>['-s', serial, 'shell', 'getprop', 'sys.boot_completed'],
      );
      if ('${booted.stdout}'.trim() == '1') return serial;
    }
    sleep(const Duration(seconds: 5));
  }
  stderr.writeln('模拟器 240s 内没起来（与 release_emulator.sh 同一个坑：起不来就别继续）');
  return null;
}

/// Windows 上 `flutter` 常是 .bat / .cmd，`Process.run*` 不能直接执行它们
/// （CreateProcess 只认 PE 文件）⇒ 必须经 `cmd /c` 包一层。
/// 与仓库里"直调 dart.exe + flutter_tools.snapshot"是同一条平台事实。
(String, List<String>) wrap(String exe, List<String> args) {
  if (exe.endsWith('.bat') || exe.endsWith('.cmd')) {
    return ('cmd', <String>['/c', exe, ...args]);
  }
  return (exe, args);
}

/// adb / flutter 的路径解析：命令行给的优先，其次 PATH。
String? _tool(String? explicit, String name) {
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final which = Process.runSync('bash', <String>['-lc', 'command -v $name || true']);
  final path = '${which.stdout}'.trim();
  return path.isEmpty ? null : path;
}

String _tail(String s, int lines) {
  final all = const LineSplitter().convert(s);
  return all.length <= lines ? s : all.sublist(all.length - lines).join('\n');
}

/// 命令行参数。公开（而不是 `_Options`）是为了让守卫能**直接喂参数**：
/// 在 `flutter test` 里 `Platform.resolvedExecutable` 指向 flutter_tester（引擎），
/// 拿它起子进程会挂住，所以"崩在参数解析"这类错法只能这样测。
class Options {
  Options(List<String> args) {
    for (final a in args) {
      // 布尔开关**必须**在找 `=` 之前单独处理并 continue：首版把 `--allow-real-device`
      // 一路带到 substring(0, -1)，直接 RangeError 崩在解析阶段（真机那一步根本没执行）。
      if (a == '--keep-emulator') {
        keepEmulator = true;
        continue;
      }
      if (a == '--allow-real-device') {
        allowRealDevice = true;
        continue;
      }
      final i = a.indexOf('=');
      if (i < 0) {
        unknown.add(a);
        continue;
      }
      final k = a.substring(0, i).replaceAll('--', '');
      final v = a.substring(i + 1);
      switch (k) {
        case 'types':
          types = v;
        case 'device':
          device = v;
        case 'avd':
          avd = v;
        case 'adb':
          adb = v;
        case 'flutter':
          flutter = v;
        case 'manifest':
          manifest = v;
        case 'matrix':
          matrix = v;
        case 'gpu':
          gpu = v;
        case 'build':
          build = v;
        default:
          // 打错一个字母的 `--devcie=` 若被静默丢掉，下一步就是"自动挑设备"——
          // 那正是最不该发生静默回退的地方。
          unknown.add(a);
      }
    }
  }
  String? types;
  String? device;
  String? avd;
  String? adb;
  String? flutter;
  String? gpu;
  String? build;

  /// 默认 false：真机路线必须显式写出来（见 _send 里那段注释）。
  bool keepEmulator = false;
  bool allowRealDevice = false;
  final List<String> unknown = [];
  String manifest = _defaultManifest;
  String matrix = _defaultMatrix;
}
