import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/services/channel_config_codec.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/channel_probe_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

/// 6e：三族共用的「非侵入探测调度」单点。
///
/// 这一层存在的理由不是"少写几行"，而是三件事必须只有口径：
/// ① 该不该探（启用 + 超过 staleness）；② 结论写到哪（健康单点的 `<family>:<id>`）；
/// ③ **探测调用本身失败时不许写"不可达"**（那会把"这次没探到"糊弄成"配置坏了"）。
/// webhook 那份循环此前长在页面里，应用/邮件两族要接入时若各抄一份，
/// 三条里任何一条改法不同就会出现"同一应用里三种通道对异常的解释不一样"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChannelHealthStore health;
  late List<MethodCall> calls;
  late List<Map<String, Object?>> results;

  /// 置为 true 时，探测调用直接抛（模拟 MissingPluginException / 原生崩在半路）
  bool throwOnCall = false;

  /// 置为 true 时，原生回 null（老 App 配新原生 / 缺桩）
  bool nullReply = false;

  void stubNative() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          calls.add(call);
          if (throwOnCall) {
            throw MissingPluginException('no handler for ${call.method}');
          }
          if (nullReply) return null;
          final index = calls.length - 1;
          return results[index % results.length];
        });
  }

  ChannelProbeService service() =>
      ChannelProbeService(health: health, channel: AppChannels.notification);

  ChannelProbeTarget target({
    String id = 'ch-1',
    bool enabled = true,
    Map<String, Object?>? args,
  }) => ChannelProbeTarget(
    id: id,
    enabled: enabled,
    method: 'probeChannelHealth',
    args: args ?? const {'url': 'https://example.com/hook'},
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    health = ChannelHealthStore();
    await health.load();
    calls = <MethodCall>[];
    results = <Map<String, Object?>>[
      {'reachable': true, 'latencyMs': 42, 'httpCode': 200},
    ];
    throwOnCall = false;
    nullReply = false;
    stubNative();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, null);
  });

  group('探测调度', () {
    test('只探"启用 + 无结论或已过期"的通道，结论写进本族的键', () async {
      // 第一轮三条都没有结论 ⇒ 全探；第二轮用同一批 id 再看判据（见下）
      final probed = await service().probeStale('webhook', [
        target(id: 'stale'),
        target(id: 'disabled', enabled: false),
        target(id: 'fresh'),
      ]);
      expect(probed, 2, reason: '停用的那条不该产生对外请求（它本来就不在推送路由里）');

      calls.clear();
      final second = await service().probeStale('webhook', [
        target(id: 'disabled', enabled: false),
        target(id: 'fresh'),
      ]);
      expect(second, 0, reason: '时效内有结论就不该再打厂商：探测不是轮询');
      expect(calls, isEmpty);
      expect(
        health.of('webhook', 'fresh')?.reachable,
        isTrue,
        reason: '结论必须落在 channel_health_webhook:<id> 上，否则首页与列表页各说一套',
      );
      expect(health.of('webhook', 'disabled'), isNull);
    });

    test('id 为空的通道不产生对外请求（也写不出键）', () async {
      final probed = await service().probeStale('app', [target(id: '')]);
      expect(probed, 0);
      expect(calls, isEmpty);
    });

    test('原生判"不可达"要如实记下（徽标变红是正确结果，不是失败）', () async {
      results = [
        {'reachable': false, 'latencyMs': 8000, 'httpCode': 0},
      ];
      await service().probeStale('app', [target(id: 'bad')]);
      final record = health.of('app', 'bad');
      expect(record?.reachable, isFalse);
      expect(record?.latencyMs, 8000);
    });

    test('探测调用本身抛异常 ⇒ 不写"不可达"（那是另一件事）', () async {
      throwOnCall = true;
      final probed = await service().probeStale('app', [target(id: 'x')]);
      expect(probed, 0);
      expect(
        health.of('app', 'x'),
        isNull,
        reason:
            '把"这次没探到"记成"这条通道坏了"，用户会去改一份本来正确的凭据；'
            '缺桩/版本错配尤其容易撞上这条（原生没有该方法时 MissingPluginException 必来）',
      );
    });

    test('原生回了非 Map（缺桩 / 老原生）同样不写结论', () async {
      nullReply = true;
      final probed = await service().probeStale('email', [target(id: 'e1')]);
      expect(probed, 0);
      expect(health.of('email', 'e1'), isNull);
    });

    test('一轮没跑完时第二轮直接退出（两个页面同时进不会双倍打厂商）', () async {
      final blocker = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppChannels.notification, (call) async {
            calls.add(call);
            await blocker.future;
            return {'reachable': true, 'latencyMs': 1};
          });
      // 同一个实例（生产里是 GetIt 单例，两个页面拿到的是同一个 ⇒ 在飞保护才有效）
      final prober = service();
      final first = prober.probeStale('webhook', [target(id: 'a')]);
      final second = await prober.probeStale('webhook', [target(id: 'b')]);
      expect(second, 0, reason: '并发跑第二轮 = 同一批凭据被连着探两次');
      blocker.complete();
      await first;
      expect(calls.map((c) => c.arguments), [
        {'url': 'https://example.com/hook'},
      ]);
      expect(calls.length, 1, reason: '只该有第一条的调用；第二条被在飞保护挡住');
    });

    test('每写回一条结论回调一次 onUpdated（页面据此 setState）', () async {
      results = [
        {'reachable': true, 'latencyMs': 1},
        {'reachable': false, 'latencyMs': 2},
      ];
      var updates = 0;
      await service().probeStale('webhook', [
        target(id: 'c1'),
        target(id: 'c2'),
      ], onUpdated: () => updates++);
      expect(updates, 2, reason: '全部跑完才刷新 = 用户看着一片空白等好几秒');
    });
  });

  group('下拉刷新那一发（#182：force 让位过期判据）', () {
    test('probeNow 对刚探过的通道照样再发一次（否则手势是装饰品）', () async {
      await service().probeStale('webhook', [target(id: 'fresh')]);
      expect(calls.length, 1);
      calls.clear();

      final probed = await service().probeNow('webhook', [target(id: 'fresh')]);
      expect(probed, 1, reason: 'stale 那一路被 staleness 挡住是对的，但用户显式拉下来这一发不该被挡');
      expect(calls.length, 1);
    });

    test('对照：同一批目标 probeStale 仍然挡住（force 只开在下拉那一路）', () async {
      await service().probeNow('webhook', [target(id: 'fresh')]);
      calls.clear();
      expect(await service().probeStale('webhook', [target(id: 'fresh')]), 0);
      expect(calls, isEmpty, reason: '进页/回前台那一轮不该被下拉的 force 带跑，否则每次露脸都发一轮请求');
    });

    test('force 也仍然只探启用的（不变量 1 不随 force 松）', () async {
      final probed = await service().probeNow('webhook', [
        target(id: 'off', enabled: false),
      ]);
      expect(probed, 0);
      expect(calls, isEmpty);
    });

    test('force 路径上探测抛异常同样不写"不可达"（不变量 3 不随 force 松）', () async {
      throwOnCall = true;
      expect(await service().probeNow('app', [target(id: 'x')]), 0);
      expect(health.of('app', 'x'), isNull);
    });

    test('probeNow 的结论写回同一把键（与 stale 那一路共用一份数据）', () async {
      results = [
        {'reachable': false, 'latencyMs': 3000, 'httpCode': 500},
      ];
      await service().probeNow('webhook', [target(id: 'ch-1')]);
      final record = health.of('webhook', 'ch-1');
      expect(record?.reachable, isFalse);
      expect(record?.latencyMs, 3000);
    });
  });

  group('探测载荷的跨端键集合', () {
    test('appProbePayload 给得出原生 appChannelTarget 读的每个键', () {
      final produced = ChannelConfigCodec.appProbePayload({
        'appType': 'wecom_app',
        'name': 'n',
        'baseUrl': 'https://qyapi.weixin.qq.com',
        'secret': 's',
        'config': <String, dynamic>{},
      }).keys.toSet();
      expect(
        nativeMapKeys('appChannelTarget'),
        subsetOf(produced),
        reason:
            '原生读得到而 Dart 不发的键 ⇒ 探测按空凭据跑，永远报"认证失败"，'
            '而这条通道其实是好的（测试与探测共用同一份载荷正是为了不再分叉）',
      );
    });

    test('EmailChannel.toMap 给得出原生 emailConfigOf 读的每个键', () {
      final produced = const EmailChannel(
        id: 'e1',
        name: 'n',
        enabled: true,
        role: 'primary',
        smtpHost: 'smtp.example.com',
        smtpPort: 465,
        username: 'alert@example.com',
        password: 'auth-code',
        fromEmail: 'alert@example.com',
        toEmail: 'oncall@example.com',
        useSSL: true,
      ).toMap(includePassword: true).keys.toSet();
      expect(
        nativeMapKeys('emailConfigOf'),
        subsetOf(produced),
        reason: '邮件探测与 testEmail 共用 toMap；漏键 = 握手用空密码，徽标永远红',
      );
    });
  });

  group('认证失败进冷却（T115 护栏②）', () {
    // 判据住在原生那一侧（它看得见异常类型），"失败之后多久不再自动探"住在这的一侧。
    // 这一族的用例都靠注入的 clock 走时间 —— 真实时间等不起，而"用墙钟推进"会让这条
    // 用例变成随机红（本仓的闸门挂死档案里那一类）。
    late DateTime fakeNow;
    ChannelProbeService prober() => ChannelProbeService(
      health: health,
      channel: AppChannels.notification,
      clock: () => fakeNow,
    );

    setUp(() {
      fakeNow = DateTime.now();
      results = [
        {'reachable': false, 'latencyMs': 100, 'authFailure': true},
      ];
    });

    test('冷却时长必须长于时效，否则这一档永远不会生效（第一版就写短了）', () {
      expect(
        ChannelProbeService.authCooldown,
        greaterThan(ChannelHealthStore.staleness),
        reason:
            '自动那一路只在记录过 staleness 之后才发下一发；冷却短于它 ⇒ 冷却在能被观察到'
            '之前就散完了，写成常量却什么都不挡（本仓说的"结构性死分支"就是这个形状）',
      );
    });

    test('认证失败 ⇒ 过了时效也不再自动认证；用户显式下拉照打', () async {
      final p = prober();
      expect(await p.probeStale('email', [target(id: 'e1')]), 1);
      expect(
        health.of('email', 'e1')?.reachable,
        isFalse,
        reason: '结论照实记（徽标变红是正确结果）',
      );

      // 走过期、没走冷却：这时自动那一路**应该**被冷却挡住。
      fakeNow = fakeNow.add(const Duration(minutes: 31));
      calls.clear();
      expect(
        await p.probeStale('email', [target(id: 'e1')]),
        0,
        reason: '授权码错着 + 用户频繁前后台 = 拿自己的账号去撞厂商封禁',
      );
      expect(calls, isEmpty);

      expect(
        await p.probeNow('email', [target(id: 'e1')]),
        1,
        reason: 'force 是用户显式做的那一发，挡掉它就成了"点了没反应"',
      );
    });

    test('冷却到期后自动那一路恢复；另一条通道不受这条的冷却影响', () async {
      final p = prober();
      await p.probeStale('email', [target(id: 'e1')]);

      fakeNow = fakeNow.add(
        ChannelProbeService.authCooldown + const Duration(minutes: 1),
      );
      calls.clear();
      expect(
        await p.probeStale('email', [target(id: 'e1'), target(id: 'e2')]),
        2,
        reason: '冷却只针对"刚认证失败过的那一条"，按 `<family>:<id>` 记账',
      );
    });

    test('非认证失败不进冷却：连不上／超时不该让人两小时不能再验', () async {
      results = [
        {'reachable': false, 'latencyMs': 9000},
      ];
      final p = prober();
      await p.probeStale('email', [target(id: 'e9')]);

      fakeNow = fakeNow.add(const Duration(minutes: 31));
      calls.clear();
      expect(
        await p.probeStale('email', [target(id: 'e9')]),
        1,
        reason: '冷却的触发条件是原生的 authFailure 布尔，不是"任何一次不可达"',
      );
    });

    test('跨语言：Dart 读的每个回包键，原生三枚探测方法里至少有一个写它', () {
      // `authFailure` 是这一片新加的那一格。没有这条守卫时，原生改名成 `isAuthFailure`
      // 或 `authFailed`，Dart 的 `r['authFailure'] == true` 恒为 false ⇒ 冷却静默失效，
      // 而两侧各自都"编译通过、测试全绿"。
      final dartRead = RegExp(
        r"r\['([A-Za-z][A-Za-z0-9]*)'\]",
      ).allMatches(_dartProbeSource()).map((m) => m.group(1)!).toSet();
      expect(dartRead, isNotEmpty, reason: '提取式没匹配到 ⇒ 本条已失效');
      final nativeWritten = <String>{};
      for (final fn in const [
        'probeAppChannelToken',
        'verifySmtp',
        'probeChannelHealth',
      ]) {
        nativeWritten.addAll(_nativeReplyKeys(fn));
      }
      expect(
        dartRead.difference(nativeWritten),
        isEmpty,
        reason: 'Dart 读而原生从不写的键 ⇒ 恒为 null，判据静默失效：$dartRead vs $nativeWritten',
      );
    });
  });
}

/// `channel_probe_service.dart` 里读回包那一段源码（去掉注释）。
String _dartProbeSource() => stripComments(
  File(
    '${projectRoot()}/lib/services/channel_probe_service.dart',
  ).readAsStringSync(),
);

/// 解析 `MainActivity` 某枚探测方法 `result.success(mapOf(...))` 里写的键集合。
Set<String> _nativeReplyKeys(String functionName) {
  final kotlin = stripComments(
    File(
      '${projectRoot()}/android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt',
    ).readAsStringSync(),
  );
  final block = blockAfter(kotlin, 'internal fun $functionName(');
  final keys = RegExp(
    r'"([A-Za-z][A-Za-z0-9]*)" to ',
  ).allMatches(block).map((m) => m.group(1)!).toSet();
  expect(keys, isNotEmpty, reason: '未解析到任何回包键 ⇒ 原生改了写法，本用例已失效（$functionName）');
  return keys;
}

/// 解析 `MainActivity` 里某个函数从 `configMap["…"]` 读到的键集合。
/// 与 channel_config_codec_test 的 `nativeReadKeys`（读 JSONObject）同一手法，
/// 区别只是 MethodChannel 载荷是 Map。锚点只写 `fun 名字(`，不抄可见性与参数表。
Set<String> nativeMapKeys(String functionName) {
  final kotlin = stripComments(
    File(
      '${projectRoot()}/android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt',
    ).readAsStringSync(),
  );
  final block = blockAfter(kotlin, 'fun $functionName(');
  final keys = RegExp(
    r'configMap\["([A-Za-z_][A-Za-z0-9_]*)"\]',
  ).allMatches(block).map((m) => m.group(1)!).toSet();
  expect(keys, isNotEmpty, reason: '未解析到任何 configMap 键 ⇒ 原生改了读取写法，本用例已失效');
  return keys;
}

/// ⊆ 断言（含"豁免不得变成死角"的反向检查），与 codec 测试共用同一语义。
Matcher subsetOf(Set<String> produced, {Set<String> aliases = const {}}) =>
    _SubsetOf(produced, aliases);

class _SubsetOf extends Matcher {
  _SubsetOf(this.produced, this.aliases);

  final Set<String> produced;
  final Set<String> aliases;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    final read = item! as Set<String>;
    final missing = read.difference(produced).difference(aliases);
    matchState['missing'] = missing;
    return missing.isEmpty && aliases.difference(read).isEmpty;
  }

  @override
  Description describe(Description description) =>
      description.add('原生读取的键都能被 Dart 载荷提供（或走别名 $aliases）');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    final missing = (matchState['missing'] as Set<String>?) ?? <String>{};
    if (missing.isNotEmpty) {
      return mismatchDescription.add('缺失：${missing.join(', ')}');
    }
    return mismatchDescription.add('豁免的别名已不被原生读取：$aliases');
  }
}
