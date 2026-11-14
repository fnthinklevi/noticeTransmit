import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T253：启动卡死那一族的三条接线守卫（2026-11-14 真机：长锁屏后 splash 永远停在
/// 「加载通知记录」，force-stop 才恢复）。
///
/// 病根：插件 `singleInstance` 缺省 true ⇒ 跨 isolate 复用同一条连接；后台引擎死在
/// 事务中途，那条连接与它的事务不被 detach 关掉 ⇒ 前台再写就排在它后面等框架连接池，
/// 而那个等待没有超时。改法四层，每一层都必须**真的接上**：
///  ① 开库各持一条连接（`singleInstance: false`）；
///  ② 开库后有界锁等待（`PRAGMA busy_timeout`）；
///  ③ 一次性后台轮跑完把连接还回去（插件 detach 不关库）；
///  ④ 启动页逐步有界，卡死时给「重启应用」这个唯一真出口。
/// 本文件钉的是接线（谁调了谁），机制本身在 `busy_timeout_mechanism_test` 与
/// `splash_bounded_step_test` 里用真 SQLite / 真超时跑。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  group('① 开库各持一条连接（singleInstance: false）', () {
    test('_initDatabase 的两条开库路径都传了 singleInstance: false', () {
      final src = read('lib/database/database_helper.dart');
      final init = blockAfter(src, 'Future<Database> _initDatabase() async');
      final opens = RegExp(r'openDatabase\(').allMatches(init).length;
      final isolated = RegExp(r'singleInstance: false').allMatches(init).length;
      expect(opens, 2, reason: '主路径与"备份后重建"那条路径各开一次库；开库点数变了先看这里');
      expect(
        isolated,
        opens,
        reason:
            '有开库点没传 singleInstance: false ⇒ 它会复用别的 isolate 留下的连接，'
            '后台悬挂事务又能把前台写堵死（T253 的病根）',
      );
    });
  });

  group('② 开库后有界锁等待（busy_timeout）', () {
    test('常量在，且开库路径真的执行了 PRAGMA busy_timeout', () {
      final src = read('lib/database/database_helper.dart');
      final m = RegExp(r'busyTimeoutMs = (\d+)').firstMatch(src);
      expect(m, isNotNull, reason: 'busy_timeout 的数值必须有一个作者');
      final tune = blockAfter(src, 'Future<Database> _tuneOpen(');
      expect(
        tune.contains(r'PRAGMA busy_timeout = $busyTimeoutMs'),
        isTrue,
        reason: '没有这条 PRAGMA ⇒ 锁冲突退回框架默认（可能无限等），界面就没有可报的错',
      );
      final init = blockAfter(src, 'Future<Database> _initDatabase() async');
      expect(
        RegExp(r'_tuneOpen\(').allMatches(init).length,
        2,
        reason: '两条开库路径都要经过 _tuneOpen；漏一条就有一条连接没有锁等待上界',
      );
    });
  });

  group('③ 一次性后台轮跑完把连接还回去', () {
    test('收货那一轮与转发那一轮的计划内终点都调了 close()', () {
      final locator = read('lib/di/service_locator.dart');
      final round = blockAfter(
        locator,
        'Future<void> fnthinkBackgroundRound() async',
      );
      expect(
        round.contains('DatabaseHelper().close()'),
        isTrue,
        reason:
            '一次性后台 isolate 跑完不关库 ⇒ 连接留在插件静态表里越积越多，'
            '死在中途的那几条还攥着 WAL 写锁（插件 3.4.1 detach 不关库）',
      );
      final fanout = read('lib/services/fnthink_fanout_entrypoint.dart');
      final entry = blockAfter(
        fanout,
        'Future<void> fnthinkFanoutEntrypoint(List<String>? args) async',
      );
      expect(
        entry.contains('DatabaseHelper().close()'),
        isTrue,
        reason: '转发 worker 每轮起一颗引擎；不关库就是每轮漏一条连接',
      );
    });

    test('DatabaseHelper.close() 真的关句柄并清缓存（下次懒打开）', () {
      final src = read('lib/database/database_helper.dart');
      final close = blockAfter(src, 'Future<void> close() async');
      expect(close.contains('_database = null'), isTrue);
      expect(close.contains('old.close()'), isTrue);
    });
  });

  group('④ 启动页逐步有界 + 卡死显式出口', () {
    test('每个服务装配步骤都经过 runBoundedStartupStep（逐步都有期限）', () {
      final src = read('lib/pages/splash_page.dart');
      final inner = blockAfter(src, 'Future<void> _initServicesInner() async');
      final steps = RegExp(r'runBoundedStartupStep\(').allMatches(inner).length;
      final services = RegExp(r'GetIt\.instance<').allMatches(inner).length;
      expect(
        steps,
        services,
        reason:
            '有服务装配没走有界步骤（steps=$steps, GetIt=$services）⇒ '
            '那一步卡住时整条链只能等 20 秒 watchdog，界面停在一句不点名的话上',
      );
      // ⚠ 这里不用 blockAfter：`runBoundedStartupStep` 带具名参数表，
      //   blockAfter 会在参数表那个 `{` 上收口（只回半截签名，断言恒真）。
      //   下面三条字面量在本文件里各自唯一，全文件断言即可。
      expect(
        src.contains('on TimeoutException') &&
            src.indexOf('on TimeoutException') < src.indexOf('catch (e)'),
        isTrue,
        reason: 'TimeoutException 必须先于通用 catch：否则超时被吞掉，"卡死"又变成沉默',
      );
      expect(src.contains('throw StartupStalledException(step)'), isTrue);
      expect(src.contains('.timeout(deadline)'), isTrue);
    });

    test('卡死档有「重启应用」按钮，且那一发打到原生的 restartApp', () {
      final src = read('lib/pages/splash_page.dart');
      expect(
        src.contains("ValueKey('splash-restart')"),
        isTrue,
        reason: '没有这一枚按钮，卡死档只剩"重试"——而重试清不掉进程内的残留连接',
      );
      expect(
        src.contains("invokeMethod<bool>('restartApp')"),
        isTrue,
        reason: '按钮存在但没打原生 ⇒ 点了什么也不发生',
      );
    });

    test('两条文案键在两种语言里都在（缺一侧会静默回落模板）', () {
      for (final rel in const [
        'lib/l10n/arb/app_zh.arb',
        'lib/l10n/arb/app_en.arb',
      ]) {
        final src = File('$root/$rel').readAsStringSync();
        for (final key in const ['startupDbStalled', 'restartApp']) {
          expect(
            src.contains('"$key"'),
            isTrue,
            reason: '$rel 缺 $key ⇒ 那个语言下按钮/说明会回落成模板文案',
          );
        }
      }
    });
  });
}
