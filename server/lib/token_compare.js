'use strict';
// T187 片1：凭据比较的唯一作者。
//
// 为什么单开一份：`lib/routes/echo.js` 里原本有一份逐字节实现，而 `/metrics` 的 token 门
// 需要同一条规则。两处各写一份的代价不是重复六行，是**下一处新增 token 门的人两处都看不到**，
// 于是有人图省事写 `===` —— 那正好把计时探测口令的口子留在最不像认证入口的那条路上。
//
// 规则本身：长度不等直接 false（不比对，不给"猜对前缀更久"计时线索），
// 等长才走 timingSafeEqual 逐字节比。

const crypto = require('crypto');

/**
 * 常量时间比较两个凭据串。任一为空 ⇒ 不相等（空值不参与比较：
 * `timingSafeEqual` 对空 Buffer 会返回 true，而"没带 token"绝不能等于"带对了 token"）。
 */
function tokenMatches(actual, expected) {
  if (!actual || !expected) return false;
  const a = Buffer.from(String(actual));
  const b = Buffer.from(String(expected));
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

module.exports = { tokenMatches };
