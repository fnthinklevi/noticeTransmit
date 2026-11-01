'use strict';
/**
 * T187 片2：幻念协议面的**业务读数** —— 投递状态机四态、队列深度、SSE 连接数、
 * 长轮询 hold 数。与片1 的进程/HTTP/安全三族同住一份 exposition。
 *
 * 两条边界：
 *  1. 标签基数由契约说了算：状态名取自 `delivery.states`（封闭词表），不按设备/端点/地址码
 *     分——那三类都会让一条时间序列随用户数增长，而地址码恰好是隐私红线。
 *  2. 这一层**只读**：不碰消息正文、不写任何表、不改变投递语义。队列深度是抓取那一刻
 *     数一遍盘上的状态，属于"观测"，不是新的状态存法（状态机仍只有 `delivery.advance`
 *     一个入口）。
 *
 * ⚠ 注册失败不许拖垮协议面：`app.js` 在 fnthink 那段自己的 try/catch 里调用，
 * 契约读不到时协议本来就已降级，指标家族跟着缺席是第二句话，不是第二个故障。
 */

const metrics = require('../metrics');
const { assertSupported, loadContract } = require('./contract');
const messagestore = require('./messagestore');
const waiters = require('./waiters');

let registered = false;

function register() {
  if (registered) return;
  registered = true;
  const contract = assertSupported(loadContract());

  // 封闭词表先播种 0：缺序列在 PromQL 里是"没有这条线"而不是 0，告警规则要写 absent() 才不瞎。
  for (const state of contract.delivery.states || []) {
    metrics.fnthink.deliveryTransitions.inc({ to: state }, 0);
  }

  metrics.collectorGauge(
    'notice_fnthink_queue_depth',
    {
      help: 'Messages currently waiting in each pollable delivery state (contract delivery.pollableStates).',
      labelNames: ['state'],
    },
    () => {
      // 每次抓取现读：服务端本来就是"请求进来读表、写完落盘"，这里不新增缓存层，
      // 也就不会出现"指标看着有货、poll 取不到"的第二份真值。
      const table = messagestore.loadMessages();
      const pollable = Array.isArray(contract.delivery.pollableStates)
        ? contract.delivery.pollableStates
        : [];
      return pollable.map((state) => ({
        labels: { state },
        value: Object.values(table).filter((m) => m && m.state === state).length,
      }));
    },
  );

  metrics.collectorGauge(
    'notice_fnthink_sse_connections',
    { help: 'SSE doorbell subscribers currently open in this process.' },
    () => waiters.subscriberCount(),
  );

  metrics.collectorGauge(
    'notice_fnthink_long_poll_holds',
    { help: 'Requests currently held by long polling in this process.' },
    () => waiters.pendingWaiterCount(),
  );
}

module.exports = { register };
