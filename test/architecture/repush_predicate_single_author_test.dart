import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';

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

  group('送达筛选：粗筛不许窄于精筛', () {
    test('精筛 failed 档认的每个状态词，SQL 粗筛都要 LIKE 到', () {
      final svc = libCode['services/notification_service.dart']!;
      final fine = blockAfter(svc, "if (filter == 'failed')");
      final accepted = RegExp(
        r"s\s*==\s*'([a-z_]+)'",
      ).allMatches(fine).map((m) => m.group(1)!).toSet();
      expect(
        accepted,
        contains('failed'),
        reason: '精筛连 "failed" 都没提到 ⇒ 提取式失效（尺窄于它量的东西），不是判据成立。',
      );

      final (_, args) = DatabaseHelper.buildSearchSql(deliveryFilter: 'failed');
      for (final word in accepted) {
        expect(
          args,
          contains('%$word%'),
          reason:
              '精筛把 "$word" 算作未送达，SQL 粗筛却没 LIKE 它 —— '
              '只有该状态的记录进不了候选集，精筛那一半永远轮不到（丢筛选项）。',
        );
      }
    });
  });
}
