import '../database/database_helper.dart';
import '../models/fnthink_peer.dart';

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
class FnthinkPeerService {
  FnthinkPeerService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  /// 名单的全部条目，最近同意的在前。排序口径只在 `DatabaseHelper.loadFnthinkPeers`
  /// 那一处（`granted_at DESC, peer_address ASC`）：页面自己再排一次，早晚与这里分叉。
  Future<List<FnthinkPeer>> list() => _db.loadFnthinkPeers();

  /// 划掉本机记得的那一行，回"这一行本来在不在"。⚠ 它**只该在服务端已经认下撤销之后**被调用
  /// （那个先后写在协调者里）：`false` 不是撤销失败，而是"本来就没有"——幂等的那一半。
  /// 反过来，"撤失败却把行删了"才是事故：本机从此看不见这个来源，而服务端还留着授权，
  /// 对面照样能推进来，屏幕上却没有任何一行解释它从哪来。
  Future<bool> remove(String peerAddress) => _db.removeFnthinkPeer(peerAddress);
}
