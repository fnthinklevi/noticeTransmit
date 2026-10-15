import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';

import '../support/source_guards.dart';

/// T150 片A：两枚**列表行**公共件（组件 A `FnthinkPeerRow` · 组件 B `FnthinkHistoryRow`）。
///
/// 维护者 2026-10-15 的方案说得很直：幻念那几张页"纯文字感"的两个来源是
/// ①「一句话说明」被当列表行用（一行里挤着是谁、什么档、结论、时刻），
/// ②一行里三个文字按钮。这一片只造件、不改页 —— 页面在片 B/C/D 逐张换，
/// 所以**这一片没有调用点**，闸门与页面级用例都看不见它。能被这一片钉住的只有形状本身，
/// 于是这里的 8 条用例就是"换件之前形状先长对"的那道证据。
///
/// ## 各条钉的是哪一件事
/// - 行高（48／44）钉的是「同页对齐」：卡片里连着几行如果高度随内容走，扫读就散了。
/// - key 的**宿主**钉的是断言能不能落地：`tester.widget<Text>(find.byKey(...))` 只对 Text 成立。
/// - 颜色那两条钉的是"件不改写调用点给的语义"，以及"四档结论不重色"。
/// - 不可点那两条钉的是本片最容易做错的一处：搬掉行内按钮之后，
///   **行本身点不动 ≠ 行尾那颗也不能点**（`IgnorePointer` 会把两者一起废掉，故这里不用它）。
void main() {
  Future<void> pump(WidgetTester tester, Widget row) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(child: Column(children: [row])),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('组件 A · FnthinkPeerRow', () {
    testWidgets('渲染：图标块 · 主副文案 · 状态件 · 行尾件各在自己的位，行高 48', (tester) async {
      await pump(
        tester,
        FnthinkPeerRow(
          keyName: 'peer-A',
          icon: Icons.phone_android,
          iconColor: AppColors.blue,
          title: 'AAAAAAAAAAAAAAAAAAAA（NAS）',
          subtitle: '2026-10-15 09:12',
          statusMark: const FnthinkStatusMark(
            role: FnthinkMarkRole.tier,
            label: 'L2',
            color: AppColors.green,
          ),
          trailing: const Icon(Icons.more_horiz, size: 18),
          onTap: () {},
        ),
      );

      expect(find.byIcon(Icons.phone_android), findsOneWidget);
      expect(find.text('AAAAAAAAAAAAAAAAAAAA（NAS）'), findsOneWidget);
      expect(find.text('2026-10-15 09:12'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('peer-A')),
        findsOneWidget,
        reason: '主文案那一格必须能被 key 找到（换件时逐字搬过去的那一枚）',
      );
      expect(find.text('L2'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      // 给了行尾件就不再画 chevron：一行里"能点的那一枚"与"只是状态的标记"不许挤成两个入口。
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('peer-A-row'))).height,
        48,
        reason: '行高是钉死的，不随主副文案长短走（同页对齐判的就是这一位）',
      );
      expect(
        tester.getSize(find.byIcon(Icons.phone_android).first),
        const Size(30, 30),
        reason:
            '那一块 30×30（`Container` 给子件的是紧约束，所以按 Icon 量到的就是块的尺寸）—— '
            '与 FnthinkEntryRow 同一枚块，两块分叉就是"两种行"',
      );
    });

    testWidgets('onTap 给了且不传 trailing ⇒ 右端画 chevron（它就是"这一行进得去"的读数）', (
      tester,
    ) async {
      await pump(
        tester,
        FnthinkPeerRow(
          keyName: 'peer-B',
          icon: Icons.phone_android,
          iconColor: AppColors.blue,
          title: 'BBBBBBBBBBBBBBBBBBBB',
          onTap: () {},
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('BBBBBBBBBBBBBBBBBBBB'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('peer-B-row'))).height,
        48,
        reason: '没有副文案的行也是 48：同一张卡里两行必须等高',
      );
    });

    testWidgets('各状态色：调用点给的图标色与状态件色原样在场，件不改写', (tester) async {
      await pump(
        tester,
        FnthinkPeerRow(
          keyName: 'peer-C',
          icon: Icons.phone_android,
          iconColor: AppColors.orange,
          title: 'CCCCCCCCCCCCCCCCCCCC',
          statusMark: const FnthinkStatusMark(
            role: FnthinkMarkRole.attribute,
            label: '已吊销',
            color: AppColors.red,
          ),
          onTap: () {},
        ),
      );

      final block = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('peer-C-row')),
              matching: find.byType(Container),
            )
            .first,
      );
      final deco = block.decoration! as BoxDecoration;
      expect(
        deco.color,
        AppColors.orange,
        reason: '左端那一块的上色是调用点的语义（哪一族设备），件不许替它挑色',
      );
      expect(
        tester
            .widget<FnthinkStatusMark>(
              find.descendant(
                of: find.byKey(const ValueKey('peer-C-row')),
                matching: find.byType(FnthinkStatusMark),
              ),
            )
            .color,
        AppColors.red,
      );
    });

    testWidgets('key 在场：主副文案的宿主都是 Text，派生 key 齐', (tester) async {
      await pump(
        tester,
        FnthinkPeerRow(
          keyName: 'peer-D',
          icon: Icons.phone_android,
          iconColor: AppColors.blue,
          title: 'DDDDDDDDDDDDDDDDDDDD',
          subtitle: 'DDDD-sub',
          onTap: () {},
        ),
      );

      // 宿主必须是 Text：本仓行级断言写法是 `tester.widget<Text>(find.byKey(...)).data`，
      // key 挂到容器上时那一发拿到 null（HistoryRowTile 把 key 挂 InkWell 是"按 key 点行"那一族）。
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('peer-D'))).data,
        'DDDDDDDDDDDDDDDDDDDD',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('peer-D-sub'))).data,
        'DDDD-sub',
        reason: '档位／时刻这类从属读数要能被单独断，而不是只能对整句 contains',
      );
      expect(find.byKey(const ValueKey('peer-D-row')), findsOneWidget);
    });

    testWidgets('不可点：行点不动，但行尾那一枚仍然点得动', (tester) async {
      var rowTaps = 0;
      var trailingTaps = 0;
      await pump(
        tester,
        FnthinkPeerRow(
          keyName: 'peer-E',
          icon: Icons.phone_android,
          iconColor: AppColors.blue,
          title: 'EEEEEEEEEEEEEEEEEEEE',
          trailing: GestureDetector(
            key: const ValueKey('peer-E-more'),
            behavior: HitTestBehavior.opaque,
            onTap: () => trailingTaps++,
            child: const Icon(Icons.more_horiz, size: 18),
          ),
          // 名单页的真实形状：这一行没有详情页，`onTap` 就是 null。
          onTap: null,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('peer-E-row')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        rowTaps,
        0,
        reason: 'onTap 为 null ⇒ 整行点不动（忙的时候就是这个状态，见 FnthinkEntryRow 同位语义）',
      );

      await tester.tap(find.byKey(const ValueKey('peer-E-more')));
      await tester.pumpAndSettle();
      expect(
        trailingTaps,
        1,
        reason:
            '正面对照：行点不动**不等于**行尾那颗也废掉。用 IgnorePointer 包整行就会在这里红 —— '
            '而红的是手法，不是判据（所以这一条必须存在）',
      );
    });

    testWidgets('可点：点在行上触发那一次，而且只触发一次', (tester) async {
      var rowTaps = 0;
      await pump(
        tester,
        FnthinkPeerRow(
          keyName: 'peer-F',
          icon: Icons.phone_android,
          iconColor: AppColors.blue,
          title: 'FFFFFFFFFFFFFFFFFFFF',
          statusMark: const FnthinkStatusMark(
            role: FnthinkMarkRole.attribute,
            label: 'L1',
            color: AppColors.blue,
          ),
          onTap: () => rowTaps++,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('peer-F-row')));
      await tester.pumpAndSettle();
      expect(rowTaps, 1, reason: '整行就是入口（与 FnthinkEntryRow 同一指点法）');
      expect(
        find.byKey(const ValueKey('peer-F-row')),
        findsOneWidget,
        reason: '读数件不能把自己变成第二个入口',
      );
    });
  });

  group('组件 B · FnthinkHistoryRow', () {
    testWidgets('渲染：方向 · 是谁 · 档位 · 结论 · 时刻，行高 44 且没有 chevron', (tester) async {
      await pump(
        tester,
        const FnthinkHistoryRow(
          keyName: 'hist-1',
          direction: FnthinkHistoryDirection.outgoing,
          directionLabel: '我发起的',
          peerLabel: 'AAAAAAAAAAAAAAAAAAAA',
          levelChip: 'L2',
          outcomeLabel: '已同意',
          outcomeTone: FnthinkOutcomeTone.approved,
          timeLabel: '3 分钟前',
        ),
      );

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.text('我发起的'), findsOneWidget);
      expect(find.text('AAAAAAAAAAAAAAAAAAAA'), findsOneWidget);
      expect(find.text('L2'), findsOneWidget);
      expect(find.text('已同意'), findsOneWidget);
      expect(find.text('3 分钟前'), findsOneWidget);
      expect(
        find.byIcon(Icons.chevron_right),
        findsNothing,
        reason: '历史不是入口：那一枚箭头一旦回来，就是在暗示"这一条还能进去改"',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('hist-1-row'))).height,
        44,
        reason: '与 HistoryRowTile 同一量级（44），历史行要比设备行矮一档',
      );
    });

    testWidgets('时刻那一格没有就不画，不写成"—"之外的东西', (tester) async {
      await pump(
        tester,
        const FnthinkHistoryRow(
          keyName: 'hist-2',
          direction: FnthinkHistoryDirection.incoming,
          directionLabel: '对方请求的',
          peerLabel: 'BBBBBBBBBBBBBBBBBBBB',
          outcomeLabel: '等待中',
          outcomeTone: FnthinkOutcomeTone.pending,
        ),
      );
      expect(find.byKey(const ValueKey('hist-2-time')), findsNothing);
      expect(find.byKey(const ValueKey('hist-2-level')), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('hist-2-row'))).height,
        44,
        reason: '少两格也不塌高度：留白是版式，不是"内容少所以矮一点"',
      );
    });

    testWidgets('各状态色：四档结论各占一色且不重色，词由调用点给', (tester) async {
      const cases = <String, FnthinkOutcomeTone>{
        '已同意': FnthinkOutcomeTone.approved,
        '已拒绝': FnthinkOutcomeTone.denied,
        '已过期': FnthinkOutcomeTone.expired,
        '等待中': FnthinkOutcomeTone.pending,
      };
      final seen = <String, Color>{};
      for (final entry in cases.entries) {
        await pump(
          tester,
          FnthinkHistoryRow(
            keyName: 'hist-tone',
            direction: FnthinkHistoryDirection.outgoing,
            directionLabel: '我发起的',
            peerLabel: 'CCCCCCCCCCCCCCCCCCCC',
            outcomeLabel: entry.key,
            outcomeTone: entry.value,
          ),
        );
        seen[entry.key] = tester
            .widget<FnthinkStatusMark>(
              find.byKey(const ValueKey('hist-tone-outcome')),
            )
            .color;
      }

      expect(seen['已同意'], AppColors.green);
      expect(seen['已拒绝'], AppColors.red);
      expect(seen['等待中'], AppColors.blue);
      expect(
        seen['已过期'],
        AppThemeColors.light().tertiaryLabel,
        reason:
            '灰这一档取 tertiaryLabel：`AppColors.systemGray` 那两枚值是**底色**（浅色档 F2F2F7），'
            '画在白卡上等于隐形 —— 这一族已经在那边踩过一次（已登记）',
      );
      expect(
        seen.values.toSet().length,
        4,
        reason: '四档结论必须四种颜色：重色的两行在扫读时就是同一件事',
      );
    });

    testWidgets('key 在场：主文案宿主是 Text，五枚派生 key 齐', (tester) async {
      await pump(
        tester,
        const FnthinkHistoryRow(
          keyName: 'hist-5',
          direction: FnthinkHistoryDirection.incoming,
          directionLabel: '对方请求的',
          peerLabel: 'DDDDDDDDDDDDDDDDDDDD',
          levelChip: 'L1',
          outcomeLabel: '已拒绝',
          outcomeTone: FnthinkOutcomeTone.denied,
          timeLabel: '昨天',
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('hist-5'))).data,
        'DDDDDDDDDDDDDDDDDDDD',
      );
      expect(find.byKey(const ValueKey('hist-5-icon')), findsOneWidget);
      expect(find.byKey(const ValueKey('hist-5-direction')), findsOneWidget);
      expect(find.byKey(const ValueKey('hist-5-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('hist-5-level')), findsOneWidget);
      expect(find.byKey(const ValueKey('hist-5-outcome')), findsOneWidget);
    });

    testWidgets('不可改：这一枚的子树里没有任何可点宿主', (tester) async {
      await pump(
        tester,
        const FnthinkHistoryRow(
          keyName: 'hist-6',
          direction: FnthinkHistoryDirection.outgoing,
          directionLabel: '我发起的',
          peerLabel: 'EEEEEEEEEEEEEEEEEEEE',
          outcomeLabel: '已过期',
          outcomeTone: FnthinkOutcomeTone.expired,
          timeLabel: '上周',
        ),
      );

      final row = find.byKey(const ValueKey('hist-6-row'));
      for (final type in const [
        CupertinoButton,
        TextButton,
        InkWell,
        GestureDetector,
      ]) {
        expect(
          find.descendant(of: row, matching: find.byType(type)),
          findsNothing,
          reason:
              '「历史不可改」钉在形状上：将来谁给历史行加一枚行内动作，这一条会红，'
              '而那一发要改的是口径不是这条判据（行内重推走的是转发行那一族，见 T133 片(b)）',
        );
      }
    });
  });

  group('两枚件的定义位置（钉"不新建文件"那一条）', () {
    test(
      '只在 lib/widgets/fnthink_card.dart 里，与 FnthinkNote／FnthinkEntryRow 并列',
      () {
        final found = <String, List<String>>{};
        for (final entry in libCodeByRel(projectRoot()).entries) {
          final names = <String>[
            for (final needle in const [
              'class FnthinkPeerRow',
              'class FnthinkHistoryRow',
            ])
              if (entry.value.contains(needle)) needle,
          ];
          if (names.isNotEmpty) found[entry.key] = names;
        }
        expect(
          found.keys.toList(),
          ['widgets/fnthink_card.dart'],
          reason:
              '两枚行件与那族小字件住同一文件是方案点名的：公共件按"行/弹层动作行/主操作"三档归家，'
              '新开一个文件就等于给"去哪找形状"多一个答案',
        );
        expect(found['widgets/fnthink_card.dart']!.length, 2);
      },
    );

    testWidgets('方向那两档与结论那四档不共色（两个主语不能有一种颜色）', (tester) async {
      // 结论那四色**从件自己产出的读数里取**，不在测试里另抄一份映射：
      // 抄了就成了第二个作者 —— 以后给 tone 加一档，抄的那份不会红，而判据已经变了。
      // `unknown` 不在这一圈里：它**不上色**（见下那条），不参与"四档四色"。
      const colored = <FnthinkOutcomeTone>[
        FnthinkOutcomeTone.approved,
        FnthinkOutcomeTone.denied,
        FnthinkOutcomeTone.expired,
        FnthinkOutcomeTone.pending,
      ];
      await pump(
        tester,
        Column(
          children: [
            for (final tone in FnthinkOutcomeTone.values)
              FnthinkHistoryRow(
                keyName: 'hist-tone-${tone.name}',
                direction: FnthinkHistoryDirection.outgoing,
                directionLabel: '我发起的',
                peerLabel: tone.name,
                outcomeLabel: tone.name,
                outcomeTone: tone,
              ),
          ],
        ),
      );
      final outcomeColors = <Color>{
        for (final tone in colored)
          tester
              .widget<FnthinkStatusMark>(
                find.byKey(ValueKey('hist-tone-${tone.name}-outcome')),
              )
              .color,
      };
      expect(
        outcomeColors.length,
        colored.length,
        reason: '四档结论四种颜色：重色的两行在扫读时就是同一件事',
      );

      final unknownMark = tester.widget<FnthinkStatusMark>(
        find.byKey(const ValueKey('hist-tone-unknown-outcome')),
      );
      expect(
        unknownMark.filled,
        isFalse,
        reason:
            '词表外那一档**不许上色**：任何一种颜色都是一个结论，而本机说不出那个结论 —— '
            '把它画成"灰=已过期"那一档，就等于把"读不出来"说成"不再有意义"',
      );

      final directionColors = <Color>{
        for (final d in FnthinkHistoryDirection.values) d.color,
      };
      expect(directionColors.length, 2);
      expect(
        directionColors.intersection(outcomeColors),
        isEmpty,
        reason:
            '同一行里"谁发出的"与"成了没有"是两个主语，共一种颜色就是让它们互相说成对方 —— '
            '箭头那一格与结论那一格挨着，肉眼分不开',
      );
    });
  });
}
