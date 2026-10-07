import 'channel_health_store.dart';
import 'update_server_regions.dart';

/// 两台各探一次 → 记账 → （只在自动档）据此重挑并落盘。T95 片4 把这四步收成**一处**。
///
/// 为什么收成一处：「第一次进入时自动选」与「打开服务器选择页时各探一次」必须按同一套
/// 判据走。两处各写一遍，先漂移的一定是"哪一台算当前"那一句 —— 而那一句正是用户看得见、
/// 并且拿去决定要不要换服务器的东西。
///
/// ⚠ 顺序不能换：**先记账、后挑**。挑用的是这一轮的新数据，徽标记的也是这一轮；
///   反过来会画出"徽标说失败、这一行却说当前在用它"。
Future<Map<UpdateServerRegion, UpdateServerProbe>> probeAllAndUpdate({
  required Future<UpdateServerProbe> Function(UpdateServerRegion region) probe,
  required ChannelHealthStore health,
  UpdateServerSettings? settings,
}) async {
  final current = settings ?? await UpdateServerSettings.load();
  final results = <UpdateServerRegion, UpdateServerProbe>{};
  await Future.wait(
    UpdateServerRegion.ordered.map((region) async {
      results[region] = await probe(region);
    }),
  );
  for (final result in results.values) {
    await health.record(
      kUpdateHealthFamily,
      result.region.name,
      reachable: result.reachable,
      latencyMs: result.latencyMs,
      httpCode: result.httpCode,
    );
  }
  if (current.isAuto) {
    final picked = pickAutoRegion(results);
    if (picked != null && picked != current.autoRegion) {
      await current.recordAutoProbe(picked);
    }
  }
  return results;
}

/// 第一次进入时按网络实测选一台（维护者 2026-10-06 那条"第一次进入根据用户网络进行选择"）。
///
/// ⚠ **只在"从没选过、也从没测出来过"时动一次**：`autoUnprobed` 为假就直接返回 ——
///   用户钉过的那一台、以及上一次已经落盘的结论，都不许被这一次探测悄悄改掉
///   （与幻念推送 `ensureFirstRunHost` 同一分工：T76 §6 ⑤ 管的是"已保存的偏好不被自动改"）。
///
/// ⚠ 判据是**实测时延**，不是 IP 归属地查询。仓库里没有任何 GeoIP 设施，而幻念那条链路
///   明确禁了 GeoIP/ping（`fnthink_endpoint_probe.dart` 的文件头）：同一条链路上长出两套
///   "你在哪个国家"的判据，比一套都不用更坏。时延测的就是"这台离你的网络有多远"，
///   它回答的正是同一个问题，而且不把用户的 IP 交给第三个服务去判。
///
/// ⚠ 两台都没探通时**不落结论**（`autoUnprobed` 还是真）：下次进入会再试一次。
///   把"没测出来"落成"就用默认这台"，界面上就再也没人知道曾经失败过。
Future<void> ensureFirstRunRegion({
  required Future<UpdateServerProbe> Function(UpdateServerRegion region) probe,
  required ChannelHealthStore health,

  /// T96 片2：**先**按国家码那条读口问一次（服务端 `GET /api/version/region`）。
  /// 不接（null）或读不到（country 为 null）⇒ 退回下面那套时延实测 —— 片1b 那条
  /// fail-closed 在这条链上的落点：**没读到不等于读到了坏消息，但也不等于读到了好消息**。
  Future<String?> Function()? countryOf,
}) async {
  final settings = await UpdateServerSettings.load();
  if (!settings.autoUnprobed) return;
  final read = countryOf;
  if (read != null) {
    final byCountry = regionForCountryCode(await read());
    if (byCountry != null) {
      await settings.recordAutoProbe(byCountry);
      return;
    }
  }
  await probeAllAndUpdate(probe: probe, health: health, settings: settings);
}
