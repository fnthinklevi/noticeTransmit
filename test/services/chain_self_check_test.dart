import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/active_channels.dart';
import 'package:notice_transmit/services/chain_self_check.dart';

/// T220 片2c：四族一键自检的编排判据。
///
/// 这里钉的是"一次自检给出四份结论"这件事，而不是某一族的发送实现（那三种原语各有
/// 自己的用例，且真的会发消息，用例里一律注入替身）。四个判据各对应一种会静默失真的写法：
///  - 每族只挑一条且**优先主通道**：挑错了就是"用户等了半天，验的是那条他平时不用的"；
///  - 没配置的族也占一行：少一行会被读成漏测，而真相是"这一族没得测"；
///  - 串行且单族失败不拦后面：一处失败让整轮停摆，等于把四份结论收回成一份；
///  - 超时/抛异常各有结论：把"没问到"糊成"对面说不行"是拿一个新谎换旧谎。
void main() {
  ActiveChannel channel({
    required String family,
    required String id,
    String name = '',
    String role = 'primary',
  }) => ActiveChannel(
    family: family,
    slug: id,
    id: id,
    displayName: id,
    configName: name,
    target: '',
    role: role,
  );

  group('chainCheckTargets', () {
    test('每族挑一条，优先主通道；只有一条时就是它', () {
      final targets = chainCheckTargets([
        channel(family: 'webhook', id: 'wh-backup', role: 'backup'),
        channel(family: 'webhook', id: 'wh-primary', name: '告警群'),
        channel(family: 'email', id: 'mail-none', role: 'none'),
      ]);
      expect(targets.map((c) => c.id), ['wh-primary', 'mail-none']);
    });

    test('顺序跟着 channelFamilies 走（不是按输入顺序）', () {
      final targets = chainCheckTargets([
        channel(family: 'fnthink', id: 'f1'),
        channel(family: 'webhook', id: 'w1'),
      ]);
      expect(targets.map((c) => c.family), ['webhook', 'fnthink']);
    });
  });

  group('runChainSelfCheck', () {
    test('四族各一行：成功的 ok、失败的 failed、没配置的 noChannel', () async {
      final channels = [
        channel(family: 'webhook', id: 'w1', name: '告警群'),
        channel(family: 'app', id: 'a1', name: '办公'),
      ];
      final sent = <String>[];
      final entries = await runChainSelfCheck(
        channels: channels,
        send: (c) async {
          sent.add(c.family);
          return (ok: c.family == 'webhook', message: '原生原话');
        },
      );
      expect(entries.length, 4);
      expect(entries.map((e) => e.family), [
        'webhook',
        'email',
        'app',
        'fnthink',
      ]);
      expect(entries[0].state, ChainCheckState.ok);
      expect(entries[0].channelName, '告警群');
      expect(entries[0].message, '原生原话');
      expect(entries[1].state, ChainCheckState.noChannel);
      expect(entries[2].state, ChainCheckState.failed);
      expect(entries[3].state, ChainCheckState.noChannel);
      // 只打了两族：没配置的族不许为了"凑四行"也发一条。
      expect(sent, ['webhook', 'app']);
    });

    test('一族抛异常不拦后面的族（四份结论照样齐）', () async {
      final channels = [
        channel(family: 'webhook', id: 'w1'),
        channel(family: 'email', id: 'e1'),
      ];
      final entries = await runChainSelfCheck(
        channels: channels,
        send: (c) async {
          if (c.family == 'webhook') throw StateError('装配缺失');
          return (ok: true, message: '');
        },
      );
      expect(entries[0].state, ChainCheckState.failed);
      expect(entries[0].message, contains('装配缺失'));
      expect(entries[1].state, ChainCheckState.ok);
    });

    test('超时也是"未通过"，并说出那一档（不是永远挂着）', () async {
      final channels = [channel(family: 'app', id: 'a1')];
      final entries = await runChainSelfCheck(
        channels: channels,
        send: (_) async => throw TimeoutException('slow'),
      );
      expect(entries[2].state, ChainCheckState.failed);
      expect(entries[2].message, 'timeout');
    });

    test('空通道表 ⇒ 四行都是 noChannel（一次也不发）', () async {
      final entries = await runChainSelfCheck(
        channels: const [],
        send: (_) async => (ok: true, message: ''),
      );
      expect(entries.length, 4);
      expect(
        entries.every((e) => e.state == ChainCheckState.noChannel),
        isTrue,
      );
    });
  });
}
