import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/delivery_status.dart';

import '../support/source_guards.dart';

/// T133 片1 的架构守卫：「这条可以再发一次吗」只许有一个作者，
/// 而「这条送达了吗」的两层口径（SQL 粗筛 / Dart 精筛）不许一层比另一层窄。
///
/// 两条各挡一种真实发生过的失效：
/// 1. 判据被抄回页面/模型 —— 于是"筛得出、选不中"这类自相矛盾能静默回归
///    （改之前 `NotificationRecord.hasFailedChannel` 与历史页里那句
///    `info['status'] == 'paused'` 就是同一件事的两份答案）；
/// 2. 粗筛收窄到漏掉精筛认的状态词 —— 精筛那一半永远轮不到，界面上表现为
///    "状态词明明写着拦截，按『失败』筛却找不到它"。
void main() {
  final root = projectRoot();

  /// lib/ 下全部 Dart 源文件（剥注释后的代码），key 为相对 `lib/` 的路径。
  final libCode = libCodeByRel(root);

  group('「可以再发一次」只有一个作者', () {
    test('旧的三个判据名不许长回来（全 lib/ 扫描）', () {
      for (final banned in [
        'hasFailedChannel',
        'failedChannels',
        'hasPausedChannel',
      ]) {
        final where = libCode.entries
            .where((e) => e.value.contains(banned))
            .map((e) => e.key)
            .toList();
        expect(
          where,
          isEmpty,
          reason:
              '『$banned』又出现在代码里了：$where。\n'
              '这一族判据的作者只有 lib/services/repush_eligibility.dart —— '
              '抄回模型/页面就等于把两个问题重新混成一个。',
        );
      }
    });

    test('重推判据的读者登记在册（新增读者要显式加进来）', () {
      final readers =
          libCode.entries
              .where(
                (e) =>
                    e.value.contains('channelNeedsRepush') ||
                    e.value.contains('recordNeedsRepush') ||
                    e.value.contains('repushableChannels') ||
                    // 片9 新增的两位：口径（文案那一头）与范围（递给原生那一头）。
                    // 扫词必须连它们一起扫，否则"页面自己拼一份范围"这种漂开法看不见。
                    e.value.contains('repushIntentOf') ||
                    e.value.contains('repushScopeKeys'),
              )
              .map((e) => e.key)
              .toList()
            ..sort();
      expect(
        readers,
        [
          'pages/history_page.dart',
          // 片4：service 是第二个读者 —— 它要按判据算出"这一发只给哪几族"再递给原生。
          'services/notification_service.dart',
          'services/repush_eligibility.dart',
        ],
        reason:
            '重推判据的读者集合变了。它今天是历史页（批量池 / 勾选框 / 单条出口那一枚的文案）'
            '加 service（补推范围）两处。\n'
            '若确实要新增读者，把它登记进本清单；若是绕过作者自己拼状态，改回调用判据。',
      );
    });

    test('单条出口的文案与范围**同源**：页面只认 repushIntentOf，不自己挑字面量', () {
      // 片9 走 (b) 之后每一行都有出口，于是"这一枚说的到底是哪件事"全靠文案承担。
      // 漂开法只有一种：页面按自己的判据选词、service 按作者的判据定范围 ⇒
      // 写着「现在推送」的那一枚其实把成功的通道也重发了一遍（这条不会崩，只会多发消息）。
      final page = libCode['pages/history_page.dart']!;
      expect(
        page.contains('repushIntentOf('),
        isTrue,
        reason: '那一枚的文案不再走作者 ⇒ 页面重新长出了第二套判据',
      );
      final service = libCode['services/notification_service.dart']!;
      expect(
        service.contains('repushScopeKeys('),
        isTrue,
        reason: '范围不在 service 里走同一位作者 ⇒ 文案与范围可以各说一套',
      );
    });

    test('历史页里那三处判定仍走作者，不自己比状态字面量', () {
      final page = libCode['pages/history_page.dart']!;
      expect(
        RegExp(r"status'\]\s*==\s*'paused'").hasMatch(page),
        isFalse,
        reason: '页面里又出现了「这一通道是 paused」的自拼判定 —— 那是作者的那一句。',
      );
      expect(page.contains('recordNeedsRepush('), isTrue);
    });

    test('补推只有一个出口：页面走 repushRecord，整表重建留在 service 内部', () {
      // 片4 之后 `pushRecordNow` 有两种范围（null = 全部启用通道 / 非 null = 那几族）。
      // 页面上那一枚「现在推送」要的永远是后者；谁绕过 `repushRecord` 直接调前者，
      // 界面上就回到"点一次把成功的通道也重发一遍"—— 而这条**不会崩，只会多发消息**。
      final callers =
          libCode.entries
              .where((e) => e.value.contains('pushRecordNow('))
              .map((e) => e.key)
              .toList()
            ..sort();
      expect(
        callers,
        ['services/notification_service.dart'],
        reason:
            '「不限定范围」那一发只有 service 内部两个读者（pushSynthesizedRecord 与 repushRecord）。\n'
            '页面要补推请走 repushRecord —— 它带着范围。',
      );
      final main = libCode['pages/main_page.dart']!;
      expect(main, contains('repushRecord('));
      expect(
        main,
        isNot(contains('pushRecordNow(')),
        reason: '历史页的装配点又直接调不限定那一发了',
      );
    });
  });

  group('送达筛选：判据只有一遍（T133 走 (c) 之后）', () {
    // 片1 时这一条是"从精筛源码里提取状态词，再要求粗筛 LIKE 到"（提取式，尺窄就可能空转）；
    // 片3 把两层收到同一张词表上，断言改成"粗筛参数逐字取自那张表"；
    // 走 (c) 之后**两层合成一层**：判据算出的桶值存进 `notifications.delivery_bucket`，
    // SQL 等值筛那一列。所以这一条现在钉的是反面 —— 状态词**不许再出现在 SQL 那一层**，
    // 出现了就是有人把判据抄了第二遍（片1 那轮漂开的正是那个形状）。
    test('SQL 那一层只剩"等值筛桶列"，一个状态词都不许抄进来', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        deliveryFilter: deliveryFilterNotDelivered,
      );
      expect(where, contains('delivery_bucket = ?'));
      expect(
        where,
        isNot(contains('delivery_info')),
        reason: '又开始对 JSON 文本做 LIKE 了 ⇒ 两层筛回来了一半，页数与 hasMore 又会分叉',
      );
      expect(
        args.whereType<String>().where(notDeliveredStatuses.contains).toList(),
        isEmpty,
        reason:
            '状态词出现在 SQL 那一层 ⇒ 判据被抄了第二遍。走 (c) 之后 SQL 只认桶值，'
            '词表动一处，历史页那一档跟着动是靠**写入侧重算**，不是靠这一层再拼一次 LIKE。',
      );
      // 尺自己的非空自证：表空了上面那句就变成"两个空集合相等"，那是假绿
      expect(notDeliveredStatuses, contains('failed'));
      expect(notDeliveredStatuses.length, greaterThanOrEqualTo(2));
    });

    test('送达词表、档名与桶值只有一个作者，其余各处只引用不另抄', () {
      final users =
          libCode.entries
              .where(
                (e) =>
                    e.value.contains('notDeliveredStatuses') ||
                    e.value.contains('deliveredStatus') ||
                    e.value.contains('deliveryFilterNotDelivered') ||
                    e.value.contains('deliveryFilterDelivered') ||
                    // 走 (c) 新增的这三位同样是"只许引用、不许自造"的词
                    e.value.contains('matchDeliveryFilter') ||
                    e.value.contains('deliveryBucketOf') ||
                    e.value.contains('deliveryBucketNone'),
              )
              .map((e) => e.key)
              .toList()
            ..sort();
      expect(
        users,
        [
          'database/database_helper.dart',
          'models/delivery_status.dart',
          'pages/history_page.dart',
        ],
        reason:
            '「这条送达了吗」的消费者集合变了。走 (c) 之后只有三处：DB（写入与回填算桶 + 等值筛那一列）、'
            '判据自己（词表与桶值）、历史页（档名）。'
            '⚠ `services/notification_service.dart` **已从这个集合里退场** —— 它以前是那句 Dart 精筛的读者，'
            '现在 SQL 筛的就是同一个判据算出的值，再补一刀就是把同一句判据跑两遍。'
            '新增读者请登记；绕过词表自己抄一份状态词/档名/桶值的，改回引用。',
      );
    });
  });
}
