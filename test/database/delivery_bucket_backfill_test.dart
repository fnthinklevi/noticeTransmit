import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/delivery_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_setup.dart';

/// T133 走 (c)：「这条送达了吗」那一档判定从"SQL LIKE 粗筛 + Dart 精筛"两层，收成
/// **一列存好的桶值 + SQL 等值筛**。这一族必须跑真 SQL，理由与 `engine_rules_schema_test` 同一条：
/// 会咬人的三个错法都在 SQL 层 —— ① 写入咽喉只写了 `delivery_info` 忘了 `delivery_bucket`
/// （那一行两档都筛不到，界面读起来像"这条被筛掉了"，而真相是漏写一列）；
/// ② 迁移回填自己抄一遍状态词（词表一改，存量行的桶值就停在旧口径，而新写的行用新口径 ——
/// 同一个档在两批行里筛出两种结果，且没有任何一层会报错）；
/// ③ 回填抛异常外传（`onUpgrade` 一抛就走"备份原库 + 重建空库"，等于把用户历史清掉）。
/// fake 存储测不出这三条，因为它自己就是断言的一部分。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabase();
  stubNativeChannels();

  final helper = DatabaseHelper();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await helper.createSchemaForTest(db);
    // 让 helper 的单例读口指到这份 ffi 库：这样 ② 与 ⑤⑥ 测的是**真正的写入咽喉与分页读口**，
    // 不是我在测试里另开的一条等价 SQL。
    helper.debugDatabase = db;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    helper.debugDatabase = null;
    await db.close();
    clearNativeChannelStubs();
  });

  /// 造一行通知（直接走 SQL，不经咽喉 —— 这里要的是"库里有了一行没有桶值的旧数据"）。
  Future<void> seedRaw({
    required String id,
    required int postTime,
    Map<String, dynamic>? delivery,
    bool writeBucket = true,
  }) async {
    final values = <String, dynamic>{
      'id': id,
      'title': 't$id',
      'content': 'c',
      'package_name': 'com.a',
      'app_name': 'A',
      'post_time': postTime,
      'time': '$postTime',
      'type': 'other',
      'timestamp': postTime,
      'delivery_info': delivery == null || delivery.isEmpty
          ? null
          : jsonEncode(delivery),
    };
    if (writeBucket) {
      values['delivery_bucket'] = deliveryBucketOf(delivery ?? const {});
    }
    await db.insert('notifications', values);
  }

  Future<String> bucketOf(String id) async {
    final rows = await db.query(
      'notifications',
      columns: ['delivery_bucket'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.first['delivery_bucket'] as String;
  }

  group('T140 走 (c) 之后 delivery_bucket 这一列', () {
    test('① 新库建表就有这一列，且带那枚复合索引（列与索引是一件事的两半）', () async {
      final cols = await db.rawQuery("PRAGMA table_info('notifications')");
      final names = cols.map((c) => c['name']).toSet();
      expect(
        names,
        contains('delivery_bucket'),
        reason: '没有这一列 ⇒ 历史页那一档 SQL 会当场 no such column（新装设备立刻红）',
      );
      final idx = await db.rawQuery("PRAGMA index_list('notifications')");
      final indexed = idx
          .map((r) => r['name'] as String)
          .where((n) => n.contains('bucket'))
          .toList();
      expect(
        indexed,
        isNotEmpty,
        reason:
            '只有列没有索引 ⇒ 每一档都要全表扫再按 post_time 排序，'
            '下沉省下的那一次 jsonDecode 被这一次全表扫吃掉',
      );
    });

    test('② 写入咽喉同一次写两列，桶值与判据同源', () async {
      await helper.insertNotification(<String, dynamic>{
        'id': 'a',
        'title': 't',
        'content': 'c',
        'packageName': 'com.a',
        'appName': 'A',
        'postTime': 1,
        'time': '1',
        'type': 'other',
        'deliveryStatus': <String, dynamic>{
          'chan:w1': {'status': 'success'},
        },
      });
      expect(
        await bucketOf('a'),
        deliveryBucketDelivered,
        reason: 'insertNotification 没同写 delivery_bucket ⇒ 那一行两档都筛不到',
      );

      await helper.updateNotificationDelivery('a', <String, dynamic>{
        'chan:w1': {'status': 'success'},
        'chan:w2': {'status': 'failed'},
      });
      expect(
        await bucketOf('a'),
        deliveryBucketNotDelivered,
        reason: '回写送达结果时桶值必须跟着改 —— 它是派生值，不跟着动就是旧口径留在库里',
      );

      await helper.updateNotificationDelivery('a', const {});
      expect(await bucketOf('a'), deliveryBucketNone);
      // 空 map 时 delivery_info 仍写 null（这一格的历史形状不许被这片改动）
      final info = await db.query(
        'notifications',
        columns: ['delivery_info'],
        where: 'id = ?',
        whereArgs: ['a'],
      );
      expect(info.first['delivery_info'], isNull);
    });

    test('③ 回填只算"没人算过"的那些行，且用的就是那一句判据（幂等）', () async {
      // 模拟升级前的库：有 delivery_info、桶列留着默认 ''
      await seedRaw(
        id: 'old1',
        postTime: 30,
        delivery: const {
          'chan:w1': {'status': 'intercepted'},
        },
        writeBucket: false,
      );
      await seedRaw(
        id: 'old2',
        postTime: 20,
        delivery: const {
          'chan:w1': {'status': 'success'},
          'chan:w2': {'status': 'success'},
        },
        writeBucket: false,
      );
      await seedRaw(
        id: 'old3',
        postTime: 10,
        delivery: null,
        writeBucket: false,
      );
      // 单行坏 JSON：真实老库里有这种行（写回时截断过），它不该拖垮整批
      await db.insert('notifications', {
        'id': 'bad',
        'title': 't',
        'content': 'c',
        'package_name': 'com.a',
        'app_name': 'A',
        'post_time': 5,
        'time': '5',
        'type': 'other',
        'timestamp': 5,
        'delivery_info': '{not json',
      });

      await helper.backfillDeliveryBucket(db);

      expect(await bucketOf('old1'), deliveryBucketNotDelivered);
      expect(await bucketOf('old2'), deliveryBucketDelivered);
      expect(await bucketOf('old3'), deliveryBucketNone);
      // 坏 JSON 那一行保持"没人算过"，而不是被猜成任何一个档
      expect(await bucketOf('bad'), '');

      // 幂等：再跑一次逐行同值（回填不是一次性魔法，重复跑要安全）
      final before = await db.query(
        'notifications',
        columns: ['id', 'delivery_bucket'],
        orderBy: 'id',
      );
      await helper.backfillDeliveryBucket(db);
      final after = await db.query(
        'notifications',
        columns: ['id', 'delivery_bucket'],
        orderBy: 'id',
      );
      expect(
        after.map((r) => '${r['id']}=${r['delivery_bucket']}').toList(),
        before.map((r) => '${r['id']}=${r['delivery_bucket']}').toList(),
      );
    });

    test('④ 正面自证：回填确实改了列（不是"默认值恰好就等于期望值"）', () async {
      await seedRaw(
        id: 'p1',
        postTime: 1,
        delivery: const {
          'chan:w1': {'status': 'failed'},
        },
        writeBucket: false,
      );
      expect(await bucketOf('p1'), '');
      await helper.backfillDeliveryBucket(db);
      expect(
        await bucketOf('p1'),
        deliveryBucketNotDelivered,
        reason: '回填没改动这一列时，③ 里那些期望值全部落空 —— 那才是假绿',
      );
    });

    test('⑤ SQL 那一档筛出的行集 == 那句判据认的行集（下沉没改变语义）', () async {
      final cases = <String, Map<String, dynamic>?>{
        's': const {
          'c1': {'status': 'success'},
        },
        'f': const {
          'c1': {'status': 'failed'},
        },
        'i': const {
          'c1': {'status': 'intercepted'},
        },
        'mix': const {
          'c1': {'status': 'success'},
          'c2': {'status': 'paused'},
        },
        'sending': const {
          'c1': {'status': 'sending'},
        },
        'empty': null,
      };
      var t = 1000;
      for (final e in cases.entries) {
        await seedRaw(id: e.key, postTime: t, delivery: e.value);
        t -= 1;
      }

      for (final filter in [
        deliveryFilterDelivered,
        deliveryFilterNotDelivered,
      ]) {
        final rows = await helper.searchNotifications(deliveryFilter: filter);
        final sqlIds = rows.map((r) => r['id']).toSet();
        // 现算的那一份（走 (c) 之前的精筛）作为对照 —— 两边必须逐行相等
        final judged = cases.entries
            .where(
              (e) => matchDeliveryFilter(
                e.value ?? const <String, dynamic>{},
                filter,
              ),
            )
            .map((e) => e.key)
            .toSet();
        expect(
          sqlIds,
          judged,
          reason:
              'filter=$filter 下 SQL 与那句判据给的行集不一样 ⇒ 下沉之后还有两层口径，'
              '分页条数与"还有没有下一页"会再次分叉',
        );
      }

      // 陌生档名：一行都不给（fail-closed 这一支从 Dart 那侧搬到了 SQL 那侧，没丢）
      final none = await helper.searchNotifications(deliveryFilter: 'failed');
      expect(none, isEmpty);
      // 「不限定」那一档照旧给全部
      final all = await helper.searchNotifications(
        deliveryFilter: deliveryFilterAll,
      );
      expect(all.length, cases.length);
    });

    test('⑥ 翻页游标从此只有一个数：本页行数就是筛中的行数', () async {
      for (var i = 0; i < 5; i++) {
        await seedRaw(
          id: 'n$i',
          postTime: 100 - i,
          delivery: const {
            'c1': {'status': 'failed'},
          },
        );
      }
      await seedRaw(
        id: 'ok',
        postTime: 999,
        delivery: const {
          'c1': {'status': 'success'},
        },
      );
      final page = await helper.searchNotifications(
        deliveryFilter: deliveryFilterNotDelivered,
        limit: 3,
        offset: 0,
      );
      expect(page.length, 3, reason: '这一页取回 3 行、筛中也是 3 行 —— 走 (c) 之前两者会不等');
      expect(page.map((r) => r['id']).toList(), ['n0', 'n1', 'n2']);
      final rest = await helper.searchNotifications(
        deliveryFilter: deliveryFilterNotDelivered,
        limit: 3,
        offset: page.length,
      );
      expect(rest.map((r) => r['id']).toList(), ['n3', 'n4']);
    });
  });
}
