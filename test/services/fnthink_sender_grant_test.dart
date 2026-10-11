import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_grant_items.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_sender_grant.dart';

/// 发送方那份**本机授权**准不准这一条（T128 片2 的唯一判据作者；
/// 逐条那一半自 T134 片4 起按**整串**吃，粒度＝参数级）。
///
/// 五条最要紧的，都是"写歪了不会崩、只会静默放开/静默打死"的那种：
///  ① 天花板按**契约那三档的顺序**判，不按字符串比大小（`L10` 会不会大于 `L2` 这种）；
///  ② 档位词表外 ⇒ 按**不够**判（读不到不是"全给"）；
///  ③ 逐条清单**整串相等、没有通配**（与服务端 `grant.items.includes` 同一口径）；
///  ④ **名字在词表里的，清单就管它**（片4 改掉的那一维：以前"要参数"的那一族被整排留在清单之外，
///     只由天花板 + 整机开关管，而 `app:launch` 那一格因此要么整条不给、要么等于允许对面
///     启动任意应用）；
///  ⑤ 只有"这个词没人认"才交回前面那一格（`unknown-action:` / `unknown-setting:`），
///     本函数不替它编一条「没勾」。
void main() {
  final contract = FnthinkContract.readFile();
  final levels = contract.capabilityLevels;
  final top = levels.last;
  final rows = pairItemRows(contract);

  String? reject({
    required String level,
    required String item,
    required String maxLevel,
    List<String> items = const <String>[],
  }) => rejectBySenderGrant(
    contract,
    level: level,
    item: item,
    grant: FnthinkGrant(maxLevel: maxLevel, items: items),
  );

  /// 给每一行拼一个**当下合法**的整串（参数的值随便取，形状必须合法）。
  /// 写这一枚是为了让下面那条数据驱动覆盖到**每一项**，而不是只有无参数那十项。
  String sampleItem(FnthinkGrantItemRow row) => switch (row.kind) {
    FnthinkGrantArgumentKind.none => row.base,
    FnthinkGrantArgumentKind.count => contract.grantItemWire(
      base: row.base,
      argument: '${contract.l2ReportMinItems(row.base)}',
    ),
    FnthinkGrantArgumentKind.keyword => contract.grantItemWire(
      base: row.base,
      argument: 'sample',
    ),
    FnthinkGrantArgumentKind.channelTarget => contract.grantItemWire(
      base: row.base,
      argument: buildChannelArgument(
        contract,
        family: contract.l2ChannelTargetFamilies.first,
        id: 'chan-1',
        enabled: true,
      ),
    ),
    FnthinkGrantArgumentKind.toggle => contract.grantItemWire(
      base: row.base,
      argument: contract.l3ItemTargetWords.first,
    ),
  };

  group('档位天花板', () {
    test('三档 × 三种封顶的真值表（只有"够得着"的那几格放行）', () {
      for (final maxLevel in levels) {
        final ceiling = levels.indexOf(maxLevel);
        for (final level in levels) {
          expect(
            reject(level: level, item: 'x', maxLevel: maxLevel),
            levels.indexOf(level) > ceiling ? 'level:$level' : isNull,
            reason: '封顶 $maxLevel 遇 $level',
          );
        }
      }
    });

    test('封顶那个词不在契约词表上 ⇒ 按不够判，不放开', () {
      expect(
        reject(level: 'L1', item: 'x', maxLevel: 'L9'),
        'unknown-ceiling:L9',
        reason: '库里那一行被手改、或契约改过档位名：读不出的封顶不能当"最高那档"',
      );
    });

    test('指令自称的档位不在词表上 ⇒ 也拒（不假设调用顺序）', () {
      expect(reject(level: 'L9', item: 'x', maxLevel: top), 'level:L9');
    });
  });

  group('逐条清单', () {
    test('L1 压根不看清单（勾与不勾同一答案）', () {
      // 契约 itemRequiredFromLevel = L2 ⇒ 给 L1 画一张"勾了才生效"的表，
      // 用户读到的是"多勾一项＝多给一项权限"，而这一档不成立。
      expect(
        reject(level: 'L1', item: 'location:get', maxLevel: top, items: []),
        isNull,
      );
      expect(
        reject(
          level: 'L1',
          item: 'location:get',
          maxLevel: top,
          items: ['location:get'],
        ),
        isNull,
      );
    });

    test('勾了才放行：同一项在 L2 与 L3 都逐条判', () {
      for (final level in ['L2', 'L3']) {
        expect(
          reject(
            level: level,
            item: 'location:get',
            maxLevel: top,
            items: ['location:get'],
          ),
          isNull,
          reason: '$level 勾了这一项',
        );
        expect(
          reject(level: level, item: 'location:get', maxLevel: top, items: []),
          'not-granted:location:get',
          reason: '$level 没勾这一项',
        );
      }
    });

    test('整串相等，没有通配：前缀与包含都不算勾上', () {
      // 这一条钉的是"清单里少写一格不等于宽松"：写 `location` 放行不了 `location:get`。
      for (final near in const ['location', 'location:', 'location:getX']) {
        expect(
          reject(
            level: 'L2',
            item: 'location:get',
            maxLevel: top,
            items: [near],
          ),
          'not-granted:location:get',
          reason: '近似串「$near」不该算勾上',
        );
      }
    });

    test('⚠ 要参数的那一族**现在归清单管**（片4 拍下的那一维）', () {
      // 片3 之前这里期望的是 `isNull`（"清单表达不了 ⇒ 清单不管"），那条逃路的代价写在
      // `rejectBySenderGrant` 顶上：`app:launch` 要么整条不给，要么等于允许对面启动任意应用。
      const toggled = 'channel:toggle/webhook:acme:off';
      expect(
        reject(level: 'L2', item: toggled, maxLevel: top, items: []),
        'not-granted:$toggled',
        reason: '没勾就是没勾 —— 天花板够也不给过',
      );
      expect(
        reject(level: 'L2', item: toggled, maxLevel: top, items: [toggled]),
        isNull,
        reason: '勾的就是那一整串 ⇒ 过（同意屏勾出的形状与线上串同一，才对得上）',
      );
      // 换一档、换一族、换一个号都是另一格：勾了 `…acme:off` 放行不了别的串。
      for (final other in const [
        'channel:toggle/webhook:acme:on',
        'channel:toggle/email:acme:off',
        'channel:toggle/webhook:other:off',
      ]) {
        expect(
          reject(level: 'L2', item: other, maxLevel: top, items: [toggled]),
          'not-granted:$other',
          reason: '「$other」不是勾过的那一条',
        );
      }
      // 但天花板照判 —— "清单管得着了"不是"天花板不管了"。
      expect(
        reject(level: 'L2', item: toggled, maxLevel: 'L1', items: [toggled]),
        'level:L2',
      );
    });

    test('裸名字不再被当成"勾过了"：老对端那一发判不过（兼容收窄，刻意的）', () {
      // 协议层仍认裸形（`l3.itemMayCarryTarget`），收窄的只有清单这一层：
      // 勾出去的是 `monitoring/on`，线上发来 `monitoring` ⇒ 不是同一串 ⇒ 不算勾过。
      // 发版次序照契约 `itemGrammar.versionOrder = server-first`（先服务端与契约、后设备包）。
      expect(
        reject(
          level: 'L3',
          item: 'monitoring',
          maxLevel: top,
          items: ['monitoring/on'],
        ),
        'not-granted:monitoring',
        reason: '把裸名字放行＝一次勾选放开"开"和"关"两档，而那正是本片要修的形状',
      );
    });

    test('名字不在词表里 ⇒ 本函数不判「没勾」（那一格由词表判据回 unknown-*）', () {
      for (final item in const ['no-such:action', 'self:destruct']) {
        expect(
          reject(level: 'L2', item: item, maxLevel: top, items: []),
          isNull,
          reason: '「$item」没人认得 —— 说它"没勾"会把"没人认"与"你没给"塌成一句',
        );
      }
      // 带参数的整串也一样只看第一段：`no-such:action/x` 该不该认由前面那一格判。
      expect(
        reject(level: 'L2', item: 'no-such:action/x', maxLevel: top, items: []),
        isNull,
      );
    });

    test('每一项都拼得出合法整串（数据驱动的兜底）', () {
      // 上面几条都是手工挑的项。这一条逐项走一遍：派生出来的每一行都得**能被勾**，
      // 而勾上的那一串必须过判据 —— 少一行（契约加了项而派生漏了）或多一行都会在这里红。
      expect(
        rows.length,
        contract.l2Actions.length + contract.l3Settings.length,
        reason: '这张表画的是两张词表的**全量**，不再做"要参数就减掉"那种减法',
      );
      for (final row in rows) {
        final item = sampleItem(row);
        expect(
          grantItemProblem(contract, item),
          isNull,
          reason: '${row.base}（${row.kind.name}）拼出来的整串本机自己都不认：$item',
        );
        expect(
          reject(level: 'L2', item: item, maxLevel: top, items: const []),
          'not-granted:$item',
          reason: '没勾 ⇒ ${row.base}',
        );
        expect(
          reject(level: 'L2', item: item, maxLevel: top, items: [item]),
          isNull,
          reason: '勾了 ⇒ ${row.base}',
        );
      }
    });
  });
}
