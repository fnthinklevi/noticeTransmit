// T50：L2 动作的**服务端那一半**（纯解析 + 回执词）。
//
// 与 Dart 的 test/services/fnthink_l2_actions_test.dart 是同一套判据的两侧断言，
// 两侧读同一份 protocol/fnthink-v1.json —— 不是各带一份夹具，因为这一层最怕的
// 缺陷正是"两端对同一份契约给出了不同的答案"。
//
// 服务端这一侧**不执行**动作（T30 那条红线：服务端看不见屏幕前的那个人），
// 所以这里只断言解析与回执；执行在设备侧那一半的用例里。

'use strict';

const path = require('path');
const fs = require('fs');

const { assertSupported, loadContract } = require('../lib/fnthink/contract');
const { l2ActionsKnownToServer, l2ReceiptFor, parseL2Item } = require('../lib/fnthink/l2actions');

const CONTRACT_PATH = path.join(__dirname, '..', '..', 'protocol', 'fnthink-v1.json');

describe('L2 动作词表（契约是唯一出处，T50）', () => {
  const raw = JSON.parse(fs.readFileSync(CONTRACT_PATH, 'utf8'));

  test('仓库里那份契约这一包解释得了（否则下面这些用例都在测空气）', () => {
    // ⚠ Node 侧**没有** validate()：那张表的自洽判据是 Dart 的 FnthinkContract.validate。
    // 这一侧只判"解释得了"（assertSupported），两边合起来才覆盖得住 ——
    // 写成 contract.validate() 会得到 "is not a function"，读起来像依赖装错了。
    expect(() => assertSupported(loadContract())).not.toThrow();
  });

  // ⚠ 这两条钉子自 T124 片B 起就没跟上契约（当时加了 4 个动作，这里的期望值没动）——
  //   C-1 校平过一次，此后每片跟进（片B 四个 + 片C 四个：calls / location /
  //   camera / contacts）。教训照旧：期望值是**契约的镜像**，契约动了而它没动，
  //   它红的那一天才发现自己没人看。
  test('actions 十二条，且服务端这一侧全认得', () => {
    expect(raw.capabilities.l2.actions).toEqual([
      'listener:start',
      'listener:stop',
      'channel:toggle',
      'device_state:push',
      'notifications:report',
      'alert:ring',
      'sms:search',
      'app:launch',
      'calls:search',
      'location:get',
      'camera:snap',
      'contacts:search',
    ]);
    expect(l2ActionsKnownToServer(raw)).toBe(true);
  });

  test('点名要参数的六个动作，且它们都在词表里', () => {
    expect(raw.capabilities.l2.requiresArgumentFrom).toEqual([
      'channel:toggle',
      'notifications:report',
      'sms:search',
      'app:launch',
      'calls:search',
      'contacts:search',
    ]);
    expect(raw.capabilities.l2.actions).toContain('channel:toggle');
  });

  test('执行失败回的那一个词在顶层 receipts 词表里', () => {
    expect(raw.capabilities.l2.actionReceipt).toBe('failed_action');
    expect(raw.receipts).toContain(raw.capabilities.l2.actionReceipt);
  });

  test('messageTypes.action 仍映射到 L2（动作表存在而 type 侧不指向它 = 没有读者）', () => {
    expect(raw.capabilities.messageTypes.action.minLevel).toBe('L2');
  });
});

describe('parseL2Item：四种拒的理由各不相同', () => {
  const c = JSON.parse(fs.readFileSync(CONTRACT_PATH, 'utf8'));

  test('认得出的四种各解析出动作与参数', () => {
    expect(parseL2Item(c, 'listener:start', 'action')).toEqual({
      ok: true,
      action: { name: 'listener:start', argument: '' },
    });
    expect(parseL2Item(c, 'channel:toggle/chan:wechat', 'action')).toEqual({
      ok: true,
      action: { name: 'channel:toggle', argument: 'chan:wechat' },
    });
  });

  test('item 为空 ⇒ missing-item（不猜一个动作出来）', () => {
    for (const given of [undefined, null, '']) {
      expect(parseL2Item(c, given, 'action')).toEqual({ ok: false, reason: 'missing-item' });
    }
  });

  test('词表外的动作 ⇒ unknown-action:<名>，不静默跳过', () => {
    // ⚠ 本组最要紧的一条：跳过它 = 对端可以拿编出来的动作名试这台设备的边界
    expect(parseL2Item(c, 'listener:reboot', 'action')).toEqual({
      ok: false,
      reason: 'unknown-action:listener:reboot',
    });
  });

  test('点名要参数而没给 ⇒ missing-argument，且不取第一条', () => {
    const r = parseL2Item(c, 'channel:toggle', 'action');
    expect(r).toEqual({ ok: false, reason: 'missing-argument:channel:toggle' });
    expect(JSON.stringify(r)).not.toContain('chan:');
  });

  test('参数里带斜杠原样保留（通道 id 里有斜杠时不被截断）', () => {
    expect(parseL2Item(c, 'channel:toggle/a/b/c', 'action')).toEqual({
      ok: true,
      action: { name: 'channel:toggle', argument: 'a/b/c' },
    });
  });

  test('type 不是 action ⇒ not-a-pair（这一层只服务 L2）', () => {
    expect(parseL2Item(c, 'listener:start', 'notice')).toEqual({
      ok: false,
      reason: 'not-a-pair',
    });
    expect(parseL2Item(c, 'listener:start', 'setting')).toEqual({
      ok: false,
      reason: 'not-a-pair',
    });
  });
});

describe('回执：成功与失败对外各是哪一个词', () => {
  const c = JSON.parse(fs.readFileSync(CONTRACT_PATH, 'utf8'));

  test('成功 ⇒ delivered，失败 ⇒ 契约那一个词', () => {
    expect(l2ReceiptFor(c, { ok: true })).toBe('delivered');
    expect(l2ReceiptFor(c, { ok: false, reason: 'no-such-channel' })).toBe('failed_action');
  });

  test('本地细节只进 reason，不进对外那个词', () => {
    const w = l2ReceiptFor(c, { ok: false, reason: 'no-such-channel:chan:wechat' });
    expect(w).not.toContain('chan:');
    expect(w).toBe('failed_action');
  });

  test('契约缺 actionReceipt 时退回 failed_action 而不是空串', () => {
    // 空串会让回执"收下了但不知道是什么"，而 receipts 词表里没有空串这一项
    const broken = JSON.parse(JSON.stringify(c));
    delete broken.capabilities.l2.actionReceipt;
    expect(l2ReceiptFor(broken, { ok: false })).toBe('failed_action');
  });
});
