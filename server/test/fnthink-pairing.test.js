'use strict';

// 幻念推送配对载荷（T28-A）· 服务端侧。Dart 那一半在 packages/fnthink_push/test/pairing_test.dart，
// 两边吃同一份 protocol/fnthink-vectors-v1.json 的 payloads 段 —— 连 reason 字符串都要一样。

const { loadContract } = require('../lib/fnthink/contract');
const { loadVectors } = require('../lib/fnthink/credentials');
const {
  qrPrefix,
  payloadFields,
  buildPairingPayload,
  parsePairingPayload,
} = require('../lib/fnthink/pairing');

const clone = (o) => JSON.parse(JSON.stringify(o));

describe('fnthink 配对载荷（服务端侧，与 Dart 共吃一份向量）', () => {
  const contract = loadContract();
  const vectors = loadVectors();
  const cases = vectors.payloads;

  test('读的是仓库根那一份向量，前缀与契约一致', () => {
    expect(vectors.payloads.length).toBeGreaterThan(0);
    expect(qrPrefix(contract)).toBe('fnthink-push://pair');
    expect(cases[0].payload.startsWith(`${qrPrefix(contract)}?`)).toBe(true);
  });

  test('逐条：ok / reason / 解析结果三项都要与期望一致（点名到 id）', () => {
    const bad = [];
    for (const c of cases) {
      const got = parsePairingPayload(contract, c.payload);
      if (got.ok !== c.expect.ok || (got.reason || null) !== (c.expect.reason || null)) {
        bad.push(
          `${c.id} → ok=${got.ok}/reason=${got.reason || 'null'}，` +
            `期望 ok=${c.expect.ok}/reason=${c.expect.reason || 'null'}`,
        );
        continue;
      }
      if (!got.ok) continue;
      const want = c.expect.request;
      if (
        got.request.v !== want.v ||
        got.request.to !== want.to ||
        got.request.code !== want.code ||
        got.request.level !== want.level
      ) {
        bad.push(`${c.id} 解析出 ${JSON.stringify(got.request)}，期望 ${JSON.stringify(want)}`);
      }
    }
    expect(bad).toEqual([]);
  });

  test('reason 词表被向量覆盖全（新增一种拒绝却没用例 ⇒ 红）', () => {
    const vocabulary = [
      'prefix',
      'empty',
      'shape:to',
      'repeat:code',
      'unknown:foo',
      'carries-secret:signature',
      'carries-secret:privateKey',
      'missing:code',
      'version:2',
      'version-unparseable',
      'address-code',
      'pairing-code',
      'level:L9',
    ];
    const seen = cases.filter((c) => !c.expect.ok).map((c) => c.expect.reason);
    for (const reason of vocabulary) {
      expect(seen).toContain(reason);
    }
  });

  test('拼出来的文本再解一次回到同一个请求，且文本恒为规范形态', () => {
    for (const c of cases) {
      if (!c.expect.ok) continue;
      const req = c.expect.request;
      const built = buildPairingPayload(contract, req);
      expect(parsePairingPayload(contract, built).request).toEqual(req);
      expect(built).toBe(
        `${qrPrefix(contract)}?v=${req.v}&to=${req.to}&code=${req.code}&level=${req.level}`,
      );
    }
  });

  test('字段顺序只在契约里：改契约，产出跟着变', () => {
    const reordered = clone(contract);
    reordered.pairing.payloadFields = ['level', 'code', 'to', 'v'];
    const req = cases[0].expect.request;
    expect(buildPairingPayload(reordered, req)).toContain('?level=L1&code=');
    expect(payloadFields(reordered)).toEqual(['level', 'code', 'to', 'v']);
  });

  test('契约缺 rejectUnknownFields ⇒ 抛，不补默认值', () => {
    const missing = clone(contract);
    delete missing.pairing.rejectUnknownFields;
    expect(() => parsePairingPayload(missing, cases[0].payload)).toThrow(/rejectUnknownFields/);
  });

  test('非法载荷不许被拼出来（两端各自产出的码必须自己先认）', () => {
    expect(() =>
      buildPairingPayload(contract, { v: 1, to: 'ILOU', code: 'x', level: 'L1' }),
    ).toThrow(/地址码不合法/);
    expect(() =>
      buildPairingPayload(contract, { v: 1, to: '8K3FJ6QPTM9WZ4VHNS', code: '7YD4', level: 'L1' }),
    ).toThrow(/配对口令不合法/);
    expect(() =>
      buildPairingPayload(contract, {
        v: 1,
        to: '8K3FJ6QPTM9WZ4VHNS',
        code: '7YD4RKQPBM8XZ3VHNT6J',
        level: 'L9',
      }),
    ).toThrow(/不在契约/);
    expect(() =>
      buildPairingPayload(contract, {
        v: 9,
        to: '8K3FJ6QPTM9WZ4VHNS',
        code: '7YD4RKQPBM8XZ3VHNT6J',
        level: 'L1',
      }),
    ).not.toThrow(); // 版本由**接收端**比对，拼的一方只负责带上
  });

  test('解析不抛异常：所有非法输入都返回 {ok:false}（原因只进日志，不进用户文案）', () => {
    for (const junk of ['', null, undefined, 'fnthink-push://pair?', 'x=y', 'a'.repeat(500)]) {
      expect(() => parsePairingPayload(contract, junk)).not.toThrow();
      expect(parsePairingPayload(contract, junk).ok).toBe(false);
    }
  });
});
