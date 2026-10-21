import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T145 片1：「本机通知触发」这一路新加的两道闸，**只有一个作者、一条交接**。
///
/// ## 为什么这本账值得存在
/// 维护者 2026-10-12 裁定 4 要的是两颗：那颗开关 + 「哪些应用的通知才允许」。这一族最坏的两个形状：
///  1. **默认值住两处**（Dart 一份 `?? false`、Kotlin 一份 `?: false`）—— 改一处时行为按
///     哪条链先跑而变。短信监听那一路为这一条写了六条守卫才钉住（`sms_default_off_test`）。
///     ⇒ 本片的取舍：判定整个收在 Dart 一处，原生**只交数据不判**（`offer` 带包名，取口原样交出）。
///  2. **交接不带包名** —— 那一判唯一的输入就是包名，丢了它的后果不是"少一道闸"，而是
///     fail-closed 成"谁都不许"：界面写着已开启、实际一条都不触发，而没人知道为什么。
///     ⇒ 所以 ③ 按"三处形状"钉，不按"有没有测试覆盖"钉。
///
/// ⚠ 读源码一律剥注释（`stripComments`）：注释里的键名不是代码里的键名（这一族本仓撞过 4 次）。
void main() {
  final root = projectRoot();

  const kTriggerKeyLiterals = [
    'fnthink.remote_execution.local_trigger_enabled',
    'fnthink.remote_execution.local_trigger_mode',
    'fnthink.remote_execution.local_trigger_packages',
  ];
  const kTriggerReasons = ['local-trigger-off', 'app-not-allowed'];

  Set<String> filesWith(String needle) => {
    for (final entry in libCodeByRel(root).entries)
      if (entry.value.contains(needle)) entry.key,
  };

  /// 整棵 `android/app/src/main` 的 Kotlin 源（剥注释）。
  /// ⚠ 刻意不逐个文件点名：只查四份的话，第五份新文件读这三个键就绕过了。
  List<File> androidKotlinFiles() =>
      Directory('$root/android/app/src/main')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt'))
          .toList();

  Map<String, String> androidKotlinSources() => {
    for (final f in androidKotlinFiles())
      f.path.replaceAll(r'\', '/').split('/').last: stripComments(
        f.readAsStringSync(),
      ),
  };

  String androidSourceNamed(String fileName) {
    final found = androidKotlinSources()[fileName];
    expect(found, isNotNull, reason: '$fileName 读不到 —— 这一条守卫在量不存在的东西');
    return found!;
  }

  /// ③ 用的尺：原生 `offer(` 的调用点**与它的参数段**。
  /// 口径不写成"文件里有没有 `packageName` 字样" —— 那样任何位置出现都算命中，
  /// 把交接那一发摘掉也照样绿。
  List<String> offerCallSites(String kotlinSource) => RegExp(
    r'LocalRemoteCommandInbox\.offer\(([^;]*?)\)',
    dotAll: true,
  ).allMatches(kotlinSource).map((m) => m.group(1)!.trim()).toList();

  test('① 三份 prefs 键名在 Dart 只有一个作者，且整棵原生都不读（默认值只住一处）', () {
    for (final key in kTriggerKeyLiterals) {
      expect(
        filesWith(key),
        {'services/fnthink_remote_settings.dart'},
        reason:
            '$key 的字面量出现在多处 ⇒ 那颗开关的默认值就有两个作者，'
            '而"同一颗开关两处·跨两种语言"这一族在本仓砸过脚',
      );
    }
    final joined = androidKotlinSources().values.join('\n');
    expect(
      joined.contains('local_trigger'),
      isFalse,
      reason:
          '原生开始读这三个键 ⇒ 默认值变成两处；这一路要加闸也应该把包名交回 Dart 判'
          '（本片就是这么接的）',
    );
  });

  test('② 那两枚理由串：造它的位置只有一处，翻它的位置也只有一处', () {
    // 钉的是**角色**，不是"字面量全库只许出现一次"：T144 片2 之后那张人话表必须按 key 引用这两枚，
    // 把表也算成"第二个作者"，就是让守卫去挡正确做法（本仓砸过的"钉写法不钉结构"）。
    // 两头的坏形状各自有牙：多出第三处字面量 ⇒ 差集对不上；表里漏了这一枚 ⇒ 屏上落机器词。
    const producer = 'services/fnthink_remote_command_handler.dart';
    const reader = 'services/fnthink_remote_reason_words.dart';
    for (final reason in kTriggerReasons) {
      expect(
        filesWith("'$reason'"),
        {producer, reader},
        reason:
            '$reason 的字面量应当只有两处：判定层**造**这条拒绝、人话表**翻**它。'
            '多一处 = 第三个作者；表那一处没了 = 这一枚在屏上是机器词',
      );
      final produced = stripComments(librarySource(root, 'lib/$producer'));
      expect(
        RegExp("RemoteCommandRejected\\([\\s\\S]{0,120}?'$reason'")
            .hasMatch(produced),
        isTrue,
        reason: '$reason 不在"造拒绝"那一段里 ⇒ 它变成页面自己造的第二个理由',
      );
      final table = stripComments(librarySource(root, 'lib/$reader'));
      expect(
        RegExp("'$reason':\\s*\\(l\\)").hasMatch(table),
        isTrue,
        reason: '表里那一枚不是表项形状 ⇒ 翻译那一路其实没接上（引用只写在注释里）',
      );
    }
  });

  test('③ 交接带着包名走：原生交出、通道回那一格、Dart 读那一格', () {
    final calls = offerCallSites(
      androidSourceNamed('NotificationMonitorService.kt'),
    );
    expect(
      calls,
      hasLength(1),
      reason: '白名单那一路的交接应当只有一个出口 —— 多一处就多一处"只交正文不交包名"的可能',
    );
    expect(
      calls.single.contains('packageName'),
      isTrue,
      reason:
          '那一发没交包名 ⇒ 判定层的「哪些应用才允许」永远读到空串 ⇒ '
          '整条路 fail-closed 成"谁都不许"，而界面上写着已开启',
    );
    expect(
      androidSourceNamed('RemoteExecChannelHandler.kt')
          .contains('"package" to'),
      isTrue,
      reason: '取口不再回那一格 ⇒ Dart 侧只会把它当"现在没有指令"',
    );
    expect(
      stripComments(
        librarySource(root, 'lib/services/remote_execution_notifier.dart'),
      ).contains("raw['package']"),
      isTrue,
      reason: 'Dart 侧不读那一格 ⇒ 包名在走到判定层之前就被丢了（同一条链两个断点）',
    );
  });

  test('④ offer 的包名那一格不许有默认值（新加一路交接必须自己交）', () {
    final params = RegExp(
      r'fun offer\(([^)]*)\)',
      dotAll: true,
    ).firstMatch(androidSourceNamed('LocalRemoteCommandInbox.kt'))!.group(1)!;
    expect(
      params.contains('packageName: String? ='),
      isFalse,
      reason:
          '给了默认值，下一处 `offer(content, at)` 就编译得过而**不交包名** —— '
          '这一族的失败形状永远是"静默降级"，不是"当场报错"',
    );
  });

  test('⑤ 尺认得合成样本（防 ③④ 退化成"恒不匹配＝恒绿"）', () {
    const multiLine =
        'LocalRemoteCommandInbox.offer(\n'
        '    info.content,\n'
        '    info.packageName,\n'
        ')';
    const bodyOnly = 'LocalRemoteCommandInbox.offer(info.content)';
    expect(offerCallSites(multiLine), hasLength(1));
    expect(offerCallSites(multiLine).single.contains('packageName'), isTrue);
    // 摘掉包名那一发：调用点仍在、参数段里没有 packageName ⇒ ③ 那一发才会红。
    expect(offerCallSites(bodyOnly), hasLength(1));
    expect(offerCallSites(bodyOnly).single.contains('packageName'), isFalse);
    const defaulted =
        'fun offer(content: String?, packageName: String? = null): Boolean';
    expect(
      RegExp(r'fun offer\(([^)]*)\)')
          .firstMatch(defaulted)!
          .group(1)!
          .contains('packageName: String? ='),
      isTrue,
      reason: '④ 的坏形状认不出来 ⇒ 那条守卫拦的是不存在的事',
    );

    // ② 的两把尺：「造拒绝」那一段 + 词表项的形状。各给一正一反，
    // 反例是"字面量在场但角色不对"—— 那正是 ② 要放走/拦住的分界。
    final rejects = RegExp(
      "RemoteCommandRejected\\([\\s\\S]{0,120}?'switch-off'",
    );
    expect(
      rejects.hasMatch(
        "return RemoteCommandRejected(\n  command,\n  sender,\n  'switch-off',\n  source,\n);",
      ),
      isTrue,
      reason: '多行形状认不出来 ⇒ ② 的"造拒绝"那一判恒红，把正确写法也挡了',
    );
    expect(
      rejects.hasMatch("final reason = 'switch-off';\n  save(reason);"),
      isFalse,
      reason: '随便一处引用也算"造拒绝" ⇒ 页面自己造第二个理由时 ② 不会红',
    );
    final tableEntry = RegExp("'switch-off':\\s*\\(l\\)");
    expect(
      tableEntry.hasMatch("  'switch-off': (l) => l.remoteReasonSwitchOff,"),
      isTrue,
      reason: '表项形状认不出来 ⇒ "翻译那一路其实没接上"这一判恒红',
    );
    expect(
      tableEntry.hasMatch("  const switchOff = 'switch-off';"),
      isFalse,
      reason: '裸常量也算表项 ⇒ 词表没这一枚时 ② 也照样绿',
    );
  });
}
