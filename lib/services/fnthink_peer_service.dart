import '../database/database_helper.dart';
import '../models/fnthink_peer.dart';
import 'fnthink_contract_loader.dart';
import 'package:fnthink_push/fnthink_push.dart' as push;

/// 本机配对名单（`fnthink_peers`）的唯一读写咽喉（T42「配对名单」那一格的数据源）。
///
/// 为什么这一层现在才存在，而不是提前一张空壳：写入者在第五片就有了（协调者在服务端认下那条
/// 授权之后写一行），而**读者**今天要才出现 —— 没有调用方的清理函数就是下一个
/// "registerDevice 没有调用方"（本仓为这类空抽象记过几次账）。
///
/// `remove` 是 T31 B 片第二片才加的，而且它**只做本机删行**：能不能推是服务端那份关系表
/// 决定的（`pairing.relationshipStoredOn`），所以"先撤服务端、再删这一行"的先后与两种失败态
/// 写在 `FnthinkReceiveCoordinator.revokePeer` 里，不在这一层。这一层若自己去发那一发，
/// 撤销就有了第二个作者，而界面拿到的结论会开始与时序有关。
///
/// 这一层被砸过什么（报告在本地 `outputs/_peers_falsify.report.txt` 与 `_peers_r1.report.txt`，
/// 按约定不入库；R1/R6/R7/R8 全 named + restored；撤销那一批是 `outputs/_revokepeer.report.txt`）：
///  - 页面渲染层把"读失败"当成空表 ⇒ 红在「名单读不出来 ⇒ 不许显示成"还没有配对过任何设备"」；
///  - `fromLocator` 里把 `loadPeers` 换成一个本地常量函数（= 页面不再经服务层）⇒ 红在装配守卫
///    「配对名单的读只有一个咽喉」；
///  - 这一层自己 `.reversed.toList()` 再排一次（= 排序口径长出第二份）⇒ 红在「新的在前」那条；
///  - DI 里那行注册摘掉 ⇒ **只有**「DI 里真的注册了它」红，其余全绿（"漏接时没人喊"那一族）。
///
/// T49 追加的那一段（`grantFor`）：把本机名单那一行读成裁决层要的 `FnthinkGrant`。
/// ⚠ **本机清单优先于服务端那份**：裁决发生在设备上，而用户当初勾选是在这台设备上点的。
/// 只读服务端那份的话，用户撤销了一项勾选而设备还在按旧的放行 —— 而那正是这一层存在的理由。
class FnthinkPeerService {
  FnthinkPeerService({DatabaseHelper? db, this.contracts})
    : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  /// 契约的来处（`grantFor` 要拿档位词表）。null ⇒ 那条路抛，不静默放行。
  final FnthinkContractLoader? contracts;

  /// 名单的全部条目，最近同意的在前。排序口径只在 `DatabaseHelper.loadFnthinkPeers`
  /// 那一处（`granted_at DESC, peer_address ASC`）：页面自己再排一次，早晚与这里分叉。
  Future<List<FnthinkPeer>> list() => _db.loadFnthinkPeers();

  /// 名单里那一个发送方的授权（读不到 ⇒ 缺省档，见下）。
  ///
  /// ⚠ **查不到这一行**时返回**缺省档**（契约 `capabilities.grantDefaults`，即 L1 + 空清单）
  /// 而不是 null：null 在裁决层与"这个发送方还没配对"读起来一样，于是调用方得再判一次
  /// "配对了没有"，而那次判迟早会漏。缺省档本身就是那个答案。
  ///
  /// ⚠ 契约**读不到就抛**（`FnthinkContractUnavailable`），不许就地退化成"库里写着什么
  /// 就是什么"：档位词表是那份契约给的，绕过它就等于让库里的一个字符串直接决定权限。
  Future<push.FnthinkGrant> grantFor(String peerAddress) async {
    final contract = await _requireContract();
    // ⚠ 走 [list] 而不是再调一次 `loadFnthinkPeers`：这一层是那张表**唯一**的读者
    // （`fnthink_receive_wiring_test.dart` 数的就是调用点个数），这里多写一遍
    // `loadFnthinkPeers` 就会把读法变成两处 —— 而守卫数的是**调用点**，
    // 不是"文件"。查询口径仍是表那一处，这一处只是转发。
    for (final row in await list()) {
      if (row.peerAddress != peerAddress) continue;
      return push.FnthinkGrant(
        maxLevel: contract.capabilityLevels.contains(row.level)
            ? row.level
            // 档位不在词表里（契约改过、或库被手改）⇒ 按缺省档，不是"最高那档"
            : contract.grantDefaultMaxLevel,
        items: row.items,
        revision: row.revision,
        grantedAt: row.grantedAt,
      );
    }
    return push.FnthinkGrant(maxLevel: contract.grantDefaultMaxLevel);
  }

  Future<push.FnthinkContract> _requireContract() async {
    final loader = contracts;
    if (loader == null) {
      throw StateError(
        'FnthinkPeerService 没注入契约装载器：档位词表在裁决前必须先从契约取，'
        '不能退化成"库里写着什么就是什么"',
      );
    }
    return loader.load();
  }

  /// 划掉本机记得的那一行，回"这一行本来在不在"。⚠ 它**只该在服务端已经认下撤销之后**被调用
  /// （那个先后写在协调者里）：`false` 不是撤销失败，而是"本来就没有"——幂等的那一半。
  /// 反过来，"撤失败却把行删了"才是事故：本机从此看不见这个来源，而服务端还留着授权，
  /// 对面照样能推进来，屏幕上却没有任何一行解释它从哪来。
  Future<bool> remove(String peerAddress) => _db.removeFnthinkPeer(peerAddress);

  /// 给名单里那一行起（或抹）一个**本机自己看的**名字（T128 片1）。
  ///
  /// ⚠ 这一发**不碰服务端、也不碰授权**：档位、逐条清单、转发勾选一个都不动 ——
  /// 改的只是"这一行在屏幕上叫什么"。所以它随时可改、不需要对面在场，
  /// 也不该被读成"给它多放了一点权限"。
  /// 回 `false` = 那一行不在名单上（地址码是主键，不是可以凭空起名的东西）。
  Future<bool> rename(String peerAddress, String alias) =>
      _db.setFnthinkPeerAlias(peerAddress, FnthinkPeer.normalizeAlias(alias));
}
