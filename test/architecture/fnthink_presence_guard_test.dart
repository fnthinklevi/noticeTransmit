import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/di/service_locator.dart';
import 'package:notice_transmit/services/fnthink_presence_scheduler.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';

import '../support/source_guards.dart';

/// 幻念推送"被杀之后还有人去问一次货"的**跨语言装配**守卫（T33 第二片 / §4-9 片1b）。
///
/// 为什么这一族只能靠守卫、不能靠功能测试：真正的失败要等一次"进程被 ROM 杀掉"才现形，
/// 而那在 CI 里复现不出来（必须真机，见任务 #124 那一栏）。所以这里钉的是**链条的每一环
/// 都还在、且两端口径一致**：
///
///  ① 装配点：`presenceNotice` 没接上时**全场测试仍然绿**（协调者的用例都把 hook 当参数传，
///     不经过 DI），表现是"收货照常、界面照常，只有被杀之后那一天没人再取货"；
///  ② 后台入口的赋值点：漏接时红的是那份占位实现，而占位实现只有在真有人从闹钟那条路进来
///     才会被调到 —— 所以钉"这行赋值在不在、在的是不是唯一一个作者"；
///  ③ 三个**跨语言字符串**（通道名、prefs 键名、方法名）：两边各写一份，错一个字符没有任何
///     东西报错，最典型的一条是"闹钟响过、任务跑过、而没人说这一轮结束了"（只能等到超时）；
///  ④ `@pragma('vm:entry-point')`：没有 Dart 调用点，tree-shaking 只看 pragma，少了它 release
///     包里那个函数会被摇掉，而 handle 指向一个不存在的符号；
///  ⑤ 节奏只有一个作者：数字只在契约里，Dart 读一次交下去，Kotlin 只转交。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  /// Kotlin 侧的源码（剥注释；`//` 与 `/* */` 两种都要，注释里的通道名同样会污染断言）。
  String kotlin(String name) =>
      read('android/app/src/main/kotlin/com/fnthink/notice/$name');

  const schedulerRel = 'lib/services/fnthink_presence_scheduler.dart';
  final scheduler = read(schedulerRel);
  final locator = read('lib/di/service_locator.dart');
  final channelNames = read('lib/services/platform_channel.dart');

  tearDown(() => getIt.reset());

  group('装配点（漏接时全场仍绿，所以只能在这儿钉）', () {
    test('DI 起来的协调者接上了续排，而闹钟与它是同一个 scheduler', () {
      setupLocator();
      final c = getIt<FnthinkReceiveCoordinator>();
      expect(
        c.presenceNotice,
        isNotNull,
        reason:
            '漏接 `presenceNotice:` 这一行时的表现不是崩，是链条悄悄断：'
            '收货照常、界面照常，只有"被 ROM 杀掉之后"那一天没人再去问一次货 —— '
            '而这正是这一片存在的唯一理由',
      );
      expect(
        getIt<FnthinkPresenceScheduler>(),
        isA<FnthinkPresenceScheduler>(),
        reason:
            '协调者那个 hook 是从这里取的，注册顺序写反会在第一次取协调者时抛 —— '
            '这条断言顺便把"注册过"钉住',
      );
    });

    test('后台那一轮的赋值点只有一个作者，且它跑的就是那个协调者（不许另起一条收货路）', () {
      // 声明那一份在 scheduler 里（占位实现），赋值那一份只许在 DI 里。
      // 数文件而不是数次数：多一处赋值 = 多一份"这一轮该干什么"，而其中一份永远跑不到。
      final writers =
          Directory('$root/lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .map(
                (f) => f.path
                    .replaceAll('\\', '/')
                    .replaceFirst(RegExp(r'^\./'), ''),
              )
              .where(
                (p) => read(
                  p.substring(p.indexOf('lib/')),
                ).contains('runFnthinkPresenceRound ='),
              )
              .toList()
            ..sort();

      expect(writers, [
        'lib/di/service_locator.dart',
        schedulerRel,
      ], reason: '除了 scheduler 里那份占位声明，全仓只许 DI 一处给它赋值');
      expect(
        blockAfter(
          scheduler,
          'Future<void> Function() runFnthinkPresenceRound =',
        ),
        contains('_presenceRoundUnavailable'),
        reason: '那份占位得一直在：装配漏了时要红得起来，而不是静默"跑了而什么都没做"',
      );
      final block = blockAfter(locator, 'runFnthinkPresenceRound =');
      expect(
        block,
        contains('receiveOnce('),
        reason:
            '后台那一轮与前台"立即收取"必须是同一条路（同一套判据、同一个内核）。'
            '在这儿拼第二个 poll 循环，就等于给同一个协议找第二个作者',
      );
      expect(block, contains('setupLocator()'));
      expect(
        block,
        contains('isRegistered'),
        reason: '那颗引擎里 getIt 是空的：不判一次就装配，等于第一轮必红',
      );
    });
  });

  group('三个跨语言字符串（各写一份，错一个字符没人报错）', () {
    test('排/撤/查那三个方法名，Kotlin 那头确实各有一条分支在接', () {
      final handler = kotlin('channels/FnthinkChannelHandler.kt');
      for (final method in const [
        'scheduleFnthinkPresence',
        'cancelFnthinkPresence',
        'fnthinkPresenceStatus',
      ]) {
        expect(scheduler, contains("'$method'"), reason: 'Dart 侧不许留下一个没人接的方法名');
        expect(
          handler,
          contains('"$method" ->'),
          reason:
              '$method 在 Kotlin 的 handler 里没有分支：invokeMethod 会拿到 '
              'MissingPluginException，而协调者那侧只留一行日志 —— 闹钟从此不再续排，'
              '界面上一点看不出来',
        );
      }
    });

    test('闹钟那三个方法走的是 App 那条通道，不是 presence 那条（presence 只承载 roundDone）', () {
      // 这一条钉的是一段已经改掉的行为：worker 把 `FnthinkChannelHandler` 注册在
      // `APP_CHANNEL`（com.fnthink.notice/notification）上，而 presence 通道只有 `roundDone`。
      // 把三个方法发在 presence 通道上，前台那次照样"成功"（协调者不 await），
      // 而闹钟从来没被排过 —— 全场仍绿。
      expect(
        scheduler,
        contains('_channel = channel ?? AppChannels.notification'),
        reason: '排/撤/查三个方法的默认通道就是这一行；写错不会有任何东西报错',
      );
      final schedulerClass = blockAfter(
        scheduler,
        'class FnthinkPresenceScheduler {',
      );
      final presenceBlock = blockAfter(
        scheduler,
        'Future<void> fnthinkPresenceEntrypoint()',
      );
      // 三个方法都在 scheduler 那一类里、都从 `_channel` 发出；一个都不许出现在入口那段里。
      for (final method in const [
        'scheduleFnthinkPresence',
        'cancelFnthinkPresence',
        'fnthinkPresenceStatus',
      ]) {
        expect(
          schedulerClass,
          contains("_channel.invokeMethod"),
          reason: '$method 应当从那条注入的通道发出',
        );
        expect(schedulerClass, contains("'$method'"));
        expect(
          presenceBlock,
          isNot(contains("'$method'")),
          reason:
              '$method 一旦从后台入口那段发出去，就是发到 presence 通道上 —— '
              'worker 只认 roundDone，别的都 notImplemented，而协调者不 await 那次调用，'
              '于是"闹钟从来没被排过"这件事全场没有一处会红',
        );
      }
      expect(
        presenceBlock,
        contains('kFnthinkPresenceChannel'),
        reason: '入口那颗引擎上，回报走的是 presence 通道（worker 自己接）',
      );
      // presence 通道名在整个文件里只许出现在两处：它自己的声明、以及入口。
      expect(
        RegExp('kFnthinkPresenceChannel').allMatches(scheduler).length,
        2,
        reason: '多一处就说明有别的方法发在 presence 通道上；少一处说明回报口没了',
      );
    });

    test('通道名与 prefs 键名：Dart 那份与 Kotlin 那份逐字相同', () {
      String dartChannelName(String constant) {
        final m = RegExp(
          "$constant\\s*=\\s*MethodChannel\\(\\s*'([^']+)'",
        ).firstMatch(channelNames);
        if (m == null) throw StateError('platform_channel.dart 里找不到 $constant');
        return m.group(1)!;
      }

      final worker = kotlin('FnthinkPresenceWorker.kt');
      String kotlinConstant(String name) {
        final m = RegExp('const val $name = "([^"]+)"').firstMatch(worker);
        if (m == null) throw StateError('worker 里找不到 $name');
        return m.group(1)!;
      }

      // ① App 那条主通道：Dart 的 AppChannels.notification ↔ Kotlin 的 APP_CHANNEL
      final appChannel = dartChannelName('notification');
      expect(
        appChannel,
        kotlinConstant('APP_CHANNEL'),
        reason: '三个闹钟方法挂在它上面。两边不同名 ⇒ MissingPluginException（静默）',
      );
      expect(
        kotlin('MainActivity.kt'),
        contains('val channel = "$appChannel"'),
        reason:
            '前台那台引擎注册 FnthinkChannelHandler 用的必须是同一条通道 —— '
            '否则"前台排得上、后台那一轮排不上"这种半瞎状态谁也说不清',
      );
      // ② 回报通道：Dart 的 kFnthinkPresenceChannel ↔ Kotlin 的 PRESENCE_CHANNEL
      expect(
        kFnthinkPresenceChannel,
        kotlinConstant('PRESENCE_CHANNEL'),
        reason: 'roundDone 送错门 ⇒ worker 只能等到超时，账上记的是"任务卡住"',
      );
      // ③ prefs 里那个 handle：Dart 写的是裸键，shared_preferences 落盘时加 `flutter.`，
      //    Kotlin 读的是带前缀那一份 —— 这层关系就靠这一条断言维持。
      expect(
        'flutter.$kFnthinkPresenceHandleKey',
        kotlinConstant('KEY_HANDLE'),
        reason: '对不上时后台那一轮每次都在 no-entry-handle 上跳过：闹钟响、任务跑、货一件不上',
      );
    });

    test('roundDone 两边各写一次：Kotlin 认的那一句就是 Dart 交回的那一句', () {
      expect(
        kotlin('FnthinkPresenceWorker.kt'),
        contains('call.method == "roundDone"'),
      );
      expect(
        blockAfter(scheduler, 'Future<void> fnthinkPresenceEntrypoint()'),
        contains("'roundDone'"),
      );
    });

    test('开机重排读的那个开关键名，与 Dart 写的那一份逐字相同（§4-9 片1c）', () {
      // 这一条是**跨语言字符串**里最容易被静默弄坏的一条：Dart 那边把 `keyReceiveEnabled`
      // 改个名，原生这一侧永远读到 false，表现是"重启之后闹钟不再重排" —— 而界面上开关
      // 明明写着开着，全场测试也都绿。这里读的是 Dart 自己的那个常量（真值在 Dart），
      // 拿它去比原生源码里那个字面量。
      expect(
        kotlin('FnthinkPresenceAlarm.kt'),
        contains(
          'getBoolean("flutter.${FnthinkSettings.keyReceiveEnabled}", false)',
        ),
        reason:
            '原生读的键名必须是 `flutter.` + Dart 那份键：对不上时开机重排永远走"开关是关的"'
            '那一支，而用户在设置页看到的是开着',
      );
      expect(
        kotlin('BootReceiver.kt'),
        contains('armIfWantedAfterBoot()'),
        reason:
            'AlarmManager 的排程不跨重启：BootReceiver 里没有这一行，手机重启一次这台就'
            '再也不自己醒了（而`重新打开 App`之前没有任何地方会发现）',
      );
    });
  });

  group('入口与节奏的形状', () {
    test('后台入口带 @pragma（没有调用点，tree-shaking 只认这一行）', () {
      final raw = File('$root/$schedulerRel').readAsStringSync();
      expect(
        RegExp(
          "@pragma\\('vm:entry-point'\\)\\s*\\nFuture<void> fnthinkPresenceEntrypoint\\(\\)",
        ).hasMatch(raw),
        isTrue,
        reason:
            '少了 pragma ⇒ release 包里这个函数被摇掉，handle 指向一个不存在的符号；'
            '而那条错误要等到第一次"被杀之后"才现形',
      );
    });

    test('roundDone 在 finally 里：那一轮成不成都要说得出话', () {
      final body = blockAfter(
        scheduler,
        'Future<void> fnthinkPresenceEntrypoint()',
      );
      // ⚠ 三条都要，顺序也有意义：只比"位置先后"的话，`roundDone` 整个消失时 indexOf 是 -1，
      //   `-1 < 任何非负数` 恒为真 ⇒ 植入"把那一发删掉"反而测不出来（本仓"断言要能红"的老账）。
      expect(
        body,
        contains("'roundDone'"),
        reason: '入口里根本没有 roundDone ⇒ worker 只能等到超时。先确认它在，再谈它在不在 finally 里',
      );
      expect(
        body,
        contains('finally'),
        reason: '没有 finally 块，"成不成都要说得出话"就只剩成功那一半',
      );
      expect(
        body.indexOf('finally') < body.indexOf("'roundDone'"),
        isTrue,
        reason:
            'roundDone 一旦不在 finally 里，失败路径就没人交回结果 —— '
            '原生那侧看到的是"任务卡住 90 秒"，不是"这一轮失败了"',
      );
    });

    test('间隔不许有第二个作者：Dart 这一层一个数字都不写', () {
      expect(
        scheduler,
        contains('pollIntervalSeconds'),
        reason: '唯一的读数处：契约 presence.pollIntervalSeconds',
      );
      expect(
        RegExp(r'seconds[^0-9A-Za-z_]*[0-9]').hasMatch(scheduler),
        isFalse,
        reason:
            '这里出现"seconds 旁边跟一个数字"就是实现里藏了一份节奏 —— '
            '改契约那一刀不会有任何东西报错（本仓"同一个数两处作者"的老错法）',
      );
    });

    test('Kotlin 那一侧不读契约（它只转交 Dart 交下来的那个数）', () {
      for (final name in const [
        'FnthinkPresenceAlarm.kt',
        'FnthinkPresenceReceiver.kt',
        'FnthinkPresenceWorker.kt',
      ]) {
        expect(
          kotlin(name),
          isNot(contains('pollIntervalSeconds')),
          reason:
              '$name 里出现 pollIntervalSeconds 就是两份节奏作者：'
              'Dart 的契约间隔与 Kotlin 自己的读数会互相追',
        );
      }
    });
  });
}
