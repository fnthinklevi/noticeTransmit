import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations_en.dart';
import 'package:notice_transmit/l10n/app_localizations_zh.dart';
import 'package:notice_transmit/services/fnthink_network_status.dart';

import '../support/source_guards.dart';

void main() {
  group('T215 片3：网关码翻人话', () {
    test('554/524 说网关超时，不把码糊在脸上', () {
      final zh = AppLocalizationsZh();
      final en = AppLocalizationsEn();
      expect(
        fnthinkPollStatusText(zh, 'gatewayTimeout:gateway-timeout:554'),
        zh.fnthinkPollGatewayTimeout,
      );
      expect(
        fnthinkPollStatusText(zh, 'failed:http:524'),
        zh.fnthinkPollGatewayTimeout,
      );
      expect(
        fnthinkPollStatusText(en, 'gatewayTimeout:gateway-timeout:554'),
        en.fnthinkPollGatewayTimeout,
      );
    });

    test('其它 5xx 说网关暂时不可用，并带状态码', () {
      final zh = AppLocalizationsZh();
      expect(
        fnthinkPollStatusText(zh, 'failed:http:502'),
        zh.fnthinkPollGatewayUnavailable('502'),
      );
    });

    test('非网关的失败仍原样返回', () {
      final zh = AppLocalizationsZh();
      expect(fnthinkPollStatusText(zh, 'failed:http:404'), 'failed:http:404');
      expect(fnthinkPollStatusText(zh, 'ok'), 'ok');
    });
  });

  group('T228：本轮跳过不是失败', () {
    test('round-in-progress 翻成人话，不把 failed 前缀摊在脸上', () {
      final zh = AppLocalizationsZh();
      final en = AppLocalizationsEn();
      expect(
        fnthinkPollStatusText(zh, 'failed:round-in-progress'),
        zh.fnthinkPollRoundInProgress,
      );
      expect(
        fnthinkPollStatusText(en, 'failed:round-in-progress'),
        en.fnthinkPollRoundInProgress,
      );
      expect(
        fnthinkPollStatusText(zh, 'failed:round-in-progress'),
        isNot('failed:round-in-progress'),
      );
    });

    test('跳过词条里不许出现 failed / 失败', () {
      for (final text in [
        AppLocalizationsZh().fnthinkPollRoundInProgress,
        AppLocalizationsEn().fnthinkPollRoundInProgress,
      ]) {
        expect(text.toLowerCase(), isNot(contains('failed')));
        expect(text, isNot(contains('失败')));
      }
    });

    test('「协议面就绪」对跳过不出结论', () {
      expect(fnthinkPollStatusReachable('failed:round-in-progress'), isNull);
    });

    test('真正的失败仍原样返回（含 signing-unavailable）', () {
      final zh = AppLocalizationsZh();
      expect(fnthinkPollStatusText(zh, 'failed:http:404'), 'failed:http:404');
      expect(
        fnthinkPollStatusText(zh, 'failed:signing-unavailable'),
        'failed:signing-unavailable',
      );
    });
  });

  test('页面三处读数都接到同一份判据', () {
    final root = projectRoot();
    final src = stripComments(
      File('$root/lib/pages/fnthink_receive_page.dart').readAsStringSync(),
    );
    expect(src, contains('fnthinkPollStatusText(l10n, diag.lastPollStatus)'));
    expect(src, contains('_protocolReachability()'));
    expect(src, contains('l10n.fnthinkPresenceLive'));
    expect(
      src,
      isNot(contains('fnthinkPresenceLive(status.liveSeconds)')),
      reason: '长轮询空闲是 hold 25 秒，再说「每 N 秒」就是自相矛盾',
    );
  });

  group('T215 片3：协议面只认最近一次结论', () {
    test('成功与服务端业务结论都算就绪', () {
      expect(fnthinkPollStatusReachable('ok'), isTrue);
      expect(fnthinkPollStatusReachable('rateLimited:30'), isTrue);
      expect(fnthinkPollStatusReachable('rejectedUnsigned:'), isTrue);
    });

    test('网络/网关失败算不可用；本地失败不给结论', () {
      expect(
        fnthinkPollStatusReachable('transportError:TimeoutException'),
        isFalse,
      );
      expect(
        fnthinkPollStatusReachable('gatewayTimeout:gateway-timeout:554'),
        isFalse,
      );
      expect(fnthinkPollStatusReachable('failed:http:500'), isFalse);
      expect(fnthinkPollStatusReachable('failed:signing-unavailable'), isNull);
      expect(fnthinkPollStatusReachable('failed:round-in-progress'), isNull);
      expect(fnthinkPollStatusReachable(''), isNull);
    });
  });
}
