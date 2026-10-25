// T185 第二步：SSE 门铃的**一次性短票**。
//
// 为什么不是签名 GET：签名载荷是固定六键、签名只覆盖 fields（`signature.canonicalOrder`），
// 把它挂进 URL 会进访问日志；而 `EventSource` 又带不了自定义头。所以走票：
//   ① 设备用**普通的 /poll**（带 `ticketRequestHeader`）换一张短票；
//   ② 拿 `ticketHeader` 去 GET /stream；服务端核票、删票、把连接绑到那台设备。
// 票只活 `ticketTtlSeconds`、只用一次、只绑一台设备；服务重启后自然全失效。
//
// ⚠ 这是**进程内**的表：单实例部署成立（与 waiters.js 同一条限制）。将来横向扩，
//   票与订阅都要换成跨进程存储，否则 A 进程发的票到 B 进程连不上。

'use strict';

const crypto = require('crypto');

/// token → { device, expiresAt }
const tickets = new Map();
/// 上限只是防一次内存泄漏，不是协议的一部分。
const TICKET_CAP = 4096;

function prune(now) {
  for (const [token, row] of tickets) {
    if (row.expiresAt <= now) tickets.delete(token);
  }
}

/// 发一张票。ttlMs <= 0 / 设备为空时返回 null（宁可不发，也不发一张永不过期的票）。
function issueTicket(device, ttlMs, now = Date.now()) {
  const key = String(device === undefined || device === null ? '' : device);
  const ttl = Math.floor(Number(ttlMs) || 0);
  if (key === '' || ttl <= 0) return null;
  prune(now);
  // 先 prune 再按上限挤：表里最老的那张先走（Map 的插入顺序就是发放顺序）。
  while (tickets.size >= TICKET_CAP) {
    const oldest = tickets.keys().next().value;
    if (oldest === undefined) break;
    tickets.delete(oldest);
  }
  const token = crypto.randomBytes(24).toString('base64url');
  tickets.set(token, { device: key, expiresAt: now + ttl });
  return token;
}

/// 核票并**立刻删掉**（一次性）。无效 / 过期 / 已用过一律返回 null —— 三种对外同形。
function consumeTicket(token, now = Date.now()) {
  const key = String(token === undefined || token === null ? '' : token);
  if (key === '') return null;
  const row = tickets.get(key);
  if (!row) return null;
  tickets.delete(key);
  if (row.expiresAt <= now) return null;
  return row.device;
}

/// 当前票数（测试用）。
function ticketCount() {
  return tickets.size;
}

module.exports = { issueTicket, consumeTicket, ticketCount };
