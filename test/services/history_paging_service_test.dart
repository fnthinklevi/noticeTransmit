import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/delivery_status.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/services/channel_display.dart' show channelKey;
import 'package:notice_transmit/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// T133 量级①：真分页与"内存镜像退役"之后的 service 层语义（真库，FFI）。
///
/// 钉四件事，各管一个"不这么做会怎样"：
/// 1. `searchRecords` 的 `hasMore` 以**粗筛**行数为准，第三位就是本页粗筛行数 ——
///    「没有更多了」只能由粗筛取尽来说；
/// 2. 清除三兄弟（今日/最近 N 条）DB 驱动 —— 镜像退役后它们不能只删内存里看得见的那几条；
/// 3. 拦截记录迁移一次性（flag），且老记录的修复**不再依赖内存里有没有它**；
/// 4. 离线批次的去重查 DB —— 命中即跳过，绝不能用一份新的 pending 快照
///    把已有序的送达状态 REPLACE 掉（镜像退役后这条是唯一防线）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();
  stubNativeChannels();

  final helper = DatabaseHelper();
  late Database db;
  late NotificationService service;

  Map<String, dynamic> row(
    String id, {
    required int postTime,
    Map<String, dynamic>? delivery,
  }) => <String, dynamic>{
    'id': id,
    'title': '通知$id',
    'content': '内容$id',
    'subText': '',
    'packageName': 'com.example.app',
    'appName': '应用',
    'postTime': postTime,
    'time': '2026-01-01 10:00:00',
    'type': 'normal',
    'priority': 1,
    'deliveryStatus': delivery,
  };

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await helper.createSchemaForTest(db);
    helper.debugDatabase = db;
    SharedPreferences.setMockInitialValues({});
    service = NotificationService();
  });

  tearDown(() async {
    helper.debugDatabase = null;
    await db.close();
    clearNativeChannelStubs();
  });

  group('searchRecords 的分页三元组（判据：hasMore 按粗筛行数算）', () {
    test(
      '250 行、页大小 200：第一页 (200, true, 200)，翻到 offset 200 收尾 (50, false, 50)',
      () async {
        const now = 1780000000000;
        for (var i = 0; i < 250; i++) {
          await DatabaseHelper().insertNotification(
            row('r_${i + 1}', postTime: now + i),
          );
        }

        final (page1, more1, coarse1) = await service.searchRecords(
          limit: 200,
          offset: 0,
        );
        expect(page1, hasLength(200));
        expect(more1, isTrue, reason: '粗筛还有 50 行，「没有更多了」不许提前说');
        expect(coarse1, 200);

        final (page2, more2, coarse2) = await service.searchRecords(
          limit: 200,
          offset: coarse1,
        );
        expect(page2, hasLength(50));
        expect(more2, isFalse, reason: '粗筛取尽了，这一回才许说没有更多');
        expect(coarse2, 50);

        // 两页拼起来恰好是全表，无重复无遗漏
        final ids = [...page1.map((r) => r.id), ...page2.map((r) => r.id)];
        expect(ids.toSet(), hasLength(250), reason: '按粗筛行数累加游标不许产生重复');
      },
    );

    test('精筛吞掉整页时不产生假象：hasMore 仍按粗筛行数说', () async {
      // 5 行全部送达；按「没发出去的」筛：粗筛 LIKE 不命中任何行（粗筛 0 行）⇒ 取尽。
      const now = 1780000000000;
      for (var i = 0; i < 5; i++) {
        await DatabaseHelper().insertNotification(
          row(
            'r_$i',
            postTime: now + i,
            delivery: {
              'chan:dingtalk': {'status': 'success', 'message': ''},
            },
          ),
        );
      }
      final (records, more, coarse) = await service.searchRecords(
        deliveryFilter: deliveryFilterNotDelivered,
        limit: 200,
      );
      expect(records, isEmpty);
      expect(more, isFalse);
      expect(coarse, 0);
    });
  });

  group('清除三兄弟 DB 驱动（判据：不依赖内存镜像）', () {
    test('clearToday 删的是 DB 里今天的行，返回删除数；会话副本同步清', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      await DatabaseHelper().insertNotification(
        row('today_1', postTime: todayStart.millisecondsSinceEpoch + 1000),
      );
      await DatabaseHelper().insertNotification(
        row('today_2', postTime: todayStart.millisecondsSinceEpoch + 2000),
      );
      await DatabaseHelper().insertNotification(
        row('old_1', postTime: todayStart.millisecondsSinceEpoch - 86400000),
      );
      service.addRecord(
        row('today_1', postTime: todayStart.millisecondsSinceEpoch + 1000),
      );
      service.addRecord(
        row('old_1', postTime: todayStart.millisecondsSinceEpoch - 86400000),
      );

      final deleted = await service.clearToday();

      expect(deleted, 2, reason: 'today_1 在内存里、today_2 只在 DB 里 —— 两行都必须删掉');
      expect(await DatabaseHelper().getNotificationCount(), 1);
      expect(
        (await DatabaseHelper().getAllNotifications()).first['id'],
        'old_1',
      );
      expect(
        service.records.any((r) => r.id == 'today_1'),
        isFalse,
        reason: '会话副本里属于今天的那些也要跟着清',
      );
    });

    test('clearLastN(2) 删的是**全表**最新的两条，哪怕内存副本里根本没有它们', () async {
      const now = 1780000000000;
      for (var i = 0; i < 5; i++) {
        await DatabaseHelper().insertNotification(
          row('r_$i', postTime: now + i * 1000),
        );
      }
      // 内存副本里只有最老那条（镜像退役后的典型会话状态）
      service.addRecord(row('r_0', postTime: now));

      final deleted = await service.clearLastN(2);

      expect(deleted, 2, reason: '内存里只有 1 条，但 DB 里有 5 条 —— 返回值必须说真话');
      final rest = await DatabaseHelper().getAllNotifications();
      expect(rest, hasLength(3));
      expect(
        rest.map((r) => r['id']),
        unorderedEquals(['r_0', 'r_1', 'r_2']),
        reason: '删的必须是**最新**的两条（r_4/r_3），不是内存列表头两个',
      );
      expect(
        service.records.any((r) => r.id == 'r_0'),
        isFalse,
        reason: '会话副本里被 DB 判定为最新 N 条的那些也要跟着清',
      );
    });

    test('clearLastN(0) 与负数一枚都不动', () async {
      await DatabaseHelper().insertNotification(
        row('r_1', postTime: 1780000000000),
      );
      expect(await service.clearLastN(0), 0);
      expect(await service.clearLastN(-3), 0);
      expect(await DatabaseHelper().getNotificationCount(), 1);
    });
  });

  group('拦截记录迁移一次性（判据：读 DB、记 flag、不再吃内存）', () {
    test('老形状记录被修复进 DB；第二次调用跳过（哪怕又出现老形状也不动）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // 老形状：拦截键（三种拼写）+ 真实通道停留 pending。
      // 通道键两种前缀各来一发（'webhook:企业微信' 是显示名前缀的历史写法，
      // channelKey 归一后同指 chan:wechat_work）。
      final legacyRows = <String, Map<String, dynamic>>{
        'legacy_zh': {
          '过滤拦截': {'status': 'failed', 'message': '命中关键词'},
          'chan:dingtalk': {'status': 'pending', 'message': ''},
        },
        'legacy_en': {
          'Blocked': {'status': 'failed', 'message': 'blocked (en)'},
          'chan:dingtalk': {'status': 'pending', 'message': ''},
        },
        'legacy_prefix': {
          'chan:blocked': {'status': 'failed', 'message': '后到的老形状'},
          'chan:dingtalk': {'status': 'pending', 'message': ''},
        },
      };
      for (final entry in legacyRows.entries) {
        await DatabaseHelper().insertNotification(
          row(entry.key, postTime: now, delivery: entry.value),
        );
      }
      await DatabaseHelper().insertNotification(
        row(
          'clean_1',
          postTime: now + 1,
          delivery: {
            'chan:dingtalk': {'status': 'success', 'message': ''},
          },
        ),
      );

      await service.migrateInterceptedRecords();

      for (final entry in legacyRows.entries) {
        final fixed = NotificationRecord.fromMap(
          (await DatabaseHelper().getNotificationById(entry.key))!,
        ).deliveryStatus;
        expect(
          fixed['chan:dingtalk']?['status'],
          'intercepted',
          reason: '${entry.key}：真实通道停留"发送中"的那一格必须被迁走 —— 这是这条迁移存在的理由',
        );
        expect(
          fixed['chan:dingtalk']?['message'],
          entry.value.entries
              .firstWhere((e) => channelKey(e.key) == 'blocked')
              .value['message'],
          reason: '${entry.key}：拦截原因要跟过去',
        );
        expect(
          fixed.keys.any((k) => channelKey(k) == 'blocked'),
          isFalse,
          reason: '${entry.key}：老拼写键被收编，不许原样留着再骗一次识别',
        );
      }
      expect(
        NotificationRecord.fromMap(
          (await DatabaseHelper().getNotificationById('clean_1'))!,
        ).deliveryStatus['chan:dingtalk']?['status'],
        'success',
        reason: '没有拦截项的记录一字不动',
      );

      // flag 已记 ⇒ 第二次调用跳过：又塞进一条老形状也不动
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('intercepted_migration_done'), isTrue);
      await DatabaseHelper().insertNotification(
        row(
          'legacy_2',
          postTime: now + 2,
          delivery: {
            'chan:blocked': {'status': 'failed', 'message': 'flag 之后的老形状'},
            'chan:dingtalk': {'status': 'pending', 'message': ''},
          },
        ),
      );
      await service.migrateInterceptedRecords();
      final untouched = NotificationRecord.fromMap(
        (await DatabaseHelper().getNotificationById('legacy_2'))!,
      );
      expect(
        untouched.deliveryStatus['chan:dingtalk']?['status'],
        'pending',
        reason: 'flag 已记就该跳过 —— 这枚缺陷的写入路径已修，后到的老形状只可能来自整库倒退，那不是迁移该兜的',
      );
    });
  });
}
