import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T135 那枚「主通道不可用时自动切到备用通道」开关，与自动切回那一条的形状契约。
///
/// 为什么这一族需要守卫而不是"改完就算"：
/// - 那枚开关的**默认值**住在三处、跨两种语言（Dart 的 prefs 回退、原生 `getBoolean` 的回退、
///   页面字段初值）。只改 Dart 的话：原生在家没写过 prefs 时按另一档处理，表现就是
///   "界面上开着，而这一台从来不自动切" —— 与短信那一族（`sms_default_off_test`）同一个形状，
///   那次是四处，这次是三处。
/// - 键名也跨语言：Dart 写裸键 `channel_auto_backup`，Flutter 插件落盘时加 `flutter.` 前缀，
///   原生读的是带前缀那一份。两侧各写一份字符串，改一侧没有任何编译期报错。
/// - 「连续几次成功才切回」那个数只有**一个作者**（原生判据 `RECOVERY_SUCCESS_COUNT`）。
///   界面上那句"连续 3 次探测成功后会自动回到主通道"必须是它带过来的，抄一份就会在判据改动时
///   继续念旧的那个数 —— 而那是用户据以判断"我这台什么时候会自己好"的唯一一句话。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  /// 取出 `path` 里**包含** `needle` 的那一行；断言它恰好出现一次，返回该行文本。
  String lineOf(String path, String needle, {required String why}) {
    final f = File('$root/$path');
    expect(f.existsSync(), isTrue, reason: '读不到 $path ⇒ 本条在空转（$why）');
    final hits = f
        .readAsStringSync()
        .split('\n')
        .where((l) => l.contains(needle))
        .toList();
    expect(
      hits.length,
      1,
      reason:
          '$path 里「$needle」命中 ${hits.length} 次，应为 1 次（$why）'
          ' —— 锚点不唯一时"读到 true"毫无意义，先修锚点。',
    );
    return hits.first.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  group('自动切备开关的默认值：三处都是开', () {
    test('① Dart prefs 缺键回退是开（升级后没人动过开关 ⇒ 照今天那样自动切）', () {
      final l = lineOf(
        'lib/services/backup_mode.dart',
        'getBool(autoBackupPrefKey)',
        why: '缺键回退',
      );
      expect(
        l,
        contains('?? true'),
        reason: '缺键回退成关：这一版一上线，所有人的自动切备同时消失（而他没碰过任何开关）',
      );
    });

    test('② 原生读的那一份默认也是开（跨语言不能只改 Dart）', () {
      final l = lineOf(
        'android/app/src/main/kotlin/com/fnthink/notice/ChannelAvailability.kt',
        'getBoolean(KEY_AUTO_BACKUP,',
        why: '原生默认值',
      );
      expect(
        l,
        contains(', true)'),
        reason: '原生默认按关处理 ⇒ 屏幕上写着"开"，而路由从不切备（只有读侧的界面知道用户的意思）',
      );
    });

    test('③ 页面字段初值是开（读到 prefs 之前不许画成"关"）', () {
      final l = lineOf(
        'lib/pages/channel_status_page.dart',
        'bool _autoBackup =',
        why: '弹层那枚开关的初值',
      );
      expect(
        l,
        contains('= true'),
        reason: '初值画成关就是在用户没做过的决定上先替他做了一个（还顺带把"关掉会怎样"那句冒出来）',
      );
    });

    test('键名两侧同一个（Dart 裸键 + 原生带 flutter. 前缀那一份）', () {
      final dartLine = lineOf(
        'lib/services/backup_mode.dart',
        "autoBackupPrefKey = '",
        why: 'Dart 侧键名',
      );
      final ktLine = lineOf(
        'android/app/src/main/kotlin/com/fnthink/notice/ChannelAvailability.kt',
        'KEY_AUTO_BACKUP =',
        why: '原生侧键名',
      );
      final bare = RegExp(r"=\s*'([^']+)'").firstMatch(dartLine)!.group(1);
      final prefixed = RegExp(r'=\s*"([^"]+)"').firstMatch(ktLine)!.group(1);
      expect(
        prefixed,
        'flutter.$bare',
        reason: '两侧不是同一把键 ⇒ 用户在界面上关掉的，原生读的是另一把',
      );
    });
  });

  group('切回那个次数只有一个作者', () {
    test('原生把判据里那个数随 getBackupMode 一起回', () {
      final l = lineOf(
        'android/app/src/main/kotlin/com/fnthink/notice/channels/ConfigChannelHandler.kt',
        '"recoveryCount" to',
        why: '那个数从判据带到界面',
      );
      expect(
        l,
        contains('ChannelRouting.RECOVERY_SUCCESS_COUNT'),
        reason: '在这里写死一个数 = 判据与用户读到的那句话分家',
      );
    });

    test('判据自己认的那个常量还在（提取失效不得让上一条空转）', () {
      final l = lineOf(
        'android/app/src/main/kotlin/com/fnthink/notice/ChannelRouting.kt',
        'const val RECOVERY_SUCCESS_COUNT =',
        why: '阈值住处',
      );
      expect(
        RegExp(r'RECOVERY_SUCCESS_COUNT = \d+').hasMatch(l),
        isTrue,
        reason: '取不到一个数字 ⇒ 上面那条在比一个不存在的符号',
      );
    });

    test('lib 里不许出现抄下来的那个次数（"连续 3 次"这类字面量一个都不许有）', () {
      // 尺的口径刻意宽到"连续 N 次"这一族说法：判据是"界面上的那个数必须来自原生"，
      // 收窄到某一句现文案就会放过下一处新抄本（本仓栽过两次：提取式收窄 ⇒ 差集恒空 ⇒ 恒绿）。
      final hits = <String>[];
      for (final f in Directory(
        '$root/lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path
            .replaceAll(r'\', '/')
            .substring(root.replaceAll(r'\', '/').length + 1);
        if (rel.contains('/l10n/')) continue; // 词条表本身不是"作者"
        if (RegExp(r'连续\s*\d+\s*次').hasMatch(f.readAsStringSync())) {
          hits.add(rel);
        }
      }
      expect(
        hits,
        isEmpty,
        reason: '这几处把次数写死在了 Dart 里：$hits ⇒ 判据改了，屏幕上还念旧的那个数',
      );
    });
  });

  group('切回的证据不能被探测那一侧断供', () {
    test('探测那条链里读不到"备用模式"这件事', () {
      // 锁存期主通道不再被发送 ⇒ 探测是"主又可用了"的唯一生产者。
      // 一旦有人在候选构造里加一句"锁存了就只探备用"，切回判据就永远等不到新读数，
      // 而屏幕上什么异常都不会报（这正是 T135 那一行原话记错的那一格）。
      final src = read('lib/services/active_channels.dart');
      for (final forbidden in ['engaged', 'BackupMode', 'backup_mode']) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason:
              '探测候选开始看那份锁存了（出现 $forbidden）⇒ 降级期间主通道不再被探，'
              '自动切回从此没有读数可用（候选集合与角色无关这一条由服务用例钉住）',
        );
      }
    });

    test('备用模式这一格的读口只有一个（页面不自己 invokeMethod）', () {
      final page = read('lib/pages/channel_status_page.dart');
      expect(
        page.contains('invokeMethod'),
        isFalse,
        reason: '页面自己调原生就长出第二份"这台切没切备用"的读法（BackupMode 是那一格唯一的读口）',
      );
      final service = read('lib/services/backup_mode.dart');
      expect(
        RegExp(r"invokeMethod<dynamic>\('getBackupMode'\)").hasMatch(service),
        isTrue,
        reason: '读口那发没了 ⇒ 上一条"页面不许 invokeMethod"就成了恒真的空守卫',
      );
    });
  });
}
