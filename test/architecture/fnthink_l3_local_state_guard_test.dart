import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';

/// T134 尾巴的守卫：`missing-grant` 改指**本机状态**（唯一作者
/// `FnthinkL3LocalState`）之后，三件事不许再漂：
/// ① 契约 `requiresExistingGrantFrom` 的每一项都有本机读数（漏一项 = 恒拒且没人喊）；
/// ② 纯函数 `parseL3Item` 不再判授权（对端清单读法已退役，长回来就是第二份判据）；
/// ③ 判定层与执行前两处真的在问唯一作者（理由码 `missing-grant` 只在这两处生产）。
String read(String path) => File(path).readAsStringSync();

String strip(String code) => code
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();
  final localState = strip(read('lib/services/fnthink_l3_local_state.dart'));
  final l3Settings = strip(read('lib/services/fnthink_l3_settings.dart'));
  final handler = strip(
    read('lib/services/fnthink_remote_command_handler.dart'),
  );
  final runner = strip(read('lib/services/fnthink_remote_runner.dart'));

  test('契约 requiresExistingGrantFrom 的每一项都有本机读数', () {
    expect(
      contract.l3SettingsRequiringExistingGrant,
      isNotEmpty,
      reason: '锚点：契约那一表空了 = 本守卫对不上任何东西',
    );
    for (final key in contract.l3SettingsRequiringExistingGrant) {
      expect(
        localState,
        contains("case '$key':"),
        reason:
            '契约要本机读数的项 "$key" 在 FnthinkL3LocalState 没有接 ⇒ '
            '它会被 fail-closed 恒拒，而没有任何用例会红',
      );
    }
  });

  test('纯函数 parseL3Item 不再判授权（对端清单读法已退役）', () {
    expect(
      l3Settings,
      isNot(contains('missing-grant')),
      reason: 'T134 尾巴之后理由码只许住在判定层与执行前两处',
    );
    expect(
      l3Settings,
      isNot(contains('grantedKeys')),
      reason: '旧形参长回来 = 对端清单读法复活，与本机状态两处各判一次',
    );
  });

  test('判定层与执行前两处真的在问唯一作者', () {
    expect(handler, contains('l3InPlace('), reason: '锚点：判定层没问 = 本守卫对判定层空转');
    expect(handler, contains("'missing-grant:\$key'"), reason: '判定层的理由码在');
    expect(runner, contains('l3InPlace('), reason: '锚点：执行前没问 = 本守卫对执行层空转');
    expect(
      runner,
      contains("'missing-grant:\$base'"),
      reason: '执行前的理由码在（窗口期本机状态变化要有真判据）',
    );
  });
}
