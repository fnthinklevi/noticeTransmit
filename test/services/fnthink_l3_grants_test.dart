import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l3_grants.dart';

/// T52：权限引导页背后那一份**读模型**。
///
/// 页面要展示的是「契约里那几项系统设置，这一台各自给了没有」。这一组用例钉的
/// 全是**这一件事的四种说法不能被混成一种**：
///  ① 给了；② 没给（要用户去开）；③ 这台读不到（没查到 ≠ 没给）；④ 这台压根没有这一项。
///
/// ⚠ ②③④ 混成一种是本仓修过的老 bug 的形状（权限页恒显「已授予」）：把「不知道」
/// 显示成「有」，用户就再也不会去查那一格。这里刻意让三句话各不相同，
/// 并且让**未授权项留在列表里**（置灰 + 一句解释），而不是被折叠掉。
void main() {
  final contract = FnthinkContract.readFile();
  final keys = contract.l3Settings.keys.toList();

  /// 造一份「全部读到」的读数：调用方按需要把某项改成 null / false。
  Map<String, bool?> allReaders({bool granted = true}) => {
    for (final k in keys) k: granted,
  };

  group('七种读法收成一处', () {
    test('每一项都在列表里，且次序取自契约', () {
      final rows = collectL3GrantRows(contract, readers: allReaders());
      expect(rows.map((r) => r.key).toList(), keys);
      expect(rows.length, contract.l3Settings.length);
    });

    test('读不到的一项仍列出，说的是「读不到」而不是「未授权」', () {
      final rows = collectL3GrantRows(
        contract,
        readers: allReaders()..['exact_alarm'] = null,
      );
      final row = rows.firstWhere((r) => r.key == 'exact_alarm');
      expect(row.granted, isFalse);
      expect(row.detail, unreadableDetail);
      // ⚠ 这一条才是本片的重点：三句话必须各不相同。合成一句，界面上就分不清
      // 「用户没去开」与「这条通道压根没读数」—— 后者要修的是代码，前者要动的是用户。
      expect(unreadableDetail, isNot(defaultDetail));
      expect(unreadableDetail, isNot(unsupportedDetail));
    });

    test('readers 里干脆没有这个键，与读到 null 同一种下场', () {
      // 少注册一个读法（换了个 Android 版本、那个方法没实现）在调用方看来就是
      // 取不到值，与显式 null 没有区别 —— 两种都得落在「读不到」那一档。
      final missing = allReaders()..remove('dnd_access');
      final absent = allReaders()..['dnd_access'] = null;
      final a = collectL3GrantRows(contract, readers: missing);
      final b = collectL3GrantRows(contract, readers: absent);
      expect(
        a.firstWhere((r) => r.key == 'dnd_access').detail,
        b.firstWhere((r) => r.key == 'dnd_access').detail,
      );
      expect(
        a.firstWhere((r) => r.key == 'dnd_access').detail,
        unreadableDetail,
      );
    });

    test('全部未授权时一行都不少（未授权是置灰，不是隐藏）', () {
      final rows = collectL3GrantRows(
        contract,
        readers: allReaders(granted: false),
      );
      expect(rows.length, contract.l3Settings.length);
      expect(rows.every((r) => r.needsUserAction), isTrue);
      // 「隐藏」在这个函数里连入口都没有：它不接任何"过滤掉哪些"的参数。
      expect(
        rows.map((r) => r.key).toList(),
        contract.l3Settings.keys.toList(),
      );
    });

    test('已授权的那一项不配解释（给了还说"你还没给"是自相矛盾）', () {
      final rows = collectL3GrantRows(
        contract,
        readers: allReaders()..['notification'] = false,
        details: const {'notification': '不开这一项，收不到任何通知'},
      );
      expect(
        rows.firstWhere((r) => r.key == 'notification').detail,
        '不开这一项，收不到任何通知',
      );
      expect(
        rows.firstWhere((r) => r.key == 'battery_optimization').detail,
        isEmpty,
      );
    });

    test('每行带的落点来自契约，不在代码里另写一份', () {
      // ⚠ 两支都要查：'读到值'那一支走 l3GrantRow（落点取自 setting），
      // '读不到'那一支在 collectL3GrantRows 里就地造行 —— 只查前者，后者改坏了没人喊。
      for (final rows in [
        collectL3GrantRows(contract, readers: allReaders()),
        collectL3GrantRows(contract, readers: const <String, bool?>{}),
      ]) {
        for (final row in rows) {
          final setting = contract.l3Settings[row.key]!;
          expect(
            row.native,
            setting.native,
            reason: '${row.key}：落点不是契约里那一个（契约说有、设备上找不到）',
          );
          expect(row.native, isNotEmpty);
          expect(row.mode, setting.mode);
        }
      }
    });
  });

  group('l3GrantRow：词表外的一行造不出来', () {
    test('拿契约里没有的 key 去渲染 ⇒ 抛错点名那个 key', () {
      expect(
        () => l3GrantRow(
          contract,
          'foreground_service',
          granted: false,
          detailWhenMissing: '这一项在 8.162 已从契约删掉',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('foreground_service'), contains('settings')),
          ),
        ),
        reason: '悄悄造一行 = 界面上出现一个契约里没有的承诺',
      );
    });

    test('契约里的 key 正常造出一行，mode/native 都取自契约', () {
      final row = l3GrantRow(
        contract,
        'monitoring',
        granted: true,
        detailWhenMissing: '没开',
      );
      expect(row.mode, 'toggle');
      expect(row.directlyToggleable, isTrue);
      expect(row.granted, isTrue);
      expect(row.detail, isEmpty);
    });
  });

  group('outstandingL3Grants：只筛不排', () {
    test('筛出来的仍是契约次序，且只含 needsUserAction 的那些', () {
      final rows = collectL3GrantRows(
        contract,
        readers: allReaders(granted: false)
          ..['notification'] = true
          ..['battery_optimization'] = true,
      );
      final outstanding = outstandingL3Grants(rows);
      expect(outstanding.map((r) => r.key).toList(), [
        'dnd_access',
        'exact_alarm',
        'autostart',
        'monitoring',
        'collect_inbox',
      ]);
      expect(outstanding.every((r) => r.needsUserAction), isTrue);
    });

    test('全给了 ⇒ 空清单（而不是"没有这一项"）', () {
      expect(
        outstandingL3Grants(
          collectL3GrantRows(contract, readers: allReaders()),
        ),
        isEmpty,
      );
    });
  });

  group('unsupportedL3Grants：「这台没有」与「用户没开」是两件事', () {
    test('契约里有、这台没有的那几项被点名，且带的是「这台没有」那句', () {
      final supported = keys.where((k) => k != 'autostart').toSet();
      final rows = unsupportedL3Grants(contract, supported);
      expect(rows.map((r) => r.key).toList(), ['autostart']);
      expect(rows.single.detail, unsupportedDetail);
      expect(rows.single.granted, isFalse);
      expect(unsupportedL3Grants(contract, keys.toSet()), isEmpty);
    });
  });

  group('mode 派生', () {
    test('能直接改的那些，恰好是契约里的 toggle 项', () {
      final toggles = contract.l3Settings.entries
          .where((e) => e.value.mode == 'toggle')
          .map((e) => e.key)
          .toSet();
      final rows = collectL3GrantRows(contract, readers: allReaders());
      expect(
        rows.where((r) => r.directlyToggleable).map((r) => r.key).toSet(),
        toggles,
      );
      final grants = rows
          .where((r) => !r.directlyToggleable)
          .map((r) => r.key)
          .toSet();
      // 今天两种形态各有实例：若契约只剩一种，上面那条断言就成了恒真。
      expect(toggles, isNotEmpty);
      expect(grants, isNotEmpty);
      expect(grants.intersection(toggles), isEmpty);
      expect(grants.union(toggles), hasLength(contract.l3Settings.length));
    });
  });

  group('真实契约而不是夹具', () {
    test('本文件读的是仓库那份契约（它自洽，否则这一组在测空气）', () {
      expect(contract.validate(), isEmpty);
      expect(File(fnthinkContractFile()).existsSync(), isTrue);
    });
  });
}
