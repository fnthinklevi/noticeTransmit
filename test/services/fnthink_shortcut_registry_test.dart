import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_shortcut_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「可被远程打开的入口」那张本机登记表（T124 片B 的 `app:launch` 的本机那一半）。
///
/// 钉四件：两种合法目标形态（组件 / deeplink）、名称与目标的校验（fail-closed）、
/// 读写往返（坏行跳过但不静默删）、以及"按名字精确匹配、不猜"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('目标校验：只有那两条合法路', () {
    test('组件形态（包名/类名）与带 scheme 的链接都收', () {
      expect(
        validateFnthinkShortcutTarget('com.tencent.mm/.ui.LauncherUI'),
        isNull,
      );
      expect(validateFnthinkShortcutTarget('weixin://dl/scan'), isNull);
      expect(validateFnthinkShortcutTarget('https://example.com/x'), isNull);
    });

    test('分不清的一律拒（不猜、不补全）', () {
      expect(validateFnthinkShortcutTarget(''), 'empty');
      expect(validateFnthinkShortcutTarget('   '), 'empty');
      expect(validateFnthinkShortcutTarget('com.tencent.mm'), 'not-a-target');
      expect(validateFnthinkShortcutTarget('weixin/Scan'), 'bad-component');
      expect(validateFnthinkShortcutTarget('com.tencent.mm/'), 'bad-component');
      expect(validateFnthinkShortcutTarget('1abc://x'), 'bad-scheme');
      expect(validateFnthinkShortcutTarget('a\nb'), 'control-char');
    });

    test('名字校验：1–32 字、无控制字符', () {
      expect(validateFnthinkShortcutName('开门'), isNull);
      expect(validateFnthinkShortcutName(''), 'empty');
      expect(validateFnthinkShortcutName('x' * 33), 'too-long');
      expect(validateFnthinkShortcutName('a\nb'), 'control-char');
    });
  });

  group('读写往返', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('存了再读是同一张表（顺序也保持）', () async {
      await saveFnthinkShortcuts(const [
        FnthinkShortcut(name: '开门', target: 'home://gate/open'),
        FnthinkShortcut(name: '相机', target: 'com.android.camera/.Main'),
      ]);
      final rows = await loadFnthinkShortcuts();
      expect(rows.map((r) => r.name), ['开门', '相机']);
      expect(rows.first.target, 'home://gate/open');
    });

    test('坏行**跳过但表还在**（不是整表读不出来）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kFnthinkShortcutsKey:
            '[{"name":"好的","target":"a://b"},{"name":"","target":"a://b"},'
            '{"name":"缺目标"},{"name":"怪目标","target":"不是目标"}, 42]',
      });
      final rows = await loadFnthinkShortcuts();
      expect(rows.map((r) => r.name), ['好的']);
    });

    test('根本不是 JSON ⇒ 回空表（不抛）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kFnthinkShortcutsKey: 'not-json{',
      });
      expect(await loadFnthinkShortcuts(), isEmpty);
    });
  });

  test('按名字精确匹配、不猜', () {
    const rows = [
      FnthinkShortcut(name: '开门', target: 'home://gate'),
      FnthinkShortcut(name: '关门', target: 'home://gate/close'),
    ];
    expect(findFnthinkShortcut(rows, '开门')?.target, 'home://gate');
    expect(findFnthinkShortcut(rows, ' 开门 ')?.target, 'home://gate');
    expect(findFnthinkShortcut(rows, '开'), isNull);
    expect(findFnthinkShortcut(rows, '大门'), isNull);
  });
}
