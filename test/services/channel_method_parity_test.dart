import '../support/source_guards.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MethodChannel 方法名双端契约守卫。
///
/// 背景：`com.fnthink.notice/notification` 是单通道 + 按域分发的结构。Kotlin 侧
/// 由 5 个 ChannelHandler 各自 `when (call.method)` 消费，Dart 侧散落在
/// pages/services 中以 `invokeMethod('xxx')` 直接调用。方法名是**字符串契约**，
/// 编译器完全不校验——重命名一端、删掉一个分支、或新增 Dart 调用而忘记加原生
/// 分支，都不会有任何编译期或测试期报错。
///
/// 本测试把这条隐式契约变成显式断言，锁两件事：
///
/// 1. **方向 1（致命）= 0**：Dart 调用的每个方法名，Kotlin 必须已定义。
///    违反后果是运行时 `MissingPluginException`——通常只在某个特定页面/按钮
///    被点到时才炸，常规回归测试（走 mock 通道）根本发现不了。
///    这是本文件存在的首要原因，不允许为通过而放宽。
///
/// 2. **总数 == 100**：防止「悄悄删掉一个原生分支」或「新增分支忘记登记」。
///    （6e 加了两个非侵入探测 `probeAppChannelToken` / `verifySmtp`：91 → 93；
///     T20 引擎规则入 DB，删掉两处原生镜像写 `setBatteryRules` / `setTemperatureRules`、
///     换成一枚无载荷的 `refreshEngineRules`：93 → 92；
///     T26 B 半给幻念推送身份开了一个**新域** `FnthinkChannelHandler`，加
///     `getFnthinkIdentity` / `signFnthinkBytes`：93 → 95。
///     这两枚的 Dart 半边随后落在 `lib/services/fnthink_identity_service.dart`（T29 入口），
///     所以方向 1 现在真的守着它们：改名或删掉原生分支 ⇒ 立刻红，不是"将来也许会红"。
///     T48 前置在同一域加 `showFnthinkInbox`：95 → 96。它的 Dart 半边是
///     `lib/services/fnthink_inbox_display.dart` —— 这条链路的返回值直接决定 ack 报
///     `displayed` 还是 `delivered`，所以改它的一端绝不会无人知晓。
///     T33 第二片（§4-9）在同一域加 `scheduleFnthinkPresence` / `cancelFnthinkPresence` /
///     `fnthinkPresenceStatus`：96 → 99。⚠ **登记是下一片才补的**：这三枚在 `80bd66f` 当天
///     就把这两条断言打红了，而那片只跑了 gradle 那三件套（JVM 守卫 / 编译 / lint），
///     没跑全量 App 套件 —— 守卫喊了，是没去听。教训写进 roadmap 那条动态。
///     再加 `roundDone`：99 → 100。它不在 `channels/` 那批里，而是 worker 自己
///     `MethodChannel(PRESENCE_CHANNEL).setMethodCallHandler(this)` 接的那一发回报，
///     所以扫描器现在必须看得见第二类 handler（见 [_nativeChannelMethods]）——
///     正确的修法从来不是把名字从 Dart 集合里剔掉，那是把守卫关掉。
///     T83 在同一域加 `takeFnthinkOpenTarget`（点通知要跳去的那一条，Dart 侧读者是
///     `FnthinkInboxDisplay.takeOpenTarget`）：100 → 101。这一枚的对应方向与其余不同 ——
///     **它是 Dart 主动拉**，因为原生推的时机（configureFlutterEngine）比 Dart 装 handler 更早，
///     推出去会静默丢，表现正是这片要修的"点了通知只打开软件"。）
///     #176 片4 再加 `takeFnthinkPairLink`（点开的配对链接，Dart 侧读者是
///     `FnthinkPairLinkReader.take`）：101 → 102。与上面那一枚同一个形状：**冷启动只能拉**，
///     热恢复才有 `onFnthinkPairLinkReceived` 那一发讯号 —— 两个入口共用 take 这一个出口，
///     所以同一个链接不可能弹两次输入层（口令是 singleUse 的）。）
///     远程执行片3c-5 开过一个新域 `RemoteExecChannelHandler`（显示/清理/问撤销/忘掉，
///     102 → 106）；片3c-6「白名单通知触发」在同一域加 `takeLocalCommand`：106 → 107。
///     它的 Dart 半边是 `RemoteExecutionNotifier.takeLocalCommand`，方向 1 真的守着它 ——
///     漏改原生那一支的话这一条会当场红，而不是运行时 MissingPluginException。
///    数字变化本身没风险，但**未经确认**的数字变化应当让人停下来看一眼：
///    改动这个期望值时必须同时确认 Dart 侧是否也该同步。
///
/// 方向 2（Kotlin 定义但 Dart 未调用）**不做断言**：其中一批是原生自用
/// （如 `openAppDetailsSettings` 被 MainActivity 内部 7 处直接调用），
/// 属正常设计，不必也不该强制 Dart 调用。
void main() {
  /// 仓库根目录。`flutter test` 的 cwd 是项目根，但为兼容从子目录运行做了探测。
  final root = projectRoot();

  /// ⚠ 两侧解析包在 try 里：目录改名时 `_nativeChannelMethods` 的 StateError 或
  ///   `listSync` 的 FileSystemException 若抛在 `main()` 顶层 = 整个文件加载失败，
  ///   CI 表现为"这个文件没有用例"而不是红（base.md（75））。改成红交给下面第一条用例。
  Object? parseError;
  Map<String, List<String>> native = const {};
  Set<String> dart = const {};
  try {
    /// 原生 MethodChannel 方法名 → 定义它的 handler 文件。
    native = _nativeChannelMethods(root);

    /// Dart 侧实际会发出的方法名集合。
    dart = _dartChannelMethods(root);
  } catch (e) {
    parseError = e;
  }

  group('MethodChannel 方法名双端契约', () {
    test('两侧源码都解析成功（口径漂移要红，不许静默变空）', () {
      final err = parseError;
      if (err != null) throw err;
      expect(native, isNotEmpty, reason: '原生侧一枚方法名都没解析到');
      expect(dart, isNotEmpty, reason: 'Dart 侧一枚方法名都没解析到');
    });

    test('方向1：Dart 调用的方法 Kotlin 必须已定义（MissingPluginException 守卫）', () {
      final undefined = dart.difference(native.keys.toSet()).toList()..sort();
      expect(
        undefined,
        isEmpty,
        reason:
            '以下方法名被 Dart 通过 MethodChannel 调用，但没有任何 Kotlin ChannelHandler '
            '定义它们。运行时将抛 MissingPluginException：\n'
            '${undefined.map((m) => '  - $m').join('\n')}\n'
            '修复方式二选一：在对应 handler 补 when 分支，或删除 Dart 侧调用。',
      );
    });

    // T55 新增三发（getSdkInt / isPromotedNotificationPermissionGranted /
    // requestPromotedNotificationPermission）—— 提升/悬浮通知权限那一族（Android 16+），
    // 见 §7 第 8.196 版。107 → 110 是**有意**改动，不是分支被删。
    // T94 片4 新增一发（`fanoutDone`，挂在 `com.fnthink.notice/fanout` 上）：
    // 「收到通知就转」那一轮跑完之后 Dart 交回结果的那一发，与 `roundDone` 同形但**不同一条通道**。
    // 110 → 111 是**有意**改动，不是分支被删。
    // 首页那颗圈的第三态（监听开着、推送被用户从通知栏/桌面小部件暂停）新增两发：
    // `isPushActive`（读原生那一份 `push_toggle_state/push_active`，Dart 此前完全读不到）
    // 与 `resumePush`（暂停态下点那一圈 = 恢复推送，**不停监听**）。
    // 111 → 113 同样是**有意**改动：这两发没有第二个读者，也没有第二个写者。
    // 113 → 114（T124 片B-2）：`showFnthinkAlert` —— 远程「让这台响一条」的显示口，
    // 与收件显示同一条渠道、同一条"没显示就回 false"的纪律。
    // 116 → 119（T124 片C-1）：通话记录那一族三发 —— `searchFnthinkCallLog`（按关键词搜）
    // 与 `isCallLogPermissionGranted` / `requestCallLogPermission`（**单独一次**申请：
    // 不并进 READ_PHONE_STATE 那次，见 MainActivity 那枚请求码上的说明）。
    test('原生方法总数 == 122（防止分支被静默删除/新增未登记）', () {
      expect(
        native.length,
        122,
        reason:
            '原生 ChannelHandler 方法数发生变化。\n'
            '当前分布：${_distribution(native).entries.map((e) => '${e.key}=${e.value}').join(', ')}\n'
            '若为有意改动，请同时更新本期望值；若为误删，请恢复分支。',
      );
    });

    test('每个 handler 的方法数固定（按域分布守卫）', () {
      final dist = _distribution(native);
      expect(dist, {
        'ConfigChannelHandler': 34,
        // T55：提升/悬浮通知那一族 +3；T124 片C-1：通话记录那两发（读权限 + 申请）+2；
        // 片C-2：定位那两发（FINE||COARSE 的读权限 + 一次'精确／大致'申请）+2。
        'PermissionChannelHandler': 30,
        // 首页第三态那两发挂在这一域（读推送开关 + 恢复推送）。15 → 17。
        'DeviceChannelHandler': 17,
        'FileChannelHandler': 12,
        'StatsChannelHandler': 9,
        // T124 片B-2 起 9（`showFnthinkAlert`）；片B-3 起 10（`searchFnthinkSms`）；
        // 片B-4 起 11（`launchFnthinkTarget`）；片C-1 起 12（`searchFnthinkCallLog`）；
        // 片C-2 起 13（`getFnthinkLocation`）。
        'FnthinkChannelHandler': 13,
        // 远程执行（片3c-5）：状态栏通知的显示/清理 + "被原生记下撤销"的读口。
        // ⚠ 前四发是**撤销入口其二**那条路径的唯一通道 —— 用户在通知栏按下的那一下
        //   落在原生（Dart 当时不一定在跑），到点动手前由 Dart 回来问一句。
        // 白名单通知触发那一路（片3c-6）加 `takeLocalCommand`：**冷启动只能拉**
        // （原生推的讯号比 Dart 装 handler 更早，推出去会静默丢），与上面
        // `takeFnthinkOpenTarget` / `takeFnthinkPairLink` 同一个形状。106 → 107。
        'RemoteExecChannelHandler': 5,
        // 不走 ChannelDispatcher 的那一类：worker 自己注册一条通道，
        // Dart 那一轮的成与败都只交这一发。它必须**被扫到**才谈得上被守住（见上面的登记）。
        'FnthinkPresenceWorker': 1,
        // T94 片4：幻念转发那一轮（事件驱动，一条通知排一次）的回报口。
        // 与上面那个形状相同、通道不同 —— 合成一个 worker 会让「收货要等下一次闹钟」
        // 和「转发要等下一条通知」共用一个 latch，而它们的截止时刻完全不同。
        'FnthinkFanoutWorker': 1,
      });
    });

    test('方法名全局唯一（不允许两个 handler 抢同一方法名）', () {
      final dup = native.entries.where((e) => e.value.length > 1).toList();
      expect(
        dup,
        isEmpty,
        reason:
            '同一方法名被多个 handler 定义：'
            '${dup.map((e) => '${e.key} -> ${e.value}').join('; ')}。'
            'ChannelDispatcher 取首个消费者，后面的分支永远不会执行（死分支）。',
      );
    });

    test('Dart 侧抽取有效（正面锚点：拦住"一个都没抓到"的假绿）', () {
      // 方向 1 判的是 dart ⊆ native —— dart 集合若因正则退化而变空，那条断言就**永远成立**，
      // 整个文件只剩"原生方法数"在守，而它守不到"Dart 调用了一个不存在的方法"。
      expect(
        dart.length,
        greaterThanOrEqualTo(70),
        reason:
            'Dart 侧只解析出 ${dart.length} 个方法名，远低于原生这一面的实际调用量：'
            '要么 _dartChannelMethods 的正则退化了，要么调用写法又多了第五种',
      );
      // 三种书写形态各钉一枚代表：少一种 = 对应的解析分支已经不再命中。
      const probes = {
        'testAppChannel': 'invokeMethod(\'m\') 同行写法',
        'isIgnoringBatteryOptimizations':
            'invokeMethod<bool>(\\n  \'m\', 带泛型跨行写法',
        'requestBatteryOptimization': '_requestPermission(\'m\') 间接转发写法',
      };
      for (final probe in probes.entries) {
        expect(
          dart,
          contains(probe.key),
          reason: '缺「${probe.value}」这一形态的样本 ⇒ 该形态以后新增方法会漏出守卫',
        );
      }
    });

    test('三个非侵入探测方法都有 Dart 侧调用点（6e 的动态方法名补钉）', () {
      // 探测走 `ChannelProbeService`，方法名来自变量 ⇒ 上面那套字面量解析看不见它。
      // 方向 2（原生有、Dart 不调）本文件整体不做断言，所以这里为这一族单独钉一次：
      // 原生多出一扇没人走的门 = 探测白写，而通道状态列会一直说"未知"。
      final dartFiles = Directory('$root/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      for (final name in const [
        'probeChannelHealth',
        'probeAppChannelToken',
        'verifySmtp',
      ]) {
        final hits = dartFiles
            .where(
              (f) => stripComments(f.readAsStringSync()).contains("'$name'"),
            )
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(
          hits,
          isNotEmpty,
          reason:
              '$name 在 lib 里没有任何字面量调用点 ⇒ 原生那扇门白开了：'
              '这一族的通道状态永远刷不出结论，而测试全绿',
        );
      }
    });
  });
}

/// 解析 Kotlin 里**所有** MethodChannel handler 的方法名，两种形态都要看见：
///
/// 1. `channels/*.kt` 里按域分发的 `ChannelHandler`：分支写作 `"methodName" ->`，
///    由 `ChannelDispatcher` 依序交给首个消费者。
/// 2. **不走分发器**的那一类：某个类自己 `MethodChannel(ch).setMethodCallHandler(this)`，
///    分支写作 `call.method == "methodName"`。目前只有 `FnthinkPresenceWorker`
///    （后台那一轮的 `roundDone` 回报口，挂在 `com.fnthink.notice/presence` 上，
///    与 App 主通道不是一条）与 `FnthinkFanoutWorker`（T94 片4：幻念转发的 `fanoutDone`，
///    挂在 `com.fnthink.notice/fanout` 上 —— **不是第三条**通道，是同一族事件驱动的第二个引擎，
///    所以单独一个 worker 而不塞进收货那一个：那个是闹钟节奏驱动的，这个是一条通知排一次的）。
///
/// ⚠ 第 2 类必须被扫到，不能靠"从 Dart 集合里把它剔掉"来放行：那样方向 1 就少了一整个
/// 通道，改名/删分支从此无人知晓。这一类漏扫时的红长得像"Dart 调了不存在的方法"，
/// 而真相是扫描器瞎了一半 —— 判据要认得全两种写法。
///
/// 返回 **方法名 → 定义它的 handler 列表**（列表而非单值）：同一方法名被两个
/// handler 定义时必须能同时看到两者，否则「重名死分支」会被 Map 覆盖而静默消失，
/// 唯一性断言将永远通过（典型「测试通过 ≠ 有保护」陷阱）。
///
/// 只认 when 分支形态（字符串字面量紧跟箭头）与 `call.method ==` 形态，
/// 避免把 `call.argument<...>("key")` 这类参数名误判成方法名。
Map<String, List<String>> _nativeChannelMethods(String root) {
  final dir = Directory(
    '$root/android/app/src/main/kotlin/com/fnthink/notice/channels',
  );
  final handlers = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.kt'))
      .where((f) => !f.path.endsWith('ChannelDispatcher.kt'))
      .toList();

  if (handlers.isEmpty) {
    throw StateError('未在 ${dir.path} 找到任何 ChannelHandler');
  }

  final standalone = [
    '$root/android/app/src/main/kotlin/com/fnthink/notice/'
        'FnthinkPresenceWorker.kt',
    '$root/android/app/src/main/kotlin/com/fnthink/notice/'
        'FnthinkFanoutWorker.kt',
  ];

  final branchPattern = RegExp(r'"([A-Za-z0-9_]+)"\s*->');
  final equalityPattern = RegExp(r'call\.method\s*==\s*"([A-Za-z0-9_]+)"');
  final result = <String, List<String>>{};
  void collect(File f, RegExp pattern) {
    final name = f.uri.pathSegments.last.replaceAll('.kt', '');
    final src = stripComments(f.readAsStringSync());
    for (final m in pattern.allMatches(src)) {
      result.putIfAbsent(m.group(1)!, () => []).add(name);
    }
  }

  for (final f in handlers) {
    collect(f, branchPattern);
  }
  for (final path in standalone) {
    final f = File(path);
    if (!f.existsSync()) {
      throw StateError('登记的独立 handler 源文件不见了：$path');
    }
    collect(f, equalityPattern);
  }
  return result;
}

/// 解析 Dart 侧实际发出的方法名。
///
/// ⚠ 两侧源码都先 `stripComments`：本守卫靠「invokeMethod 之后第一个字符串字面量」
/// 取名字，注释里出现 `invokeMethod` 这个词（写文档时很常见）就会把注释正文里的
/// 引号片段当成方法名 —— T08-C 就是这么红了一次（`'switch'` 被当成方法）。
/// 剥注释是引号感知的，所以真实字符串字面量不受影响。
///
/// 两种来源：
/// 1. `invokeMethod` 之后的第一个字符串字面量。用「窗口内首个字面量」而非
///    「同行正则」，是为了同时覆盖 `invokeMethod('m')`、`invokeMethod('m', {..})`、
///    `invokeMethod<T>('m')`、`invokeMethod(\n  'm',\n)` 四种写法——项目中四种都在用。
/// 2. 项目内的间接转发点 `_requestPermission('m')`（permission_service.dart 的
///    统一权限请求入口，方法名以参数传入，不直接出现在 invokeMethod 之后）。
///
/// 第三种写法是**方法名来自变量**（`ChannelProbeService` 按 family 选探测方法）：
/// 这种调用点必须跳过 —— 窗口里的首个字面量会是**后面的**表达式
/// （`r['reachable']` ⇒ 曾被当成方法名 `'reachable'` 而假红）。跳过不等于漏守：
/// 变量取值的集合由下面那条「三个探测方法都得在 lib 里出现为字面量」钉住。
Set<String> _dartChannelMethods(String root) {
  final files = Directory('$root/lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  final window = RegExp(r'''['"]([A-Za-z0-9_]+)['"]''');
  final indirect = RegExp(r"_requestPermission\(\s*'([A-Za-z0-9_]+)'");
  final methods = <String>{};

  for (final f in files) {
    final src = stripComments(f.readAsStringSync());
    for (final call in RegExp(r'invokeMethod\b').allMatches(src)) {
      // 240 字符足够覆盖 invokeMethod<T>(\n  'name',\n) 的最长现实形态；
      // 不足以跨到下一次 invokeMethod（方法名之间通常隔着参数与日志）。
      final end = call.end + 240;
      final slice = src.substring(
        call.end,
        end > src.length ? src.length : end,
      );
      final lit = window.firstMatch(slice);
      if (lit == null) continue;
      // 字面量之前除泛型与标点之外还有标识符 ⇒ 方法名不是字面量（动态调用点）
      final before = slice
          .substring(0, lit.start)
          .replaceAll(RegExp(r'<[^<>]*>'), '');
      if (RegExp(r'[A-Za-z_$][\w$]*').hasMatch(before)) continue;
      methods.add(lit.group(1)!);
    }
    for (final m in indirect.allMatches(src)) {
      methods.add(m.group(1)!);
    }
  }
  return methods;
}

Map<String, int> _distribution(Map<String, List<String>> native) {
  final dist = <String, int>{};
  for (final handlers in native.values) {
    for (final handler in handlers) {
      dist[handler] = (dist[handler] ?? 0) + 1;
    }
  }
  return dist;
}
