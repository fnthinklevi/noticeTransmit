import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/pages/splash_page.dart';

/// T253：启动装配每一步的**有界**等待。
///
/// 真机现形（2026-11-14）：长锁屏后 splash 永远停在「加载通知记录」——那一步的
/// `await` 不会自己回来（数据库被后台残留连接占住，框架连接池那个等待没有超时）。
/// 这条判据保证"卡住"会变成一个**点名到步骤**的异常，由启动页显示显式出口，
/// 而不是让整条链停在原地等 20 秒 watchdog 再显示一句"初始化超过 20 秒"。
void main() {
  test('超时 ⇒ StartupStalledException（不吞、点名到步骤）', () async {
    final never = Completer<void>();
    final sw = Stopwatch()..start();
    Object? err;
    try {
      await runBoundedStartupStep(
        'records',
        () => never.future,
        deadline: const Duration(milliseconds: 50),
      );
    } catch (e) {
      err = e;
    }
    sw.stop();
    expect(err, isA<StartupStalledException>());
    expect((err as StartupStalledException).step, 'records');
    expect(
      sw.elapsedMilliseconds,
      lessThan(2000),
      reason: '有界：期限到就该回来；等了 2 秒以上说明"超时"这条判据根本没生效',
    );
  });

  test('普通异常照旧只记日志、不挡启动（与原来的逐步 try/catch 同语义）', () async {
    await runBoundedStartupStep(
      '某一步',
      () async => throw StateError('boom'),
      deadline: const Duration(milliseconds: 50),
    );
  });

  test('正常完成不抛，且动作真的跑了', () async {
    var ran = false;
    await runBoundedStartupStep('某一步', () async {
      ran = true;
    }, deadline: const Duration(milliseconds: 50));
    expect(ran, isTrue);
  });
}
