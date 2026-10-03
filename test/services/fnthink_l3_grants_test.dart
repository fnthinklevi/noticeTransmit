import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l3_grants.dart';

/// T52：权限引导页背后那一份**读模型**。
///
/// 页面要展示的是「契约里那几项系统设置，这一台各自是哪一态」。这一组用例钉的全是
/// **四态不能被混成一态**：
///  ① `granted` 给了；② `missing` 没给（要用户去开）；
///  ③ `unreadable` 读不到（没查到 ≠ 没给，要修的是代码）；
///  ④ `unsupported` 这台压根没有这一项（设备事实，换一台就变）。
///
/// ⚠ ②③④ 合成一种是本仓修过的老 bug 的形状（权限页恒显「已授予」）：把「不知道」
/// 显示成「有」，用户就再也不会去查那一格。这里同时钉住**未授权项留在列表里**
/// （置灰 + 一句说明），而不是被折叠掉。
void main() {
  final contract = FnthinkContract.readFile();
  final keys = contract.l3Settings.keys.toList();

  /// 造一份「全部读到」的读数：调用方按需要把某项改成 null / false。
  Map<String, bool?> allReaders({bool granted = true}) => {
    for (final k in keys) k: granted,
  };

  FnthinkL3GrantRow rowOf(List<FnthinkL3GrantRow> rows, String key) =>
      rows.firstWhere((r) => r.key == key);

  group('四态不合并', () {
    test('true / false / null 各落一态，且这三态今天就都在词表里跑得通', () {
      final rows = collectL3GrantRows(
        contract,
        readers: allReaders()
          ..['notification'] = true
          ..['battery_optimization'] = false
          ..['exact_alarm'] = null,
      );
      expect(rowOf(rows, 'notification').state, FnthinkL3GrantState.granted);
      expect(
        rowOf(rows, 'battery_optimization').state,
        FnthinkL3GrantState.missing,
      );
      expect(rowOf(rows, 'exact_alarm').state, FnthinkL3GrantState.unreadable);
    });

    test('读不到的一项仍列出，且不降级成「未授权」', () {
      // ⚠ 这一条才是本片的重点：读不到要的是**修代码**，未授权要的是**用户动手**。
      // 合成一态之后，界面上会出现一句催用户去开的话，而那一格压根没有读数可催。
      final rows = collectL3GrantRows(
        contract,
        readers: allReaders()..['exact_alarm'] = null,
      );
      final row = rowOf(rows, 'exact_alarm');
      expect(row.unreadable, isTrue);
      expect(row.granted, isFalse);
      expect(
        row.needsUserAction,
        isFalse,
        reason: 'unreadable 不该被算进「等用户去开」那一堆',
      );
    });

    test('readers 里干脆没有这个键，与读到 null 同一种下场', () {
      // 少注册一个读法（那个方法在这个 Android 版本上没实现）在调用方看来就是
      // 取不到值，与显式 null 没有区别 —— 两种都得落在「读不到」那一档。
      final missing = allReaders()..remove('battery_optimization');
      final absent = allReaders()..['battery_optimization'] = null;
      expect(
        rowOf(
          collectL3GrantRows(contract, readers: missing),
          'battery_optimization',
        ).state,
        FnthinkL3GrantState.unreadable,
      );
      expect(
        rowOf(
          collectL3GrantRows(contract, readers: absent),
          'battery_optimization',
        ).state,
        FnthinkL3GrantState.unreadable,
      );
    });

    test('「这台没有」是第四态，不与「用户没开」共用一档', () {
      // ⚠ 与 missing 混起来，用户会一直为一个换台手机就不存在的问题去设置里找开关。
      final rows = unsupportedL3Grants(
        contract,
        keys.where((k) => k != 'autostart').toSet(),
      );
      expect(rows.map((r) => r.key).toList(), ['autostart']);
      expect(rows.single.state, FnthinkL3GrantState.unsupported);
      expect(rows.single.granted, isFalse);
      expect(rows.single.needsUserAction, isFalse);
      expect(unsupportedL3Grants(contract, keys.toSet()), isEmpty);
    });

    test('四态各有来路：今天每一条都真造得出来（不是写着好看）', () {
      final produced = <FnthinkL3GrantState>{};
      produced.addAll(
        collectL3GrantRows(contract, readers: allReaders()).map((r) => r.state),
      );
      produced.addAll(
        collectL3GrantRows(
          contract,
          readers: allReaders(granted: false),
        ).map((r) => r.state),
      );
      produced.addAll(
        collectL3GrantRows(
          contract,
          readers: const <String, bool?>{},
        ).map((r) => r.state),
      );
      produced.addAll(
        unsupportedL3Grants(contract, const <String>{}).map((r) => r.state),
      );
      expect(produced, FnthinkL3GrantState.values.toSet());
    });
  });

  group('置灰而不是隐藏', () {
    test('每一项都在列表里，且次序取自契约', () {
      final rows = collectL3GrantRows(contract, readers: allReaders());
      expect(rows.map((r) => r.key).toList(), keys);
      expect(rows.length, contract.l3Settings.length);
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

    test('全部读不到时同样一行都不少', () {
      // 「这台读不到」那一支与「读到值」那一支是两段代码，只查前者等于没查后者。
      final rows = collectL3GrantRows(contract, readers: const {});
      expect(rows.length, contract.l3Settings.length);
      expect(rows.every((r) => r.unreadable), isTrue);
    });
  });

  group('每行带的仍是契约里那一份', () {
    test('落点与形态取自契约，两种读法造出的行都查', () {
      final rows = [
        collectL3GrantRows(contract, readers: allReaders()),
        unsupportedL3Grants(contract, const <String>{}),
      ];
      for (final batch in rows) {
        for (final row in batch) {
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

    test('已授权的那一项不配说明（给了还说"你还没给"是自相矛盾）', () {
      final rows = collectL3GrantRows(
        contract,
        readers: allReaders()
          ..['notification'] = false
          ..['battery_optimization'] = true,
        notes: const {
          'notification': '不开这一项，收不到任何通知',
          'battery_optimization': '这句在已授权时用不上',
        },
      );
      expect(rowOf(rows, 'notification').note, '不开这一项，收不到任何通知');
      expect(rowOf(rows, 'battery_optimization').note, isEmpty);
    });
  });

  group('l3GrantRow：词表外的一行造不出来', () {
    test('拿契约里没有的 key 去渲染 ⇒ 抛错点名那个 key', () {
      expect(
        () => l3GrantRow(
          contract,
          'foreground_service',
          state: FnthinkL3GrantState.missing,
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
        state: FnthinkL3GrantState.granted,
        note: '这句该被丢掉',
      );
      expect(row.mode, 'toggle');
      expect(row.directlyToggleable, isTrue);
      expect(row.granted, isTrue);
      expect(row.note, isEmpty);
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
      expect(outstandingL3Grants(rows).map((r) => r.key).toList(), [
        'exact_alarm',
        'autostart',
        'monitoring',
        'collect_inbox',
      ]);
    });

    test('读不到与这台没有的，都不算进「等用户去开」', () {
      // 「还差哪几项」这一句是要催人的：把没有读数的那格算进去，催的是修代码的人；
      // 把这台没有的那格算进去，催的是一件在这台设备上做不成的事。
      final rows = [
        ...collectL3GrantRows(
          contract,
          readers: allReaders()
            ..['notification'] = false
            ..['battery_optimization'] = null
            ..remove('exact_alarm'),
        ),
        ...unsupportedL3Grants(
          contract,
          keys.where((k) => k != 'battery_optimization').toSet(),
        ),
      ];
      expect(outstandingL3Grants(rows).map((r) => r.key).toList(), [
        'notification',
      ]);
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
