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
                    e.value.contains('repushableChannels'),
              )
              .map((e) => e.key)
              .toList()
            ..sort();
      expect(
        readers,
        ['pages/history_page.dart', 'services/repush_eligibility.dart'],
        reason:
            '重推判据的读者集合变了。它今天只有历史页一处（批量池 / 勾选框 / 单条「现在推送」都取自同一个作者）。\n'
            '若确实要新增读者，把它登记进本清单；若是绕过作者自己拼状态，改回调用判据。',
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
  });

  group('送达筛选：粗筛与精筛同源', () {
    // 片1 时这一条是"从精筛源码里提取状态词，再要求粗筛 LIKE 到"（提取式，尺窄就可能空转）。
    // 片3 把两层收到同一张词表上 ⇒ 断言改成**构造**：粗筛的参数必须逐字取自那张表。
    test('SQL 粗筛的 LIKE 参数恰好是词表那几个状态词', () {
      final (_, args) = DatabaseHelper.buildSearchSql(
        deliveryFilter: deliveryFilterNotDelivered,
      );
      expect(
        args,
        notDeliveredStatuses.map((s) => '%$s%').toList(),
        reason:
            '粗筛不许再自己抄状态词。顺序也要与词表一致 —— 同一份表在两层排成两样，'
            '读代码的人会以为有两张表（片1 那轮的缺陷正是两层各抄一遍后漂开）。',
      );
      // 尺自己的非空自证：表空了上面那句就变成"两个空集合相等"，那是假绿
      expect(notDeliveredStatuses, contains('failed'));
      expect(notDeliveredStatuses.length, greaterThanOrEqualTo(2));
    });

    test('送达词表与档名只有一个作者，其余各处只引用不另抄', () {
      final users =
          libCode.entries
              .where(
                (e) =>
                    e.value.contains('notDeliveredStatuses') ||
                    e.value.contains('deliveredStatus') ||
                    e.value.contains('deliveryFilterNotDelivered') ||
                    e.value.contains('deliveryFilterDelivered') ||
                    e.value.contains('matchDeliveryFilter'),
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
          'services/notification_service.dart',
        ],
        reason:
            '「这条送达了吗」的消费者集合变了。今天只有 DB（粗筛取词表）、'
            'service（精筛调那一句）、历史页（档名）三处 —— 新增读者请登记；'
            '若是绕过词表自己抄一份状态词或档名，改回引用。',
      );
    });
  });
}
