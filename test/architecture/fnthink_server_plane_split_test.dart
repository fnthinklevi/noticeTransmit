import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T157 的源码守卫：**「服务可达」与「协议面」是两个主语，不许共用一份记录**。
///
/// 这一条缺陷的形状是：`/health` 200 证明"这台机器上有进程在答 HTTP"，而页面用它
/// 说"在线"；协议面（签名请求能不能通）根本没被问过。修法把两条读数拆成两个 family，
/// 并让协议面那一格只读协议请求写的那一份。
String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

String _read(String rel) => _strip(File(rel).readAsStringSync());

String _window(String src, String start, String end) {
  final at = src.indexOf(start);
  expect(at, greaterThanOrEqualTo(0), reason: '未找到 $start');
  final endAt = src.indexOf(end, at);
  expect(endAt, greaterThan(at), reason: '未找到 $start 之后的 $end');
  return src.substring(at, endAt);
}

String _value(String arb, String key) {
  final match = RegExp('"$key": "([^"]*)"').firstMatch(arb);
  expect(match, isNotNull, reason: 'ARB 缺 $key');
  return match!.group(1)!;
}

void main() {
  final display = _read('lib/services/channel_display.dart');
  final settings = _read('lib/pages/fnthink_settings_page.dart');
  final receive = _read('lib/pages/fnthink_receive_page.dart');
  final zh = File('lib/l10n/arb/app_zh.arb').readAsStringSync();
  final en = File('lib/l10n/arb/app_en.arb').readAsStringSync();

  test('可达性与协议面是两个具名 family，探针只写可达性', () {
    expect(
      display,
      contains("kFnthinkReachabilityFamily = 'fnthink-reachability'"),
    );
    expect(display, contains("kFnthinkServerFamily = 'fnthink-server'"));
    final locator = _window(
      settings,
      'factory FnthinkSettingsDeps.fromLocator()',
      'final FnthinkContractLoader contracts;',
    );
    expect(locator, contains('kFnthinkReachabilityFamily'));
    expect(
      RegExp(r'record\(\s*kFnthinkReachabilityFamily,').hasMatch(locator),
      isTrue,
      reason: '探针没写可达性族 ⇒ 那一格又回到两个主语共用一份记录',
    );
    expect(
      RegExp(r'record\(\s*kFnthinkServerFamily,').hasMatch(locator),
      isFalse,
      reason: '探针写回协议面 = 一次 /health 200 把协议面的失败盖成"有应答"',
    );
  });

  test('两格各读各的：可达性读 reachabilityOf，协议面读 healthOf', () {
    final reach = _window(
      settings,
      'String _reachabilityWord(',
      'String _protocolWord(',
    );
    final proto = _window(
      settings,
      'String _protocolWord(',
      'Widget _hostReadout(',
    );
    expect(reach, contains('_deps.reachabilityOf'));
    expect(proto, contains('_deps.healthOf'));
    expect(proto, contains('_hostVerdicts[host] == null'));
    expect(proto, contains('fnthinkProtocolUnverified'));
    expect(proto, contains('fnthinkProtocolNever'));
    expect(settings, contains("'fnthink-host-reachability'"));
    expect(settings, contains("'fnthink-host-protocol'"));
  });

  test('协议面的未知只由当前 host 的 /health 版本那一半决定', () {
    expect(settings, contains('_hostVerdicts[host] = text'));
    expect(
      settings,
      contains('_hostVerdicts[host]'),
      reason: '协议面那一格必须问当前这台有没有 /health 版本读数，不能拿候选全集的结论顶',
    );
  });

  test('收货页那一行也改说「协议面」，不再说服务器有应答/在线', () {
    expect(receive, contains('fnthinkHealthNever'));
    expect(receive, contains('fnthinkHealthReachable'));
    expect(receive, contains('fnthinkHealthUnreachable'));
    expect(receive, isNot(contains('healthReachable(')));
  });

  test('三句旧文案改成协议面措辞，且中文里没有「在线」', () {
    for (final key in [
      'fnthinkHealthNever',
      'fnthinkHealthReachable',
      'fnthinkHealthUnreachable',
    ]) {
      expect(_value(zh, key), contains('协议面'), reason: '$key 没说清是协议面');
      expect(_value(zh, key), isNot(contains('在线')));
      expect(_value(en, key).toLowerCase(), contains('protocol plane'));
    }
    expect(_value(zh, 'fnthinkHealthReachable'), isNot(contains('服务器有应答')));
    expect(_value(zh, 'fnthinkHealthUnreachable'), isNot(contains('连不上服务器')));
  });

  test('两格的新词条中英都在', () {
    for (final arb in [zh, en]) {
      for (final key in [
        'fnthinkReachabilityLabel',
        'fnthinkProtocolLabel',
        'fnthinkReachabilityOk',
        'fnthinkReachabilityFailed',
        'fnthinkReachabilityStale',
        'fnthinkReachabilityNever',
        'fnthinkProtocolReadyShort',
        'fnthinkProtocolFailedShort',
        'fnthinkProtocolStale',
        'fnthinkProtocolNever',
        'fnthinkProtocolUnverified',
      ]) {
        expect(arb, contains('"$key"'), reason: '缺 $key');
      }
    }
  });
}
