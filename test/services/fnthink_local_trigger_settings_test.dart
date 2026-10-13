import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_remote_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T145 片1：「本机通知触发」那两格的**设置层**（解析、判「许不许」、落盘回读同形）。
///
/// 判定层那两道闸本身在 `fnthink_remote_command_handler_test.dart` 的
/// 「本机通知那一路的两道闸」那一组；这一文件只管这三枚纯件与 prefs。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();

  FnthinkLocalTriggerFilter filter(String mode, List<String> packages) =>
      parseLocalTriggerFilter(mode: mode, rawPackages: jsonEncode(packages));

  group('parseLocalTriggerFilter：坏值一律退回最窄那一档，不抛', () {
    test('从没写过 ⇒ allow + 空集', () {
      final f = parseLocalTriggerFilter();
      expect(f.mode, 'allow');
      expect(f.packages, isEmpty);
    });

    test('模式不认识 ⇒ 归成 allow（只有 block 才是另一档）', () {
      expect(filter('白名单', ['a']).mode, 'allow');
      expect(filter('block', ['a']).mode, 'block');
    });

    test('清单不是 JSON 数组 / 坏 JSON ⇒ 空集（这一档读成"谁都不许"）', () {
      for (final bad in ['{not an array}', '"com.a"', '']) {
        final f = parseLocalTriggerFilter(
          mode: 'allow',
          rawPackages: bad.isEmpty ? null : bad,
        );
        expect(f.packages, isEmpty, reason: '坏值 `$bad` 不许留下任何可用清单');
      }
    });

    test('数组里的非字符串与空白项被丢掉，其余留形', () {
      final f = parseLocalTriggerFilter(
        mode: 'allow',
        rawPackages: '["  com.a  ", 7, "", null, "com.b"]',
      );
      expect(f.packages, {'com.a', 'com.b'});
    });
  });

  group('localTriggerAllows：这一路的空集与转发面那条**相反**', () {
    test('allow + 空集 ⇒ 谁都不许', () {
      expect(
        localTriggerAllows(filter('allow', []), 'com.a'),
        isFalse,
        reason:
            '转发面那一条"空集=不限"少推一条只是吵到用户；这一路多执行一次'
            '是替他动一次手 ⇒ 缺省必须往窄的那一侧',
      );
    });

    test('allow + 清单里有 ⇒ 只许它', () {
      final f = filter('allow', ['com.a']);
      expect(localTriggerAllows(f, 'com.a'), isTrue);
      expect(localTriggerAllows(f, 'com.b'), isFalse);
    });

    test('block + 空集 ⇒ 全都许（block 的语义就是"除这些之外"）', () {
      expect(localTriggerAllows(filter('block', []), 'com.a'), isTrue);
    });

    test('block + 清单里有 ⇒ 只拦它', () {
      final f = filter('block', ['com.a']);
      expect(localTriggerAllows(f, 'com.a'), isFalse);
      expect(localTriggerAllows(f, 'com.b'), isTrue);
    });

    test('拿不到包名 ⇒ 不许（"未知"不等于"放行"）', () {
      final f = filter('block', []);
      expect(localTriggerAllows(f, ''), isFalse);
      expect(localTriggerAllows(f, '   '), isFalse);
    });
  });

  group('落盘与回读：界面显示的那一份与判定读的那一份同形', () {
    test('那颗开关默认关；点过之后读得回来', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = FnthinkRemoteSettings(contract: contract);
      expect(await settings.localTriggerEnabled, isFalse);
      await settings.setLocalTriggerEnabled(true);
      expect(await settings.localTriggerEnabled, isTrue);
      await settings.setLocalTriggerEnabled(false);
      expect(await settings.localTriggerEnabled, isFalse);
    });

    test('写进去的清单读出来逐字同形（模式归一 + 空白被裁）', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = FnthinkRemoteSettings(contract: contract);
      // 从没写过 ⇒ 最窄那一档，而不是"不限"。
      expect((await settings.localTriggerFilter()).packages, isEmpty);

      await settings.setLocalTriggerFilter(
        mode: 'ALLOW',
        packages: ['  com.a  ', 'com.b'],
      );
      final read = await settings.localTriggerFilter();
      expect(read.mode, 'allow', reason: '模式只有一个作者认的两档，存的必须是归一后的那一个');
      expect(read.packages, {'com.a', 'com.b'});
      expect(localTriggerAllows(read, 'com.b'), isTrue);
      expect(localTriggerAllows(read, 'com.c'), isFalse);

      await settings.setLocalTriggerFilter(mode: 'block', packages: const []);
      expect((await settings.localTriggerFilter()).mode, 'block');
    });

    test('那颗开关与那份清单互不越界（关掉开关不毁清单，反之亦然）', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = FnthinkRemoteSettings(contract: contract);
      await settings.setLocalTriggerEnabled(true);
      await settings.setLocalTriggerFilter(mode: 'allow', packages: ['com.a']);
      await settings.setLocalTriggerEnabled(false);
      expect((await settings.localTriggerFilter()).packages, {'com.a'});

      await settings.setLocalTriggerFilter(mode: 'block', packages: ['com.z']);
      expect(await settings.localTriggerEnabled, isFalse);
    });
  });

  test('这三份键与转发面那两份不共用（一复用就同时改了推送名单）', () {
    const owned = [
      FnthinkRemoteSettings.keyLocalTriggerEnabled,
      FnthinkRemoteSettings.keyLocalTriggerMode,
      FnthinkRemoteSettings.keyLocalTriggerPackages,
    ];
    for (final key in owned) {
      expect(key, isNot('enabled_packages'));
      expect(key, isNot('app_filter_mode'));
      expect(key.startsWith('fnthink.remote_execution.'), isTrue);
    }
    expect(owned.toSet(), hasLength(3));
  });
}
