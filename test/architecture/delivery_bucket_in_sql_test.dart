import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T133 走 (c)：「这条送达了吗」那一档判定**从两层收成一层**之后，形状不许退回两层。
///
/// 以前的形状：SQL 拿 `notifications.delivery_info`（一段 JSON 文本）做 LIKE 粗筛，
/// 调用方再 jsonDecode 精筛。两层必然宽窄不一 ⇒ 一页取回 200 行、筛中 6 行，
/// 而「还有没有下一页」按那 200 行回答 —— 用户翻到的"第 3 页"没有定义。
/// 现在：判据算出的**桶值**存进 `notifications.delivery_bucket`（写入咽喉就地算 + v25 迁移回填），
/// SQL 等值筛那一列。引 JSON1 那两条路都没走 —— Android 各版本带的 SQLite 有没有编进 JSON1
/// 不是本机可以假设的事。
///
/// 五件事各管一个"不这么做会怎样"，主语互不重叠：
///  ① 判据只有一遍：`matchDeliveryFilter` 必须**调**桶值那一句，而不是自己再写一遍 any/every。
///  ② 写入咽喉同写两列：只写 `delivery_info` 不写 `delivery_bucket` 的那一行，两档都筛不到 ——
///     界面读起来是"这条被筛掉了"，而真相是漏写一列（且没有任何一层会报错）。
///  ③ SQL 那一层不再出现状态词，也不再对 `delivery_info` 做 LIKE：出现了就是有人抄了第二遍。
///  ④ 列与索引在**两条建库路径**上都在（新装 `_onCreate` 与升级 `oldVersion < 25`）；
///     而默认值 `''`（"没人算过"）不许被当成查询条件 —— 那是把 bug 伪装成"这一档没数据"。
///  ⑤ 回填调同一个作者、且不外抛：回填里自己抄一份状态词 ⇒ 存量行停旧口径、新行用新口径；
///     回填抛出 ⇒ `onUpgrade` 走"备份原库 + 重建空库"，等于把用户历史清掉。
///
/// ⚠ 这里用"签名 → 下一个成员收尾"切函数体（不是 `blockAfter`）：具名参数表会被当成函数体、
/// 而 `}) {` 那种写法会把体截早 —— 两种都造得出"体内断言对着半截签名恒真"的假绿。
/// 切不到就**停手报红**，不许让空体蒙过断言（每条都先断 `isNotEmpty`）。
void main() {
  final root = projectRoot();
  const dbRel = 'lib/database/database_helper.dart';
  const judgeRel = 'lib/models/delivery_status.dart';

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  /// 从签名那一行切到**这个成员自己的**收尾。
  ///
  /// ⚠ 定界必须同时认两种收尾：类成员是 `\n  }\n`（两空格），**顶层函数是 `\n}\n`（一列）**。
  ///   只找两空格那一种时，顶层函数的体被一直切到文件尾 —— 于是"体内含 `deliveryBucketOf(`"
  ///   这种断言会被后面那个**定义本身**满足：断言恒真、尺根本没在量那一句（假绿）。
  ///   本文件第一版就中过这一枪，是反证 Y1（把精筛改成自己抄判定、不调作者）跑出
  ///   `exit 0 / named=False` 才暴露的 —— 这就是"改守卫必须同日重跑反证"的全部理由。
  /// ⚠ 也不能只找 `\n  }`：多行具名参数表的收尾是 `  }) {`，会把体在参数表处截早。
  String memberBody(String src, String signature) {
    final i = src.indexOf(signature);
    if (i < 0) return '';
    final a = src.indexOf('\n  }\n', i);
    final b = src.indexOf('\n}\n', i);
    final end = <int>[
      a,
      b,
    ].where((x) => x >= 0).fold(-1, (m, x) => m < 0 || x < m ? x : m);
    return end < 0 ? '' : src.substring(i, end);
  }

  group('T133 走 (c)｜送达判定在 SQL 那一层只剩一列等值', () {
    test('① 判据只有一遍：精筛那一句调桶值，不自己再写一遍', () {
      final judge = read(judgeRel);
      final body = memberBody(judge, 'bool matchDeliveryFilter(');
      expect(body, isNotEmpty, reason: '切不到 matchDeliveryFilter ⇒ 这条尺什么都没量到');
      expect(
        body,
        contains('deliveryBucketOf('),
        reason:
            '精筛又开始自己判了 ⇒ 与写入时算的那个桶值成两个作者，'
            'SQL 筛的与内存筛的会分叉（那正是这一片要消掉的形状）。',
      );
      final bucketBody = memberBody(judge, 'String deliveryBucketOf(');
      expect(
        bucketBody,
        isNotEmpty,
        reason: '切不到 deliveryBucketOf ⇒ ① 的前半句是空的',
      );
      expect(
        bucketBody,
        contains('notDeliveredStatuses'),
        reason: '桶值不读词表 ⇒ 状态词改哪儿都行，那张表成了摆设',
      );
    });

    test('② 每个运行时送达写入点都同一次写两列（例外只有 v11 键归一那处）', () {
      final db = read(dbRel);
      for (final throat in const [
        'Future<void> insertNotification(',
        'Future<void> updateNotificationDelivery(',
      ]) {
        final body = memberBody(db, throat);
        expect(body, isNotEmpty, reason: '切不到写入咽喉 $throat ⇒ 尺空转');
        expect(
          body,
          contains("'delivery_info'"),
          reason: '$throat 不再写 delivery_info 了？那是另一件事，本条只钉两列同写',
        );
        expect(
          body,
          contains("'delivery_bucket'"),
          reason:
              '$throat 漏写 delivery_bucket ⇒ 那一行两档都筛不到，而界面把它说成"被筛掉了"。'
              '桶值是派生值，必须在同一语句里由 deliveryBucketOf 算出来。',
        );
      }
      // 全仓 `'delivery_info':` 作为写入键的出现集合必须**已知**：多一枚就是新增写点。
      final writers = <String>[];
      for (final f in Directory(
        '$root/lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = stripComments(f.readAsStringSync());
        final n = RegExp(r"'delivery_info':").allMatches(s).length;
        if (n > 0) {
          final rel = f.path.replaceAll('\\', '/').substring(root.length + 1);
          writers.add('${rel.startsWith('lib/') ? rel.substring(4) : rel}=$n');
        }
      }
      expect(
        writers..sort(),
        const ['database/database_helper.dart=3'],
        reason:
            'delivery_info 的写入者变了。今天只有三处：两个运行时咽喉 + v11「键归一」那处'
            '（它必须跑在 v25 回填之前，所以那一处**不写**桶列 —— 由 ⑤ 钉着"回填随后会算")。'
            '新增写点请先回答它同不同写两列。',
      );
    });

    test('③ SQL 那一层没有状态词，也不再对 JSON 文本 LIKE', () {
      final db = read(dbRel);
      expect(
        db,
        isNot(contains('delivery_info LIKE')),
        reason: '两层筛回来了：粗筛宽、精筛窄，分页条数与 hasMore 又会分叉',
      );
      final body = memberBody(
        db,
        'static (String where, List<dynamic> args) buildSearchSql(',
      );
      expect(body, isNotEmpty, reason: '切不到 buildSearchSql ⇒ 这条尺空转');
      expect(
        body,
        contains('delivery_bucket = ?'),
        reason: '这一档不再是等值筛桶列了？那"下沉"就没有发生',
      );
      for (final word in const ['failed', 'intercepted', 'paused', 'success']) {
        expect(
          body,
          isNot(contains("'$word'")),
          reason:
              'SQL 那一层出现了状态词字面量 $word ⇒ 判据被抄了第二遍。'
              '词表改一处时这一层不会跟着动，而它的表现是"某些记录永远筛不到"。',
        );
      }
    });

    test('④ 两条建库路径都有这一列与那枚索引；默认值不被当查询条件', () {
      final db = read(dbRel);
      final create = memberBody(
        db,
        'Future<void> _onCreate(Database db, int version) async {',
      );
      expect(create, isNotEmpty, reason: '切不到 _onCreate ⇒ 尺空转');
      expect(
        create,
        contains('delivery_bucket TEXT NOT NULL'),
        reason: '新装的库没有这一列 ⇒ 历史页那一档 SQL 当场 no such column',
      );
      expect(
        create,
        contains('idx_notifications_bucket_post'),
        reason: '只有列没有索引 ⇒ 每一档全表扫再排序，下沉省的那次 jsonDecode 被这次全表扫吃掉',
      );
      // 升级路径：v25 那一块必须加列 + 建索引 + 回填（三件都在这块里，缺一件就是"升级的库没有这一列"）
      final v25 = memberBodyOfBlock(db, 'if (oldVersion < 25) {');
      expect(
        v25,
        contains("'delivery_bucket'"),
        reason: '升级路径没加列 ⇒ 新装正常、老库升级后那一档 SQL 直接报错',
      );
      expect(v25, contains('idx_notifications_bucket_post'));
      expect(v25, contains('backfillDeliveryBucket(db)'));
      // `''` 的含义是"没人算过"。把它当查询值就是"把 bug 伪装成这一档没数据"。
      expect(
        db,
        isNot(contains("delivery_bucket = ''")),
        reason: "SQL 拿默认值 '' 当条件 ⇒ 那一档筛的是「漏写的行」，不是任何一个真实档",
      );
    });

    test('⑤ 回填调同一个作者、单行坏 JSON 不拖垮整批、异常不外抛', () {
      final db = read(dbRel);
      final body = memberBody(
        db,
        'Future<void> backfillDeliveryBucket(Database db) async {',
      );
      expect(body, isNotEmpty, reason: '切不到 backfillDeliveryBucket ⇒ 尺空转');
      expect(
        body,
        contains('deliveryBucketOf('),
        reason:
            '回填自己抄一份状态词 ⇒ 存量行按旧口径、新写行按新口径，'
            '同一个档在两批行里筛出两种结果，而没有任何一层会报错（片1 那轮的形状）。',
      );
      for (final word in const ['failed', 'intercepted', 'paused', 'success']) {
        expect(
          body,
          isNot(contains("'$word'")),
          reason: '回填里出现状态词字面量 $word ⇒ 同上，判据被抄了第二遍',
        );
      }
      expect(
        body,
        isNot(contains('throw')),
        reason:
            '回填抛出会走 _initDatabase 的「备份原库 + 重建空库」分支 —— '
            '那等于把用户历史连库内配置一起清掉，而代价不在这一片的可见面上',
      );
      expect(
        body,
        contains('debugPrint('),
        reason: '不外抛又不出声的迁移，坏了没人知道；失败必须留一行话（v11 那轮的口径）',
      );
    });

    test('⑥ 反向自检：尺真的切到了那几个成员（防空转与空集假绿）', () {
      final db = read(dbRel);
      final judge = read(judgeRel);
      // 剥注释管线本身：探针取的是**只在代码里**出现、且不属于本守卫断言对象的标识符。
      expect(
        db,
        contains('searchNotifications'),
        reason: 'stripComments 把代码也剥掉了 ⇒ 上面每条都是假的',
      );
      expect(db, contains('CREATE INDEX idx_notifications_bucket_post'));
      expect(judge, contains('const List<String> notDeliveredStatuses'));
      // 签名逐个验：任何一条改名后没被同步，对应那条判据会静默空转（isNotEmpty 只在测试体里断，
      // 这里先整体数一遍，坏在哪一句就报哪一句）。
      for (final sig in const [
        'Future<void> _onCreate(',
        'Future<void> backfillDeliveryBucket(',
        'Future<void> insertNotification(',
        'Future<void> updateNotificationDelivery(',
      ]) {
        expect(
          memberBody(db, sig),
          isNotEmpty,
          reason: '切不到成员 $sig ⇒ 该条判据没在量任何东西',
        );
      }
      for (final sig in const [
        'bool matchDeliveryFilter(',
        'String deliveryBucketOf(',
      ]) {
        expect(
          memberBody(judge, sig),
          isNotEmpty,
          reason: '切不到成员 $sig ⇒ 该条判据没在量任何东西',
        );
      }
    });
  });
}

/// 块作用域的切法：`if (oldVersion < N) { ... }` 收尾是**四空格**缩进的 `}`（它在 `_onUpgrade`
/// 体内），与成员切法 `\n  }` 不是同一个定界 —— 所以单独一个函数，别把两种混成一把尺。
String memberBodyOfBlock(String src, String opener) {
  final i = src.indexOf(opener);
  if (i < 0) return '';
  final end = src.indexOf('\n    }', i);
  return end < 0 ? '' : src.substring(i, end);
}
