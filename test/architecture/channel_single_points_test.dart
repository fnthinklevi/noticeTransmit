import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 「一件事只有一处实现」的第 6 步守卫。
///
/// 本仓库反复出现同一类故障：同一个事实被抄成几份，抄漏的那份不会报错，
/// 只是某些通道永远行为不同。第 6 步收口的三件事各留一条守卫：
/// 1. 通道 URL 合法性规则（原生两处 + Dart 一处必须同一口径）；
/// 2. 健康度缓存的读写（只有 `ChannelHealthStore` 碰 prefs）；
/// 3. `'null'` 脏数据清洗（只有 `ChannelConfigCodec` 做）。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  group('URL 规则跨端同一口径', () {
    // 锚点一律写成 `fun 名字(`：带 `fun ` 就不会命中调用点，而不抄参数表/返回类型 ——
    // 那些细节一改，blockAfter 抛的 StateError 会让整条守卫变红却跟"口径"无关（base.md（75））。
    test('原生两处仍是 http+https，Dart 规则字面一致', () {
      final base = blockAfter(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/AppChannelTokenManager.kt',
        ),
        'fun normalizeBase(',
      );
      final probe = blockAfter(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/ChannelHealthProbe.kt',
        ),
        'fun isProbeableUrl(',
      );
      for (final (where, block) in [
        ('normalizeBase', base),
        ('isProbeableUrl', probe),
      ]) {
        expect(
          block,
          allOf(
            contains('startsWith("https://")'),
            contains('startsWith("http://")'),
          ),
          reason:
              '原生 $where 的 scheme 口径变了：Dart 侧 `ChannelUrlPolicy` 必须同步，'
              '否则备份/保存与推送判定用的是两套规则',
        );
      }

      final policy = read('lib/services/channel_url_policy.dart');
      expect(
        policy,
        allOf(contains("'https://'"), contains("'http://'")),
        reason: 'Dart 侧规则必须同时接受 http 与 https（自建 ntfy/Gotify 常在局域网 http）',
      );
    });

    test('备份与设置页复用规则，不再自己判 scheme', () {
      for (final rel in [
        'lib/services/backup_service.dart',
        'lib/pages/webhook_settings_page.dart',
      ]) {
        final src = read(rel);
        expect(
          src,
          contains('ChannelUrlPolicy.isHttpUrl'),
          reason: '$rel 又绕开单点自己判 URL 了',
        );
        expect(
          src,
          isNot(contains("scheme == 'https'")),
          reason: '$rel 里残留「只认 https」的旧规则 —— 它会在恢复备份时静默丢掉自建 http 通道',
        );
      }
    });
  });

  group('健康度只有一个生产者', () {
    test('页面不再直接读写 channel_health_ / email_test_results', () {
      final offenders = <String>[];
      final dir = Directory('$root/lib/pages');
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'lib/pages 不在了：目录型守卫会"扫不到文件 ⇒ 没有违规"，绿得毫无意义',
      );
      var scanned = 0;
      for (final file in dir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        scanned++;
        final src = stripComments(file.readAsStringSync());
        // 认「字符串字面量」而不是裸前缀：`import '../services/channel_health_store.dart'`
        // 也含 channel_health_，那样每条 import 都会变成假阳性
        for (final marker in ["'channel_health_", "'email_test_results"]) {
          if (src.contains(marker)) {
            offenders.add('${file.uri.pathSegments.last} 含 $marker');
          }
        }
      }
      // 正面锚点：扫到的文件数要跟得上页面规模（口径变了 / 目录搬走时这条会红，
      // 而不是悄悄变成"零个文件、零条违规"）。
      expect(
        scanned,
        greaterThanOrEqualTo(25),
        reason: '只扫到 $scanned 个页面文件（当前约 30）⇒ 页面目录口径变了，本条已在空跑',
      );
      expect(
        offenders,
        isEmpty,
        reason:
            '健康度缓存的键格式与时效只在 ChannelHealthStore 一处定义；'
            '页面自己拼键就会再次分裂成三族不同行为：$offenders',
      );
    });

    test('只有 store 碰健康键，email 服务也不再自存一份', () {
      final store = read('lib/services/channel_health_store.dart');
      expect(store, contains('channel_health_'));
      expect(store, contains('email_test_results'));

      final email = read('lib/services/email_service.dart');
      expect(email, isNot(contains('email_test_results')));
      expect(email, contains('ChannelHealthStore'), reason: '邮件测试结果必须落健康单点');
    });
  });

  group("'null\" 脏数据清洗只有一处", () {
    test('除 codec 外，服务层不再自己比较 == "null"', () {
      final offenders = <String>[];
      for (final rel in [
        'lib/services/webhook_service.dart',
        'lib/services/app_channel_service.dart',
        'lib/services/email_service.dart',
        'lib/database/database_helper.dart',
      ]) {
        final src = read(rel);
        if (src.contains("== 'null'") || src.contains('== "null"')) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '清洗逻辑散回各处 = 迟早有一处漏洗（漏洗的字段看起来有值、原生读到 "null"）；'
            '统一走 ChannelConfigCodec.nullableText：$offenders',
      );
      expect(
        read('lib/services/channel_config_codec.dart'),
        contains("'null'"),
        reason: '清洗必须确实存在于单点里',
      );
    });
  });

  // T04：三族通道的"测一下"与"什么状态"必须各只有一个来源。
  // 抄本的代价本项目已经付过多次：徽标抄成两份 ⇒ 一份看时效、一份不看，
  // 设置页画绿勾、首页说未知；测试入口只长在 app 页 ⇒ 另两族只能靠保存触发。
  group('通道测试入口与健康徽标各只有一处（T04）', () {
    const pages = [
      'lib/pages/app_channel_settings_page.dart',
      'lib/pages/webhook_settings_page.dart',
      'lib/pages/email_settings_page.dart',
    ];

    test('三族设置页都得有「仅测试」入口', () {
      for (final rel in pages) {
        expect(
          read(rel),
          contains('l10n.testOnly'),
          reason: '$rel 没有「仅测试」⇒ 想验一次配置就只能把半成品保存进去',
        );
      }
      final arb = stripComments(
        File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync(),
      );
      expect(arb, contains('"testOnly"'), reason: '三处共用同一个资源名，别再各自写一份字面量');
    });

    test('健康状态只有 ChannelHealthBadge / channelHealthState 这一条判定', () {
      // T115 决定一之后这条判定分成两枚：调度侧读 `channelHealthState`（过没过时效），
      // 显示侧读 `channelHealthStateForDisplay`（过期那档拿不出时间就退回未知）。
      // 单点还是单点 —— 但"显示点不许读调度那一枚"必须一起钉住，否则四处又会各自
      // 决定"过期要不要说正常"，那正是这次改的东西。
      final badge = read('lib/widgets/channel_health_badge.dart');
      expect(
        badge,
        contains('channelHealthStateForDisplay('),
        reason: '徽标自己判态 = 又开一份真值（T04），绕过显示契约 = 能画出没带时间的"正常"',
      );
      // 注意 webhook：它的卡片构建在 part 文件 `webhook_settings_item.dart` 里，
      // 所以列的是"真正渲染健康的地方"，不是页面的库文件。
      for (final rel in [
        'lib/pages/app_channel_settings_page.dart',
        'lib/pages/email_settings_page.dart',
        'lib/pages/webhook_settings_item.dart',
      ]) {
        expect(
          read(rel),
          anyOf(
            contains('ChannelHealthBadge'),
            contains('channelHealthStateForDisplay('),
            contains('.healthState'),
          ),
          reason: '$rel 显示通道健康却没走单点',
        );
      }
      // 抄本的特征就是这个三元：只看 reachable、不看探测时效
      final offenders = <String>[
        for (final rel in [
          ...pages,
          'lib/pages/webhook_settings_item.dart',
          'lib/pages/channel_status_page.dart',
          'lib/pages/main_page.dart',
        ])
          if (read(rel).contains('reachable ?')) rel,
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            '直接对 reachable 做三元判断会漏掉"成功但已过期"，'
            '首页说未知、设置页画绿勾：$offenders',
      );
    });
  });

  // ── T113（维护者 2026-10-08 第 7 条：首页那个主备通道设置里不显示幻念推送通道）─────
  // 病灶不是"少了个 if"，是**同一件事在三处各数一遍**：页面分组顺序、主备弹层要列的族、
  // `updateChannelRole` 的 switch。弹层那一处少数了一族，表现就是"能配能显示、快捷入口里没有它"；
  // 而反过来"列表里有这行、写路径却掉进 `default: return false`"会说成「这条通道已经不在了」——
  // 那句话说的是没找到，不是没人会写。所以这里钉的是**集合只能有一份作者**，不是钉行数。
  group('主备这一档的族集合只有一份作者（T113）', () {
    test('清单、弹层遍历、写路径 switch 三处指向同一份', () {
      final codec = read('lib/services/active_channels.dart');
      final page = read('lib/pages/channel_status_page.dart');

      final declared = RegExp(
        r"const List<String> channelFamilies = \[([^\]]*)\];",
      ).firstMatch(codec);
      expect(declared, isNotNull, reason: '那份清单不在了 ⇒ 作者换了地方，先看清再谈覆盖');
      final families = RegExp(
        r"'([a-z]+)'",
      ).allMatches(declared!.group(1)!).map((m) => m.group(1)!).toSet();
      expect(
        families,
        containsAll(<String>['webhook', 'email', 'app', 'fnthink']),
        reason: '主备这一档少了哪一族，首页那个弹层就列不出哪一族',
      );

      // ① 写路径：switch 的 case 标签集合必须与清单**相等**（少一个 = 点了没人写）
      final start = codec.indexOf('Future<bool> updateChannelRole(');
      final stop = codec.indexOf('Future<bool> updateChannelEnabled(');
      expect(start, greaterThanOrEqualTo(0));
      expect(stop, greaterThan(start), reason: '两条写口的先后顺序变了 ⇒ 这段提取尺量错了对象');
      final cases = RegExp(r"case '([a-z]+)':")
          .allMatches(codec.substring(start, stop))
          .map((m) => m.group(1)!)
          .toSet();
      expect(cases, families, reason: '写路径能改的族与那份清单不一致：$cases vs $families');

      // ② 弹层：遍历的就是这一份，且页面里不再留着手写的那三族
      expect(
        page.contains('for (final family in channelFamilies)'),
        isTrue,
        reason: '主备弹层不再遍历那份清单 ⇒ 它开始自己数族了',
      );
      expect(
        page.contains("['webhook', 'email', 'app']"),
        isFalse,
        reason: '页面里还留着一份三族的手写清单 ⇒ 改名/加族时又会漏一处',
      );

      // ③ 显示分组顺序也读同一份（它以前是页面里的第二份清单）
      expect(
        page.contains('List<String> get _familyOrder => channelFamilies;'),
        isTrue,
        reason: '页面自己又数了一遍族 ⇒ 两处会开始不一致',
      );

      // 尺自证：提取到的必须真是四族，不是把空集合比空集合
      expect(families.length, 4, reason: '提取到的族数不是 4 ⇒ 尺比被量的东西窄');
    });

    test('族显示名那张表与这份清单同集合（不然第五族会画成英文 token）', () {
      final codec = read('lib/services/active_channels.dart');
      final display = read('lib/services/channel_display.dart');
      final declared = RegExp(
        r"const List<String> channelFamilies = \[([^\]]*)\];",
      ).firstMatch(codec)!;
      final families = RegExp(
        r"'([a-z]+)'",
      ).allMatches(declared.group(1)!).map((m) => m.group(1)!).toSet();
      final block = display.substring(
        display.indexOf('const Map<String, (String, String)> _familyNames = {'),
      );
      final named = RegExp(
        r"^\s*'([a-z]+)': \(",
        multiLine: true,
      ).allMatches(block).map((m) => m.group(1)!).toSet();
      expect(
        named.intersection(families),
        families,
        reason:
            '有一族进了清单却没进显示名表：$families 里缺的是 ${families.difference(named)} '
            '—— `channelFamilyName` 会原样返回英文 token 而不是猜一个',
      );
    });
  });

  // ── T103（维护者 2026-10-08 两条追问：「更多页那一行为什么不是已配置 X 个 ·
  //    启用 X 个」「幻念推送通道列表为什么没有通道健康度！」）─────────────────
  // 第一条的根因是这一组四行**从来没有过一个共享口径**：webhook 与自建应用各抄了一份
  // 逐字相同的词条，邮件与幻念两行干脆画静态描述。第二条的根因是徽标对"没有记录"的
  // 缺省是不吭声 —— 那对能自动探测的三族是对的，对没有探针的这一族就成了"看着没有"。
  group('推送通道那一组入口行的摘要与健康度缺省态（T103）', () {
    test('更多页那四行都走同一个 `channelFamilySummary`，页面不留第二份', () {
      final page = read('lib/pages/more_page.dart');
      // ⚠ 第一版这条只数 `channelFamilySummary(` 出现四次 —— 反证 G2 当场证伪：
      //   把幻念那一行的 `subtitle:` 换回静态描述，赋值那一侧还在，四次调用照旧凑齐 ⇒ 假绿。
      //   现在按**行**钉：每一行都得"从公共件取"，而且"画出去的就是那一句"。
      for (final row in const ['webhook', 'email', 'app', 'fnthink']) {
        expect(
          page.contains('final ${row}Summary = channelFamilySummary('),
          isTrue,
          reason: '$row 那一行的读数不是从公共件来的 ⇒ 又开一份口径',
        );
        expect(
          page.contains('subtitle: ${row}Summary,'),
          isTrue,
          reason: '$row 那一行画出去的不是这一句摘要 ⇒ 四行又各自一种读法（维护者点名的就是这个）',
        );
      }
      expect(
        page.contains('_channelSummary'),
        isFalse,
        reason: '页面里再留一枚私有副本 ⇒ 两份又会各自长',
      );
      expect(
        read(
          'lib/widgets/channel_visuals.dart',
        ).contains('String channelFamilySummary('),
        isTrue,
        reason: '装配点必须在公共件那一处',
      );
    });

    test('那两份逐字相同的重复词条不许回字典', () {
      for (final p in const [
        'lib/l10n/arb/app_zh.arb',
        'lib/l10n/arb/app_en.arb',
      ]) {
        final arb = read(p);
        for (final old in const [
          'webhookConfigured',
          'webhookNotConfigured',
          'appChannelConfigured',
          'appChannelNotConfigured',
          'emailChannelDesc',
        ]) {
          expect(
            arb.contains('"$old"'),
            isFalse,
            reason:
                '$old 已被 channelConfigured/channelNotConfigured 取代；'
                '留着就是"改文案的人只改到自己搜到的那一个"那颗暗雷',
          );
        }
        expect(arb.contains('"channelConfigured"'), isTrue);
        expect(arb.contains('"channelNotConfigured"'), isTrue);
      }
    });

    test('幻念那两页必须说出「从未探测」，能自动探测的三族保持不吭声', () {
      for (final p in const [
        'lib/pages/fnthink_channel_list_page.dart',
        'lib/pages/fnthink_channel_settings_page.dart',
      ]) {
        expect(
          read(p).contains('absentText:'),
          isTrue,
          reason:
              '$p：这一族没有非侵入探针，空着读起来像"这一族没有健康度"，'
              '而真话是"还没测过 —— 进详情点那一枚"',
        );
      }
      for (final p in const [
        'lib/pages/webhook_settings_item.dart',
        'lib/pages/app_channel_settings_page.dart',
        'lib/pages/email_settings_page.dart',
        'lib/pages/main_page.dart',
        'lib/pages/channel_status_page.dart',
      ]) {
        expect(
          read(p).contains('absentText:'),
          isFalse,
          reason:
              '$p 那一族过一轮非侵入探测就有数，没记录只是"还没来得及"——'
              '立个牌子反而替用户说了他没做过的事',
        );
      }
    });
  });
}
