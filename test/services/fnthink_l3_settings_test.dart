import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l3_settings.dart';

/// T51：L3 能力表的**设备侧那一半**（设置项词表 + 纯解析 + 派发）。
///
/// 这一组钉的是五件事：
///  ① 词表来自契约，代码里不重复写一遍（两端各持一份映射是刻意的，名单**只能**在契约里）；
///  ② `grant` 与 `toggle` 两种形态分开 —— 原生侧至今**没有**静默改系统设置的能力，
///     那七项 `grant` 全部是「跳设置页请用户自己点」，混成一张没有 mode 的表，
///     界面上就会把两种承诺显示成同一种；
///  ③ 认不出的设置项一律拒，**不静默跳过**；
///  ④ 每次都要确认，且**没有免确认这条路**（契约 allowSkipConfirm: false）；
///  ⑤ 先有授权才谈得上翻的那两项：缺授权就是缺，**不自动去拿**。
class RecordingExecutor implements FnthinkL3Executor {
  final List<String> calls = [];
  bool failEverything = false;
  bool throwEverything = false;

  @override
  Future<bool> grant(FnthinkL3Setting setting) async {
    calls.add('grant(${setting.key})');
    if (throwEverything) throw StateError('bridge down');
    return !failEverything;
  }

  @override
  Future<bool> toggle(FnthinkL3Setting setting) async {
    calls.add('toggle(${setting.key})');
    if (throwEverything) throw StateError('bridge down');
    return !failEverything;
  }
}

void main() {
  final contract = FnthinkContract.readFile();

  group('契约词表（唯一出处）', () {
    test('读得到设置项，且每一项都有形态与落点（项数不在这里写死）', () {
      final settings = contract.l3Settings;
      expect(settings, isNotEmpty);
      expect(
        l3SettingsCoveredByDevice(contract),
        isTrue,
        reason: '契约加了设置项而设备侧没接 ⇒ 对端能发一个这台机器做不了的动作',
      );
      for (final entry in settings.entries) {
        expect(
          entry.value.native,
          isNotEmpty,
          reason: '${entry.key} 没写落点 = 契约说有、设备上找不到',
        );
        expect(contract.l3SettingModes, contains(entry.value.mode));
      }
    });

    test('两种形态都有实例（今天只有这两种，没有第三种）', () {
      expect(contract.l3SettingModes, ['grant', 'toggle']);
      final settings = contract.l3Settings.values;
      expect(settings.where((s) => s.isGrant), isNotEmpty);
      expect(settings.where((s) => s.isToggle), isNotEmpty);
    });

    test('先有授权才谈得上翻的那两项，都是 toggle', () {
      final needs = contract.l3SettingsRequiringExistingGrant;
      expect(needs, isNotEmpty);
      for (final key in needs) {
        expect(
          contract.l3Settings[key]!.isToggle,
          isTrue,
          reason: '$key 不是 toggle：要求「先有授权才翻」的只可能是 toggle',
        );
      }
    });

    test('执行失败回的那一个词在顶层 receipts 词表里', () {
      expect(contract.l3SettingsReceipt, 'failed_action');
    });
  });

  group('parseL3Item：四种拒的理由各不相同', () {
    test('认得出的两项各解析成设置项（确认过之后）', () {
      expect(
        parseL3Item(contract, 'exact_alarm', confirmedThisTime: true),
        FnthinkL3Ok(contract.l3Settings['exact_alarm']!),
      );
      expect(
        parseL3Item(
          contract,
          'monitoring',
          confirmedThisTime: true,
          grantedKeys: const {'monitoring'},
        ),
        FnthinkL3Ok(contract.l3Settings['monitoring']!),
      );
    });

    test('item 为空或 null ⇒ missing-item（不猜一个设置项出来）', () {
      for (final given in [null, '']) {
        expect(
          parseL3Item(contract, given),
          const FnthinkL3Rejected('missing-item'),
        );
      }
    });

    test('词表外的项 ⇒ unknown-setting:<名>，不静默跳过', () {
      expect(
        parseL3Item(contract, 'wipe_everything', confirmedThisTime: true),
        const FnthinkL3Rejected('unknown-setting:wipe_everything'),
      );
      expect(
        parseL3Item(contract, 'wipe_everything'),
        isA<FnthinkL3Rejected>(),
      );
    });

    test('没确认 ⇒ confirm-required（且没有免确认这条路）', () {
      // ⚠ 本组最要紧的一条：跳过它 = L3 这一档变成"发一次就生效"，
      // 而这一档的全部意义就是每次都要用户自己点一下
      expect(
        parseL3Item(contract, 'exact_alarm'),
        const FnthinkL3Rejected('confirm-required'),
      );
      expect(
        contract.boolOf(const ['capabilities', 'l3', 'allowSkipConfirm']),
        isFalse,
        reason: '契约里没有免确认这条路',
      );
    });

    test('先有授权才谈得上翻的项，缺授权就是缺（不自动去拿）', () {
      expect(
        parseL3Item(contract, 'monitoring', confirmedThisTime: true),
        const FnthinkL3Rejected('missing-grant:monitoring'),
      );
      // 授权已在那台设备上 ⇒ 放行
      expect(
        parseL3Item(
          contract,
          'monitoring',
          confirmedThisTime: true,
          grantedKeys: const {'monitoring'},
        ),
        isA<FnthinkL3Ok>(),
      );
    });

    test('不需要预授权的 grant 项不查已授权清单（去拿授权正是它要做的事）', () {
      expect(
        parseL3Item(contract, 'battery_optimization', confirmedThisTime: true),
        isA<FnthinkL3Ok>(),
      );
    });
  });

  group('派发：grant 与 toggle 走两个不同的方法', () {
    test('两种形态各落到该落的方法上', () async {
      final exec = RecordingExecutor();
      for (final key in ['exact_alarm', 'monitoring']) {
        final parsed = parseL3Item(
          contract,
          key,
          confirmedThisTime: true,
          grantedKeys: {if (key == 'monitoring') 'monitoring'},
        );
        expect(parsed, isA<FnthinkL3Ok>());
        await dispatchL3Setting(
          contract,
          exec,
          (parsed as FnthinkL3Ok).setting,
        );
      }
      expect(exec.calls, ['grant(exact_alarm)', 'toggle(monitoring)']);
    });

    test('做不到 ⇒ failed（不是"已开"：grant 的成功只是把人送到那一页）', () async {
      final exec = RecordingExecutor()..failEverything = true;
      final r = await dispatchL3Setting(
        contract,
        exec,
        contract.l3Settings['exact_alarm']!,
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'not-applied:exact_alarm');
      expect(r.receipt(contract), contract.l3SettingsReceipt);
    });

    test('抛异常也记成"做失败了"，不往上抛（别让一次失败拖垮整轮收货）', () async {
      final exec = RecordingExecutor()..throwEverything = true;
      final r = await dispatchL3Setting(
        contract,
        exec,
        contract.l3Settings['autostart']!,
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'threw:autostart');
    });
  });

  group('回执与留痕的分工', () {
    test('成功 ⇒ delivered，失败 ⇒ 契约那一个词', () async {
      final exec = RecordingExecutor();
      final ok = await dispatchL3Setting(
        contract,
        exec,
        contract.l3Settings['exact_alarm']!,
      );
      expect(ok.receipt(contract), 'delivered');

      const bad = FnthinkL3Result.failed('not-applied:exact_alarm');
      expect(bad.receipt(contract), 'failed_action');
    });

    test('本地细节只进 reason，不进对外那个词', () {
      const r = FnthinkL3Result.failed('not-applied:exact_alarm');
      expect(r.receipt(contract), isNot(contains('exact_alarm')));
    });
  });

  group('真实契约而不是夹具', () {
    test('这些用例读的是仓库那份契约（它自洽，否则本文件在测空气）', () {
      expect(contract.validate(), isEmpty);
      expect(File(fnthinkContractFile()).existsSync(), isTrue);
    });
  });

  group('L3 item 目标值（契约 l3.itemMayCarryTarget）', () {
    // ⚠ 与 `server/test/fnthink-l3target.test.js` **逐条对应**：两端各拆一次同一个 item，
    //   两份都改或都不改 —— 否则漂了只有真发一次才看得见。

    // ⚠ `grantedKeys` **给了**（Dart 侧那一格没给就是拒）：`monitoring` /
    //   `collect_inbox` 在契约 `requiresExistingGrantFrom` 里。
    //   ⚗ 顺带记一处两端不同的默认值：Node 侧 `opts.grantedKeys` 不给就**跳过**
    //   那一格，Dart 侧默认是空集合 ⇒ **全拒**。调用方两边都得给，
    //   而"不给"在两端的含义不同（放行 vs 拒）—— 本组按 Dart 的约定给。
    FnthinkL3Ok ok(String item) =>
        parseL3Item(
              contract,
              item,
              confirmedThisTime: true,
              grantedKeys: const {'monitoring', 'collect_inbox'},
            )
            as FnthinkL3Ok;

    test('裸 key 收，且目标值是 null（沿用旧语义：读当前再翻，不幂等）', () {
      expect(ok('monitoring').setting.targetValue, isNull);
    });

    test('<key>/on ⇒ 目标值 true（幂等那一档）', () {
      expect(ok('monitoring/on').setting.targetValue, isTrue);
      expect(ok('monitoring/on').setting.key, 'monitoring');
    });

    test('<key>/off ⇒ 目标值 false', () {
      expect(ok('collect_inbox/off').setting.targetValue, isFalse);
    });

    test('⚠ 大小写不同 ⇒ 不拆（unknown-setting 带整串，不是猜）', () {
      final r = parseL3Item(contract, 'monitoring/ON', confirmedThisTime: true);
      expect(r, isA<FnthinkL3Rejected>());
      expect((r as FnthinkL3Rejected).reason, 'unknown-setting:monitoring/ON');
    });

    test('尾部不是目标值词 ⇒ 不拆，仍按整串查词表', () {
      expect(
        parseL3Item(contract, 'monitoring/enabled', confirmedThisTime: true),
        isA<FnthinkL3Rejected>(),
      );
    });

    test('不存在的 key 带目标值 ⇒ 拒的理由说的是拆出来的那个 key', () {
      final r = parseL3Item(contract, 'nope/off', confirmedThisTime: true);
      expect((r as FnthinkL3Rejected).reason, 'unknown-setting:nope');
    });

    test('grant 项也能带目标值（协议不按 mode 限制；设备侧忽略它）', () {
      final setting = ok('exact_alarm/on').setting;
      expect(setting.mode, 'grant');
      expect(setting.targetValue, isTrue);
    });

    test('前置授权那一格仍然按**拆出来的 key** 判', () {
      // ⚠ `grantedKeys` 给了（即使是空列表）那一格才判。
      final bare = parseL3Item(
        contract,
        'collect_inbox',
        confirmedThisTime: true,
        grantedKeys: const <String>{},
      );
      expect((bare as FnthinkL3Rejected).reason, 'missing-grant:collect_inbox');
      final withTarget = parseL3Item(
        contract,
        'collect_inbox/on',
        confirmedThisTime: true,
        grantedKeys: const <String>{},
      );
      expect(
        (withTarget as FnthinkL3Rejected).reason,
        'missing-grant:collect_inbox',
      );
    });

    test('词从契约读：契约里去掉 itemTargetWords ⇒ 目标值不再被拆', () {
      // 这一条钉住「那两个词**不写死**」——它们经服务端透传回执、两端各拆一次，
      // 写死等于第三份，而第三份不会随契约一起改。
      final stripped = Map<String, Object?>.from(contract.raw);
      final caps = Map<String, Object?>.from(stripped['capabilities']! as Map);
      final l3 = Map<String, Object?>.from(caps['l3']! as Map)
        ..remove('itemTargetWords');
      caps['l3'] = l3;
      stripped['capabilities'] = caps;
      final bare = FnthinkContract(stripped);

      expect(
        parseL3Item(bare, 'monitoring/on', confirmedThisTime: true),
        isA<FnthinkL3Rejected>(),
        reason: '契约没给那两个字 ⇒ 不该再拆（写死的话这里会拆开并放行）',
      );
    });
  });
}
