import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/update_manager.dart';

/// T61 更新流双语：更新弹窗里那段说明**按软件语言只显示一种**，取不到英文那份就回退中文。
///
/// 为什么这些要钉在纯函数上而不是 widget 上：弹窗那一格只在真机/闸门里点得到一次，
/// 而"该显示哪一份"是一个**取法**问题 —— 它错时的表现是"英文系统下仍然显示中文"，
/// 没有任何一条 widget 用例会红。所以裁决抽成 `pickUpdateChangelog`，这里直接断它。
///
/// ⚠ 三种"取不到英文"要分得开（合起来只有两条断言时，第三种会悄悄退化成恒真）：
///  ① 服务端没这个字段（老数据）⇒ 空串；
///  ② 字段在但只有空白/换行 ⇒ 也是空串；
///  ③ 英文系统**之外**的语言（zh / 跟随系统落到其它语言）⇒ 一律中文，
///     哪怕英文那份有内容 —— 这条是"只显示一种"的核心，不是"有英文就显示英文"。
void main() {
  const zh = '中文说明：导航重构 + 三族通道统一';
  const en = 'English notes: navigation rework and unified channel pages';

  VersionCheckResult build({String changelog = zh, String changelogEn = en}) =>
      VersionCheckResult(
        hasUpdate: true,
        latestVersion: '1.5.76',
        latestBuild: 116,
        forceUpdate: false,
        changelog: changelog,
        changelogEn: changelogEn,
        downloadUrl: '',
        fileSize: 0,
        minSupportedVersion: '1.0.0',
      );

  String pick(VersionCheckResult r, Locale locale) =>
      pickUpdateChangelog(zh: r.changelog, en: r.changelogEn, locale: locale);

  group('按软件语言只显示一种', () {
    test('英文软件 → 显示英文那一份（不是中文、也不是混排）', () {
      final r = build();
      expect(pick(r, const Locale('en')), en);
      expect(
        pick(r, const Locale('en')),
        isNot(contains('中文')),
        reason: '混排的更新日志读起来像半成品；两份拼起来正是这一条要防的',
      );
    });

    test('中文软件 → 一律中文，哪怕英文那份有内容', () {
      final r = build();
      expect(pick(r, const Locale('zh')), zh);
    });

    test('英文那一份没有（空串 / 只有空白）⇒ 回退中文，不显示空白弹层', () {
      final none = build(changelogEn: '');
      expect(pick(none, const Locale('en')), zh);
      final blank = build(changelogEn: '  \n \n');
      expect(
        pick(blank, const Locale('en')),
        zh,
        reason: '"只有空白"与"没有"在用户眼里是同一件事：框里什么都没有',
      );
    });

    test('中文那份也没有 ⇒ 仍回中文（空串），不因为英文是空就返回空', () {
      final r = build(changelog: '', changelogEn: '');
      expect(pick(r, const Locale('en')), '');
    });

    // ⚠ 判的是**语言码**而不是整串 locale：`en_US` / `en-GB` 都是英文软件。
    //   照整串比的话，英文用户在小数点格式不同的区域会看到中文，而且没有用例会红。
    test('en_US / en-GB 也算英文（判语言码，不是整串）', () {
      final r = build();
      expect(pick(r, const Locale('en', 'US')), en);
      expect(pick(r, const Locale('en', 'GB')), en);
    });
  });

  // ── 两条读取路径 ────────────────────────────────────────────────────
  // ⚠ 这一族最容易出的错是**只改一条路径**：`fromJson`（API 模式）与直接解析那一处
  //   各写一遍 changelog，漏掉后者时表现是"英文系统下仍然显示中文"，而全量测试全绿。
  group('changelogEn 两条读取路径都要带出来', () {
    test('fromJson：拿到 changelogEn（缺键时是空串，不是抛）', () {
      final withEn = VersionCheckResult.fromJson(<String, dynamic>{
        'changelog': zh,
        'changelogEn': en,
      });
      expect(withEn.changelogEn, en);
      final withoutEn = VersionCheckResult.fromJson(<String, dynamic>{
        'changelog': zh,
      });
      expect(withoutEn.changelogEn, '', reason: '老服务端没有这个字段是常态，不是错误');
      expect(
        pick(withoutEn, const Locale('en')),
        zh,
        reason: '回退中文这一步是从"空串"这一格出发的；这里抛了就等于回退从未被验过',
      );
    });

    test('构造器默认空串：不写 changelogEn 也能构造（老调用点不必改）', () {
      final r = VersionCheckResult(
        hasUpdate: true,
        latestVersion: '1.5.76',
        latestBuild: 116,
        forceUpdate: false,
        changelog: zh,
        downloadUrl: '',
        fileSize: 0,
        minSupportedVersion: '1.0.0',
      );
      expect(r.changelogEn, '');
    });
  });
}
