'use strict';
// T09（维护者 2026-10-17 拍「加就行」）：token 门控的 echo 端点 ——
// 给「真发一次 15/15 盖章」里 generic 类型当**能看请求日志的收件方**。
//
// ⚠ 这是新增公网入面，两条纪律：
//  1. `ECHO_TOKEN` 没配 ⇒ 一律 404，与未知路由**同形**（调用方分不出"没有这条路"
//     和"有但没开"）—— 默认不存在比"存在但拒绝"更稳；
//  2. token 在**请求时**读 env（不缓存进模块），比对走 timingSafeEqual
//     （长度不同直接 false，等长才逐字节比，不给逐字探测留计时口子）。
//
// token 从请求头 `x-echo-token` 来（不进 URL ⇒ 不落 access log；T89 那条
// "口令不进日志"的同一取向）。回执里带回 body 预览与长度：盖章那一轮要的
// 就是"服务器到底收到了什么"，预览截在 500 字符 —— 足够看懂一条通知，
// 不会把一条大 payload 整个灌进日志。

const crypto = require('crypto');

const express = require('express');

const PREVIEW_MAX = 500;

function tokenMatches(actual, expected) {
  if (!actual || !expected) return false;
  const a = Buffer.from(String(actual));
  const b = Buffer.from(String(expected));
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function bodyTextOf(req) {
  // express.json 已在全局挂（app.js）：JSON 进来是对象；发不出合法 JSON 的
  // 调用方会落到 `{}`。两种都按"序列化回字符串"给预览 —— 盖章要看的是
  // 服务器视角的形状，不是客户端自称发了什么。
  if (typeof req.body === 'string') return req.body;
  if (req.body === undefined) return '';
  try {
    return JSON.stringify(req.body) ?? '';
  } catch (_) {
    return '';
  }
}

function createEchoRouter() {
  const router = express.Router();

  router.post('/', (req, res, next) => {
    const expected = process.env.ECHO_TOKEN;
    // 没配 ⇒ **不接**：next() 透传给应用的 404 —— 与未知路由逐字节同形，
    // 不是自造一个 404 体（那种"同状态码不同身杮"分得出来）。
    if (!expected) return next();
    const got = req.get('x-echo-token') || '';
    if (!tokenMatches(got, expected)) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    const body = bodyTextOf(req);
    // 这一行就是"能看请求日志"的落点：时间、来源、长度、预览，一行一条。
    console.log(
      `[echo] ${new Date().toISOString()} from=${req.ip} len=${body.length} ` +
        `body=${body.slice(0, PREVIEW_MAX)}`,
    );
    return res.status(200).json({
      ok: true,
      echo: {
        at: Date.now(),
        method: req.method,
        contentType: req.get('content-type') || '',
        bodyLength: body.length,
        bodyPreview: body.slice(0, PREVIEW_MAX),
        query: req.query,
      },
    });
  });

  return router;
}

module.exports = { createEchoRouter, PREVIEW_MAX };
