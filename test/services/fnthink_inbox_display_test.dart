import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/services/fnthink_inbox_display.dart';
import 'package:notice_transmit/services/platform_channel.dart';

/// 收件 → 系统通知那一枚通道调用（T48 的前置）。
///
/// 这里盯的是**键名**和**不许抛**：
///  ① 键名是字符串契约，改一端另一端不会红 —— 而 Kotlin 侧读不到就 `.orEmpty()`，
///     表现是"通知显示出来了但标题、正文、发件人全空"，一条错误都不会留。
///     所以断言的是**实际发出去的那份 map**，不是方法名。
///  ② 这个返回值直接决定 ack 报 `displayed` 还是 `delivered`（收货循环判据 ⑤）：
///     把"没显示"报成"已显示"，服务端下一秒就按契约删正文，而用户两头都没见过这条。
///     因此通道缺失 / 返回 null / 原生抛异常，三种都必须落到 false，而不是往上抛。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const messageId = 'm_01EXAMPLE';
  FnthinkInboxMessage row({
    String id = messageId,
    String sender = 'endpoint:ep_7',
    String title = '机箱温度',
    String body = '温度 63 度',
  }) => FnthinkInboxMessage(
    messageId: id,
    sender: sender,
    type: 'notice',
    item: '',
    title: title,
    body: body,
    receivedAt: 1780000000000,
  );

  late List<MethodCall> calls;
  final display = FnthinkInboxDisplay();

  void mock(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() => calls = <MethodCall>[]);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, null);
  });

  test(
    '发出去的键名与取值：messageId / sender / title / body / unreadCount 一枚不多一枚不少',
    () async {
      mock((_) => true);
      expect(await display.show(row(), unreadCount: 3), isTrue);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'showFnthinkInbox');
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args.keys.toSet(), {
        'messageId',
        'sender',
        'title',
        'body',
        // T55 ③ 角标那个数。⚠ 它是**后来加的第五个键** —— 加它时这条断言当场红了
        // （这正是"键名一枚不多一枚不少"存在的理由：多传/少传两端都不报错，
        // 表现是角标永远是 0 或者原生读到 null）。
        'unreadCount',
      }, reason: '多传 = 原生不读的那一份会误导后人；少传 = 通知里那一栏静默变空');
      expect(args['messageId'], messageId);
      expect(args['sender'], 'endpoint:ep_7');
      expect(args['title'], '机箱温度');
      expect(args['body'], '温度 63 度');
      expect(args['unreadCount'], 3);
    },
  );

  // ── T55 ③ 角标那个数 ───────────────────────────────────────────────
  // 断的是**转发与归一**：数从调用方一路到那份 map，中间不许被丢成 null 或原样传负数。
  group('T55 角标那个数（unreadCount）', () {
    test('不给时按 0 发出去，而不是不发这个键', () async {
      mock((_) => true);
      await display.show(row());
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(
        args['unreadCount'],
        0,
        reason:
            '老 Dart 与通道被直调都不会带这个键；原生侧读不到就按 0，'
            '但**这枚键必须在** —— 少一枚就是"角标永远是 0"那种静默失效',
      );
    });

    test('负数按 0 发：调用方没数到时不该让桌面自己发挥', () async {
      mock((_) => true);
      await display.show(row(), unreadCount: -3);
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['unreadCount'],
        0,
      );
    });

    test('数从服务层到通道一路没丢（点显示时读的那一份）', () async {
      mock((_) => true);
      // 一轮里可能落了好几条：每条都要带当刻的数，而不是循环开始时的数。
      for (final n in [1, 2, 3]) {
        await display.show(row(id: 'm_$n'), unreadCount: n);
      }
      expect(
        calls.map((c) => (c.arguments as Map<Object?, Object?>)['unreadCount']),
        [1, 2, 3],
        reason: '三条通知各带自己那一刻的未读数；全带同一个数就是"角标永远停在 1"',
      );
    });
  });

  test('messageId 为空 ⇒ 直接回 false，连通道都不碰', () async {
    mock((_) => true);
    expect(await display.show(row(id: '')), isFalse);
    expect(calls, isEmpty, reason: '空 id 不是一次显示请求：让原生去处理"没有 id"，撤回与标已读都会按空串说话');
  });

  test('原生回 false（通知权限被关）⇒ 原样回 false，不改写成"成功"', () async {
    mock((_) => false);
    expect(await display.show(row()), isFalse);
  });

  test('通道返回 null ⇒ 按未显示处理', () async {
    mock((_) => null);
    expect(
      await display.show(row()),
      isFalse,
      reason: '`invokeMethod<bool>` 回 null 与回 false 是同一件事：没显示',
    );
  });

  test('通道抛（MissingPluginException / 原生 error）⇒ 回 false 而不往上抛', () async {
    mock((_) => throw MissingPluginException('没有接原生'));
    expect(
      await display.show(row()),
      isFalse,
      reason: '显示失败不是收货失败：这条已经安全落库，往上抛会让整轮 ack 停摆',
    );

    mock(
      (_) =>
          throw PlatformException(code: 'notification_failed', message: '渠道炸了'),
    );
    expect(await display.show(row()), isFalse);
  });

  // ── T83：那一条待跳的消息 id ─────────────────────────────────────────
  // 这里钉的是**取法只有一个、而且取不到就等于没跳**：
  // 通道抛/回 null 都必须落到 null，因为调用方拿 null 的分支是"什么都不做"或"只打开列表" ——
  // 若这里改成抛，首页那条冷启动那一发会把整页 initState 的后半截一起带走。
  group('takeOpenTarget（点通知要跳去的那一条）', () {
    test('原生给了那一枚 ⇒ 原样交出去，不多做判空', () async {
      mock((_) => 'm_0f48df96');
      expect(await display.takeOpenTarget(), 'm_0f48df96');
      expect(calls.single.method, 'takeFnthinkOpenTarget');
      expect(
        calls.single.arguments,
        isNull,
        reason: '这一发是"取走我手上那一条"，不是查询：带上参数就等于允许调用方指定要跳哪条',
      );
    });

    test('没有待跳的（回 null）⇒ 交 null，不换成空串', () async {
      mock((_) => null);
      expect(
        await display.takeOpenTarget(),
        isNull,
        reason: '空串与 null 到了页面那边是两种空，判漏一种就是"展开了一条猜出来的行"',
      );
    });

    test('通道抛 ⇒ 也回 null：这一发不该让启动那一路断在半截', () async {
      mock((_) => throw MissingPluginException('没有接原生'));
      expect(
        await display.takeOpenTarget(),
        isNull,
        reason: '取不到就是要跳的那条不存在，与"没接原生"是同一件事',
      );
    });
  });
}
