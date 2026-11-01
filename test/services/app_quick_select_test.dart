import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/app_quick_select.dart';

/// T209：快速选择目录的唯一作者（分组、目录顺序、已安装命中）。
///
/// 这些判据原本藏在规则编辑页的私有常量里，另两页够不着；抽出来之后，任何"某一页有
/// 自己的一份目录"的写法都会先在这里红。
void main() {
  group('appQuickGroupOf / appQuickOrderOf', () {
    test('目录里的包各自归组；大小写不敏感', () {
      expect(appQuickGroupOf('com.tencent.mm'), AppQuickGroup.comm);
      expect(appQuickGroupOf('com.android.mms'), AppQuickGroup.sms);
      expect(appQuickGroupOf('com.android.dialer'), AppQuickGroup.phone);
      expect(appQuickGroupOf('com.google.android.gm'), AppQuickGroup.mail);
      // ROM 回传偶有大写（目录里就写着 com.Slack）
      expect(appQuickGroupOf('com.slack'), AppQuickGroup.comm);
      expect(appQuickGroupOf('COM.TENCENT.MM'), AppQuickGroup.comm);
    });

    test('目录外 ⇒ null（那一页把它当"其他应用"）', () {
      expect(appQuickGroupOf('com.alpha.app'), isNull);
      expect(appQuickOrderOf(AppQuickGroup.comm, 'com.alpha.app'), isNull);
    });

    test('MIUI 的拨号器 com.android.contacts 归「电话」组（2026-11-01 真机发现）', () {
      // 2410DPN6CC / Android 17 上原来「电话」组一枚都不画：MIUI 的拨号器与联系人共用
      // com.android.contacts，而目录里只有 AOSP/Google/三星那几枚。
      expect(appQuickGroupOf('com.android.contacts'), AppQuickGroup.phone);
      final groups = appQuickGroupsOfInstalled([
        'com.android.contacts',
        'com.android.mms',
        'com.tencent.mm',
        'com.google.android.gm',
      ]);
      expect(groups.keys.toList(), [
        AppQuickGroup.sms,
        AppQuickGroup.phone,
        AppQuickGroup.comm,
        AppQuickGroup.mail,
      ]);
    });

    test('组内序号就是目录顺序', () {
      expect(appQuickOrderOf(AppQuickGroup.comm, 'com.tencent.mm'), 0);
      expect(
        appQuickOrderOf(AppQuickGroup.comm, 'com.tencent.mobileqq'),
        lessThan(appQuickOrderOf(AppQuickGroup.comm, 'com.tencent.tim')!),
      );
      expect(appQuickOrderOf(AppQuickGroup.comm, 'COM.SLACK'), isNotNull);
    });

    test('同一包不许出现在两个组（否则分组会静默取后写入的那个）', () {
      final seen = <String, AppQuickGroup>{};
      for (final entry in appQuickPackages.entries) {
        for (final pkg in entry.value) {
          final lower = pkg.toLowerCase();
          expect(
            seen[lower],
            isNull,
            reason: '$pkg 同时出现在 ${seen[lower]} 与 ${entry.key}',
          );
          seen[lower] = entry.key;
        }
      }
    });
  });

  group('appQuickGroupsOfInstalled', () {
    test('只返回有命中的组，顺序跟着 appQuickGroups（不跟着输入顺序）', () {
      final groups = appQuickGroupsOfInstalled([
        'com.google.android.gm',
        'com.tencent.mm',
        'com.alpha.app',
      ]);
      expect(groups.keys.toList(), [AppQuickGroup.comm, AppQuickGroup.mail]);
      expect(groups[AppQuickGroup.comm], ['com.tencent.mm']);
    });

    test('值用设备上的原始包名（大小写不统一时不改写）', () {
      // 落进选中集的必须是页面拿到的那个串；统一降小写会加进一个页面里不存在的包名。
      final groups = appQuickGroupsOfInstalled(['com.Slack']);
      expect(groups[AppQuickGroup.comm], ['com.Slack']);
    });

    test('组内按目录顺序，不按安装顺序', () {
      final groups = appQuickGroupsOfInstalled([
        'com.tencent.tim',
        'com.tencent.mm',
        'com.tencent.mobileqq',
      ]);
      expect(groups[AppQuickGroup.comm], [
        'com.tencent.mm',
        'com.tencent.mobileqq',
        'com.tencent.tim',
      ]);
    });

    test('一个目录包都没装 ⇒ 空 Map（界面据此整条不画）', () {
      expect(appQuickGroupsOfInstalled(['com.alpha.app']), isEmpty);
    });
  });
}
