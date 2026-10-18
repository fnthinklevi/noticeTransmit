import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/delivery_status.dart';
import 'package:notice_transmit/services/channel_display.dart';
import 'package:notice_transmit/services/fnthink_delivery_link_store.dart';
import 'package:notice_transmit/services/fnthink_fanout_entrypoint.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// T154 端到端「已送达」：`messageId ↔ 本地通知记录 id` 的映射与回执落库。
///
/// 这一片补的是片1 留下的那句「对端取走后回『已送达』要另立一行」：
///  - 发送侧只拿到 `messageId`，而历史那一格挂在**通知记录 id** 上 ⇒ 中间必须有这枚映射；
///  - 映射由后台转发 isolate 写、由收货 isolate 读，而 SharedPreferences 在两个
///    isolate 里各有一份缓存 ⇒ 读之前必须 `reload()`（否则永远读不到对方刚写的那条）；
///  - 回执可能迟到、重复、或来自旧服务端：终态只许往「已送达」走，不许被后到的失败回执降级。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('映射的读写', () {
    test('link 之后取得到，且取一次就没了（回执只该改一次那一行）', () async {
      final store = FnthinkDeliveryLinkStore();
      await store.link(messageId: 'm_1', recordId: 'rec_1');

      expect(await store.takeRecordId('m_1'), 'rec_1');
      expect(
        await store.takeRecordId('m_1'),
        isNull,
        reason: '同一条回执重复送到时，第二次已经没有映射可改 —— 这是幂等，不是丢失',
      );
    });

    test('空 messageId / 空 recordId 不写（写进去也只会留一条永远对不上的账）', () async {
      final store = FnthinkDeliveryLinkStore();
      await store.link(messageId: '', recordId: 'rec_1');
      await store.link(messageId: 'm_1', recordId: '');

      expect(await store.takeRecordId(''), isNull);
      expect(await store.takeRecordId('m_1'), isNull);
    });

    test('上限 500：第 501 条进来时最旧的那条被挤掉，新的一条照取', () async {
      final store = FnthinkDeliveryLinkStore();
      for (var i = 0; i < FnthinkDeliveryLinkStore.maxLinks + 1; i++) {
        await store.link(messageId: 'm_$i', recordId: 'rec_$i');
      }

      expect(
        await store.takeRecordId('m_0'),
        isNull,
        reason: '映射没有上限就会让 prefs 无界增长；挤掉最旧的那条是可接受的代价',
      );
      expect(
        await store.takeRecordId('m_${FnthinkDeliveryLinkStore.maxLinks}'),
        'rec_${FnthinkDeliveryLinkStore.maxLinks}',
      );
    });

    test('存量不是合法 JSON ⇒ 按"没有映射"处理，且下一发照写不崩', () async {
      SharedPreferences.setMockInitialValues({
        FnthinkDeliveryLinkStore.prefsKey: '这不是 JSON',
      });
      final store = FnthinkDeliveryLinkStore();

      expect(await store.takeRecordId('m_1'), isNull);
      await store.link(messageId: 'm_1', recordId: 'rec_1');
      expect(await store.takeRecordId('m_1'), 'rec_1');
    });
  });

  group('回执 → 送达格（纯函数）', () {
    final key = channelDeliveryKey(kFnthinkChannelSlug);

    test('delivered / displayed 落「已送达」；expired / dropped 落失败', () {
      for (final receipt in const ['delivered', 'displayed']) {
        final next = applyFnthinkReceiptToDelivery(<String, dynamic>{
          key: {'status': 'queued'},
        }, receipt);
        expect(next?[key]['status'], peerDeliveredStatus, reason: receipt);
      }
      for (final receipt in const ['expired', 'dropped']) {
        final next = applyFnthinkReceiptToDelivery(<String, dynamic>{
          key: {'status': 'queued'},
        }, receipt);
        expect(next?[key]['status'], 'failed', reason: receipt);
      }
    });

    test('非终态回执不改那一格（宁可不说，也不把"还在路上"写成失败）', () {
      for (final receipt in const ['waiting_online', 'queued', '', 'unknown']) {
        expect(
          applyFnthinkReceiptToDelivery(<String, dynamic>{
            key: {'status': 'queued'},
          }, receipt),
          isNull,
          reason: receipt,
        );
      }
    });

    test('一台设备取走就够了：后到的失败回执不许把「已送达」降级', () {
      final next = applyFnthinkReceiptToDelivery(<String, dynamic>{
        key: {'status': peerDeliveredStatus},
      }, 'expired');
      expect(next, isNull, reason: '多目标里一台成一台败是常态；把已送达改成失败＝对用户撒一次谎');
    });

    test('别的通道那一格与 viaBackup 标记都留着', () {
      final next = applyFnthinkReceiptToDelivery(<String, dynamic>{
        'chan:webhook': {'status': 'success'},
        key: {'status': 'queued', 'viaBackup': true},
      }, 'delivered');
      expect(next?['chan:webhook'], {'status': 'success'});
      expect(next?[key]['viaBackup'], true, reason: '这一发确实走了备用 ⇒ 回执不许把它抹掉');
    });
  });

  group('落库那一路（映射 → 记录 id → delivery_info）', () {
    final helper = DatabaseHelper();
    late final String dbPath;

    setUpAll(() async {
      dbPath = join(await getDatabasesPath(), 'fnthink_delivery_link_test.db');
    });

    tearDownAll(() async {
      helper.debugDatabase = null;
      if (await databaseFactory.databaseExists(dbPath)) {
        await databaseFactory.deleteDatabase(dbPath);
      }
    });

    Future<Database> freshDb() async {
      if (await databaseFactory.databaseExists(dbPath)) {
        await databaseFactory.deleteDatabase(dbPath);
      }
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: DatabaseHelper.dbVersion),
      );
      await helper.createSchemaForTest(db);
      helper.debugDatabase = db;
      addTearDown(() async {
        helper.debugDatabase = null;
        await db.close();
      });
      return db;
    }

    Future<String> insertRecord() async {
      final key = channelDeliveryKey(kFnthinkChannelSlug);
      await helper.insertNotification({
        'id': 'rec_1',
        'title': '标题',
        'content': '正文',
        'postTime': 1780000000000,
        'deliveryStatus': <String, dynamic>{
          key: {'status': 'queued', 'viaBackup': true},
        },
      });
      return key;
    }

    test('回执顺着映射改到本机那一行：状态、桶值、viaBackup 一起对', () async {
      await freshDb();
      final key = await insertRecord();
      await FnthinkDeliveryLinkStore().link(
        messageId: 'm_out',
        recordId: 'rec_1',
      );

      await applyFnthinkDeliveryReceipt('m_out', 'delivered');

      final row = await helper.getNotificationById('rec_1');
      final info = jsonDecode(row!['delivery_info'] as String) as Map;
      expect(info[key]['status'], peerDeliveredStatus);
      expect(info[key]['viaBackup'], true);
      expect(
        row['delivery_bucket'],
        deliveryBucketDelivered,
        reason:
            '只改 delivery_info 不重算桶值 ⇒ 历史页「已送达」那一档永远筛不到这一条 '
            '（写入咽喉里两列是同一次写的）',
      );
    });

    test('映射被取走之后，同一条回执再来一次什么都不改（幂等）', () async {
      await freshDb();
      await insertRecord();
      await FnthinkDeliveryLinkStore().link(
        messageId: 'm_out',
        recordId: 'rec_1',
      );

      await applyFnthinkDeliveryReceipt('m_out', 'delivered');
      await applyFnthinkDeliveryReceipt('m_out', 'expired');

      final row = await helper.getNotificationById('rec_1');
      final info = jsonDecode(row!['delivery_info'] as String) as Map;
      expect(
        info.values.single['status'],
        peerDeliveredStatus,
        reason: '后到的失败回执既没有映射、也不许把已送达降级',
      );
    });

    test('非终态回执不消耗映射：后到的 delivered 照样落得到那一行', () async {
      await freshDb();
      final key = await insertRecord();
      await FnthinkDeliveryLinkStore().link(
        messageId: 'm_out',
        recordId: 'rec_1',
      );

      await applyFnthinkDeliveryReceipt('m_out', 'waiting_online');
      var row = await helper.getNotificationById('rec_1');
      var info = jsonDecode(row!['delivery_info'] as String) as Map;
      expect(info[key]['status'], 'queued', reason: '还在路上 ⇒ 那一格不动');

      await applyFnthinkDeliveryReceipt('m_out', 'delivered');
      row = await helper.getNotificationById('rec_1');
      info = jsonDecode(row!['delivery_info'] as String) as Map;
      expect(
        info[key]['status'],
        peerDeliveredStatus,
        reason:
            '取映射是消耗性的 ⇒ 若在判词之前取走，非终态那一条会把映射用掉，'
            '同一 messageId 后面真正的 delivered 就永远对不上本地那一行',
      );
    });

    test('回执先到、转发结局后到 ⇒ 已送达不许被 queued 降级', () async {
      await freshDb();
      final key = await insertRecord();
      await FnthinkDeliveryLinkStore().link(
        messageId: 'm_out',
        recordId: 'rec_1',
      );
      // 收货循环（另一个 author）先拿到回执。
      await applyFnthinkDeliveryReceipt('m_out', 'delivered');
      // 后台转发轮此时才写完这一条的结局（多目标时两件事会并行）。
      await fnthinkDefaultRecordFanoutOutcome(
        'rec_1',
        const FnthinkFanoutOutcome(sent: 1, failed: 0),
      );

      final row = await helper.getNotificationById('rec_1');
      final info = jsonDecode(row!['delivery_info'] as String) as Map;
      expect(
        info[key]['status'],
        peerDeliveredStatus,
        reason:
            '转发结局那一笔是后到的：它对这一格的了解比回执旧 ⇒ '
            '拿 queued 覆盖 delivered，用户会看到已经取走的记录退回「待目标设备上线」',
      );
    });

    test('找不到映射 / 记录已被删 ⇒ 不抛，静默收手', () async {
      await freshDb();
      await insertRecord();

      await applyFnthinkDeliveryReceipt('m_unknown', 'delivered');

      final row = await helper.getNotificationById('rec_1');
      final info = jsonDecode(row!['delivery_info'] as String) as Map;
      expect(info.values.single['status'], 'queued', reason: '没有映射就不该改任何人的那一格');
    });
  });
}
