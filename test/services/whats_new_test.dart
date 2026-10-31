import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/update_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T203：大版本升级后首启那一句「这次更新带来了什么」。
///
/// 钉的是四件事（都在数据层，弹层那半份排版与守卫各自在别处）：
/// ① 「大版本」只认 major/minor（1.6.2→1.6.3 与 build 级都不弹）；
/// ② 写入点只落**大版本**那一次，且两份日志都空白时什么都不落；
/// ③ 读的那三条判据少一条都不弹（侧载／装的不是那一版／已经弹过／空壳）；
/// ④ 语言裁决沿用 `pickUpdateChangelog` —— 英文没写就回退中文，不混排。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const zh = Locale('zh');
  const en = Locale('en');

  VersionCheckResult checkResult({
    required String version,
    String notes = '修掉了数据库锁死\n门铃降级后改用短轮询',
    String notesEn = '',
  }) => VersionCheckResult(
    hasUpdate: true,
    latestVersion: version,
    latestBuild: 200,
    forceUpdate: false,
    changelog: notes,
    changelogEn: notesEn,
    downloadUrl: 'https://example.invalid/app.apk',
    fileSize: 1,
    minSupportedVersion: '1.0.0',
  );

  group('大版本口径（维护者 2026-10-26 拍：major/minor 两档，build 级永不弹）', () {
    test('版本号前两节读得出来，带 `+build`／`-beta` 后缀也算', () {
      expect(parseAppVersionHead('1.6.4'), (major: 1, minor: 6));
      expect(parseAppVersionHead('1.7.0+170'), (major: 1, minor: 7));
      expect(parseAppVersionHead('1.7.0-beta1'), (major: 1, minor: 7));
      expect(parseAppVersionHead(' 2.0 '), (major: 2, minor: 0));
    });

    test('读不出前两节就是 null（与"这一版确实小"分得开）', () {
      expect(parseAppVersionHead('1'), isNull);
      expect(parseAppVersionHead('1.x'), isNull);
      expect(parseAppVersionHead(''), isNull);
      expect(parseAppVersionHead('beta'), isNull);
    });

    test('1.6.2→1.7.0 与 →2.0.0 算大版本；→1.6.3 与同版不算', () {
      expect(isMajorMinorUpgrade(from: '1.6.2', to: '1.7.0'), isTrue);
      expect(isMajorMinorUpgrade(from: '1.6.2', to: '2.0.0'), isTrue);
      expect(isMajorMinorUpgrade(from: '1.6.2', to: '1.6.3'), isFalse);
      expect(isMajorMinorUpgrade(from: '1.6.2', to: '1.6.2'), isFalse);
    });

    test('任何一侧读不出版本 ⇒ 不算大版本（宁可不弹）', () {
      expect(isMajorMinorUpgrade(from: '1.6.2', to: 'nightly'), isFalse);
      expect(isMajorMinorUpgrade(from: '', to: '1.7.0'), isFalse);
    });
  });

  group('落盘：唯一写入点（确认安装那一刻）', () {
    test('大版本 ⇒ 三枚键都落，且落的是目标版本', () async {
      final prefs = await SharedPreferences.getInstance();
      final staged = await stageWhatsNewChangelog(
        prefs: prefs,
        fromVersion: '1.6.4',
        update: checkResult(version: '1.7.0'),
      );
      expect(staged, isTrue);
      expect(prefs.getString(kWhatsNewVersionKey), '1.7.0');
      expect(prefs.getString(kWhatsNewZhKey), contains('数据库锁死'));
      expect(prefs.getString(kWhatsNewEnKey), '');
    });

    test('小版本升级 ⇒ 什么都不落（1.6.2→1.6.3 按口径不弹）', () async {
      final prefs = await SharedPreferences.getInstance();
      final staged = await stageWhatsNewChangelog(
        prefs: prefs,
        fromVersion: '1.6.2',
        update: checkResult(version: '1.6.3'),
      );
      expect(staged, isFalse);
      expect(prefs.getString(kWhatsNewVersionKey), isNull);
    });

    test('不是从「检查更新→确认安装」来的（侧载，update 为 null）⇒ 不落', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await stageWhatsNewChangelog(
          prefs: prefs,
          fromVersion: '1.6.4',
          update: null,
        ),
        isFalse,
      );
      expect(prefs.getString(kWhatsNewVersionKey), isNull);
    });

    test('两份日志都是空白 ⇒ 不落（落进去首启就弹成空壳）', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await stageWhatsNewChangelog(
          prefs: prefs,
          fromVersion: '1.6.4',
          update: checkResult(version: '1.7.0', notes: '  \n  ', notesEn: '\n'),
        ),
        isFalse,
      );
      expect(prefs.getString(kWhatsNewZhKey), isNull);
    });
  });

  group('读：三条判据少一条都不弹', () {
    test('正常一份 ⇒ 出中文那一条，字面量 `\\n` 归一化成真换行', () {
      expect(
        pickWhatsNewChangelog(
          pendingVersion: '1.7.0',
          changelogZh: r'第一条\n第二条',
          changelogEn: 'one\\ntwo',
          shownVersion: null,
          currentVersion: '1.7.0',
          locale: zh,
        ),
        '第一条\n第二条',
      );
    });

    test('没有待读日志（侧载／没走过那次确认安装）⇒ null', () {
      expect(
        pickWhatsNewChangelog(
          pendingVersion: null,
          changelogZh: null,
          changelogEn: null,
          shownVersion: null,
          currentVersion: '1.7.0',
          locale: zh,
        ),
        isNull,
        reason: '没走过那条路就是无话可说；弹空壳或拿旧日志凑一句都是不实陈述',
      );
      expect(
        pickWhatsNewChangelog(
          pendingVersion: '   ',
          changelogZh: '有内容',
          changelogEn: '',
          shownVersion: null,
          currentVersion: '1.7.0',
          locale: zh,
        ),
        isNull,
      );
    });

    test('装上的并不是落盘那一版 ⇒ null（那份日志说的不是这次更新）', () {
      expect(
        pickWhatsNewChangelog(
          pendingVersion: '1.7.0',
          changelogZh: '1.7 的新功能',
          changelogEn: '',
          shownVersion: null,
          currentVersion: '1.8.0',
          locale: zh,
        ),
        isNull,
      );
    });

    test('这一版已经弹过 ⇒ null（一次性，不是每次启动）', () {
      expect(
        pickWhatsNewChangelog(
          pendingVersion: '1.7.0',
          changelogZh: '1.7 的新功能',
          changelogEn: '',
          shownVersion: '1.7.0',
          currentVersion: '1.7.0',
          locale: zh,
        ),
        isNull,
      );
    });

    test('两份日志全空白 ⇒ null（不许弹空壳）', () {
      expect(
        pickWhatsNewChangelog(
          pendingVersion: '1.7.0',
          changelogZh: '  \n\n ',
          changelogEn: '',
          shownVersion: null,
          currentVersion: '1.7.0',
          locale: zh,
        ),
        isNull,
      );
    });

    test('语言裁决只有一处：英文没写就回退中文，写了就用英文', () {
      String? picked(Locale locale, String notesEn) => pickWhatsNewChangelog(
        pendingVersion: '1.7.0',
        changelogZh: '中文那一份',
        changelogEn: notesEn,
        shownVersion: null,
        currentVersion: '1.7.0',
        locale: locale,
      );
      expect(picked(en, ''), '中文那一份');
      expect(picked(en, 'English copy'), 'English copy');
      expect(picked(zh, 'English copy'), '中文那一份');
    });
  });

  group('管理器的读口与"弹过"记号（首启弹一次、二启不弹）', () {
    test('落盘 ⇒ 读到一次；记过这一版之后读不到', () async {
      final manager = AppUpdateManager.instance;
      final current = manager.currentVersion;
      final prefs = await SharedPreferences.getInstance();
      // 拿本机这版当"目标版本"来造：大版本那一判在 stage 里比的是 from，
      // 所以这里直接从更早的一版出发，保证 stage 一定落盘。
      final staged = await stageWhatsNewChangelog(
        prefs: prefs,
        fromVersion: '0.1.0',
        update: checkResult(version: current, notes: '这一版的说明'),
      );
      expect(staged, isTrue);

      expect(
        await manager.readWhatsNewChangelog(locale: zh),
        '这一版的说明',
        reason: '首启必须读到这一句，否则"落盘"那一半就白做了',
      );

      await manager.markWhatsNewShown(current);
      expect(
        await manager.readWhatsNewChangelog(locale: zh),
        isNull,
        reason: '二启再弹就等于每次启动都打断用户一次',
      );
    });
  });
}
