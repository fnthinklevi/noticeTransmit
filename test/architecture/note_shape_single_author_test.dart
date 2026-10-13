import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T100 片5：「小字说明」这一族的画法只有一个作者（判据① 收口的那一刀）。
///
/// ## 量出来的旧状态（2026-10-13 现读）
/// `lib/` 里挂着三枚同形的小字件：公共件 `FnthinkNote`（幻念七张页在用的那枚）＋
/// `remote_history_page` 与 `remote_credential_settings_page` **各抄一份的私有 `_Note`**。
/// 两枚私抄本与公共件**逐字相同**（`vertical: 4` 的 padding、12px、`height: 1.4`、
/// `AppColors.secondaryLabel`），差别只有一行 —— 公共件多一个 `super.key`。
/// ⇒ 这不是一次"改版式"，是把三份抄本合回一份：以后调那一族的字号只改一处。
///
/// ## 这本账的牙
/// ① **全族扫描再对差集**：扫 `lib/` 里所有 `class <名以 Note 结尾> extends StatelessWidget`，
///   期望集合就是 `{FnthinkNote}`。任何一页再长回一枚私抄本（`_Note`／`NoteText`／别的名字都算）⇒ 红。
///   ⚠ 不写"不许出现 `_Note`"那种字面判据：换名（`_SmallNote`）就绕过，而这正是这一族会漂的方式。
/// ② **尺认得合成样本**：①那条全绿时，"没有私抄本"与"提取器根本没匹配到任何东西"同形
///   —— 本仓已栽过两次（提取式收窄后正则恒不匹配 ⇒ 差集恒空 ⇒ 绿着什么都没量到）。
/// ③ **两页各自的用量台账**：换掉的 19 处现在都归公共件；逐文件枚数与登记值相等
///   ⇒ 有人偷偷改回自搭壳、或页面被删了半张而账没跟着动，都会红。这本账**不许为空**。
///
/// ⚠ 读源码一律剥注释（`stripComments`）：注释里写的 `_Note` 不是代码里的 `_Note`。
void main() {
  final root = projectRoot();

  /// 每一页现在由公共件画出多少格小字。改代码要同时改这本账 —— 它是剩余工作量，也是回退网。
  const kNoteUsageByFile = <String, int>{
    'pages/remote_history_page.dart': 7,
    'pages/remote_credential_settings_page.dart': 12,
  };

  /// 尺的本体：给一段源码，抓出里面所有"小字说明件"的类名。
  /// 口径刻意放宽到"名字以 Note 结尾"，而不是逐个名字去列 —— 逐个列就等于允许新名字。
  Set<String> noteWidgetClasses(String strippedSource) => RegExp(
    r'class\s+([A-Za-z_][A-Za-z0-9_]*Note)\s+extends\s+StatelessWidget',
  ).allMatches(strippedSource).map((m) => m.group(1)!).toSet();

  Map<String, String> libNotes() {
    final found = <String, String>{};
    for (final entry in libCodeByRel(root).entries) {
      for (final name in noteWidgetClasses(entry.value)) {
        found[name] = entry.key;
      }
    }
    return found;
  }

  test('① 小字说明件的作者只有一个（私抄本一律红）', () {
    final found = libNotes();
    expect(
      found.keys.toSet(),
      {'FnthinkNote'},
      reason:
          '量到的作者集合：${found.entries.map((e) => "${e.key}@${e.value}").toList()} —— '
          '同一种小字有两枚件，字号就会在两处各漂各的（T100 判据① 立的就是这一条）',
    );
  });

  test('② 尺认得合成样本（防① 退化成"恒不匹配＝恒绿"）', () {
    const sample = '''
class FnthinkNote extends StatelessWidget {
  const FnthinkNote({super.key});
}

class _Note extends StatelessWidget {
  const _Note();
}

class SmallNote extends StatelessWidget {
  const SmallNote();
}
''';
    expect(
      noteWidgetClasses(sample),
      {'FnthinkNote', '_Note', 'SmallNote'},
      reason:
          '尺连自造的样本都认不出 ⇒ ① 那条绿只说明"正则没匹配到任何东西"，'
          '不说明"这一族干净"',
    );
    // 反向也要成立：不是 Note 结尾的类不许被抓进来（否则任何一枚 StatelessWidget 都算抄本，
    // 这本账会红得没有信息量）。
    expect(
      noteWidgetClasses('class FnthinkCard extends StatelessWidget {'),
      isEmpty,
    );
  });

  test('③ 两页的用量与台账相等（这本账不许为空）', () {
    final code = libCodeByRel(root);
    expect(kNoteUsageByFile, isNotEmpty, reason: '账空了 ⇒ 这一族今天谁在用小字，没人知道');
    for (final entry in kNoteUsageByFile.entries) {
      final src = code[entry.key];
      expect(src, isNotNull, reason: '${entry.key} 读不到了（改名或挪走，账要一起改）');
      final used = RegExp('FnthinkNote\\(').allMatches(src!).length;
      expect(
        used,
        entry.value,
        reason:
            '${entry.key} 里公共件画出 $used 格、台账记 ${entry.value} 格 —— '
            '少了就是又长回一枚自搭壳，多了就是页面被搬走而账没跟着改',
      );
      expect(
        used,
        greaterThan(0),
        reason:
            '这一页现在一格公共小字都不画 ⇒ 上面那条"相等"会在 0==0 上恒真，'
            '这一族在这张页面上就没有证人行了（下限钉在这里）',
      );
    }
  });
}
