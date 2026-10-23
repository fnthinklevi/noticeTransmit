import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/update_manager.dart';

/// T169：更新弹层首屏摘要的纯函数。
///
/// 断三件事：空行不占名额、字面量 `\n` 与 CRLF 都算换行、超过四行才需要「展开」。
/// 摘要与全文共用 [normalizeUpdateChangelog] —— 两处各 replace 一次的话，摘要里会留着
/// 一串字面量 `\n`，而全文那一份是正常的，界面上同一段日志两种样子。
void main() {
  test('摘要取前 4 条非空行，空行不占名额', () {
    expect(updateChangelogSummary('标题\n\n一\n二\n三\n四\n五'), [
      '标题',
      '一',
      '二',
      '三',
    ]);
  });

  test('字面量 \\n 与 CRLF 都按换行处理', () {
    expect(updateChangelogSummary('A\\nB\r\nC'), ['A', 'B', 'C']);
    expect(normalizeUpdateChangelog('A\\nB\r\nC'), 'A\nB\nC');
  });

  test('只有四行时不需要展开', () {
    expect(updateChangelogHasMore('一\n二\n三\n四'), isFalse);
    expect(updateChangelogHasMore('一\n二\n三\n四\n五'), isTrue);
  });

  test('没有内容时摘要为空且不需要展开', () {
    expect(updateChangelogSummary('  \n\n'), isEmpty);
    expect(updateChangelogHasMore('  \n\n'), isFalse);
  });
}
