import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_pair_items.dart';
import 'package:notice_transmit/services/fnthink_sender_grant.dart';

/// 发送方那份**本机授权**准不准这一条（T128 片2 的唯一判据作者）。
///
/// 四条最要紧的，都是"写歪了不会崩、只会静默放开/静默打死"的那种：
///  ① 天花板按**契约那三档的顺序**判，不按字符串比大小（`L10` 会不会大于 `L2` 这种）；
///  ② 档位词表外 ⇒ 按**不够**判（读不到不是"全给"）；
///  ③ 逐条清单**整串相等、没有通配**（与服务端 `grant.items.includes` 同一口径）；
///  ④ 清单**表达不了**的形状不判"没勾"（判了就是把契约点名要参数那六项当场永久打死）。
void main() {
  final contract = FnthinkContract.readFile();
  final levels = contract.capabilityLevels;
  final top = levels.last;
  final checkable = pairItemCandidates(contract);

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

    test('⚠ 清单表达不了的形状 ⇒ 不判「没勾」（登记，不是遗漏）', () {
      // 契约 `l2.requiresArgumentFrom` 那六项与 L3 两枚 toggle 都不在候选集里
      // （[pairItemCandidates] 刻意做的那道减法），而线上串长成 `<名>/<参数>`。
      // 判"没勾"= 把这六项永久打死；粒度（动作级 / 参数级）是要维护者拍的一条。
      expect(checkable.contains('channel:toggle'), isFalse);
      expect(
        reject(
          level: 'L2',
          item: 'channel:toggle/webhook:acme:off',
          maxLevel: top,
          items: [],
        ),
        isNull,
      );
      // 但天花板照判 —— "不判清单"从来不是"什么都放"。
      expect(
        reject(
          level: 'L2',
          item: 'channel:toggle/webhook:acme:off',
          maxLevel: 'L1',
          items: [],
        ),
        'level:L2',
      );
    });

    test('候选集里的每一项：没勾 ⇒ 一律拒；勾上 ⇒ 一律过', () {
      // 数据驱动这一条是为了给上面那条"表达式"兜底：候选集哪天变宽（粒度拍了），
      // 这里必须逐项都走得通，而不是只有 `location:get` 那一格被手工验过。
      for (final item in checkable) {
        expect(
          reject(level: 'L2', item: item, maxLevel: top, items: const []),
          'not-granted:$item',
          reason: '没勾 ⇒ $item',
        );
        expect(
          reject(level: 'L2', item: item, maxLevel: top, items: [item]),
          isNull,
          reason: '勾了 ⇒ $item',
        );
      }
    });
  });
}
