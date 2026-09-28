// 幻念推送的突增告警读取口（#130-A4）。
//
// 为什么挂在管理面而不是公网面：这份列表回答的是"谁的额度快满了、谁已经被拦住、从什么时候开始"，
// 它本身就是一台定位用的探针 —— 公网可读等于给外人一份"这台服务器上哪些地址码活跃、每台跑在什么
// 节奏"的快照，而地址码虽然是公开标识，**它活跃与否**不是。管理面已经有会话 + 2FA + 限流 + IP 封锁
// 那一套，复用而不是另建一个信任根（本仓在 T35 那次已经定过同样的调子：不为省事给协议面新增签名方）。
//
// 为什么只有 GET、没有"清除/确认"按钮：这一层只负责"看见"，不负责"处置"。处置归 A5（一键冻结），
// 把两者合进一个口会让"打开列表"变成一次可被误点、可被 CSRF 的动作 —— 而误点一次冻结的代价是
// 一整个设备群失联，那比看漏一条告警严重得多。
//
// ⚠ 响应里的每一条都由 `anomaly.publicShape` 白名单挑字段：新加一个键就等于往管理面多端出去一个
//   字段，而告警条目离"正文"最近（它记的是哪个端点、哪个主体），绝不能顺手把请求体带进来。

const express = require('express');

const { asyncHandler, authMiddleware } = require('../middleware');
const { isContractAvailabilityError } = require('../fnthink/contract');
const { sharedTracker } = require('../fnthink/anomaly');

const router = express.Router();

// 突增告警列表（内存环，不落盘）
router.get(
  '/fnthink/alerts',
  authMiddleware,
  asyncHandler(async (req, res) => {
    // ⚠ 告警环要读契约（四个数只从那里来），所以它是**首请求**才建的：契约文件不在、或内容不达标时
    //   这里必须答成与协议面同一套 503，而不是冒到 errorMiddleware 变成 500 —— 诊断口在"协议面
    //   起不来"的时刻恰恰最有用，它自己不能再变成一种新的看不懂。
    let tracker;
    try {
      tracker = sharedTracker();
    } catch (e) {
      if (!isContractAvailabilityError(e)) throw e;
      return res.status(503).json({ error: 'fnthink_protocol_unavailable' });
    }
    return res.json({
      code: 0,
      message: 'success',
      data: {
        generatedAt: Date.now(),
        // 运维读这份列表时必须知道它有多长记忆：这一段按契约 persistToDisk=false 只活在本进程里，
        // 重启即空。所以"空列表"的含义是"这个进程起来以后没发生过"，不是"没有异常" —— 这两句话在
        // 排障时是完全不同的结论，故把口径随数据一起给出，而不是写在文档里等人想起来查。
        persisted: false,
        nearQuotaRatio: tracker.alerts.nearQuotaRatio,
        cooldownSeconds: Math.round(tracker.alerts.cooldownMs / 1000),
        maxActiveAlerts: tracker.alerts.maxActiveAlerts,
        count: tracker.size(),
        alerts: tracker.recent(),
      },
    });
  }),
);

module.exports = router;
