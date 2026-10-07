/// 首页那一格的状态判定（纯函数）。
///
/// 为什么要有它：这一格原本只有"监听在跑 / 没在跑"两态，而**推送可以被用户在
/// 通知栏或桌面小部件上单独暂停**（原生 `push_toggle_state/push_active`，监听继续、
/// 只不发 webhook）。那种时刻屏幕上说的是"正在运行、点击可停止"——监听确实开着，
/// 但那一下点的是"恢复推送"，不是"停止监听"，两件事都被这一句糊掉了。
///
/// ⚠ 颜色、图标、文案都留在页面上（那是 UI 的决定），这里只回答"此刻是哪一态"。
/// ⚠ `pushActive == null` 是"没读到"，不是"暂停了"：把"我们没问"说成"用户暂停了"
///   与把它说成"没暂停"是同一类假话（T52 那本账分开的就是这两档）。
enum HomeServiceTone {
  /// 监听没在跑（红色，点它 = 启动监听）。
  stopped,

  /// 监听在跑、推送被暂停（橙色，点它 = 恢复推送，**不停监听**）。
  paused,

  /// 监听在跑、推送也开着（绿色，点它 = 停止监听）。
  listening,
}

/// [listening] 来自原生 `isMonitoringEnabled()`；[pushActive] 来自 `PushToggleManager.isPushActive()`，
/// 读不到时传 null。
HomeServiceTone homeServiceTone({required bool listening, bool? pushActive}) {
  if (!listening) return HomeServiceTone.stopped;
  if (pushActive == false) return HomeServiceTone.paused;
  return HomeServiceTone.listening;
}
