import 'package:fnthink_push/fnthink_push.dart';

import 'fnthink_grant_items.dart';
import 'fnthink_pair_items.dart';

/// 发送方在**本机名单**里那一行准不准这一条指令（T128 片2，逐条那一半自 T134 片4 起吃整串）。
///
/// 回 null = 准；回一句 = 拒的理由：`level:<那一档>` ｜`unknown-ceiling:<档>` ｜
/// `not-granted:<item>`（最后这一条由调用方加 `item:` 前缀，与同族的
/// `unknown-setting:` / `missing-grant:` 一个形状）。
///
/// ## 为什么这一判落在设备上，而且它是**唯一一道**
/// 一条远程指令在**线上一律是一条 L1 通知**：发送侧只有 `sendNotice(peer, title, text)`
/// 那一个口，而被签的六个字段里没有 `item`（`send_kernel.dart` 明写「顶层不放 item，
/// 放了也一定被服务端丢掉」）。⇒ 服务端 `decideCapability` 拿到的永远是
/// `type=notice / item=''`，契约 `capabilities.itemRequiredFromLevel` 那一段对这一族
/// **根本不响**。「这一条是 L3、动的是 `location:get`」只写在正文那个信封里，
/// 而信封是**收件这一台**拆的。
/// ⇒ 用户在这台设备上勾的那份清单（`fnthink_peers.items`）必须在这里生效，否则
///   「只允许 A 读定位、不允许 B 读定位」这一句在本仓没有任何一行代码能表达；
///   而今天真正拦住「L1 配对的那台发来 L3 指令」的只剩凭据那一道 ——
///   契约 `auth.l2Requires = false` 意味着 **L2 连凭据都不必带**。
///
/// ## 逐条那一段判的是「这一串在不在清单里」（片4 起的口径）
/// 清单的比对是**整串相等**（没有通配，与服务端 `grant.items.includes(item)` 同一口径），
/// 而片4 之后同意屏勾出来的也是整串（`<名>/<参数>`）—— 两边同一形状，才对得上。
///
/// 这里唯一"不看清单"的一维是**这一串的名字根本不在词表里**：那种指令在前面那一格
/// （`_rejectItem`）就会被拒成 `unknown-action:` / `unknown-setting:`，本函数不替它编一条
/// 「没勾」—— 那会把"这个词没人认"与"这个词你没给"两种下一步动作塌成一句。
/// 除此之外，**只要名字在词表里，清单就管它**：片3 那份"要参数 ⇒ 清单表达不了 ⇒ 清单不管"
/// 的减法是一条逃路，它让契约点名要参数的那六项（含 `app:launch`）只由档位天花板 +
/// 整机那一枚读能力开关管，而"这一台能不能启动某一条应用"在本机名单里那一格表达不出来。
///
/// ⚠ 由此产生的兼容收窄是刻意的：**老对端发来的裸名字**（`battery_saver` 而不带 `/on`）
/// 从此判不过。协议层仍认那个裸形（`l3.itemMayCarryTarget`），收窄的只有清单这一层 ——
/// 顺序照契约 `itemGrammar.versionOrder = server-first`（先传服务端与契约，再上设备包），
/// 反过来的表现是"勾不上而界面当场说一句"，不是静默放行。
String? rejectBySenderGrant(
  FnthinkContract contract, {
  required String level,
  required String item,
  required FnthinkGrant grant,
}) {
  final at = contract.levelRank(level);
  final ceiling = contract.levelRank(grant.maxLevel);
  // 名单里那一行的档位词不在契约词表上（契约改过、或那一行被手改）⇒ **按不够判**。
  // 退化成"最高那档"等于让一个坏读数放开全部三档；而这一条的默认方向必须是收紧。
  if (ceiling < 0) return 'unknown-ceiling:${grant.maxLevel}';
  // 指令自称的档位不在词表上：正常走不到这里（来源渠道那一道按契约那张表判，
  // 词表外的档位查不到任何来源 ⇒ 已被 `source-not-allowed:` 拒掉）。
  // 留这一条是因为本函数不该假设调用顺序 —— 判不了就拒，不放开。
  if (at < 0) return 'level:$level';
  if (at > ceiling) return 'level:$level';
  // 逐条清单：从契约 `itemRequiredFromLevel` 那一档起才看（L1 压根不看清单 ——
  // 给它画一张"勾了也不参与判据"的表，用户读到的是"多勾一项＝多给一项权限"）。
  if (!pairItemsApplyAtLevel(contract, level)) return null;
  if (!grantItemBases(contract).contains(contract.grantItemBase(item))) {
    return null;
  }
  if (!grant.items.contains(item)) return 'not-granted:$item';
  return null;
}
