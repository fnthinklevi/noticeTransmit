import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T95 的**接线**守卫：更新流那两路探测的记账、幻念推送那一格的探测口，
/// 必须在装配点/替身默认值里真的接上。
///
/// 为什么单独一条：这几处漏接时**没有任何别的用例会红** ——
/// 更新照常、页面照常、徽标永远"没测过"。同一个形状在幻念那一格已经栽过一次
/// （`fnthink_receive_wiring_test.dart` 盯的就是它），所以这次不等真机发现。
///
/// ⚠ 断的是**契约**（谁写给谁、认哪个 family/开关名），不是行号；
///   抽取落空一律当场喊"没判到"，不许空跑变绿。
void main() {
  String src(String rel) {
    final f = File(rel);
    if (!f.existsSync()) throw StateError('读不到 $rel ⇒ 本文件一条都没判');
    return f.readAsStringSync();
  }

  /// 取 `name(` 起、到配对收尾的那一段（这里够用：注册块之间不嵌套同名）。
  String blockFrom(String hay, String anchor, String where) {
    final start = hay.indexOf(anchor);
    if (start < 0) {
      throw StateError('认不出「$where」的形状（锚点 `$anchor` 不在盘上）⇒ 本条没判');
    }
    final end = hay.indexOf('\n  );', start);
    if (end < 0) throw StateError('「$where」的块收不出边界 ⇒ 本条没判');
    return hay.substring(start, end);
  }

  test('更新检查那一发的健康度接进了单点（family 认的是档位表里那一枚）', () {
    final di = src('lib/di/service_locator.dart');
    final block = blockFrom(di, 'UpdateService(', 'UpdateService 的注册块');
    for (final needle in [
      'onProbe:',
      'ChannelHealthStore',
      'kUpdateHealthFamily',
    ]) {
      expect(
        block,
        contains(needle),
        reason:
            'UpdateService 没接 $needle ⇒ 检查更新那一发探出来的结论没人记账，'
            '「更新服务器」那一页的徽标永远"没测过"，而更新照常、没有一条用例会红',
      );
    }
    // 写源认的 family 必须与读源同一个常量（写死第二份字符串 = 两处各说各话）。
    expect(
      block,
      contains('probe.region.name'),
      reason: '健康度的 id 用的是档位名；换成别的（比如主机名）会让两档的记录对不上行',
    );
  });

  test('幻念推送「切换服务」那一格的探测与记账两个口都给了默认值', () {
    final page = src('lib/pages/fnthink_settings_page.dart');
    final block = blockFrom(
      page,
      'factory FnthinkSettingsDeps.fromLocator()',
      'FnthinkSettingsDeps.fromLocator',
    );
    expect(
      block,
      contains('probeHosts: measureEndpointLatency'),
      reason: '默认值没接 ⇒ 生产环境打开弹层不探，选项上那句"能不能用"永远是旧数据',
    );
    expect(
      block,
      contains('recordHealth:'),
      reason: '探完没人写 ⇒ 徽标与选项读的是同一份空，看着像"从没测过"，其实是被漏接',
    );
    // 读写两侧必须认同一个 family：折行/缩进怎么排都算（形状判据，不是字面抄本）。
    // ⚠ 这里是 **`kFnthinkServerFamily`**（服务器主语，id＝host），不是 `kFnthinkChannelSlug`
    //   （通道主语，id＝通道行 id）—— T104 片① 把两种主语拆开的正是这一对，串台时不报错，
    //   只是首页那条通道行会替一台服务器说话。
    final writes = RegExp(r'record\(\s*kFnthinkServerFamily,').hasMatch(block);
    final reads = page.contains('of(kFnthinkServerFamily, host)');
    expect(
      [writes, reads].where((x) => x).length,
      2,
      reason:
          '写源或读源丢了一边 ⇒ "写进 A、读的是 B"那种串台（本条实测：折行写法变了会只认到一边，'
          '所以判据按形状取，不抄源码里那一行的换行位置）',
    );
  });

  test('更新服务器那一页不自己判 reachable，交出现有的显示侧判定', () {
    // 判定只有 `channelHealthState` 一枚（T115 之后分两枚：调度侧那枚 + 显示侧那枚
    // `channelHealthStateForDisplay`）。这一页要的是**显示**那一条 —— 反向也成立：
    // 显示点去读调度那枚就绕过了"过期必须带时间"那条契约，见 channel_single_points_test。
    final page = src('lib/pages/fnthink_settings_page.dart');
    expect(
      page,
      contains('channelHealthStateForDisplay(health)'),
      reason: '选项上那句"能不能用"没走显示侧单点 ⇒ 会与徽标/首页各说一套（T01 那次）',
    );
  });
}
