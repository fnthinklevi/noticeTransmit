// #138 T39 + T40 + T41：端点收单（两种形态、字段容错、配额、能力边界、日志脱敏）。
//
// 这一片真正要守的五件事：
//  ① **不存在的端点 / 口令错 / IP 不在白名单三者逐字节同形** —— 否则这一面是枚举器；
//  ② **配额只在口令验过之后记** —— 按未验证的 endpointId 计额是 DoS 转移；
//  ③ **能力边界只到 L1**，且拒绝时不产生任何消息；
//  ④ **载荷超限是 400，不是静默截断**（"不静默丢"那一半）；
//  ⑤ 长期口令**不出现在 kind、日志与响应**里（路径段 + 脱敏规则盖不住 = 把口令送给别人）。
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');

process.env.NODE_ENV = 'test';
process.env.PORT = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-fnthink-ing-'));
// `lib/store.js` 在没有 ADMIN_TOKEN_HASH 时直接 `process.exit(1)`，而 `lib/app.js` 会 dotenv 吃到本机
// `.env` ⇒ 只在"没有 .env 的机器上"（CI）才炸，且炸的是整个 worker（jest 只报 child process exceptions）。
// 与其余 15 个套件一致：自带一份哈希，不吃环境。
process.env.ADMIN_TOKEN_HASH = bcrypt.hashSync('test-admin-token-for-intake', 10);
// 正文是加密落盘的，用例要解密回来断言 ⇒ 密钥必须固定（不吃本机 .env，否则这条用例在
// 别人机器上解不开，看起来像"产品缺陷"而不是"桩没配好"）。
process.env.ENCRYPTION_KEY = 'b'.repeat(64);
// supertest 打的是本机 http；HTTPS-only 默认会拒掉一切 —— 这一组默认开逃生阀，
// 并单独有一条用例验证"没开时确实拒"。
process.env.FNTHINK_ALLOW_INSECURE_ENDPOINT = '1';

const request = require('supertest');
const app = require('../lib/app');
const { loadContract, assertSupported, statusCode } = require('../lib/fnthink/contract');
const ds = require('../lib/fnthink/devicestore');
const ms = require('../lib/fnthink/messagestore');
const intake = require('../lib/fnthink/endpointintake');
const capabilities = require('../lib/fnthink/capabilities');
const { endpointKindOf } = require('../lib/fnthink/ratelimit');

const contract = assertSupported(loadContract());
const ingress = intake.ingressFromContract(contract);
const status = statusCode(contract, 'queued');
const OWNER = '8K3FJ6QPTM9WZ4VHNS';

function publicKey() {
  const { publicKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return der.subarray(der.length - 32).toString('base64');
}

let endpoint = null; // {id, secret}：允许 GET 的那个（显式关掉 postOnly）
let strict = null; // 只收 POST 的那个（postOnly 的缺省值）

function resetTable() {
  const devices = ds.loadDevices();
  ds.registerDevice(
    contract,
    devices,
    { addressCode: OWNER, publicKey: publicKey(), name: '本机' },
    Date.now(),
  );
  ds.saveDevices(devices);
  const endpoints = ds.loadEndpoints();
  endpoint = ds.createEndpoint(
    contract,
    endpoints,
    { owner: OWNER, name: 'NAS', postOnly: false },
    Date.now(),
  );
  strict = ds.createEndpoint(contract, endpoints, { owner: OWNER, name: '仅 POST' }, Date.now());
  // 缺省方向本身要钉住：契约 transport.postOnlySwitch=true ⇒ 新建端点就是"只收 POST"
  expect(endpoints[strict.id].postOnly).toBe(true);
}

const getPath = (secret = null, extra = '') =>
  `/api/fnthink/p/${endpoint.id}/${secret === null ? endpoint.secret : secret}${extra}`;
const postPath = () => `/api/fnthink/p/${endpoint.id}`;
const strictGetPath = (extra = '') => `/api/fnthink/p/${strict.id}/${strict.secret}${extra}`;
const strictPostPath = () => `/api/fnthink/p/${strict.id}`;
const bearer = (secret = null) => ({
  Authorization: `Bearer ${secret === null ? endpoint.secret : secret}`,
});

beforeAll(() => resetTable());

describe('端点收单：两种形态与字段容错（T39）', () => {
  test('GET 形态收单 ⇒ 202 + messageId，且消息真的落在端点所属那台设备上', async () => {
    const res = await request(app).get(getPath(null, '?title=机箱&body=温度 63 度'));
    expect(res.status).toBe(status);
    expect(res.body.messageId).toMatch(/^m_/);
    const messages = ms.loadMessages();
    const mine = messages[res.body.messageId];
    expect(mine.device).toBe(OWNER);
    expect(mine.state).toBe(contract.delivery.initialState);
    // 目标不是请求里给的（maySpecifyTarget=false），而是端点记录上那台设备
    expect(mine.sender).toBe(`endpoint:${endpoint.id}`);
    const content = ms.decryptBodyFor(contract, process.env.ENCRYPTION_KEY, mine.body);
    expect(content).toEqual({ title: '机箱', body: '温度 63 度' });
  });

  test('POST + Bearer 形态收单 ⇒ 202，正文字段优先于同名 query', async () => {
    const res = await request(app)
      .post(`${postPath()}?body=来自query&title=来自query`)
      .set(bearer())
      .send({ body: '来自正文', title: '备份完成' });
    expect(res.status).toBe(status);
    // 盘上是密信封（标题与正文装进同一个信封），所以断言必须先解密：
    // 直接 toContain 一个明文字符串，永远只能红着提醒我"这里存的是密文"。
    const stored = ms.loadMessages()[res.body.messageId];
    expect(stored.body).toMatch(/^v1\./);
    expect(stored.body).not.toContain('来自正文');
    const content = ms.decryptBodyFor(contract, process.env.ENCRYPTION_KEY, stored.body);
    expect(content.body).toBe('来自正文');
    expect(content.title).toBe('备份完成');
  });

  test('别名表由契约管：title|message|text|msg 取第一个非空，多余字段一概不看也不回显', async () => {
    const res = await request(app)
      .post(postPath())
      .set(bearer())
      .send({ text: '   ', msg: '用这个', whatever: '没人认的键', levelTarget: 'x' });
    expect(res.status).toBe(status);
    const stored = ms.loadMessages()[res.body.messageId];
    // 标题取到了 msg（前面的 text 是纯空白 ⇒ 不算"非空"）
    const content = ms.decryptBodyFor(contract, process.env.ENCRYPTION_KEY, stored.body);
    expect(content.title).toBe('用这个');
    expect(content.body).toBe('');
    // 多余字段是**没被读**，不是"读了再擦"：记录里连这个键都不该出现（键名来自契约 storedFields 白名单）
    for (const stray of ['whatever', 'levelTarget', 'text', 'msg']) {
      expect(stored).not.toHaveProperty(stray);
    }
    expect(JSON.stringify(res.body)).not.toContain('没人认的键');
  });

  // T99：第三方推进来的正文十有八九嵌一层。旧实现只读顶层，于是钉钉/企业微信那种
  // {"text":{"content":…}} 形状会把顶层那个对象 String() 成 [object Object] —— 而
  // "标题正文都空才拒"那道闸会放它过去，用户收到的是一条标题写着乱码的通知、且不报错。
  test('通用 webhook 形状收单：嵌套正文取得到，且输出里不许出现 [object Object]', async () => {
    const ding = await request(app)
      .post(postPath())
      .set(bearer())
      .send({ msgtype: 'text', text: { content: 'CPU 92%' } });
    expect(ding.status).toBe(status);
    const dingContent = ms.decryptBodyFor(
      contract,
      process.env.ENCRYPTION_KEY,
      ms.loadMessages()[ding.body.messageId].body,
    );
    expect(dingContent.body).toBe('CPU 92%');
    expect(dingContent.title).toBe('');

    const feishu = await request(app)
      .post(postPath())
      .set(bearer())
      .send({ msg_type: 'text', content: { text: '构建失败' } });
    expect(feishu.status).toBe(status);
    const feishuContent = ms.decryptBodyFor(
      contract,
      process.env.ENCRYPTION_KEY,
      ms.loadMessages()[feishu.body.messageId].body,
    );
    expect(feishuContent.body).toBe('构建失败');

    for (const content of [dingContent, feishuContent]) {
      expect(JSON.stringify(content)).not.toContain('object Object');
    }
  });

  test('dedupe 覆盖走同一条状态机：queued 时刷新，已发出的判 duplicate 不重发', async () => {
    const first = await request(app)
      .post(postPath())
      .set(bearer())
      .send({ title: '电量', body: '剩 20%', dedupe: 'bat-closeout' });
    expect(first.status).toBe(status);
    expect(first.body.action).toBe('new');
    const second = await request(app)
      .post(postPath())
      .set(bearer())
      .send({ title: '电量', body: '剩 15%', dedupe: 'bat-closeout' });
    expect(second.status).toBe(status);
    // 三个词的出处是 messagestore 那套状态机（new / refreshed / duplicate），不是这里另起一套：
    // 端点与签名面共用同一条入队链，"覆盖"在两面上必须是同一个结论。
    expect(second.body.action).toBe('refreshed');
    expect(second.body.messageId).toBe(first.body.messageId);
    const refreshed = ms.decryptBodyFor(
      contract,
      process.env.ENCRYPTION_KEY,
      ms.loadMessages()[first.body.messageId].body,
    );
    expect(refreshed.body).toBe('剩 15%');

    // 已经被设备取走的那一条不能再覆盖：把它推进到 pollable 之外（走真实状态机，不手改 state）
    const messages = ms.loadMessages();
    ms.dispatchForDevice(contract, messages, OWNER, Date.now());
    ms.saveMessages(messages);
    const third = await request(app)
      .post(postPath())
      .set(bearer())
      .send({ title: '电量', body: '剩 8%', dedupe: 'bat-closeout' });
    expect(third.status).toBe(status);
    expect(third.body.action).toBe('duplicate');
    expect(third.body.messageId).toBe(first.body.messageId);
    const untouched = ms.decryptBodyFor(
      contract,
      process.env.ENCRYPTION_KEY,
      ms.loadMessages()[first.body.messageId].body,
    );
    expect(untouched.body).toBe('剩 15%'); // 判重 ⇒ 一个字都不改（同一通知提醒两次就是这么来的）
  });
});

describe('同形与配额（T40）', () => {
  test('不存在的端点 / 口令错 / IP 不在白名单：三个响应逐字节相同（这一面不是枚举器）', async () => {
    const missing = await request(app).get('/api/fnthink/p/e_nope/' + 'K'.repeat(32));
    const badSecret = await request(app).get(getPath('K'.repeat(32)));
    // 口令对、端点在，但来源不在白名单里 ⇒ 必须与前两者一模一样
    ds.setEndpointPolicy(contract, ds.loadEndpoints(), endpoint.id, { ipAllowlist: ['10.0.0.9'] });
    const deniedIp = await request(app).get(getPath());
    ds.setEndpointPolicy(contract, ds.loadEndpoints(), endpoint.id, { ipAllowlist: [] });

    for (const one of [missing, badSecret, deniedIp]) {
      expect(one.status).toBe(statusCode(contract, 'unauthorized'));
      expect(JSON.stringify(one.body)).toBe('{}');
    }
    expect(JSON.stringify(deniedIp.body)).toBe(JSON.stringify(badSecret.body));
    expect(JSON.stringify(missing.body)).toBe(JSON.stringify(badSecret.body));
  });

  test('配额按端点计，且口令错的请求一发都不消耗（否则攻击者能替受害者花额度）', async () => {
    const endpoints = ds.loadEndpoints();
    const other = ds.createEndpoint(
      contract,
      endpoints,
      { owner: OWNER, name: '另一台' },
      Date.now(),
    );
    const cfg = { ...ingress, perMinute: 2, perDay: 100 };
    const state = {
      ingress: cfg,
      charge: intake.createEndpointQuota(cfg, () => {}),
      endpointCfg: ds.endpointConfigFromContract(contract),
    };
    const base = {
      endpoints,
      message: { title: 't', body: 'b', type: 'notice', level: '', item: '', dedupeId: '' },
      secure: true,
      ip: '203.0.113.9',
      method: 'POST',
      now: Date.now(),
    };
    // 先来 50 发错口令：一秒都不该动到别的端点的额度
    for (let i = 0; i < 50; i += 1) {
      intake.decideIngress(contract, cfg, state, {
        ...base,
        endpointId: other.id,
        secret: 'K'.repeat(32),
      });
    }
    const ok = [];
    for (let i = 0; i < 4; i += 1) {
      ok.push(
        intake.decideIngress(contract, cfg, state, {
          ...base,
          endpointId: other.id,
          secret: other.secret,
        }),
      );
    }
    expect(ok.slice(0, 2).every((r) => r.ok)).toBe(true);
    expect(
      ok.slice(2).every((r) => !r.ok && r.status === statusCode(contract, 'rateLimited')),
    ).toBe(true);
    expect(ok[2].retryAfter).toBeGreaterThan(0);
    // 主键必须是**端点**：上面那台已经被自己的 2 发/分打满了，另一台一发都不该跟着挨 429。
    // （一台 NAS 出口后面挂三个端点是常态 —— 按 IP 或按"整个面"计都会让它们互相挤额度。）
    const neighbours = ds.loadEndpoints();
    const third = ds.createEndpoint(
      contract,
      neighbours,
      { owner: OWNER, name: '隔壁那台' },
      Date.now(),
    );
    const alone = intake.decideIngress(contract, cfg, state, {
      ...base,
      endpoints: neighbours,
      endpointId: third.id,
      secret: third.secret,
    });
    expect(alone.ok).toBe(true);
  });

  test('429 的响应体是空的：配额不是投递结论，不许在实现里发明第九个回执词', async () => {
    const res = await request(app)
      .post(postPath())
      .set(bearer())
      .send({ title: '压测', body: 'x' });
    expect([status, statusCode(contract, 'rateLimited')]).toContain(res.status);
    if (res.status === statusCode(contract, 'rateLimited')) {
      expect(JSON.stringify(res.body)).toBe('{}');
      expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
    }
  });

  test('postOnly 的端点拒 GET ⇒ 码来自契约（405），POST 照旧收；缺省就是只收 POST', async () => {
    const viaGet = await request(app).get(strictGetPath('?title=a&body=b'));
    expect(viaGet.status).toBe(ingress.methodStatus);
    expect(JSON.stringify(viaGet.body)).toBe('{}');
    const viaPost = await request(app)
      .post(strictPostPath())
      .set({ Authorization: `Bearer ${strict.secret}` })
      .send({ title: 'a', body: 'b' });
    expect(viaPost.status).toBe(status);
  });

  test('HTTPS-only：明文一律拒，除非部署侧显式打开开关（403 且 body 空）', async () => {
    delete process.env.FNTHINK_ALLOW_INSECURE_ENDPOINT;
    const res = await request(app).post(postPath()).set(bearer()).send({ title: 'a', body: 'b' });
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(JSON.stringify(res.body)).toBe('{}');
    process.env.FNTHINK_ALLOW_INSECURE_ENDPOINT = '1';
    const ok = await request(app).post(postPath()).set(bearer()).send({ title: 'a', body: 'b' });
    expect(ok.status).toBe(status);
  });
});

describe('能力边界（T41）', () => {
  const rejectOnly = (payload) => request(app).post(postPath()).set(bearer()).send(payload);

  test('type=action ⇒ 403 + rejected_capability，且一条消息都不产生', async () => {
    const before = Object.keys(ms.loadMessages()).length;
    const res = await rejectOnly({ title: '关掉监听', body: 'x', type: 'action' });
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body.receipt).toBe('rejected_capability');
    expect(Object.keys(ms.loadMessages()).length).toBe(before);
  });

  test('外部自称的 level 也管住：type 合规但 level=L2 ⇒ 一样拒（裁决不看它，所以这里必须看）', async () => {
    const res = await rejectOnly({ title: '改亮度', body: 'x', type: 'notice', level: 'L3' });
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(res.body.receipt).toBe('rejected_capability');
  });

  test('带 item ⇒ 当噪音忽略，而落队那一位**恒是空串**（这才是这条的牙）', async () => {
    // T120 把这一支从"403"翻成"忽略"（契约 endpoint.ingress.ignoreItemField=true）。它成立的
    // 前提是「这一面永远不把 item 转发下去」—— 所以只断 202 不够：那种写法在"把别人的动作
    // 钩子塞进一条普通通知"时同样绿。断的是落库那一位的值。
    const res = await rejectOnly({ title: 'a', body: 'b', item: '4521' });
    expect(res.status).toBe(status);
    const stored = ms.loadMessages()[res.body.messageId];
    expect(stored.item).toBe('');
  });

  test('契约把 ignoreItemField 关掉 ⇒ 旧行为回来了（带 item 一律 403 + rejected_capability）', () => {
    // 这一条不打 HTTP：它要证明的是"那个开关真的接在裁决上"，而不是实现里读了一次。
    // 打 HTTP 反而证不到 —— 路由读的是进程装载的那份契约，改不动。
    const strict = {
      ...contract,
      endpoint: {
        ...contract.endpoint,
        ingress: { ...contract.endpoint.ingress, ignoreItemField: false },
      },
    };
    const cfg = intake.ingressFromContract(strict);
    expect(cfg.ignoreItemField).toBe(false);
    const message = intake.readIngress(strict, {}, { title: 'a', body: 'b', item: 'toggle_watch' });
    expect(message.item).toBe('toggle_watch');
    // 档位裁决这一层拦不住它（L1 通知不查清单）⇒ 拦住它的是收单那一格的 itemBeyondGrant。
    expect(
      capabilities.decideCapability(strict, {
        stage: 'intake',
        type: message.type,
        item: message.item,
        grant: cfg.endpointGrant,
      }).allowed,
    ).toBe(true);
    const verdict = intake.decideIngress(
      strict,
      cfg,
      { charge: () => null, endpointCfg: ds.endpointConfigFromContract(strict) },
      {
        endpoints: ds.loadEndpoints(),
        endpointId: endpoint.id,
        secret: endpoint.secret,
        message,
        secure: true,
        ip: '127.0.0.1',
        method: 'POST',
        now: Date.now(),
      },
    );
    expect(verdict.ok).toBe(false);
    expect(verdict.status).toBe(statusCode(strict, 'forbidden'));
    expect(verdict.receipt).toBe('rejected_capability');
  });

  test('空载荷 ⇒ 400（一条没有内容的通知不该占一个队列位）', async () => {
    const empty = await rejectOnly({ title: '   ', body: '' });
    expect(empty.status).toBe(statusCode(contract, 'badRequest'));
    expect(JSON.stringify(empty.body)).toBe('{}');
  });

  test('超 maxBodyChars ⇒ 400，而不是截断后收下', async () => {
    const long = await rejectOnly({
      title: 't',
      body: 'y'.repeat(ingress.maxBodyChars + 1),
    });
    expect(long.status).toBe(statusCode(contract, 'badRequest'));
    // 截断后收下 = 发送方以为发成功了，而用户看到半句话 —— 比拒收难排查得多。
    // ⚠ 必须解密来查：盘上是密信封，在信封里搜 'yyyy' 永远搜不到，那条断言就成了自证的空话。
    const opened = Object.values(ms.loadMessages())
      .filter((m) => m.body)
      .map((m) => ms.decryptBodyFor(contract, process.env.ENCRYPTION_KEY, m.body));
    expect(opened.some((c) => c.body.includes('yyyy'))).toBe(false);
  });

  test('端点没绑到一台合法设备上 ⇒ 403 空 body（内部说清，对外不说）', async () => {
    // 这是端点自己的配置事实（创建时 owner 空 / 地址码后来漂了），与攻击者无关 ——
    // 但**不能**因此就把消息投给一个不存在的人：enqueue 那里会抛"消息必须归属一台设备"，
    // 冒到 asyncHandler 变成 500，而 500 会告诉对方"这把口令是对的，只是服务端没接住"。
    const endpoints = ds.loadEndpoints();
    const unbound = ds.createEndpoint(
      contract,
      endpoints,
      { owner: '', name: '没绑设备' },
      Date.now(),
    );
    const res = await request(app)
      .post(`/api/fnthink/p/${unbound.id}`)
      .set({ Authorization: `Bearer ${unbound.secret}` })
      .send({ title: 'a', body: 'b' });
    expect(res.status).toBe(statusCode(contract, 'forbidden'));
    expect(JSON.stringify(res.body)).toBe('{}');
    const calls = ds.loadEndpoints()[unbound.id].calls;
    expect(calls.map((c) => c.outcome)).toContain('unbound_endpoint');
  });
});

// T120（维护者 2026-10-09 定的口径：这一面要能接住第三方对 webhook 的调用，不是为自家软件特调）。
// 截图那次是 `chan:generic` 与 `chan:fnthink` 各 403 + rejected_capability，根因是载荷里那枚
// `type` 被裸读成协议字段。下面这组钉的是三件事，缺一件就回到那个 403：
//  ① 读不懂的取值 ⇒ 折成**契约声明的那个词**（不是实现里藏着的 'notice'），并真的收进队列；
//  ② 读得懂而本面给不起的那两个词 ⇒ 照旧 403（折价不能变成放行越权）；
//  ③ 折价住在入口那一层，共享裁决 `capabilities.decideCapability` 那句 fail-closed 一字未动
//     —— 签名面的对端是有身份的设备，那边"认不出就当普通通知"才是把词表的解释权交给别人。
describe('第三方载荷那枚 type 的折价（T120）', () => {
  // 单独一把口令：端点配额按端点计（15/分钟，进程内按墙钟开窗），而这一组有八九发成功的推送 ——
  // 与前两组共用 `endpoint` 会把同一文件里后面的用例打到 429（那是计额，不是产品结论）。
  // 语义上也对：第三方集成本来就是"一条集成一把口令"。
  let foreign = null;
  beforeAll(() => {
    foreign = ds.createEndpoint(
      contract,
      ds.loadEndpoints(),
      { owner: OWNER, name: '第三方' },
      Date.now(),
    );
  });
  const post = (payload) =>
    request(app)
      .post(`/api/fnthink/p/${foreign.id}`)
      .set({ Authorization: `Bearer ${foreign.secret}` })
      .send(payload);

  test('第三方自己的分类词（alert／warning／msg…）⇒ 202，落队那条是契约声明的那个词', async () => {
    const declared = contract.endpoint.ingress.unknownTypeAs;
    expect(Object.keys(contract.capabilities.messageTypes)).toContain(declared);
    for (const foreign of ['alert', 'warning', 'news_push', 'DongCheDi']) {
      const res = await post({ title: '一条推送', body: 'x', type: foreign });
      expect(res.status).toBe(status);
      const stored = ms.loadMessages()[res.body.messageId];
      // ⚠ 断的是**落库那位**而不是 202：闸门放行而队列里带着一个词表外的词，设备侧迟早撞上
      // 同一道 unknown-type，表现和今天这个 403 只差一层，且更难查。
      expect(stored.type).toBe(declared);
    }
  });

  test('本机通用 webhook 那一发的载荷形状照收（不为我们自己的客户端特调，也不为它开后门）', async () => {
    // 这就是 WebhookPayloadBuilder.kt 那一份的形状：`type` 是那条 Android 通知自己的 type。
    const res = await post({
      title: '懂车帝',
      content: '您订阅的车有更新',
      appName: '懂车帝',
      packageName: 'com.ss.android.auto',
      time: '2026-10-09 07:30',
      deviceName: '测试机',
      type: 'auto_push',
      timestamp: 1762000000000,
    });
    expect(res.status).toBe(status);
    const stored = ms.loadMessages()[res.body.messageId];
    const content = ms.decryptBodyFor(contract, process.env.ENCRYPTION_KEY, stored.body);
    expect(content.title).toBe('懂车帝');
    expect(content.body).toBe('您订阅的车有更新');
    expect(stored.type).toBe(contract.endpoint.ingress.unknownTypeAs);
    // 那些自家键一个都不许进记录（名单由契约 retention.storedFields 管）。
    for (const stray of ['appName', 'packageName', 'deviceName', 'timestamp']) {
      expect(stored).not.toHaveProperty(stray);
    }
  });

  test('读得懂而本面给不起的那两个词照旧 403：折价只给"读不懂"，不给"越权"', async () => {
    for (const escalate of ['action', 'setting']) {
      const res = await post({ title: '开灯', body: 'x', type: escalate });
      expect(res.status).toBe(statusCode(contract, 'forbidden'));
      expect(res.body.receipt).toBe('rejected_capability');
    }
  });

  test('level 写自家严重级（info／high／P0）⇒ 忽略；写着词表内的高档才是申请 ⇒ 403', async () => {
    for (const foreign of ['info', 'high', 'P0']) {
      const res = await post({ title: 'a', body: 'b', level: foreign });
      expect(res.status).toBe(status);
    }
    const escalated = await post({ title: 'a', body: 'b', level: 'L2' });
    expect(escalated.status).toBe(statusCode(contract, 'forbidden'));
    expect(escalated.body.receipt).toBe('rejected_capability');
  });

  test('折价住在入口那一层：共享裁决那句 fail-closed 没被改软（签名面仍按 unknown-type 拒）', () => {
    const decided = capabilities.decideCapability(contract, {
      stage: 'intake',
      type: 'alert',
      item: '',
      grant: ingress.endpointGrant,
    });
    expect(decided.allowed).toBe(false);
    expect(decided.reason).toBe('unknown-type:alert');
  });

  test('折价的缺省词只从契约读：契约给不出词表内的词时折成空串（由裁决拒），实现里没有藏着的 notice', () => {
    expect(intake.coerceIngressType(contract, 'alert')).toBe(
      contract.endpoint.ingress.unknownTypeAs,
    );
    expect(intake.coerceIngressType(contract, 'notice')).toBe('notice');
    const broken = {
      capabilities: { messageTypes: { notice: { minLevel: 'L1' } } },
      endpoint: { ingress: { unknownTypeAs: 'notification' } },
    };
    // 'notification' 不在那份词表上 ⇒ 回空串，而不是"顺手用第一个键"或硬写的 'notice'。
    expect(intake.coerceIngressType(broken, 'alert')).toBe('');
    expect(intake.coerceIngressType({}, 'alert')).toBe('');
  });
});

describe('口令不进日志与 kind（T40 的脱敏前提）', () => {
  test('限流的 kind 归一化：/p/<id>/<secret> 一律算 endpoint，绝不把尾段当种类', () => {
    expect(endpointKindOf('/p/e_abc/' + endpoint.secret)).toBe('endpoint');
    expect(endpointKindOf('/poll')).toBe('poll');
  });

  test('调用日志里搜不到口令、路径与正文；轮换宽限期内的旧口令仍能推', async () => {
    const rotated = ds.rotateEndpoint(contract, ds.loadEndpoints(), endpoint.id, Date.now());
    const old = await request(app)
      .post(postPath())
      .set(bearer(endpoint.secret))
      .send({ title: '旧口令', body: '还在宽限期' });
    expect(old.status).toBe(status);
    const fresh = await request(app)
      .post(postPath())
      .set(bearer(rotated.secret))
      .send({ title: '新口令', body: 'ok' });
    expect(fresh.status).toBe(status);
    const calls = ds.loadEndpoints()[endpoint.id].calls;
    expect(calls.length).toBeGreaterThanOrEqual(2);
    for (const entry of calls) {
      expect(Object.keys(entry).sort()).toEqual(['at', 'ip', 'outcome']);
    }
    const flat = JSON.stringify(calls);
    for (const forbidden of [endpoint.secret, rotated.secret, '旧口令', '还在宽限期', '/p/']) {
      expect(flat).not.toContain(forbidden);
    }
  });
});

describe('数字只从契约读', () => {
  test('改契约副本：配额与长度上限跟着变（断来源，不是断值等于某个数）', () => {
    const mutated = {
      ...contract,
      endpoint: {
        ...contract.endpoint,
        ingress: {
          ...contract.endpoint.ingress,
          quota: { perMinute: 4, perDay: 40 },
          maxTitleChars: 10,
          maxBodyChars: 128,
        },
      },
    };
    const cfg = intake.ingressFromContract(mutated);
    expect(cfg.perMinute).toBe(4);
    expect(cfg.perDay).toBe(40);
    expect(cfg.maxTitleChars).toBe(10);
    expect(cfg.maxBodyChars).toBe(128);
    expect(cfg.methodStatus).toBe(mutated.endpoint.postOnlyMethodStatus);
  });

  test('契约里三条方向性判据在 JS 侧同样生效（缺省方向反了就抛，且是可降级的 SHAPE）', () => {
    const flipped = {
      ...contract,
      endpoint: {
        ...contract.endpoint,
        ingress: {
          ...contract.endpoint.ingress,
          quota: { perMinute: 15, perDay: 5 },
        },
      },
    };
    expect(() => intake.ingressFromContract(flipped)).toThrow(/日额度必须大于分钟额度/);
    const mayTarget = {
      ...contract,
      endpoint: {
        ...contract.endpoint,
        ingress: { ...contract.endpoint.ingress, maySpecifyTarget: true },
      },
    };
    let err = null;
    try {
      intake.ingressFromContract(mayTarget);
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    const { isContractAvailabilityError } = require('../lib/fnthink/contract');
    expect(isContractAvailabilityError(err)).toBe(true);
  });

  test('折价的三条判据在 JS 侧同样生效（折向词表外／折向升权档／开关不是布尔 ⇒ 都抛）', () => {
    const withIngress = (patch) => ({
      ...contract,
      endpoint: {
        ...contract.endpoint,
        ingress: { ...contract.endpoint.ingress, ...patch },
      },
    });
    // ① 折成的词必须在这张词表上：造一个新词等于把 unknown-type 那道闸往后推给设备。
    expect(() =>
      intake.ingressFromContract(withIngress({ unknownTypeAs: 'notification' })),
    ).toThrow(/messageTypes 里的一个词/);
    // ② 折价只能朝下：action 要 L2，而本面上限是 L1 ⇒ 拿它当缺省就是每次读不懂都升一档。
    expect(() => intake.ingressFromContract(withIngress({ unknownTypeAs: 'action' }))).toThrow(
      /不许高于/,
    );
    // ③ 那枚开关必须是布尔（写成 "yes" 不能静默按真值用）。
    expect(() => intake.ingressFromContract(withIngress({ ignoreItemField: 'yes' }))).toThrow(
      /必须是布尔/,
    );
    // 缺键也抛：两条新判据都不许有"实现里那份缺省"。
    const noKeys = {
      ...contract,
      endpoint: {
        ...contract.endpoint,
        ingress: { ...contract.endpoint.ingress },
      },
    };
    delete noKeys.endpoint.ingress.unknownTypeAs;
    delete noKeys.endpoint.ingress.ignoreItemField;
    expect(() => intake.ingressFromContract(noKeys)).toThrow(/messageTypes 里的一个词|必须是布尔/);
  });
});
