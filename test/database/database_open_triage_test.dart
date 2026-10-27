import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_open_triage.dart';

import '../support/source_guards.dart';

/// T199：开库异常的分诊。
///
/// 这条判据要回答的不是“异常有没有发生”，而是**能不能把健康库改名重建**。
/// 旧代码把所有异常都当损坏；这里逐条钉住“哪些像文件坏了、哪些绝对不像”。
void main() {
  group('DatabaseOpenTriage｜只有文件坏了才允许备份重建', () {
    test('SQLCipher 认不出的库 / 磁盘映像损坏 ⇒ corruption', () {
      expect(
        DatabaseOpenTriage.classify(StateError('file is not a database')),
        DatabaseOpenFailureKind.corruption,
      );
      expect(
        DatabaseOpenTriage.classify(
          StateError('database disk image is malformed'),
        ),
        DatabaseOpenFailureKind.corruption,
      );
      expect(
        DatabaseOpenTriage.classify(
          StateError('file is encrypted or is not a database'),
        ),
        DatabaseOpenFailureKind.corruption,
      );
    });

    test('反馈里的类型转换错误 ⇒ unavailable（绝不清库）', () {
      final error = StateError(
        "type 'SqfliteSqlCipherOpenDatabaseOptions' is not a subtype of "
        "type 'OpenDatabaseOptions'",
      );
      expect(
        DatabaseOpenTriage.classify(error),
        DatabaseOpenFailureKind.unavailable,
      );
    });

    test('迁移 SQL 写错（duplicate column / no such table）⇒ unavailable', () {
      for (final message in [
        'duplicate column name: sub_text',
        'no such table: fnthink_messages',
      ]) {
        expect(
          DatabaseOpenTriage.classify(StateError(message)),
          DatabaseOpenFailureKind.unavailable,
          reason: '迁移 SQL 错误被当成库损坏会直接清掉用户历史：$message',
        );
      }
    });

    test('锁库 / 权限 / 磁盘打不开 ⇒ unavailable（可重试，不是损坏）', () {
      for (final message in [
        'database is locked',
        'unable to open database file',
      ]) {
        expect(
          DatabaseOpenTriage.classify(StateError(message)),
          DatabaseOpenFailureKind.unavailable,
          reason: '暂时性/环境问题不许触发改名：$message',
        );
      }
    });

    test('认不出的异常按 unavailable 处理（保留原库是可逆选择）', () {
      expect(
        DatabaseOpenTriage.classify(StateError('something new from a plugin')),
        DatabaseOpenFailureKind.unavailable,
      );
      expect(DatabaseOpenTriage.isCorruption(StateError('boom')), isFalse);
    });
  });

  group('DatabaseHealth｜诊断计数', () {
    setUp(() {
      DatabaseHealth.openFailures = 0;
      DatabaseHealth.lastOpenError = null;
      DatabaseHealth.writeFailures = 0;
      DatabaseHealth.lastWriteError = null;
    });

    test('打开失败与写失败分开计数，快照带最后一条', () {
      DatabaseHealth.recordOpenFailure(StateError('open-a'));
      DatabaseHealth.recordOpenFailure(StateError('open-b'));
      DatabaseHealth.recordWriteFailure(StateError('write-a'));

      final snap = DatabaseHealth.snapshot();
      expect(snap['openFailures'], 2);
      expect(snap['writeFailures'], 1);
      expect(snap['lastOpenError'], contains('open-b'));
      expect(snap['lastWriteError'], contains('write-a'));
    });

    test('clearOpenFailure 只清打开那一族，不动写失败', () {
      DatabaseHealth.recordOpenFailure(StateError('open'));
      DatabaseHealth.recordWriteFailure(StateError('write'));
      DatabaseHealth.clearOpenFailure();

      expect(DatabaseHealth.openFailures, 0);
      expect(DatabaseHealth.lastOpenError, isNull);
      expect(DatabaseHealth.writeFailures, 1);
    });
  });

  group('源码守卫｜分诊必须在备份重建之前，页面必须有重试', () {
    final root = projectRoot();

    test('_initDatabase 先分诊再备份；非损坏异常直接抛 DatabaseUnavailable', () {
      final src = File('$root/lib/database/database_helper.dart')
          .readAsStringSync();
      final triage = src.indexOf('DatabaseOpenTriage.isCorruption(e)');
      expect(triage, greaterThan(0), reason: '找不到分诊 ⇒ 这条守卫在空转');
      // 必须只看**这个 catch 块**：同文件前面的密钥丢失分支也有一次备份，
      // 拿全文第一个 _backupDatabaseFile 会把两段无关的代码比较成红。
      final catchStart = src.lastIndexOf('} catch (e) {', triage);
      expect(catchStart, greaterThan(0), reason: '找不到分诊所在的 catch 块');
      final block = src.substring(catchStart, catchStart + 1400);
      final localTriage = block.indexOf('DatabaseOpenTriage.isCorruption(e)');
      final localBackup = block.indexOf('_backupDatabaseFile(encryptedPath)');
      expect(localBackup, greaterThan(0), reason: '分诊块里找不到备份调用');
      expect(localTriage, lessThan(localBackup), reason: '分诊必须在备份之前；先备份就等于旧行为');
      expect(
        src.contains('throw DatabaseUnavailableException(e)'),
        isTrue,
        reason: '非损坏异常必须抛显式错误，不能落进重建分支',
      );
      expect(
        src.contains('DatabaseHealth.recordOpenFailure(e)'),
        isTrue,
        reason: '打开失败必须进诊断计数，否则页面只看到一句“打不开”',
      );
      expect(
        '_write('.allMatches(src).length,
        greaterThanOrEqualTo(3),
        reason: '写失败计数不能是死字段：三条核心写路径必须走同一个包手',
      );
    });

    test('两条重建分支都先让原生通道失效，普通重试不失效', () {
      final src = stripComments(
        File('$root/lib/database/database_helper.dart').readAsStringSync(),
      );
      final init = blockAfter(src, 'Future<Database> _initDatabase() async');
      expect('_invalidateNativeChannels();'.allMatches(init).length, 2);

      final keyLost = init.indexOf('on DatabaseKeyLostException');
      final keyInvalidate = init.indexOf(
        '_invalidateNativeChannels();',
        keyLost,
      );
      final keyBackup = init.indexOf(
        '_backupDatabaseFile(encryptedPath)',
        keyLost,
      );
      expect(keyLost, greaterThan(0));
      expect(keyInvalidate, greaterThan(keyLost));
      expect(keyBackup, greaterThan(keyInvalidate));

      final triage = init.indexOf('DatabaseOpenTriage.isCorruption(e)');
      final corruptInvalidate = init.indexOf(
        '_invalidateNativeChannels();',
        triage,
      );
      final corruptBackup = init.indexOf(
        '_backupDatabaseFile(encryptedPath)',
        triage,
      );
      expect(triage, greaterThan(0));
      expect(corruptInvalidate, greaterThan(triage));
      expect(corruptBackup, greaterThan(corruptInvalidate));

      final retry = blockAfter(src, 'Future<Database> retryOpen() async');
      expect(retry.contains('_invalidateNativeChannels'), isFalse);
    });

    test('原生失效失败必须按 DatabaseUnavailable 中止重建', () {
      final src = stripComments(
        File('$root/lib/database/database_helper.dart').readAsStringSync(),
      );
      final helper = blockAfter(
        src,
        'Future<void> _invalidateNativeChannels() async',
      );
      expect(helper.contains('await invalidateNativeChannelMirrors()'), isTrue);
      expect(helper.contains('DatabaseHealth.recordOpenFailure(e)'), isTrue);
      expect(helper.contains('throw DatabaseUnavailableException(e)'), isTrue);
    });

    test('主页面把 DatabaseUnavailable 显式弹出来并给重试入口', () {
      final src = File('$root/lib/pages/main_page.dart').readAsStringSync();
      expect(src.contains('e is DatabaseUnavailableException'), isTrue);
      expect(src.contains('DatabaseHelper().retryOpen()'), isTrue);
      expect(
        src.contains('IosDialogActions.askConfirm('),
        isTrue,
        reason: '不许在页面里手搭第二枚 CupertinoAlertDialog；走公共确认框',
      );
      expect(src.contains('l10n.databaseUnavailableTitle'), isTrue);
    });
  });
}
