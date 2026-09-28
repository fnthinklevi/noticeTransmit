// 设备表上限走真实 HTTP 的那一条（#131 第二片 2B）。
//
// ⚠ 为什么单独一个文件，而不是塞进 fnthink-routes.test.js 里 mutate 那份契约：
//   上一版在这里写的是 `require('../lib/fnthink/routes').contract.limits.devicesMax = N`，
//   DBG 打印确认值改到了（cap=7、表里 7 行、新码也不在那 7 行里），HTTP 却仍回 200 ——
//   也就是 jest 里"我 require 到的那份 contract"与"app.js 挂上去的那份"不是同一个对象
//   （本仓在 Windows 上工作，盘符大小写在解析路径里出现过两种形态，那是这类双实例的常见成因）。
//   与其去追一个测试框架里的实例同一性，不如让**服务端自己加载一份小上限的契约**：
//   `FNTHINK_CONTRACT` 这个口子本来就是为"部署时契约不在仓库根"留的，这里复用它。
//   复制的那份只改一个数（devicesMax），其它一律逐字取自真契约 —— 它是一次夹具，不是第二份协议。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-cap-'));
const REAL_CONTRACT = path.resolve(__dirname, '..', '..', 'protocol', 'fnthink-v1.json');
const real = JSON.parse(fs.readFileSync(REAL_CONTRACT, 'utf8'));

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = path.join(TMP, 'data');
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-cap', 10);
process.env.ENCRYPTION_KEY = 'a'.repeat(64);
process.env.RATE_LIMIT_GENERAL_MAX = '100000';
process.env.RATE_LIMIT_AUTH_MAX = '100000';
process.env.RATE_LIMIT_FNTHINK_MAX = '100000'; // 本文件测的是**设备表上限**，不是 IP 额度
process.env.TRUST_PROXY = '1';

// 上限设成 2：beforeAll 之后表里正好能容下前两台，第三台就该被拒。
const capped = JSON.parse(JSON.stringify(real));
capped.limits.devicesMax = 2;
const CONTRACT_COPY = path.join(TMP, 'fnthink-v1-cap.json');
fs.writeFileSync(CONTRACT_COPY, JSON.stringify(capped, null, 2), 'utf8');
process.env.FNTHINK_CONTRACT = CONTRACT_COPY;

const request = require('supertest');
const app = require('../lib/app');
const store = require('../lib/store');
const devicestore = require('../lib/fnthink/devicestore');
const {
  loadContract,
  assertSupported,
  canonicalOrder,
  statusCode,
} = require('../lib/fnthink/contract');

const contract = assertSupported(loadContract());

function keypair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { rawBase64: der.subarray(der.length - 32).toString('base64'), privateKey };
}

function registerBody(addressCode, kp, name) {
  const fields = {
    version: '1',
    type: contract.clientEvents.register.messageType,
    target: addressCode,
    ts: String(Math.floor(Date.now() / 1000)),
    nonce: 'cap-' + crypto.randomBytes(6).toString('hex'),
    body: '',
  };
  const map = {};
  for (const key of canonicalOrder(contract)) map[key] = fields[key];
  const canonical = require('../lib/fnthink/verify').canonicalBytes(contract, map);
  return {
    sender: addressCode,
    publicKey: kp.rawBase64,
    name: name || '上限用例',
    signature: crypto.sign(null, canonical, kp.privateKey).toString('base64'),
    fields: map,
  };
}

const FIRST = '2CF4GHJKMNPQRSTVWX';
const SECOND = '3D4GHJKMNPQRSTVWX9';
const THIRD = '4E5GHJKMNPQRSTVWX9';
// FIRST 那台的密钥必须在"刷新自己那一行"那条用例里还能签名用 ——
// 所以它是模块级的：上一版在这里现造一把新钥匙、却把表里那把公钥抄进请求，
// 结果是**签名对不上**（403），测的根本不是"满表下的幂等更新"。
const firstKey = keypair();
const secondKey = keypair();

test('这份夹具是真契约的副本，只改了 devicesMax 这一个数', () => {
  expect(contract.limits.devicesMax).toBe(2);
  expect(real.limits.devicesMax).toBeGreaterThan(2);
  const withoutCap = JSON.parse(JSON.stringify(capped));
  withoutCap.limits.devicesMax = real.limits.devicesMax;
  expect(JSON.stringify(withoutCap)).toBe(JSON.stringify(real));
});

test('满表之前一切正常：两台都登记得上，第二台之后表里就是两行', async () => {
  await request(app).post('/api/fnthink/register').send(registerBody(FIRST, firstKey)).expect(200);
  await request(app)
    .post('/api/fnthink/register')
    .send(registerBody(SECOND, secondKey))
    .expect(200);
  expect(Object.keys(devicestore.loadDevices()).length).toBe(2);
});

test('第三台 ⇒ 429 + 空正文，且表里没有它、也没覆盖任何已有记录', async () => {
  const before = JSON.stringify(devicestore.loadDevices());
  const thirdKey = keypair();
  const res = await request(app).post('/api/fnthink/register').send(registerBody(THIRD, thirdKey));
  expect(res.status).toBe(statusCode(contract, 'rateLimited'));
  // 正文是空的：429 不透露任何身份信息，与限流器那一份形状一致。
  expect(res.body).toEqual({});
  const after = devicestore.loadDevices();
  expect(after[THIRD]).toBeUndefined();
  expect(Object.keys(after).length).toBe(2);
  // 已有记录逐字未动（"到上限就覆盖一条"是最坏的那种"降级"）：
  // 只比公钥与名称 —— createdAt/lastSeenAt 这类时间戳本来就会因别的写入而动。
  const beforeParsed = JSON.parse(before);
  for (const code of Object.keys(beforeParsed)) {
    expect(after[code].publicKey).toBe(beforeParsed[code].publicKey);
    expect(after[code].name).toBe(beforeParsed[code].name);
  }
});

test('满了不影响已登记的设备刷新自己那一行（不然表一满，现网设备连改名都做不了）', async () => {
  // 同一把钥匙再登记一次 = 幂等更新；换钥匙那条路是"静默替换"，会被拒（另一条用例已钉）。
  const res = await request(app)
    .post('/api/fnthink/register')
    .send(registerBody(FIRST, firstKey, '改个名字'));
  expect(res.status).toBe(200);
  expect(res.body.name).toBe('改个名字');
  expect(Object.keys(devicestore.loadDevices()).length).toBe(2);
});

test('上限这条只在 devicestore 判一次（路由不自己数行 ⇒ 没有第二份判据）', () => {
  const routes = fs.readFileSync(path.join(__dirname, '../lib/fnthink/routes.js'), 'utf8');
  const storeSrc = fs.readFileSync(path.join(__dirname, '../lib/fnthink/devicestore.js'), 'utf8');
  expect(storeSrc).toMatch(/devicesMax/);
  // 路由只认那枚 code；自己数行数、自己比上限就是第二份判据。
  expect(routes).not.toMatch(/Object\.keys\((state\.)?devices\)\.length\s*>=/);
  expect(routes).toMatch(/DEVICE_CAP_CODE/);
});

afterAll(() => {
  // 这份契约副本与数据目录是本文件造的临时物；清掉，免得下次读到一份 devicesMax=2 的旧夹具。
  for (const f of [CONTRACT_COPY]) {
    if (fs.existsSync(f)) fs.rmSync(f);
  }
});
