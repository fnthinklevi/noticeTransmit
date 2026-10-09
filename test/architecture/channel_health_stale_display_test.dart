import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T115 决定一与决定二的守卫：**过期结论必须与它的时间同屏**，两条护栏必须各在自己的位置。
///
/// 为什么这一族值得单独一个文件：这次改的是一条**被推翻的禁令**（`active_channels.dart`
/// 原来写"没有新鲜的探测结果既不能说正常也不能说异常"）。旧口径的牙全在"过期 ⇒ unknown"
/// 这一条上；新口径把牙挪到"过期 ⇒ 必须带时间"上。如果只改实现不留新闸，
/// 下一个人把首页那行的时间删掉，得到的是一句**没有时间的"正常"** ——
/// 那既不是旧口径也不是新口径，而是两句禁令都反对的那种谎，而全场测试仍绿。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  group('过期结论与它的时间必须同屏（T115 决定一）', () {
    test('「多久以前」这句话只有一个作者', () {
      // 口径：`lib/` 里读这几句 l10n 词条的地方必须只有那一个文件。
      // ⚠ 提取式守卫先确认自己认得合成样本（本仓两次栽在"尺收窄 ⇒ 差集恒空 ⇒ 恒绿"）。
      // T110 把这一族从一句扩成两句（健康度那句是"探测"，配对那面是"发起/结论"），
      // 但**分档只有一处**：`fnthinkAgoBucket`。所以这里扫的是"谁在格式化这几句"，
      // 允许它们在同一个文件里，绝不允许第二个文件自己算分钟/小时。
      final hits = <String>[];
      for (final f in Directory(
        '$root/lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path
            .replaceAll(r'\', '/')
            .substring(root.replaceAll(r'\', '/').length + 1);
        if (rel.contains('/l10n/')) continue; // 生成物与词条表不是"作者"
        final src = read(rel);
        if (src.contains('healthProbedMinutes(') ||
            src.contains('healthProbedHours(') ||
            src.contains('agoMinutes(') ||
            src.contains('agoHours(')) {
          hits.add(rel);
        }
      }
      expect(
        hits,
        equals(['lib/widgets/channel_health_badge.dart']),
        reason:
            '这两句的格式化出现了第二个作者：$hits ⇒ 同一条记录会一处说"3 天前"、'
            '一处说"72 小时前"（而徽标那份抄本今天就错过 60 倍，见 badge 那条用例）',
      );
      final badge = read('lib/widgets/channel_health_badge.dart');
      expect(
        badge,
        contains('ago ~/ (60 * 60 * 1000)'),
        reason:
            '小时那一句的除数必须是 60*60*1000 —— 徽标旧抄本写的是 ~/ (60 * 1000)。'
            '它现在住在 `fnthinkAgoBucket` 里（两句共用的那把尺），不在调用点上',
      );
      expect(
        badge,
        contains('inHours'),
        reason: '分档只许有一处判：两句都从同一个 bucket 取分钟还是小时',
      );
    });

    test('首页那张卡的状态载荷带得出时间，且拿不出时间就退回未知', () {
      final actions = librarySource(root, 'lib/pages/main_page.dart');
      final builder = blockAfter(
        actions,
        'List<Map<String, String>> _getActiveChannels()',
      );
      expect(
        builder,
        contains("'probedAt'"),
        reason: '页面没有 probedAt 就画不出"上次探测于 X 前"，这一档只能整块退回未知',
      );

      final card = read('lib/pages/notification_page.dart');
      final rows = blockAfter(card, 'if (activeChannels.isNotEmpty)');
      expect(
        rows,
        contains("channelHealthAgoLabel("),
        reason: '过期那一档在首页必须同屏带出时间（决定一）',
      );
      expect(
        rows,
        contains("rawStatus == 'stale' && ageText != null"),
        reason:
            '时间拿不出来时不许照画"正常" —— 这一句是那条禁令换了个方向后的新牙：'
            '旧写法是"过期一律画未知"，新写法是"过期且说不出时间才画未知"',
      );
    });

    test('通道状态页与邮件列表也各自把时间带在同一行', () {
      final status = read('lib/pages/channel_status_page.dart');
      final row = blockAfter(status, 'Widget _row(');
      expect(
        row,
        contains('_probeAge(l10n, channel.health)'),
        reason: '这一页说"正常"的那一行必须同屏挂着"上次探测于 X 前"',
      );
      expect(
        blockAfter(status, 'String _probeAge('),
        contains('channelHealthAgoLabel('),
        reason: '时间那句话走唯一作者，不许在这一页再抄一份分支',
      );

      final email = read('lib/pages/email_settings_page.dart');
      final label = blockAfter(email, 'String? _lastTestLabel(');
      expect(
        label,
        contains('_withProbeAge('),
        reason: '邮件列表那一行画"验证通过"时必须带着它的时间（旧写法是干脆不画）',
      );
    });

    test('四态枚举只有一处定义，且 statusLabel 把 stale 说成一个独立的值', () {
      final src = read('lib/services/active_channels.dart');
      expect(
        RegExp(r'enum ChannelHealthState').allMatches(src).length,
        1,
        reason: '第二份枚举 = 两处各判各的（本仓"一个命名空间两种主语"那一族的同类）',
      );
      expect(
        src,
        contains("ChannelHealthState.stale => 'stale'"),
        reason: '状态标签里没有 stale ⇒ 页面只能把它折进 unknown 或 ok，两者都是假话',
      );
    });
  });

  group('决定二的两条护栏（T115）', () {
    test('一轮内同一通道只测一次：幻念那一族有自己那份在飞保护', () {
      // 原生三族靠 `ChannelProbeService._running`，幻念走自己那条路 ⇒ 那把锁管不到它。
      final src = read('lib/services/fnthink_channel_probe.dart');
      expect(
        src,
        contains('_probing.add(channel.id)'),
        reason: '并发两轮叠发同一条通道的签名探针 = 这一族的"只测一次"没落地',
      );
      expect(
        src,
        contains('_probing.remove(channel.id)'),
        reason: '只加不减 = 一次异常之后这条通道永远探不了（比叠发更坏）',
      );
    });

    test('认证失败进冷却，且只挡自动那一路', () {
      final src = read('lib/services/channel_probe_service.dart');
      // ⚠ 不能用 blockAfter：签名之后**先**遇到的是具名参数列表的花括号
      //   （`{ required bool force, ... }`），取到的"块"只到参数表为止 ⇒ 要量的那句
      //   根本不在尺里 —— 这是"尺比被量的东西窄"那一类，它永远不会红。
      final probe = src.substring(src.indexOf('Future<int> _probe('));
      expect(
        probe,
        contains('isInAuthCooldown(family, t.id)'),
        reason: '认证失败没有冷却 = 授权码错着时被频繁前后台撞到厂商临时封禁',
      );
      expect(
        probe,
        contains('authFailure'),
        reason: '触发条件必须是原生明说的那一格，不是"任何一次不可达"',
      );
      // 冷却只在 `force ||` 的那个括号里生效（force 那一发 = 下拉刷新不受它挡）。
      // ⚠ 这里只断**先后**，不断相邻：折行与注释会让"距离型正则"今天绿明天红（本仓记过的
      //   "断形状"那一类）。真正的牙在那两条行为用例里（认证失败后 force 仍发、stale 不发），
      //   这条守卫只拦"把冷却挪到 force 外面去"这一种改法。
      final forceAt = probe.indexOf('force ||');
      final cooldownAt = probe.indexOf('isInAuthCooldown');
      expect(
        forceAt >= 0 && cooldownAt > forceAt,
        isTrue,
        reason:
            '冷却没排在 `force ||` 之后 ⇒ 它挡的是显式下拉那一发，'
            '用户的手势变成"点了没反应"（本仓反复修过的那类缺陷）',
      );
    });

    test('认证分类住在原生那一侧（Dart 不许匹配那句中文措辞）', () {
      final kotlin = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/EmailSender.kt',
        ).readAsStringSync(),
      );
      expect(
        RegExp(r'fun isAuthFailure\(').allMatches(kotlin).length,
        1,
        reason: '判据要有作者：两处各判各的 ⇒ 一处改了另一处静默失效',
      );
      final dartSide = read('lib/services/channel_probe_service.dart');
      for (final wording in const ['认证失败', '授权码', '握手']) {
        expect(
          dartSide,
          isNot(contains("'$wording")),
          reason: 'Dart 侧开始匹配原生那句中文 ⇒ 原生改文案就静默失效（第二份口径）',
        );
      }
    });
  });
}
