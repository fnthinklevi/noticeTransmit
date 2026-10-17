'use strict';

/**
 * T155：客户端契约版本的**关联键收件箱**（`contractVersion` ↔ 服务器那份）。
 *
 * ⚠ 契约 `versionEcho._whySeparateModule` 记的就是这个文件为什么独立。
 *
 * ## 为什么单独一个文件，而不是放在 `fnthink/routes.js` 里让 `/health` 去 require 它
 *
 * ⚠⚠ **这一条是被一个真实回归逼出来的形状，不是洁癖**：
 * 第一版把那一格放在 `fnthink/routes.js`，`lib/routes/version.js` 去 require 它。
 * 后果：`routes.js` 的**模块顶层**就会构造 `createSenderQuota()`，而那一构造要读
 * 契约的 `alerts` 段 —— 于是「只上传了 server/、protocol/ 还是上一批那份」那种部署下，
 * `version.js` 在 `app.js` 那道 `try/catch` **之外**被加载时直接抛，
 * **`/health` 与整个更新面一起崩在启动**。
 *
 * 那正是 `test/fnthink-contract-shape.test.js` 钉住的口径（A1 那次事故的修复）：
 * 契约不达标时**只降级协议面**，更新面与管理后台必须照常活着。
 * 第一版那个接法把那道降级机制**从背后绕过去了** —— 降级代码还在，只是没人跑得到它。
 *
 * ## 这一格因此的三条纪律
 *
 * 1. **不 require 任何会读契约其它段的东西**：这个模块只有内存里的一个变量，
 *    没有 fs、没有 `assertSupported`、没有限流器。契约读不动时它照样能加载。
 * 2. **不落盘**：它答的是"此刻这台服务器见到的是什么"，不是账本。
 *    落盘会把「三天前有一台旧客户端来过」读成「现在不一致」。
 * 3. **判据在 `fnthink/contract` 里**：这里只存结果。
 *    复制一份判据就是"不一致"的第二个作者，两份各判各的必然漂开。
 */

/** 收到过带版本的请求之后的最后一次比对结论。没收到过时是 `null`。 */
let lastSeen = null;

/**
 * 记一次比对结论。**由 `fnthink/routes` 的入口中间件调用**，不散进各 handler
 * ——散进去会漏掉某一条路，而"漏掉的那条路恰好不打这个标记"与"没有不一致"
 * 在 `/health` 上长得一模一样。
 *
 * @param {'match'|'mismatch'|'unreadable'} verdict 由 `compareClientContractVersion` 判
 * @param {unknown} value 客户端报上来的那个原值（回显用，`/health` 不直接吐它）
 */
function note(verdict, value) {
  lastSeen = { verdict, value };
  return lastSeen;
}

/**
 * `/health` 上那一格读它。
 *
 * ⚠ **没收到过时回 `null` 而不是 `false`**：「还没见过任何带版本的请求」与
 * 「见过且一致」是两件事；折成 `false` 就与「见过且不一致」同形了 ——
 * 而这一格存在的全部意义就是让那三件事互相分得开。
 * ⚠ 只回 `verdict`，**不把 `value` 原样吐出去**：那是客户端自报的东西，
 *   回显它等于让 `/health` 变成一个可以往响应里塞任意类型的口。
 */
function read() {
  return lastSeen === null ? null : { verdict: lastSeen.verdict };
}

/** 只给测试用：把这一格恢复到"没收到过"。生产代码不许调它。 */
function reset() {
  lastSeen = null;
}

module.exports = { note, read, reset };
