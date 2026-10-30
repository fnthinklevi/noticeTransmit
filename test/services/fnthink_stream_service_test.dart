import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/services/fnthink_stream_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T185 第二步 / T218：SSE 门铃。
///
/// T218 把"50 秒没字节"从"判死并断开"改成三态：
///  - `degraded`：门铃静默但短轮询可达，保持连接、走短轮询、每 safetyPollSeconds 重探一次；
///  - `offline`：短轮询也不可达，才关连接走既有退避；
///  - 任一字节（含心跳）回到 `healthy`。
///
/// 这里钉的每一件事都对应一个"错了也看不出来"的现场：
///  ① 只有 `event: wake` 才算唤醒 —— 心跳注释不算；
///  ② 三态回调各出现一次，且 degraded 不许重连、不许每 50 秒抖；
///  ③ 断了要**换新票**重连（票是一次性的），退避期间不叠出第二条连接。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final contract = FnthinkContract.readFile();

  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('连上 ⇒ healthy；只有 event: wake 触发 onWake，心跳注释不触发', () async {
    final controller = StreamController<List<int>>();
    final opened = Completer<void>();
    final wakes = <void>[];
    final states = <FnthinkStreamLinkState>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () => wakes.add(null),
      onLinkStateChanged: states.add,
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

    expect(states, [FnthinkStreamLinkState.healthy]);
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

  test('19s 心跳保持健康；50s 静默 ⇒ degraded，探针只跑一次', () async {
    var now = 100000;
    final controller = StreamController<List<int>>();
    final opened = Completer<void>();
    final states = <FnthinkStreamLinkState>[];
    var probes = 0;
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () {},
      onLinkStateChanged: states.add,
      probeOnStale: () async {
        probes++;
        return true;
      },
      degradedProbeInterval: const Duration(days: 1),
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
    expect(states, [FnthinkStreamLinkState.healthy]);

    now += 19000;
    controller.add(utf8.encode(': ping\n\n'));
    await flush();
    service.checkStaleForTest();
    expect(service.isHealthy, isTrue, reason: '19s < 2.5×20s，不许误杀');

    now += 50001;
    service.checkStaleForTest();
    await flush();
    expect(service.isHealthy, isFalse);
    expect(service.isDegraded, isTrue);
    expect(states, [
      FnthinkStreamLinkState.healthy,
      FnthinkStreamLinkState.degraded,
    ]);
    expect(probes, 1, reason: '一次静默只探一次');
  });

  test('degraded 不每 50 秒重连；任一字节（含心跳）回 healthy', () async {
    var now = 100000;
    final controllers = <StreamController<List<int>>>[];
    final states = <FnthinkStreamLinkState>[];
    var opens = 0;
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () {},
      onLinkStateChanged: states.add,
      probeOnStale: () async => true,
      degradedProbeInterval: const Duration(days: 1),
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
    expect(states, [FnthinkStreamLinkState.healthy]);

    now += 50001;
    service.checkStaleForTest();
    await flush();
    await flush();
    expect(opens, 1, reason: 'degraded 不是"再连一次"，连接保持不动');
    expect(service.isDegraded, isTrue);

    now += 50000;
    service.checkStaleForTest();
    await flush();
    expect(opens, 1, reason: 'degraded 里旧 Timer 再敲门也不许重连');

    controllers.single.add(utf8.encode(': ping\n\n'));
    await flush();
    expect(service.isHealthy, isTrue);
    expect(states, [
      FnthinkStreamLinkState.healthy,
      FnthinkStreamLinkState.degraded,
      FnthinkStreamLinkState.healthy,
    ]);

    service.stop();
    expect(states.last, FnthinkStreamLinkState.offline);
  });

  test('探针说不可达 ⇒ offline；不假装在线', () async {
    var now = 100000;
    final controller = StreamController<List<int>>();
    final states = <FnthinkStreamLinkState>[];
    var probes = 0;
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () {},
      onLinkStateChanged: states.add,
      probeOnStale: () async {
        probes++;
        return false;
      },
      degradedProbeInterval: const Duration(days: 1),
      nowMs: () => now,
      open: (uri, headers) async => FnthinkSseConnection(
        status: 200,
        body: controller.stream,
        close: () => unawaited(controller.close()),
      ),
      backoff: const [Duration(days: 1)],
    );
    addTearDown(service.stop);
    service.start();
    await flush();
    expect(states, [FnthinkStreamLinkState.healthy]);

    now += 50001;
    service.checkStaleForTest();
    await flush();
    expect(service.isHealthy, isFalse);
    expect(service.isDegraded, isFalse);
    expect(states, [
      FnthinkStreamLinkState.healthy,
      FnthinkStreamLinkState.degraded,
      FnthinkStreamLinkState.offline,
    ]);
    expect(probes, 1);
  });

  test('degraded 的默认重探间隔 = 契约 stream.safetyPollSeconds', () async {
    final controller = StreamController<List<int>>();
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () {},
      onLinkStateChanged: (_) {},
      probeOnStale: () async => true,
      open: (uri, headers) async => FnthinkSseConnection(
        status: 200,
        body: controller.stream,
        close: () => unawaited(controller.close()),
      ),
      backoff: const [Duration.zero],
    );
    addTearDown(service.stop);
    service.start();
    await flush();

    expect(
      service.degradedProbeIntervalForTest,
      Duration(seconds: contract.streamSpec!.safetyPollSeconds),
      reason: 'T218 复用契约的 safetyPollSeconds 做降级重探，不另开一个数',
    );
  });

  test('degraded 到点只重连一次（不是每 50 秒）', () async {
    var now = 100000;
    final controllers = <StreamController<List<int>>>[];
    var opens = 0;
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async =>
          const FnthinkStreamTicket(ticket: 't1', expiresAt: 0),
      onWake: () {},
      onLinkStateChanged: (_) {},
      probeOnStale: () async => true,
      degradedProbeInterval: const Duration(milliseconds: 20),
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
      backoff: const [Duration(days: 1)],
    );
    addTearDown(service.stop);
    service.start();
    await flush();
    expect(opens, 1);

    now += 50001;
    service.checkStaleForTest();
    await flush();
    expect(opens, 1, reason: '判死当拍不重连');

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(opens, 2, reason: 'degraded 的低频重探到点连一次');
  });

  test('换票失败仍按既有退避重试，且从不假装在线', () async {
    var tickets = 0;
    final states = <FnthinkStreamLinkState>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async {
        tickets++;
        return null;
      },
      onWake: () {},
      onLinkStateChanged: states.add,
      backoff: const [Duration.zero, Duration.zero],
    );
    addTearDown(service.stop);
    service.start();
    await flush();
    await flush();
    expect(tickets, greaterThanOrEqualTo(2), reason: '换票失败不能停在那儿');
    expect(states, isEmpty);
    expect(service.isHealthy, isFalse);
  });

  test('流断了 ⇒ offline，并用**新票**重连（一次性票不能复用）', () async {
    final controllers = <StreamController<List<int>>>[];
    var tickets = 0;
    final states = <FnthinkStreamLinkState>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async {
        tickets++;
        return FnthinkStreamTicket(ticket: 't$tickets', expiresAt: 0);
      },
      onWake: () {},
      onLinkStateChanged: states.add,
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
    expect(states, [FnthinkStreamLinkState.healthy]);

    // 服务器把流关了 ⇒ 客户端要重新换票、重新连。
    await controllers.first.close();
    await flush();
    await flush();
    expect(states, [
      FnthinkStreamLinkState.healthy,
      FnthinkStreamLinkState.offline,
      FnthinkStreamLinkState.healthy,
    ]);
    expect(tickets, 2);
    expect(controllers, hasLength(2));

    service.stop();
    expect(states.last, FnthinkStreamLinkState.offline);
  });

  test('票都换不到 / 连上不是 200 ⇒ 一直不是 healthy，不假装在线', () async {
    var opens = 0;
    final states = <FnthinkStreamLinkState>[];
    final service = FnthinkStreamService(
      contract: contract,
      baseUri: Uri.https('push.example', ''),
      requestTicket: () async => null,
      onWake: () {},
      onLinkStateChanged: states.add,
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
    // 换不到票 ⇒ 连 open 都不会被调；没有"开过"这一档。
    expect(opens, 0);
    expect(states, isEmpty);
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
      onLinkStateChanged: (_) {},
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
