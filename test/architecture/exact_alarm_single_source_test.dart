import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T140 走 (c)：精确闹钟**只剩系统授权这一枚真值**。
///
/// 来历（维护者 2026-10-14 拍）：这一族此前有**两个**读数被当成一枚用 ——
/// 设置页那枚 App 内开关（一个写在 Flutter 共享偏好里的布尔，**默认关**）与系统授权
/// （`AlarmManager.canScheduleExactAlarms()`）。三处排闹钟的代码读的是偏好，
/// 权限页那一行画的却是授权，于是「已授权」与「到点晚几分钟」会同时成立：
/// 两句各自都不算假，合起来是一句假话（而契约对常态收取承诺的是 5–60 秒）。
/// 裁定是删掉 App 内那枚开关，唯一真值＝系统授权；本守卫钉的是**这个现状不许漂回去**。
///
/// 为什么值得一条守卫而不是改完就走：被删掉的那枚开关是一个**看起来合理的功能**
/// （"让用户自己决定要不要准点"），下一次有人加回来时不会想到这里曾撤过。
///
/// 钉四件事，每件都是不同主语，外加一条反向自检：
///  ① 那枚开关零落笔 —— 偏好键名与两枚通道方法名，在**会跑的那三面**（原生 main /
///     Dart lib / 集成测试）里一处都不许有。
///  ② 每一处排精确闹钟的 Kotlin 代码都必须问那个唯一作者 —— 判据是**派生**的：
///     谁调 `setExactAndAllowWhileIdle(`，谁就得同时调 `ExactAlarmPolicy.allowed(`。
///     这样"新增长出的第四处闹钟"会被自动管住，不必再补一条"名单里加一行"。
///  ③ 唯一作者读的是系统授权，不是本地偏好 —— 它一旦去读 SharedPreferences，
///     开关就换了个地方长回来，而 ① 看不见（键名可以不一样）。
///  ④ 通道侧那份也转交同一作者 —— 界面报的与排闹钟读的必须同一个表达式，
///     否则 ③ 修好了 ① 也还回来的还是"两句话"那个形状。
///  ⑤ 反向自检：扫描真的覆盖到了那几处（防路径写错时"零命中"是空集假绿、
///     也防 `stripComments` 本身坏掉把代码剥成空串）。
void main() {
  final root = projectRoot();

  /// 会跑的三面：原生 main、Dart lib、集成测试。
  /// `test/` 刻意不在内 —— 守卫自己要写出被禁的字面量，把尺扫到自己身上就恒红了。
  final scannedDirs = <String>[
    '$root/android/app/src/main',
    '$root/lib',
    '$root/integration_test',
  ];

  List<File> sourceFiles() {
    final out = <File>[];
    for (final dir in scannedDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      out.addAll(
        d.listSync(recursive: true).whereType<File>().where((f) {
          final p = f.path.replaceAll('\\', '/');
          return p.endsWith('.kt') || p.endsWith('.dart');
        }).toList(),
      );
    }
    return out;
  }

  final files = sourceFiles();

  String relOf(File f) =>
      f.path.replaceAll('\\', '/').substring(root.length + 1);

  /// 命中位置逐个点名到 文件:行 —— 只报"有 N 处"的话，改的人不知道该看哪一行。
  /// 剥注释：注释里提到那个开关（本文档就写了它）≠ 代码在读它。
  List<String> hitsOf(String token) {
    final hits = <String>[];
    for (final f in files) {
      final stripped = stripComments(f.readAsStringSync());
      final rel = relOf(f);
      final lines = stripped.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains(token)) hits.add('$rel:${i + 1}');
      }
    }
    return hits;
  }

  String readKotlin(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  const policyRel =
      'android/app/src/main/kotlin/com/fnthink/notice/ExactAlarmPolicy.kt';
  const callersRel =
      'android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt';

  /// 现在排精确闹钟的三处（延迟推送／聚合推送／幻念收货闹钟）。
  const alarmSites = <String>[
    'android/app/src/main/kotlin/com/fnthink/notice/DelayedPushManager.kt',
    'android/app/src/main/kotlin/com/fnthink/notice/MergePushManager.kt',
    'android/app/src/main/kotlin/com/fnthink/notice/FnthinkPresenceAlarm.kt',
  ];

  group('T140 (c)｜精确闹钟只剩系统授权一枚真值', () {
    test('① 那枚 App 内开关零落笔（偏好键名 + 两枚通道方法名）', () {
      for (final token in [
        'exact_alarm_enabled',
        'isExactAlarmEnabled',
        'setExactAlarmEnabled',
      ]) {
        expect(
          hitsOf(token),
          isEmpty,
          reason:
              '$token 又出现在会跑的代码里了。这一族撤掉的正是"两枚读数当一枚用"：'
              '排闹钟读偏好、界面画授权 ⇒ 用户看到「已授权」而到点晚几分钟。'
              '要恢复开关必须先回答"界面那一句由谁负责"，与维护者另行定稿，'
              '并同步 ③④ 与本文件（别只删这条断言）。',
        );
      }
    });

    test('② 每一处排精确闹钟的代码都问那个唯一作者', () {
      // 派生判据：以"谁调了 setExactAndAllowWhileIdle"为准，而不是抄一份文件名单——
      // 名单会漏掉新长出的那一处，而漏掉的那处就是在自己判定。
      final schedulers = files
          .where((f) => relOf(f).endsWith('.kt'))
          .where(
            (f) => stripComments(
              f.readAsStringSync(),
            ).contains('setExactAndAllowWhileIdle('),
          )
          .map(relOf)
          .toSet();
      final notAsking =
          schedulers
              .where(
                (rel) => !readKotlin(rel).contains('ExactAlarmPolicy.allowed('),
              )
              .toList()
            ..sort();
      expect(
        notAsking,
        isEmpty,
        reason:
            '这些文件排了精确闹钟却没问唯一作者：$notAsking。'
            '自己判一次就多长出一份判定，下一次改动只会改到其中一处。',
      );
    });

    test('③ 唯一作者读的是系统授权，不是本地偏好', () {
      final policy = File('$root/$policyRel');
      expect(policy.existsSync(), isTrue, reason: '作者不在了 ⇒ ② 的"都问它"退化成一句空话');
      final body = stripComments(policy.readAsStringSync());
      expect(
        body,
        contains('canScheduleExactAlarms'),
        reason:
            '这一枚判定的本体必须是系统授权（AlarmManager.canScheduleExactAlarms）。'
            '换成别的来源（写死的 true、厂商判断）就不是"界面画的＝排闹钟读的"了。',
      );
      expect(
        body,
        isNot(contains('SharedPreferences')),
        reason: '作者去读偏好 ⇒ 开关只是换了个地方长回来，而 ① 那三个键名看不见它。',
      );
      expect(
        body,
        contains('Build.VERSION_CODES.S'),
        reason:
            'Android 12 以下没有 SCHEDULE_EXACT_ALARM 这一档，恒为可排；'
            '少了这一层判断，12 以下的机器会被当成"没授权"而全都走非精确。',
      );
    });

    test('④ 通道侧那份也转交同一作者（界面报的＝排闹钟读的）', () {
      expect(
        readKotlin(callersRel),
        contains('ExactAlarmPolicy.allowed('),
        reason:
            'MainActivity 若自己内联一份 `AlarmManager.canScheduleExactAlarms()`，'
            '就又是两个表达式：③ 修好了、① 也会跟着长回来。'
            '这一条钉的是"界面那一行报出去的那一份，与三处闹钟读的那一份同源"。',
      );
    });

    test('⑤ 反向自检：扫描真的覆盖到那几处（防空集假绿）', () {
      expect(files, isNotEmpty, reason: '一个源文件都没扫到 ⇒ ① 恒真');
      // 覆盖面必须包含**将来最可能消费它的那一层**：原生 main 里的闹钟代码。
      final rels = files.map(relOf).toList();
      for (final rel in alarmSites) {
        expect(
          rels,
          contains(rel),
          reason: '扫描范围里少了 $rel ⇒ ① 的"零命中"是量尺没伸到，不是约束成立。',
        );
      }
      // 剥注释管线本身也得还活着：拿一个**只在代码里出现**的标识符当探针。
      final delayed = File('$root/${alarmSites.first}').readAsStringSync();
      expect(
        stripComments(delayed),
        contains('ACTION_PUSH_DUE'),
        reason: '探针取不到 ⇒ stripComments 把代码也剥掉了，此时 ①② 的"零命中"全是假的。',
      );
    });
  });
}
