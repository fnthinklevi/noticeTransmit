'use strict';

// 幻念推送凭证（T26）· 服务端侧的跨端一致性测试。
// Dart 那一半在 packages/fnthink_push/test/vectors_test.dart，两边吃同一份
// protocol/fnthink-vectors-v1.json。期望值与摘要是**手写在向量文件里的**（见
// outputs/_fnthink_vectors_gen.py），不是从任何一端实现里跑出来的 —— 否则实现错了，
// 这份文件会跟着一起错，测试就只是给 bug 盖章。

const fs = require('fs');
const path = require('path');

const { CONTRACT_FILE, loadContract } = require('../lib/fnthink/contract');
const {
  VECTORS_FILE,
  STANDARD_ALPHABET,
  STANDARD_EXCLUDED,
  loadVectors,
  alphabetFromContract,
  lengthFromContract,
  normalize,
  isValidAddressCode,
  isValidPairingCode,
  credentialDigest,
} = require('../lib/fnthink/credentials');

const clone = (o) => JSON.parse(JSON.stringify(o));

describe('fnthink 凭证（服务端侧，与 Dart 共吃一份向量）', () => {
  const contract = loadContract();
  const vectors = loadVectors();

  test('读的是仓库根那两份文件，不是 server 里的副本', () => {
    expect(CONTRACT_FILE).toContain(path.join('protocol', 'fnthink-v1.json'));
    expect(CONTRACT_FILE).not.toContain(path.join('server', 'lib'));
    expect(fs.existsSync(VECTORS_FILE)).toBe(true);
    expect(VECTORS_FILE).toContain(path.join('protocol', 'fnthink-vectors-v1.json'));
  });

  test('逐条向量：归一化、合法性、摘要三项都要与期望一致（报错点名到 id）', () => {
    const alphabet = alphabetFromContract(contract);
    const bad = [];
    for (const c of vectors.cases) {
      const got = normalize(alphabet, c.input);
      const valid =
        c.kind === 'addressCode'
          ? isValidAddressCode(contract, c.input)
          : isValidPairingCode(contract, c.input);
      if (valid !== c.expect.valid || got !== c.expect.normalized) {
        bad.push(
          `${c.id}(${c.kind}) "${c.input}" → 合法=${valid}/归一化=${got}，` +
            `契约要求 合法=${c.expect.valid}/归一化=${c.expect.normalized}`,
        );
        continue;
      }
      if (!c.expect.valid) continue;
      const digest = credentialDigest(contract, c.kind, c.input);
      if (digest !== c.expect.digest) {
        bad.push(`${c.id} 摘要 ${digest} ≠ 向量 ${c.expect.digest}`);
      }
    }
    expect(bad).toEqual([]);
  });

  test('向量覆盖到位：两种凭证各自有正例，四个排除字符各挡一次', () => {
    const kinds = new Set(vectors.cases.map((c) => c.kind));
    expect(kinds).toEqual(new Set(['addressCode', 'pairingCode']));
    for (const kind of kinds) {
      expect(vectors.cases.some((c) => c.kind === kind && c.expect.valid)).toBe(true);
      expect(vectors.cases.some((c) => c.kind === kind && !c.expect.valid)).toBe(true);
    }
    for (const char of STANDARD_EXCLUDED) {
      const hit = vectors.cases.filter(
        (c) => !c.expect.valid && c.input.toUpperCase().includes(char),
      );
      expect(hit.length).toBeGreaterThan(0);
    }
  });

  test('位数只在契约里：改契约，判定跟着改（代码里没有第二份 18/20）', () => {
    const shrunk = clone(contract);
    shrunk.identity.addressCode.length = 17;
    expect(isValidAddressCode(shrunk, STANDARD_ALPHABET.slice(0, 17))).toBe(true);

    const grown = clone(contract);
    grown.identity.pairingCode.length = 21;
    expect(isValidPairingCode(grown, 'A'.repeat(21))).toBe(true);
  });

  test('契约位数缺失就抛，不补默认值', () => {
    const missing = clone(contract);
    delete missing.identity.addressCode.length;
    expect(() => lengthFromContract(missing, 'addressCode')).toThrow(
      /identity\.addressCode\.length/,
    );
    expect(() => isValidAddressCode(missing, 'A'.repeat(18))).toThrow(/不补默认位数/);
  });

  test('字母表或排除集与实现不符 ⇒ 拒绝工作（不照自己那份继续跑）', () => {
    const otherAlphabet = clone(contract);
    otherAlphabet.identity.addressCode.alphabet = 'base32-rfc4648';
    expect(() => alphabetFromContract(otherAlphabet)).toThrow(/crockford-base32/);

    const otherExcluded = clone(contract);
    otherExcluded.identity.addressCode.excludedChars = 'ILQU';
    expect(() => alphabetFromContract(otherExcluded)).toThrow(/排除集/);
  });

  test('同一凭证的不同书写形式是同一个值：摘要只认归一化后的字节', () => {
    const one = credentialDigest(contract, 'addressCode', '8K3FJ6QPTM9WZ4VHNS');
    expect(one).toBe(credentialDigest(contract, 'addressCode', '8k3f-j6qp tm9w-z4vhns'));
    expect(one).toHaveLength(64);
    expect(one).toBe(one.toLowerCase());
    // 差一个字符就完全是另一个值（否则"抄错一位还能配上对"就是漏洞）
    expect(credentialDigest(contract, 'addressCode', '8K3FJ6QPTM9WZ4VHNR')).not.toBe(one);
  });

  test('不合法的凭证拒绝计算摘要（空串会算出稳定摘要，那正是越权的入口）', () => {
    expect(() => credentialDigest(contract, 'pairingCode', 'ILOU-ILOU-ILOU-ILOU')).toThrow(
      /拒绝计算摘要/,
    );
    expect(() => credentialDigest(contract, 'addressCode', '')).toThrow(/18 位/);
    expect(() => credentialDigest(contract, 'addressCode', 'A'.repeat(20))).toThrow(/18 位/);
  });

  test('摘要算法与向量文件声明一致（sha256 / hex）', () => {
    expect(vectors.digest.algorithm).toBe('sha256');
    expect(vectors.digest.encoding).toBe('hex-lowercase');
  });
});
