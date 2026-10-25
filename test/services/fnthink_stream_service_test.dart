import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/services/fnthink_stream_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T185 第二步：SSE 门铃。
///
/// 这一层只回答三件事，每一件都对应一个"错了也看不出来"的现场：
///  ① 只有 `event: wake` 才算唤醒 —— 心跳注释不算。把注释当唤醒会让循环每秒跑一轮；
///  ② 连上/断开各回调一次 —— 调用方据此决定要不要常驻持锁；
///  ③ 断了要**换新票**重连（票是一次性的），退避期间不叠出第二条连接。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final contract = FnthinkContract.readFile();

  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('连上 ⇒ healthy=true；只有 event: wake 触发 onWake，心跳注释不触发', () async {
    final controller = StreamController<List<int>>();
    final opened = Completer<void>();
    final wakes = <void>[];
    final healthy = <bool>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () => wakes.add(null),
      onHealthyChanged: healthy.add,
      open: (uri, headers) async {
        opened.complete();
        return FnthinkSseConnection(
          status: 200,
          body: controller.stream,
          close: () => unawaited(controller.close()),
        );
      },
      backoff: const [Duration.zero],
    );
    addTearDown(service.stop);

    service.start();
    await opened.future;
    await flush();

    expect(healthy, [true]);
    // 心跳注释不是唤醒。
    controller.add(utf8.encode(': ping\n\n'));
    await flush();
    expect(wakes, isEmpty);
    // 一个事件块里有 event: wake 才是。
    controller.add(utf8.encode('event: wake\ndata: {}\n\n'));
    await flush();
    expect(wakes, hasLength(1));
    // CRLF 也要认得。
    controller.add(utf8.encode('event: wake\r\ndata: {}\r\n\r\n'));
    await flush();
    expect(wakes, hasLength(2));
  });

  test('19s 心跳保持健康；50s 静默才判死', () async {
    var now = 100000;
    final controller = StreamController<List<int>>();
    final opened = Completer<void>();
    final healthy = <bool>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () {},
      onHealthyChanged: healthy.add,
      nowMs: () => now,
      open: (uri, headers) async {
        opened.complete();
        return FnthinkSseConnection(
          status: 200,
          body: controller.stream,
          close: () => unawaited(controller.close()),
        );
      },
      backoff: const [Duration(days: 1)],
    );
    addTearDown(service.stop);
    service.start();
    await opened.future;
    await flush();
    expect(healthy, [true]);

    now += 19000;
    controller.add(utf8.encode(': ping\n\n'));
    await flush();
    service.checkStaleForTest();
    expect(service.isHealthy, isTrue, reason: '19s < 2.5×20s，不许误杀');

    now += 50001;
    service.checkStaleForTest();
    await flush();
    expect(service.isHealthy, isFalse);
    expect(healthy, [true, false]);
  });

  test('50s 静默只重连一次；旧代际 Timer 不能改写新连接；stop 后不翻转', () async {
    var now = 100000;
    final controllers = <StreamController<List<int>>>[];
    final healthy = <bool>[];
    var opens = 0;
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () {},
      onHealthyChanged: healthy.add,
      nowMs: () => now,
      open: (uri, headers) async {
        opens++;
        final c = StreamController<List<int>>();
        controllers.add(c);
        return FnthinkSseConnection(
          status: 200,
          body: c.stream,
          close: () => unawaited(c.close()),
        );
      },
      backoff: const [Duration.zero],
    );
    addTearDown(service.stop);
    service.start();
    await flush();
    expect(opens, 1);
    expect(healthy, [true]);

    now += 50001;
    service.checkStaleForTest();
    await flush();
    await flush();
    expect(healthy, [true, false, true]);
    expect(opens, 2, reason: '一次静默只触发一次重连');

    // 初始连接代际是 1，新连接已是 3；旧 Timer 带着 1 来敲门必须原地返回。
    service.checkStaleForTest(generation: 1);
    expect(service.isHealthy, isTrue);
    service.stop();
    service.checkStaleForTest();
    expect(service.isHealthy, isFalse);
    expect(healthy.last, isFalse);
  });

  test('换票失败仍按既有退避重试，且从不假装在线', () async {
    var tickets = 0;
    final healthy = <bool>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async {
        tickets++;
        return null;
      },
      onWake: () {},
      onHealthyChanged: healthy.add,
      backoff: const [Duration.zero, Duration.zero],
    );
    addTearDown(service.stop);
    service.start();
    await flush();
    await flush();
    expect(tickets, greaterThanOrEqualTo(2), reason: '换票失败不能停在那儿');
    expect(healthy, isEmpty);
    expect(service.isHealthy, isFalse);
  });

  test('流断了 ⇒ healthy=false，并用**新票**重连（一次性票不能复用）', () async {
    final controllers = <StreamController<List<int>>>[];
    var tickets = 0;
    final healthy = <bool>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async {
        tickets++;
        return FnthinkStreamTicket(ticket: 't$tickets', expiresAt: 0);
      },
      onWake: () {},
      onHealthyChanged: healthy.add,
      open: (uri, headers) async {
        final controller = StreamController<List<int>>();
        controllers.add(controller);
        return FnthinkSseConnection(
          status: 200,
          body: controller.stream,
          close: () => unawaited(controller.close()),
        );
      },
      backoff: const [Duration.zero, Duration.zero],
    );
    addTearDown(service.stop);

    service.start();
    await flush();
    expect(controllers, hasLength(1));
    expect(healthy, [true]);

    // 服务器把流关了 ⇒ 客户端要重新换票、重新连。
    await controllers.first.close();
    await flush();
    await flush();
    expect(healthy, [true, false, true]);
    expect(tickets, 2);
    expect(controllers, hasLength(2));

    service.stop();
    expect(healthy.last, isFalse);
  });

  test('票都换不到 / 连上不是 200 ⇒ 一直 healthy=false，不假装在线', () async {
    var opens = 0;
    final healthy = <bool>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async => null,
      onWake: () {},
      onHealthyChanged: healthy.add,
      open: (uri, headers) async {
        opens++;
        return const FnthinkSseConnection(status: 403, body: Stream.empty());
      },
      backoff: const [Duration.zero, Duration.zero, Duration.zero],
    );
    addTearDown(service.stop);

    service.start();
    await flush();
    await flush();
    // 换不到票 ⇒ 连 open 都不会被调；healthy 从头到尾只有"没开"这一档。
    expect(opens, 0);
    expect(healthy, isEmpty);
    expect(service.isHealthy, isFalse);
  });

  test('stop 之后不再重连', () async {
    var tickets = 0;
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async {
        tickets++;
        return FnthinkStreamTicket(ticket: 't$tickets', expiresAt: 0);
      },
      onWake: () {},
      onHealthyChanged: (_) {},
      open: (uri, headers) async =>
          const FnthinkSseConnection(status: 403, body: Stream.empty()),
      backoff: const [Duration.zero, Duration.zero],
    );

    service.start();
    await flush();
    final before = tickets;
    service.stop();
    await flush();
    await flush();
    expect(tickets, before);
  });
}
