import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T62 片2 的形状守卫：更新流「安装被阻止」这句话，**服务层出码、界面出词**。
///
/// 钉的是四件事（都是"第二份规则"的形状，编译器管不到、只有这类守卫管得到）：
///  ① 服务层不再自己判断语言（`_isEnglish` 那套三元是 ARB 之外的第二份本地化机制）；
///  ② 服务层的代码里不再住中文句子（会显示给人的那批）；
///  ③ 界面那一处 `switch` 覆盖枚举的**全部**档，且**每一档映射到对的那个词条**
///     （少一档编译就红 —— 但"接错线"编译器看不出来，所以这里断具体对应关系）；
///  ④ 那三枚 ARB 词条在中英两份里都在（缺一份就是英文界面回落到中文，或反之）。
void main() {
  final manager = File('lib/update_manager.dart').readAsStringSync();
  final page = File('lib/pages/main_page_update.dart').readAsStringSync();

  String stripComments(String src) =>
      src.split('\n').map((l) => l.split('//').first).join('\n');

  /// 枚举 `UpdateInstallBlockReason` 的全部档（从源码现取，不在测试里抄第二份名单）。
  List<String> enumValues() {
    final m = RegExp(
      r'enum\s+UpdateInstallBlockReason\s*\{([^}]*)\}',
    ).firstMatch(manager);
    expect(m, isNotNull, reason: '枚举没了？那 ③④ 两断言都在测空气');
    return m!
        .group(1)!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 界面 `switch` 里的 `码 => _l10n.词条` 对应关系。
  Map<String, String> mappingInPage() {
    final body = page.substring(page.indexOf('String _installBlockText('));
    final pairs = RegExp(
      r'UpdateInstallBlockReason\.(\w+)\s*=>\s*_l10n\.(\w+)',
    ).allMatches(body);
    return {for (final p in pairs) p.group(1)!: p.group(2)!};
  }

  test('① 服务层不再自己判断语言（本地化只有 ARB 一份）', () {
    expect(
      stripComments(manager).contains('_isEnglish'),
      isFalse,
      reason: '又长出第二份本地化机制了：新文案会继续往那套三元上长，而不是进 ARB',
    );
    expect(
      stripComments(manager).contains('LocaleService'),
      isFalse,
      reason: '服务层读语言只为拼一句文案 ⇒ 那一句话该由界面出',
    );
  });

  test('② 服务层代码里不再有"已阻止安装"这类会显示给人的中文句子', () {
    expect(
      stripComments(manager).contains('已阻止安装'),
      isFalse,
      reason: '这三句已进 ARB；再出现就是有人把措辞抄回了服务层',
    );
  });

  test('③ 界面把每一码都接到对的那个词条上（两边差集都空 + 对应关系逐个断）', () {
    final codes = enumValues();
    final mapping = mappingInPage();
    expect(
      mapping.keys.toSet().difference(codes.toSet()),
      isEmpty,
      reason: '界面接了一个枚举里没有的码',
    );
    expect(
      codes.toSet().difference(mapping.keys.toSet()),
      isEmpty,
      reason: '枚举加了一档而界面没接：那一档会走到 default 或编译错，两种都不该悄悄过',
    );
    expect(mapping, {
      'integrityFailed': 'updateBlockIntegrityFailed',
      'checksumMismatch': 'updateBlockChecksumMismatch',
      'unverifiable': 'updateBlockUnverifiable',
    });
  });

  test('④ 三枚词条在中英两份 ARB 里都在且非空', () {
    Map<String, dynamic> arb(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final zh = arb('lib/l10n/arb/app_zh.arb');
    final en = arb('lib/l10n/arb/app_en.arb');
    for (final key in mappingInPage().values) {
      expect(zh[key], isA<String>(), reason: '$key 缺中文那份');
      expect((zh[key] as String).trim(), isNotEmpty);
      expect(en[key], isA<String>(), reason: '$key 缺英文那份');
      expect((en[key] as String).trim(), isNotEmpty);
      expect(zh[key], isNot(en[key]), reason: '$key 两份一模一样 ⇒ 有一份是占位');
    }
    expect(enumValues(), isNotEmpty);
  });
}
