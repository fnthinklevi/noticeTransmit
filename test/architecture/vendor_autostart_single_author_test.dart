import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T140 (b) ② 的守卫：厂商分流表**只许一个作者**。
///
/// 钉的是形状而不是行号：㊀ 厂商词面（`'xiaomi'` 这种带引号的串）除作者文件外全仓零落笔；
/// ㊁ 那张表自己不能被删空或搬走（14 枚词一枚都不能少）；㊂ 三个使用点必须现取作者。
/// 砸过脚的三份表：L3 派发只认五个裸名、权限页认全套变体、小组件引导页认全套变体但少了魅族
/// —— 于是同一台荣耀上"磁贴能跳、远端那一发什么都不做"，而这一族没有公开读数，
/// 用户唯一的线索是"点了没反应"。
String read(String path) => File(path).readAsStringSync();

String strip(String code) => code
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

const authorFile = 'lib/services/vendor_family.dart';

/// 表里那 14 枚词。**`'android'` 不在禁抄名单里**：`update_manager.dart` 那句
/// `'platform': 'android'` 是更新接口的平台字段、与厂商分流无关，把它算进来就是假红。
const tableWords = [
  'xiaomi',
  'redmi',
  'mi ',
  'meizu',
  'huawei',
  'honor',
  'oppo',
  'realme',
  'oneplus',
  'vivo',
  'iqoo',
  'samsung',
  'google',
  'android',
];

/// 只许出现在作者文件里的那 13 枚（去掉那个有合法他处命中的通用词）。
final ownedWords = tableWords.take(13).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  final source = {
    for (final f in files) f.path.replaceAll(r'\', '/'): strip(read(f.path)),
  };

  test('反向自检：这把尺扫到的是整棵 lib，且作者文件真的在扫描面上', () {
    expect(files.length, greaterThan(100), reason: '只扫到几十份 = 路径写错，本守卫对谁都不成立');
    expect(source.containsKey(authorFile), isTrue, reason: '锚点：作者文件不在 = 本守卫空转');
    // 正面对照：这些词在作者文件里**必须**扫得到，否则"零落笔"是因为尺看不见东西
    for (final word in tableWords) {
      expect(
        source[authorFile],
        contains("'$word'"),
        reason: '$word 不在表里 = 这张表已被删空',
      );
    }
  });

  test('厂商词面除作者文件外零落笔（第二张表长不回来）', () {
    for (final word in ownedWords) {
      final hits = [
        for (final entry in source.entries)
          if (entry.key != authorFile && entry.value.contains("'$word'"))
            entry.key,
      ];
      expect(hits, isEmpty, reason: "'$word' 被抄进了 $hits —— 两份厂商分流表＝某一台只在一处被引导");
    }
  });

  test('三个使用点都现取作者，派发也只有一处', () {
    expect(
      source['lib/di/service_locator.dart'],
      contains('fnthinkRequestVendorAutoStart('),
      reason: 'L3 的 autostart 那一发必须走唯一派发，不许在装配里再 if 一遍厂商名',
    );
    for (final page in [
      'lib/pages/permission_settings_page.dart',
      'lib/pages/widget_guide_page.dart',
    ]) {
      expect(
        source[page],
        contains('fnthinkVendorFamilyOf('),
        reason: '$page 不再现取这张表 = 它退回自己那份词表了',
      );
    }
    // 判定函数的落笔处只许是"作者 + 那两个使用者"，多一处就是第四张表在长
    final users = [
      for (final entry in source.entries)
        if (entry.value.contains('fnthinkVendorFamilyOf(')) entry.key,
    ]..sort();
    expect(users, [
      'lib/pages/permission_settings_page.dart',
      'lib/pages/widget_guide_page.dart',
      authorFile,
    ]);
  });
}
