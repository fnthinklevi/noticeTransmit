import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_grant_items.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_remote_action_labels.dart';

/// T134 片4：勾选项的**整串语法**（粒度＝参数级）。
///
/// 三条线各一条判据，不许合成一条"看起来对就行"：
///  ① **行集**：契约两张表的全量，每行的参数种类由契约那一格说（派生不出来 ⇒ 抛）；
///  ② **拼与切**：分隔符只有契约那一枚，拼出来必须切得回去；
///  ③ **能不能进授权表**：四类理由各归各的（词表外 / 裸名字 / 多带参数 / 参数不成形），
///     而"裸名字"那一句是从契约读的 —— 服务端拒收与本机留痕要说同一句话。
void main() {
  final contract = FnthinkContract.readFile();

  FnthinkContract mutate(void Function(Map<String, Object?> root) edit) {
    final root = jsonDecode(jsonEncode(contract.raw)) as Map<String, Object?>;
    edit(root);
    return FnthinkContract(root);
  }

  /// 路径版 mutate（这一组要改的都是三层以内的格子）。
  FnthinkContract setPath(List<String> path, Object? value) => mutate((root) {
    var node = root;
    for (final key in path.take(path.length - 1)) {
      node = node[key] as Map<String, Object?>;
    }
    if (value == null) {
      node.remove(path.last);
    } else {
      node[path.last] = value;
    }
  });

  /// 给每一行拼一个当下合法的整串（值随便取，形状照契约）。
  String legalItem(FnthinkContract c, FnthinkGrantItemRow row) =>
      switch (row.kind) {
        FnthinkGrantArgumentKind.none => row.base,
        FnthinkGrantArgumentKind.count => c.grantItemWire(
          base: row.base,
          argument: '${c.l2ReportMinItems(row.base)}',
        ),
        FnthinkGrantArgumentKind.keyword => c.grantItemWire(
          base: row.base,
          argument: 'sample',
        ),
        FnthinkGrantArgumentKind.channelTarget => c.grantItemWire(
          base: row.base,
          argument: buildChannelArgument(
            c,
            family: c.l2ChannelTargetFamilies.first,
            id: 'chan-1',
            enabled: true,
          ),
        ),
        FnthinkGrantArgumentKind.toggle => c.grantItemWire(
          base: row.base,
          argument: c.l3ItemTargetWords.first,
        ),
      };

  group('行集（pairItemRows）', () {
    test('画的是两张词表的全量，顺序照契约', () {
      final rows = pairItemRows(contract);
      expect(rows.map((r) => r.base), [
        ...contract.l2Actions,
        ...contract.l3Settings.keys,
      ], reason: '次序也是判据：那张表按契约的顺序画，界面不重排一遍（重排就是第二个作者）');
    });

    test('每行的参数种类都由契约那一格说，界面不自己认', () {
      final needsArgument = contract.l2ActionsRequiringArgument.toSet();
      for (final row in pairItemRows(contract)) {
        final expected = contract.l3Settings.containsKey(row.base)
            ? (contract.l3Settings[row.base]!.isToggle
                  ? FnthinkGrantArgumentKind.toggle
                  : FnthinkGrantArgumentKind.none)
            : switch (contract.l2ReportKind(row.base)) {
                'count' => FnthinkGrantArgumentKind.count,
                'keyword' => FnthinkGrantArgumentKind.keyword,
                'channelTarget' => FnthinkGrantArgumentKind.channelTarget,
                _ => FnthinkGrantArgumentKind.none,
              };
        expect(row.kind, expected, reason: '${row.base} 的种类被读成别的东西');
        expect(
          row.needsArgument,
          needsArgument.contains(row.base) ||
              (contract.l3Settings[row.base]?.isToggle ?? false),
          reason: '${row.base} 该不该收参数，两处说法必须一致',
        );
      }
    });

    test('每一项都在契约声明的取值域里，且配了人话标签', () {
      final rows = pairItemRows(contract);
      expect(rows.map((r) => r.base), grantItemBases(contract));
      for (final row in rows) {
        expect(
          hasFnthinkRemoteActionLabel(row.base),
          isTrue,
          reason: '${row.base} 没配词条就会被画成裸标识符（屏幕上那串英文冒号词）',
        );
      }
    });

    test('要参数却没声明 argumentKind ⇒ 抛（那一串没有作者，画出来就是一格必然 400 的勾）', () {
      final broken = setPath(const [
        'capabilities',
        'l2',
        'reports',
        'channel:toggle',
      ], null);
      expect(
        () => pairItemRows(broken),
        throwsStateError,
        reason: 'requiresArgumentFrom 列了它、reports 却没给形状 ⇒ 静默少画一行是假绿',
      );
    });

    test('声明了别的 kind 却没列进 requiresArgumentFrom ⇒ 抛（两处说法反了）', () {
      final broken = setPath(
        const ['capabilities', 'l2', 'requiresArgumentFrom'],
        contract.l2ActionsRequiringArgument
            .where((a) => a != 'channel:toggle')
            .toList(),
      );
      expect(
        () => pairItemRows(broken),
        throwsStateError,
        reason: '一处说要参数、一处说不要 ⇒ 界面与判据会各按一种读法拼串',
      );
    });

    test('契约给了本机看不懂的 argumentKind ⇒ 抛，不猜一种拼法', () {
      final broken = setPath(const [
        'capabilities',
        'l2',
        'reports',
        'sms:search',
        'argumentKind',
      ], 'flag');
      expect(() => pairItemRows(broken), throwsStateError);
    });
  });

  group('拼与切（分隔符只有契约那一枚）', () {
    test('拼出来的整串切回来还是那一段名字 + 那一段参数', () {
      for (final row in pairItemRows(contract)) {
        final item = legalItem(contract, row);
        expect(contract.grantItemBase(item), row.base);
        if (row.needsArgument) {
          expect(
            contract.grantItemArgument(item),
            isNotEmpty,
            reason: '${row.base} 收了参数却切不出参数段',
          );
        } else {
          expect(
            contract.grantItemArgument(item),
            isEmpty,
            reason: '无参数那一项不该切出参数段',
          );
        }
      }
    });

    test('无参数的项：整串就是名字（不多一枚斜杠）', () {
      const plain = FnthinkGrantItemRow(
        base: 'listener:start',
        kind: FnthinkGrantArgumentKind.none,
      );
      expect(contract.grantItemWire(base: plain.base), 'listener:start');
      expect(contract.grantItemBase('listener:start'), 'listener:start');
      expect(contract.grantItemArgument('listener:start'), '');
    });

    test('分隔符换一枚，拼与切跟着换（写死斜杠的那一处会在这里红）', () {
      final broken = setPath(const [
        'clientEvents',
        'pairConfirm',
        'itemGrammar',
        'argumentSeparator',
      ], '~');
      expect(broken.grantItemSeparator, '~');
      expect(
        broken.grantItemWire(base: 'app:launch', argument: 'demo'),
        'app:launch~demo',
      );
      expect(broken.grantItemBase('app:launch~demo'), 'app:launch');
      expect(broken.grantItemArgument('app:launch~demo'), 'demo');
    });

    test('三段串的段分隔符与勾选项的分隔符不是同一枚', () {
      // 同一枚的话 `channel:toggle/webhook:acme:off` 就没有唯一拆法了。
      expect(
        contract.l2ChannelTargetSeparator,
        isNot(contract.grantItemSeparator),
      );
    });
  });

  group('能不能进授权表（grantItemProblem）', () {
    test('每一项都拼得出合法整串', () {
      for (final row in pairItemRows(contract)) {
        final item = legalItem(contract, row);
        expect(
          grantItemProblem(contract, item),
          isNull,
          reason: '${row.base}（${row.kind.name}）自己拼的串本机不认：$item',
        );
      }
    });

    test('要参数的项：裸名字被判不过，理由那句从契约读', () {
      for (final row in pairItemRows(contract).where((r) => r.needsArgument)) {
        expect(
          grantItemProblem(contract, row.base),
          contract.grantItemBareNameRejectedFor(row.base),
          reason: '${row.base} 的裸名字必须被拒，且回的是契约那一句（服务端同一句）',
        );
      }
      // 反证方向：那句换了词，判据跟着换 ⇒ 没有在实现里写死。
      final broken = setPath(const [
        'clientEvents',
        'pairConfirm',
        'itemGrammar',
        'bareNameRejected',
      ], 'needs-arg:X');
      expect(grantItemProblem(broken, 'app:launch'), 'needs-arg:app:launch');
    });

    test('不要参数的项带了参数 ⇒ unexpected-argument（带了就是带了件没人认的东西）', () {
      expect(
        grantItemProblem(contract, 'listener:start/1'),
        'unexpected-argument:listener:start',
      );
      // 无参数那一项**不带**参数才是合法形状（带一枚空斜杠也不行：`listener:start/` 的
      // 参数段是空串，读起来与"带了个没人认的东西"同形）。
      expect(grantItemProblem(contract, 'listener:start'), isNull);
      expect(
        grantItemProblem(contract, 'listener:start/'),
        'unexpected-argument:listener:start',
      );
    });

    test('名字不在词表里 ⇒ unknown-item（服务端回 400，状态码从契约那枚旋钮读）', () {
      expect(
        grantItemProblem(contract, 'no-such:action'),
        'unknown-item:no-such:action',
      );
      expect(
        grantItemProblem(contract, 'no-such:action/x'),
        'unknown-item:no-such:action',
      );
    });

    test('count 越界与 keyword 越界各报各的（形状的理由不合并）', () {
      expect(
        grantItemProblem(contract, 'notifications:report/999'),
        startsWith('bad-report-count'),
      );
      expect(
        grantItemProblem(contract, 'sms:search/${'x' * 40}'),
        startsWith('bad-keyword'),
      );
    });

    test('通道目标那一段三种不成形都拒：段数、族、目标词', () {
      final family = contract.l2ChannelTargetFamilies.first;
      expect(
        grantItemProblem(contract, 'channel:toggle/$family:acme'),
        startsWith('bad-channel-argument'),
        reason: '少一段（没有目标档）⇒ 重投会翻两次，必须拒',
      );
      expect(
        grantItemProblem(contract, 'channel:toggle/$family:acme:off:extra'),
        startsWith('bad-channel-argument'),
        reason: '多一段也要拒：静默取前三段的话，对面拼错一个字符就变成另一条指令',
      );
      expect(
        grantItemProblem(
          contract,
          'channel:toggle/${contract.l2ChannelTargetFamilies.last}x:acme:off',
        ),
        startsWith('bad-channel-argument'),
        reason: '族不在契约那张表里',
      );
      expect(
        grantItemProblem(contract, 'channel:toggle/$family:acme:maybe'),
        startsWith('bad-channel-argument'),
        reason: '目标词只认那两个，宽容归一会把拼错变成一次真实的启停',
      );
    });

    test('L3 toggle 的目标词只认契约那两个', () {
      final toggle = pairItemRows(
        contract,
      ).firstWhere((r) => r.kind == FnthinkGrantArgumentKind.toggle);
      expect(
        grantItemProblem(contract, '${toggle.base}/up'),
        'unknown-target-word:up',
      );
      expect(
        grantItemProblem(
          contract,
          contract.grantItemWire(
            base: toggle.base,
            argument: contract.l3ItemTargetWords[1],
          ),
        ),
        isNull,
      );
    });
  });
}
