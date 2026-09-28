// 公网面的请求体上限（#130-A3）。
//
// 为什么这是"限流之外"的另一件事：限流量的是**请求条数**，而一条请求可以多大是另一个维度 ——
// 验签比解析 JSON 贵，所以闸门必须排在解析之前？不，恰恰相反：**解析本身就是要防的成本**。
// 一发几百 MB 的 body 只需要攻击者花带宽，花掉的是服务端的内存与 CPU，而这一切发生在他
// 出示任何签名之前。所以这一档既不能按 IP 计（一个 IP 发一发大的就够了），也不能等验签后
// 再判（那时候已经解析完了）。
//
// 为什么单独挂、不与管理面共用那把 1 MB：
//  · 对公网面，1 MB 松了 16 倍 —— 而收紧它不会伤到任何合法客户端（上限的推导见契约
//    `limits._requestBodyMaxBytesWhy`，并由 test/architecture/fnthink_body_size_guard_test.dart
//    跨语言盯着原生侧最宽的正文上限）；
//  · 对管理面，备份导入就是要 1 MB 以上 —— 把公网的数硬套过去，症状是"用户的备份传不上来"。
//    两把尺子量的是两个方向不同的东西，只能分开。
//
// 数字只从契约读：实现里再写一个 1mb 就是第二份真值（上一片刚在限流上犯过这个错）。

'use strict';

const express = require('express');

const { statusCode, loadContract, assertSupported, shapeError } = require('./contract');

/// 从契约取公网面的字节上限。取不到就抛 —— 与 windowsFor 同一个口径：
/// 一份读不出数字的契约表，正确行为是这一档**不挂**并被 app.js 明说，而不是缺省成"不限"。
function bodyMaxBytes(src) {
  const v = src && src.limits ? src.limits.requestBodyMaxBytes : undefined;
  if (!Number.isInteger(v) || v < 4096) {
    throw shapeError(
      `limits.requestBodyMaxBytes 必须是 ≥4096 的整数（实际 ${v}）：` +
        '公网面没有体积上限时，攻击者花的只是带宽，花服务端的是内存与 CPU',
    );
  }
  return v;
}

/**
 * 返回一组挂在 `/api/fnthink` 上的中间件：解析 + 把"载荷读不出来"这一类错误按协议形状答复。
 *
 * ⚠ 这里顺手补了一个真实缺陷：改造前畸形 JSON 会冒到应用级 `errorMiddleware`，
 * 公网面上回的是管理面那套 `{code:-5, message:'Internal server error'}` + 500。
 * 同一份协议面上出现两套错误契约，客户端只能靠猜；而 500 会让设备端以为是自己坏了，
 * 于是退避重试 —— 一个永远不可能成功的请求被重试了三遍。
 */
function createFnthinkBodyLimit() {
  const contract = assertSupported(loadContract());
  const max = bodyMaxBytes(contract);
  const parser = express.json({ limit: max });
  const tooLarge = statusCode(contract, 'requestTooLarge');
  const badRequest = statusCode(contract, 'badRequest');
  const handler = (err, req, res, next) => {
    // body-parser 的错误都带 `entity.*` / `encoding.*` 的 type；其余错误原样上抛，
    // 本片不该顺手改掉别类错误的形状。
    const isPayloadProblem =
      err && typeof err.type === 'string' && /^(entity|encoding)\./.test(err.type);
    if (!isPayloadProblem) return next(err);
    if (err.type === 'entity.too.large') {
      // 也不区分"哪个字段太长"：身份都没证明之前，多说一个字都是给探测者送信息。
      return res.status(tooLarge).json({});
    }
    return res.status(badRequest).json({});
  };
  return { middlewares: [parser, handler], max, code: tooLarge, badCode: badRequest };
}

module.exports = { createFnthinkBodyLimit, bodyMaxBytes };
