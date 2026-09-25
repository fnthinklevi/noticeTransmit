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
      expect(second, 0, reason: '六小时内有结论就不该再打厂商：探测不是轮询');
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
