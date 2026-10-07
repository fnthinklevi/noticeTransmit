'use strict';

// 幻念推送协议契约（T71）· 服务端这一半的契约测试。
// Dart 那一半在 packages/fnthink_push/test/contract_test.dart。
// 两边读同一个 protocol/fnthink-v1.json，各自钉一遍同样的事：
// 任何一侧把常量或路径改掉，这里就红 —— 而不是等到线上两端行为不一致才发现。

const fs = require('fs');
const path = require('path');

const {
  SUPPORTED_MAJOR,
  CONTRACT_FILE,
  loadContract,
  assertSupported,
  statusCodes,
  statusCode,
  isReceipt,
  canonicalOrder,
  aliasesFor,
  pickField,
  onlineThresholdMs,
} = require('../lib/fnthink/contract');

describe('fnthink 协议契约（服务端侧）', () => {
  const c = loadContract();

  test('读的是仓库根那一份契约，不是 server 里的副本', () => {
    expect(fs.existsSync(CONTRACT_FILE)).toBe(true);
    expect(CONTRACT_FILE).not.toContain(path.join('server', 'lib'));
    expect(CONTRACT_FILE.endsWith(path.join('protocol', 'fnthink-v1.json'))).toBe(true);
  });

  test('版本闸门：名字里的 v 号、contractVersion、本模块 major 三者一致', () => {
    expect(c.protocol).toBe('fnthink-v1');
    expect(c.contractVersion).toBe(SUPPORTED_MAJOR);
    expect(() => assertSupported(c)).not.toThrow();
  });

  test('版本不一致时拒绝解释，而不是半懂不懂地跑', () => {
    expect(() => assertSupported({ ...c, contractVersion: 2 })).toThrow(/contractVersion/);
    expect(() => assertSupported({ ...c, protocol: 'fnthinkV1' })).toThrow(/fnthink-v<N>/);
    // v2 的表交给 v2 的实现去解释：这里只允许"原样返回"或"抛错"，不许半懂不懂地跑通
    const v2 = { ...c, protocol: 'fnthink-v2', contractVersion: 2 };
    expect(() => assertSupported(v2)).toThrow(/只实现到 v/);
  });

  test('签名规范化顺序与 Dart 侧逐字段相同（换序就是换签名）', () => {
    expect(canonicalOrder(c)).toEqual(['version', 'type', 'target', 'ts', 'nonce', 'body']);
    expect(c.signature.timestampSource).toBe('serverTime');
    expect(c.signature.trustLocalClock).toBe(false);
  });

  test('同步状态码表；未知名字要抛而不是回 500', () => {
    expect(statusCodes(c)).toEqual({
      queued: 202,
      unauthorized: 401,
      forbidden: 403,
      duplicate: 409,
      expired: 410,
      rateLimited: 429,
      // #130-A3：载荷读不出来时的两种协议形状（太大 / 畸形），都是空 body、都不带 receipt
      requestTooLarge: 413,
      badRequest: 400,
    });
    expect(statusCode(c, 'queued')).toBe(202);
    expect(() => statusCode(c, 'teapot')).toThrow(/契约文件/);
    // 口令错误与端点不存在必须同形：否则响应码本身能枚举端点
    expect(c.statusCodes.indistinguishable).toEqual(
      expect.arrayContaining(['unauthorized', 'notFoundEndpoint']),
    );
  });

  test('八种异步回执都在表里，表外的一律不认', () => {
    for (const name of [
      'delivered',
      'displayed',
      'waiting_online',
      'expired',
      'dropped',
      'rejected_unsigned',
      'rejected_capability',
      'failed_action',
    ]) {
      expect(isReceipt(c, name)).toBe(true);
    }
    expect(isReceipt(c, 'delivered_but_maybe')).toBe(false);
  });

  test('字段容错：按别名顺序取第一个非空，多余字段忽略', () => {
    expect(aliasesFor(c, 'title')[0]).toBe('title');
    expect(pickField(c, 'title', { title: '甲', message: '乙' })).toBe('甲');
    expect(pickField(c, 'title', { message: '乙', text: '丙' })).toBe('乙');
    expect(pickField(c, 'title', { title: '   ', msg: '丁' })).toBe('丁');
    expect(pickField(c, 'body', { content: '正文', description: '另一段' })).toBe('正文');
    expect(pickField(c, 'title', { unrelated: 'x' })).toBe('');
    expect(pickField(c, 'title', {})).toBe('');
    expect(pickField(c, 'title', null)).toBe('');
  });

  // T99：别名表扩到"嵌一层的形状"，配套那条实现判据（对象/数组值跳过）在这里钉住。
  // 旧实现把顶层那个 `text` 对象 `String()` 成 `[object Object]`，而 intake 那道闸是
  // "标题正文都空才拒" ⇒ 粘钉钉/企业微信形状会发出一条标题是乱码的通知，且不报错。
  test('字段容错：别名支持点分路径，对象与数组值一律跳过而不是变成 [object Object]', () => {
    expect(pickField(c, 'body', { msgtype: 'text', text: { content: 'CPU 92%' } })).toBe('CPU 92%');
    expect(pickField(c, 'body', { msg_type: 'text', content: { text: '构建失败' } })).toBe(
      '构建失败',
    );
    expect(pickField(c, 'body', { title: 'NAS', data: { content: '备份完成' } })).toBe('备份完成');
    // 标题位上是个对象 ⇒ 跳过它继续往下找别名，不把容器当值。
    expect(pickField(c, 'title', { title: { x: 1 }, message: '甲' })).toBe('甲');
    for (const payload of [
      { msgtype: 'text', text: { content: '甲' } },
      { msg_type: 'text', content: { text: '乙' } },
      { title: { x: 1 }, body: '丙' },
      { title: ['丁'], body: '戊' },
    ]) {
      const wire = pickField(c, 'title', payload) + pickField(c, 'body', payload);
      expect(wire).not.toContain('object Object');
    }
    // own property 纪律：载荷里出现 constructor 也不许顺着原型链摸值。
    expect(pickField(c, 'title', JSON.parse('{"text":{"constructor":{}}}'))).toBe('');
    // 同一纪律的**可观察**那一半：把别名换成原型链上的键（真实别名表里不会，但
    // readAliasPath 的写法对任何别名表都成立），弱写法会摸到 Object.prototype 上去。
    expect(pickField({ fieldTolerance: { title: ['constructor', 'toString'] } }, 'title', {})).toBe(
      '',
    );
    // 数字与布尔照旧转字符串 —— 它们不是容器，这一档行为与改动前一致。
    expect(pickField(c, 'title', { subject: 404 })).toBe('404');
  });

  test('在线阈值 = 3 × 拉取间隔（poll 即心跳，不另设协议）', () => {
    expect(onlineThresholdMs(c)).toBe(60000);
    expect(onlineThresholdMs(c, 30)).toBe(90000);
    expect(c.presence.separateHeartbeatProtocol).toBe(false);
    // T88：常态下界被压到 5s、与提频档同值 ⇒ 这里判的是"不许比常态更慢"，等号放行。
    // 真正要拦住的是倒挂（提频比常态还快不起来），而不是相等；Dart 侧 contract.dart 的
    // 两处校验同一口径。
    expect(c.presence.burstWhenPending.intervalSeconds).toBeLessThanOrEqual(
      c.presence.pollIntervalSeconds.min,
    );
  });

  test('红线：端点只产 L1、L3 默认全关且不可免确认、私钥不可导出', () => {
    expect(c.capabilities.levels[0]).toBe('L1');
    expect(c.capabilities.endpointMaxLevel).toBe('L1');
    expect(c.capabilities.l3.default).toBe('off');
    expect(c.capabilities.l3.allowSkipConfirm).toBe(false);
    expect(c.capabilities.l3.unknownAction).toBe('reject');
    expect(c.capabilities.l3.noKeyValueGenericWrite).toBe(true);
    expect(c.identity.identityKey.privateKeyExportable).toBe(false);
    expect(c.identity.identityKey.neverIn).toEqual(expect.arrayContaining(['url', 'log']));
    expect(c.identity.pairingCode.singleUse).toBe(true);
    expect(c.identity.pairingCode.derivedFromDeviceIdentity).toBe(false);
  });

  test('红线：端点长期口令是秘密、可比配对口令更长、可轮换（T27 存储按此校验）', () => {
    const ep = c.identity.endpointSecret;
    expect(ep.public).toBe(false);
    expect(ep.singleUse).toBe(false);
    expect(ep.rotatable).toBe(true);
    expect(ep.derivedFromDeviceIdentity).toBe(false);
    expect(ep.length).toBeGreaterThanOrEqual(c.identity.pairingCode.length);
  });

  test('留存与投递：delivered 与 expired 都删正文；ack 是唯一送达依据', () => {
    expect(c.retention.deleteBodyOn).toEqual(expect.arrayContaining(['delivered', 'expired']));
    expect(c.retention.whilePending).toBe('static_encrypted');
    expect(c.delivery.ackIsOnlyProof).toBe(true);
    expect(c.delivery.senderPollsStatusEndpoint).toBe(false);
    expect(c.waitingOnline.mutuallyExclusive).toBe(true);
    expect(c.transport.httpsOnly).toBe(true);
    expect(c.transport.secretPlacement).toBe('path_segment');
  });
});
