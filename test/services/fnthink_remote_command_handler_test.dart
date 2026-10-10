import 'dart:io';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/services/fnthink_pair_items.dart';
import 'package:notice_transmit/services/fnthink_remote_command_handler.dart';
import 'package:notice_transmit/services/fnthink_remote_settings.dart';
import 'package:notice_transmit/services/fnthink_sender_grant.dart';
import 'package:notice_transmit/services/remote_credential_store.dart';
import 'package:notice_transmit/services/remote_credentials.dart';
import 'package:notice_transmit/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

/// 内存替身（让这一组能在 `flutter test` 里跑真加密存取那一层）。
class _MemStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> clearAll() async => data.clear();

  @override
  Future<void> saveWebhookUrls(List<String> urls) async {}

  @override
  Future<List<String>> loadWebhookUrls() async => const [];

  @override
  Future<void> saveWebhookChannels(String jsonStr) async {}

  @override
  Future<String?> loadWebhookChannels() async => null;
}

/// 远程执行 片3c：**指令判定**（是不是 / 开关 / 渠道 / 凭据 / item 词表）。
///
/// 这一组是安全面，四条最要紧的：
///  ① 开关关着 ⇒ 回「不是指令」而不是「拒」—— 回拒会把那条消息吃掉且不显示，
///     用户唯一看到的是"对方说发了，我这儿什么也没有"；
///  ② 凭据错 / 渠道不对 / item 不认得 ⇒ 那一档**拒**，而 L2 不带凭据放行；
///  ③ item **分档判**：L2 走动作表、L3 走设置表、L1 走两者并集（不共用一张表）；
///  ④ 来源渠道按**契约那一档**判（`remoteExecutionSourcesFor`），不写死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();

  /// 契约词表里最高那一档（名单那一行"顶格"的含义，不写死 'L3'）。
  final top = contract.capabilityLevels.last;

  late _MemStorage storage;
  late RemoteCredentialStore store;
  late FnthinkRemoteSettings settings;
  var nowMs = 1700000000000;

  /// 判定层的装配。T128 片2 起多一枚 `grants`（发送方 → 本机名单里那一行）。
  ///
  /// ⚠ 缺省给的是「名单里**有**这一行、档位顶格、勾了同意屏能勾的**全表**」那一份。
  ///   不是偷懒：本组的其它用例判的是**渠道 / 凭据 / 词表 / 参数形状**这四道，
  ///   若让名单那一格先把它们一律挡住，那二十几条就全红成同一条理由
  ///   （红的原因与它们各自要钉的判据无关 —— 那是把五道判据挤成一道）。
  ///   名单本身那一族（没有这一行 / 档位不够 / 没勾这一项）在下面
  ///   `本机名单才是这一条的依据` 那组里逐条钉，不在这里默认。
  Future<RemoteCommandRecognizer> recognizer({
    bool enabled = true,
    Future<FnthinkGrant> Function(String peer)? grants,
  }) async {
    SharedPreferences.setMockInitialValues(
      enabled ? {FnthinkRemoteSettings.keyEnabled: true} : <String, Object>{},
    );
    settings = FnthinkRemoteSettings(contract: contract);
    store = RemoteCredentialStore(
      contract: contract,
      storage: storage,
      clockMs: () => nowMs,
    );
    return RemoteCommandRecognizer(
      contract: contract,
      settings: settings,
      credentials: store,
      grantForSender:
          grants ??
          (peer) async =>
              FnthinkGrant(maxLevel: top, items: pairItemCandidates(contract)),
    );
  }

  String wire({
    String level = 'L2',
    String item = 'listener:start',
    String argument = '',
    String? key,
    String? totp,
  }) => RemoteCommandEnvelope.encode(
    level: level,
    item: item,
    argument: argument,
    key: key,
    totpCode: totp,
  );

  FnthinkInboxMessage msg(
    String body, {
    String sender = '8K3FJ6QPTM9WZ4VHNS',
  }) => FnthinkInboxMessage(
    messageId: 'm_00000001',
    sender: sender,
    type: 'notice',
    item: '',
    title: '',
    body: body,
    receivedAt: 1700000000000,
  );

  setUp(() {
    storage = _MemStorage();
    nowMs = 1700000000000;
  });

  group('是不是远程指令', () {
    test('一条普通通知 ⇒ 不是指令', () async {
      final r = await recognizer();
      expect(await r.parse(msg('今天天气不错')), isA<RemoteCommandNotACommand>());
    });

    test('指令载荷 ⇒ 认得（开关开着、无凭据、L2）', () async {
      final r = await recognizer();
      final parsed = await r.parse(msg(wire()));
      expect(parsed, isA<RemoteCommandAccepted>());
      expect((parsed as RemoteCommandAccepted).command.item, 'listener:start');
    });

    test('带凭据的那一条也认得（L2 可选）', () async {
      // ⚠ **先 recognizer() 再 setCustomKey**：`recognizer` 会 new 一个 store（拿新的
      //   安装盐），顺序反了的话密钥写进上一个 store 那个对象 —— 于是判"不带凭据"
      //   而这一档本该放行。第一版就是这个顺序（1 条红）。
      final r = await recognizer();
      await store.setCustomKey('my-long-key-1234');
      final parsed = await r.parse(msg(wire(key: 'my-long-key-1234')));
      expect(parsed, isA<RemoteCommandAccepted>());
      expect((parsed as RemoteCommandAccepted).credential, 'key');
    });
  });

  group('开关关着 ⇒ 当成"不是指令"（照常显示，不静默丢弃）', () {
    test('开关关着 ⇒ RemoteCommandNotEnabled（**不是** Rejected）', () async {
      final r = await recognizer(enabled: false);
      final parsed = await r.parse(msg(wire()));
      expect(parsed, isA<RemoteCommandNotEnabled>());
      expect(parsed, isNot(isA<RemoteCommandRejected>()));
      expect(parsed, isNot(isA<RemoteCommandNotACommand>()));
    });
  });

  group('凭据（L2 可选 / L3 必填）', () {
    test('L3 不带凭据 ⇒ 拒 missing-required', () async {
      final r = await recognizer();
      await store.setCustomKey('my-long-key-1234');
      final parsed = await r.parse(msg(wire(level: 'L3', item: 'exact_alarm')));
      expect(parsed, isA<RemoteCommandRejected>());
      expect((parsed as RemoteCommandRejected).reason, 'auth:missing-required');
    });

    test('L3 带**错的**密钥 ⇒ 拒 wrong', () async {
      final r = await recognizer();
      await store.setCustomKey('my-long-key-1234');
      final parsed = await r.parse(
        msg(wire(level: 'L3', item: 'exact_alarm', key: 'wrong-key')),
      );
      expect(parsed, isA<RemoteCommandRejected>());
      expect((parsed as RemoteCommandRejected).reason, 'auth:wrong');
    });

    test('L3 带对的密钥 ⇒ 放行', () async {
      final r = await recognizer();
      await store.setCustomKey('my-long-key-1234');
      final parsed = await r.parse(
        msg(wire(level: 'L3', item: 'exact_alarm', key: 'my-long-key-1234')),
      );
      expect(parsed, isA<RemoteCommandAccepted>());
    });

    test('L3 带对的 TOTP 码 ⇒ 放行（credential 是 totp 不是 key）', () async {
      final r = await recognizer();
      final issue = await store.generateTotp(account: 'x');
      final shape = contract.remoteExecutionTotpShape;
      // 先把时钟对到能算出码的那一刻
      nowMs = 1700000000000;
      final code = totpCodeAt(
        issue.secret,
        atMs: nowMs,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      );
      final parsed = await r.parse(
        msg(wire(level: 'L3', item: 'exact_alarm', totp: code)),
      );
      expect(parsed, isA<RemoteCommandAccepted>());
      expect((parsed as RemoteCommandAccepted).credential, 'totp');
    });

    test('L2 不带凭据 ⇒ 放行（契约 l2Requires:false）', () async {
      final r = await recognizer();
      expect(await r.parse(msg(wire())), isA<RemoteCommandAccepted>());
    });
  });

  group('来源渠道按契约那一档判', () {
    test('L1 允许白名单应用那一路（契约 sources 有它）', () async {
      final r = await recognizer();
      expect(
        contract.remoteExecutionSourcesFor('L1'),
        contains('localNotificationWhitelist'),
      );
      // 白名单那一路 sender 为空（没有远端发送方），授权按契约的**缺省档**（L1 + 空清单）
      final parsed = await r.judge(
        command: RemoteCommandEnvelope.decode(wire(level: 'L1'))!,
        sender: '',
        source: 'localNotificationWhitelist',
        grant: FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel),
      );
      expect(parsed, isA<RemoteCommandAccepted>());
    });

    test('L2 不允许白名单那一路（契约 sources 只有 fnthink）', () async {
      final r = await recognizer();
      final parsed = await r.judge(
        command: RemoteCommandEnvelope.decode(wire(level: 'L2'))!,
        sender: '',
        source: 'localNotificationWhitelist',
        grant: FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel),
      );
      expect(parsed, isA<RemoteCommandRejected>());
      expect((parsed as RemoteCommandRejected).reason, 'source-not-allowed:L2');
    });
  });

  group('item 词表分档判（不共用一张表）', () {
    test('L2 认得一个 L2 动作', () async {
      final r = await recognizer();
      expect(
        await r.parse(msg(wire(level: 'L2', item: 'listener:start'))),
        isA<RemoteCommandAccepted>(),
      );
    });

    test('L2 收一个 L3 设置项 ⇒ 拒（不共用那张表）', () async {
      final r = await recognizer();
      final parsed = await r.parse(msg(wire(level: 'L2', item: 'exact_alarm')));
      expect(parsed, isA<RemoteCommandRejected>());
      expect((parsed as RemoteCommandRejected).reason, startsWith('item:'));
    });

    test('L1 认得 L2 动作 ∪ L3 设置（并集那张表）', () async {
      final r = await recognizer();
      // L1 动作（L2 表里的）
      expect(
        await r.parse(msg(wire(level: 'L1', item: 'listener:start'))),
        isA<RemoteCommandAccepted>(),
      );
      // L1 设置（L3 表里的）
      expect(
        await r.parse(msg(wire(level: 'L1', item: 'exact_alarm'))),
        isA<RemoteCommandAccepted>(),
      );
    });

    test('三档都不认得的 item ⇒ 拒', () async {
      final r = await recognizer();
      final parsed = await r.parse(
        msg(wire(level: 'L1', item: 'made-up-item')),
      );
      expect(parsed, isA<RemoteCommandRejected>());
    });

    test('L3 缺前置授权的那一项 ⇒ 拒 missing-grant', () async {
      // requiresExistingGrantFrom = [monitoring, collect_inbox]
      final r = await recognizer();
      await store.setCustomKey('my-long-key-1234');
      final parsed = await r.parse(
        msg(wire(level: 'L3', item: 'collect_inbox', key: 'my-long-key-1234')),
      );
      expect(parsed, isA<RemoteCommandRejected>());
      expect(
        (parsed as RemoteCommandRejected).reason,
        contains('missing-grant'),
      );
    });

    test('名单里勾了这一项 ⇒ 同一项放行（grantedKeys 来自那一行）', () async {
      final r = await recognizer(
        grants: (peer) async =>
            FnthinkGrant(maxLevel: top, items: ['collect_inbox']),
      );
      await store.setCustomKey('my-long-key-1234');
      final parsed = await r.parse(
        msg(wire(level: 'L3', item: 'collect_inbox', key: 'my-long-key-1234')),
      );
      expect(parsed, isA<RemoteCommandAccepted>());
    });
  });

  /// 本机名单才是这一条的依据（T128 片2：「按设备设权限」终于有了一行代码）。
  ///
  /// ⚠ 这一组不是"多一道保险"：一条远程指令在线上是**一条 L1 通知**（发送侧只有
  ///   `sendNotice(peer,title,text)` 那个口，被签的六个字段里没有 `item`）⇒ 服务端的
  ///   能力判据拿到的永远是 `type=notice / item=''`，`itemRequiredFromLevel` 那一段**根本不响**。
  ///   「这条是 L3、动的是 `location:get`」只有收件这一台知道，也只有它能判。
  ///   少了下面这几条，配对到 L1 的那台发 L2 指令**连凭据都不必带**（契约 l2Requires:false）。
  group('本机名单才是这一条的依据（T128 片2）', () {
    test('名单里没有这一台 ⇒ 按契约缺省档：L2 拒在档位上', () async {
      final r = await recognizer(
        grants: (peer) async =>
            FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel),
      );
      final parsed = await r.parse(msg(wire()));
      expect(parsed, isA<RemoteCommandRejected>());
      expect((parsed as RemoteCommandRejected).reason, 'level:L2');
    });

    test('勾了这一项但档位不够 ⇒ 仍拒 level，凭据不是通行证', () async {
      final r = await recognizer(
        grants: (peer) async =>
            FnthinkGrant(maxLevel: 'L1', items: ['exact_alarm']),
      );
      await store.setCustomKey('my-long-key-1234');
      final parsed = await r.parse(
        msg(wire(level: 'L3', item: 'exact_alarm', key: 'my-long-key-1234')),
      );
      expect(parsed, isA<RemoteCommandRejected>());
      expect((parsed as RemoteCommandRejected).reason, 'level:L3');
    });

    test('两台各一行：勾了 location:get 的那台放行，没勾的那台被拒', () async {
      // 这一条就是维护者要的那句「只允许 A 读定位、不允许 B 读定位」的可执行形式。
      final r = await recognizer(
        grants: (peer) async => peer == 'AAAAAAAAAAAAAAAAAA'
            ? FnthinkGrant(maxLevel: top, items: ['location:get'])
            : FnthinkGrant(maxLevel: top, items: ['camera:snap']),
      );
      expect(
        await r.parse(
          msg(wire(item: 'location:get'), sender: 'AAAAAAAAAAAAAAAAAA'),
        ),
        isA<RemoteCommandAccepted>(),
      );
      final blocked = await r.parse(
        msg(wire(item: 'location:get'), sender: 'BBBBBBBBBBBBBBBBBB'),
      );
      expect(blocked, isA<RemoteCommandRejected>());
      expect(
        (blocked as RemoteCommandRejected).reason,
        'item:not-granted:location:get',
      );
    });

    test('本机白名单那一路不吃远端名单：一个都没勾也放行它的 L1', () async {
      // 摘掉名单 ≠ 收紧本机那一路：那一行的授权对象是**远端发送方**，
      // 而这一路没有发送方（契约 sources 已经把它限在 L1）。
      final r = await recognizer();
      final parsed = await r.judge(
        command: RemoteCommandEnvelope.decode(wire(level: 'L1'))!,
        sender: '',
        source: contract.remoteExecutionLocalTriggerSource,
        grant: FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel),
      );
      expect(parsed, isA<RemoteCommandAccepted>());
    });

    test('⚠ 带参数的形状：本机清单今天表达不了它 ⇒ 不为它判「没勾」（边界）', () async {
      // 一份**什么都没勾**的授权，而这一条照过：`channel:toggle` 在契约
      // `l2.requiresArgumentFrom` 里，同意屏那张表（[pairItemCandidates]）刻意不给它，
      // 线上串又长成 `<名>/<参数>` ⇒ 判"没勾"就是把这一族当场永久打死。
      // 「粒度收到动作级还是参数级」要维护者拍（roadmap T134 行），不由这一片代拍。
      final r = await recognizer(
        grants: (peer) async => FnthinkGrant(maxLevel: top),
      );
      expect(
        await r.parse(msg(wire(item: 'channel:toggle/webhook:acme:off'))),
        isA<RemoteCommandAccepted>(),
        reason: '清单判不了形状，但档位天花板照判（maxLevel=L3 ⇒ L2 够）',
      );
      expect(
        rejectBySenderGrant(
          contract,
          level: 'L2',
          item: 'channel:toggle/webhook:acme:off',
          grant: FnthinkGrant(maxLevel: top, items: ['listener:start']),
        ),
        isNull,
        reason: '这一族的逐条判据今天恒为"不判"（登记，不是遗漏）',
      );
    });

    test('名单里那一行的档位词表外 ⇒ 按不够判，不放开（unknown-ceiling）', () async {
      final r = await recognizer(
        grants: (peer) async => FnthinkGrant(maxLevel: 'L9'),
      );
      final parsed = await r.parse(msg(wire()));
      expect(parsed, isA<RemoteCommandRejected>());
      expect((parsed as RemoteCommandRejected).reason, 'unknown-ceiling:L9');
    });

    test('名单读不出来 ⇒ 抛出去，不咽成缺省档', () async {
      // 咽成缺省档会把「读不到」与「这一台确实没被勾过」混成同一件事；
      // 抛出去由收货循环那一格按"不是指令"处置（照常显示、不执行）——
      // 收紧的方向仍然成立，而"这一格坏了"是能被日志看见的。
      final r = await recognizer(
        grants: (peer) async => throw StateError('表读不出来'),
      );
      await expectLater(r.parse(msg(wire())), throwsStateError);
    });
  });

  group('channel:toggle 的参数形状（片3c-2）', () {
    // ⚠⚠ **参数写在 `item` 的 `/` 后面**，不是信封里那个 `argument` 字段 ——
    //   `parseL2Item` 拆的是前者（契约 `itemFormat = <family>:<verb>/<参数>`），
    //   后者是另一处。本组第一版用 `wire(argument: …)` 写，红了才发现：
    //   形状判据读的是信封那一份，于是**每一条** channel:toggle 都被拒，
    //   而现场看到的是「命令认得，就是没反应」—— 看不出读错了哪一处。
    //   这一条把两处的区别钉死，改任一处时它会红。
    test('参数取自 item 的斜杠段，不是信封的 argument 字段', () async {
      final r = await recognizer();
      expect(
        await r.parse(msg(wire(item: 'channel:toggle/webhook:acme:off'))),
        isA<RemoteCommandAccepted>(),
        reason: '斜杠后那一段才是参数',
      );
      expect(
        await r.parse(
          msg(wire(item: 'channel:toggle', argument: 'webhook:acme:off')),
        ),
        isA<RemoteCommandRejected>(),
        reason: '信封那个字段不参与动作参数（item 里没有斜杠段 ⇒ 参数为空）',
      );
    });

    test('三段齐全（族:id:on|off）⇒ 放行', () async {
      final r = await recognizer();
      for (final arg in const ['webhook:acme:off', 'app:x:on', 'email:y:off']) {
        expect(
          await r.parse(msg(wire(item: 'channel:toggle/$arg'))),
          isA<RemoteCommandAccepted>(),
          reason: '参数「$arg」应当放行',
        );
      }
    });

    test('缺目标值 ⇒ 拒（重投一次就翻回去的那种"翻"不许做）', () async {
      final r = await recognizer();
      final parsed = await r.parse(
        msg(wire(item: 'channel:toggle/webhook:acme')),
      );
      expect(parsed, isA<RemoteCommandRejected>());
      expect(
        (parsed as RemoteCommandRejected).reason,
        startsWith('item:bad-channel-argument'),
      );
    });

    test('族/id 为空、族名不认识、目标值拼错、多一段 ⇒ 全拒', () async {
      final r = await recognizer();
      for (final arg in const [
        ':acme:off',
        'webhook::off',
        'sms:acme:off',
        'webhook:acme:ON',
        'webhook:acme:enabled',
        'webhook:acme:off:extra',
      ]) {
        expect(
          await r.parse(msg(wire(item: 'channel:toggle/$arg'))),
          isA<RemoteCommandRejected>(),
          reason: '参数「$arg」应当被拒',
        );
      }
    });

    test('⚠ L1 也要判参数形状（L1 的 item 是 L2∪L3 那张并集表）', () async {
      // 只把形状判据写进 `case 'L2'` 的话，L1 那条路会直接放行 ——
      // 而 L1 **不需要任何凭据**，那等于任何人配对过就能启停本机的投递通道。
      final r = await recognizer();
      expect(
        await r.parse(
          msg(wire(level: 'L1', item: 'channel:toggle/webhook:acme')),
        ),
        isA<RemoteCommandRejected>(),
        reason: 'L1 无凭据 ⇒ 参数形状更不能放过',
      );
      expect(
        await r.parse(
          msg(wire(level: 'L1', item: 'channel:toggle/webhook:acme:off')),
        ),
        isA<RemoteCommandAccepted>(),
      );
    });

    test('参数形状这一格对没有参数的动作是 no-op', () async {
      final r = await recognizer();
      expect(
        await r.parse(msg(wire(item: 'listener:start'))),
        isA<RemoteCommandAccepted>(),
      );
      expect(
        await r.parse(msg(wire(item: 'device_state:push'))),
        isA<RemoteCommandAccepted>(),
      );
    });
  });

  group('结构守卫：这一层不许碰执行与延时', () {
    test('判定层不 import 执行器/延时那一族（执行与窗口在调用方）', () {
      final src = stripComments(
        File(
          '${projectRoot()}/lib/services/fnthink_remote_command_handler.dart',
        ).readAsStringSync(),
      );
      // 它**用** checkRemoteExecutionAuth（凭据判定）—— 那是允许的；
      // 但不许出现执行/窗口那三个函数名。
      expect(
        src.contains('resolveRemoteExecutionWindow'),
        isFalse,
        reason: '延时窗口是执行那一层的事，判定层碰它就会长出第二个读者',
      );
      expect(src.contains('dispatchL2Action'), isFalse);
      expect(src.contains('dispatchL3Setting'), isFalse);
    });

    test('授权只能经那个咽喉拿：判定层不许自己读那张表', () {
      final src = stripComments(
        File(
          '${projectRoot()}/lib/services/fnthink_remote_command_handler.dart',
        ).readAsStringSync(),
      );
      // 那张表（`fnthink_peers`）的读只有一个咽喉 = `FnthinkPeerService.list/grantFor`。
      // 判定层里出现 `loadFnthinkPeers` 就是第二个读法 —— 而守卫数的是**调用点**，
      // 多一处不会有人喊，直到两处排序/容错分叉那天。
      expect(
        src.contains('loadFnthinkPeers'),
        isFalse,
        reason: '授权必须由注入进来的 grantForSender 给（装配点接 FnthinkPeerService.grantFor）',
      );
      expect(src.contains('grantForSender('), isTrue);
      expect(
        src.contains('DatabaseHelper'),
        isFalse,
        reason: '判定层碰库就等于把"读名单"这件事从服务层偷走',
      );
    });
  });
}
