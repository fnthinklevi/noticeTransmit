import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_recovery.dart';
import 'package:path/path.dart' as p;

void main() {
  group('T199 ②：旧库备份文件判据', () {
    test('只认 .corrupt-* 两种文件名，主库与回滚副本不算', () {
      const encrypted = 'notice_transmit_encrypted.db';
      const legacy = 'notice_transmit.db';
      expect(
        DatabaseRecovery.isBackupFileName('$encrypted.corrupt-123'),
        isTrue,
      );
      expect(DatabaseRecovery.isBackupFileName('$legacy.corrupt-123'), isTrue);
      expect(DatabaseRecovery.isBackupFileName(encrypted), isFalse);
      expect(
        DatabaseRecovery.isBackupFileName('$encrypted.before-restore-123'),
        isFalse,
      );
      expect(DatabaseRecovery.isBackupFileName('random.db'), isFalse);
    });

    test('大小与时间只说人话', () {
      expect(DatabaseRecovery.formatBytes(512), '512 B');
      expect(DatabaseRecovery.formatBytes(2048), '2.0 KB');
      expect(DatabaseRecovery.formatBytes(3 * 1024 * 1024), '3.0 MB');
      expect(
        DatabaseRecovery.formatMoment(DateTime(2026, 1, 2, 3, 4)),
        '2026-01-02 03:04',
      );
    });
  });

  group('T199 ②：最新备份选择', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('db_recovery_');
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> write(String name, DateTime modifiedAt) async {
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(const [1, 2, 3]);
      await file.setLastModified(modifiedAt);
    }

    test('按修改时间取最新的一份，忽略主库与回滚副本', () async {
      await write(
        'notice_transmit_encrypted.db.corrupt-1000',
        DateTime(2026, 1, 1),
      );
      await write(
        'notice_transmit_encrypted.db.corrupt-2000',
        DateTime(2026, 1, 2),
      );
      await write('notice_transmit_encrypted.db', DateTime(2026, 1, 3));
      await write(
        'notice_transmit_encrypted.db.before-restore-3000',
        DateTime(2026, 1, 4),
      );

      final latest = await DatabaseRecovery(databasesPath: () async => dir.path)
          .latestBackup();

      expect(latest, isNotNull);
      expect(latest!.fileName, 'notice_transmit_encrypted.db.corrupt-2000');
      expect(latest.sizeBytes, 3);
    });

    test('没有备份时返回 null', () async {
      await write('notice_transmit_encrypted.db', DateTime(2026, 1, 1));
      final latest = await DatabaseRecovery(databasesPath: () async => dir.path)
          .latestBackup();
      expect(latest, isNull);
    });
  });
}
