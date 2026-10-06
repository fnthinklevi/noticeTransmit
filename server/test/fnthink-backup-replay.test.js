'use strict';

// 补推与补发二选一（T46）的 **Node 侧**断言。Dart 那一半在
// packages/fnthink_push/test/backup_replay_test.dart，两边吃同一份
// protocol/fnthink-vectors-v1.json 的 backupReplay 段。
//
// 这一组要防的分叉是互斥：备用补推与排队补发并存 = 同一条消息提醒两次，
// 而两边的实现分叉时不会报错，只会在用户手机上响两声。

const fs = require('fs');
const path = require('path');

const { loadContract, assertSupported } = require('../lib/fnthink/contract');
const backupReplay = require('../lib/fnthink/backupReplay');

const contract = assertSupported(loadContract());
const vectors = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', '..', 'protocol', 'fnthink-vectors-v1.json'), 'utf8'),
);
const cases = vectors.backupReplay;

const waiting = () => contract.waitingOnline;
const run = (given) => backupReplay.decide(contract, given);

const clone = () => JSON.parse(JSON.stringify(contract));

describe('补推/补发二选一向量（Node 侧，T46）', () => {
  test('向量非空', () => {
    expect(cases.length).toBeGreaterThan(0);
  });

  test.each(cases.map((c) => [c.id, c]))(
    '%s：路线词、标签、去重键、上限、没做的原因都要对上',
    (_id, c) => {
      const got = run(c.given);
      // 比的是契约路线词（got.route），不是 action 名：action 是代码里的名字，
      // 路线词是契约里的名字，两份词表各写一份时改名的那天两边悄悄对不上。
      expect(got.route || 'none').toBe(c.expect.action);
      if ('label' in c.expect) expect(got.label).toBe(c.expect.label);
      if ('dedupeKey' in c.expect) expect(got.dedupeKey).toBe(c.expect.dedupeKey);
      if ('max' in c.expect) expect(got.max).toBe(c.expect.max);
      if ('limitReason' in c.expect) expect(got.limitReason).toBe(c.expect.limitReason);
    },
  );

  test('互斥：一条消息的结论里同时只可能出现一条路', () => {
    const { withBackupChannel, withoutBackupChannel } = waiting();
    expect(withBackupChannel).not.toBe(withoutBackupChannel);
    const both = [];
    const missingOnReplay = [];
    for (let count = 0; count <= 3; count += 1) {
      for (const alreadyReplayed of [true, false]) {
        for (const route of [withBackupChannel, withoutBackupChannel]) {
          const tag = `route=${route} replayed=${alreadyReplayed} count=${count}`;
          const got = run({ route, alreadyReplayed, replayCount: count, messageId: 'msg-x' });
          const picksReplay = got.action === backupReplay.ACTION.backupReplay;
          const picksQueue = got.action === backupReplay.ACTION.queueResend;
          if (picksReplay && picksQueue) both.push(tag);
          // 走了补推那一档时去重键与标签必须都在（缺一个就是"补推了但记不住"）。
          if (picksReplay && (got.dedupeKey == null || got.label == null)) {
            missingOnReplay.push(tag);
          }
        }
      }
    }
    expect(both).toEqual([]);
    expect(missingOnReplay).toEqual([]);
  });

  test('词表与读数全部取自契约：实现里不许写死路线词、标签与上限', () => {
    expect(backupReplay.backupReplayMax(contract)).toBe(contract.limits.backupReplayMax);
    expect(backupReplay.idempotencyKeyName(contract)).toBe(
      contract.waitingOnline.backupReplayIdempotencyKey,
    );
    const first = run({
      route: waiting().withBackupChannel,
      alreadyReplayed: false,
      replayCount: 0,
      messageId: 'msg-y',
    });
    expect(first.label).toBe(waiting().backupReplayLabel);
  });
});

describe('读不出契约时照抛，不退回默认值', () => {
  test('limits.backupReplayMax 缺了 ⇒ 抛（退回 0 等于把这条路径悄悄关掉）', () => {
    const broken = clone();
    delete broken.limits.backupReplayMax;
    expect(() => backupReplay.backupReplayMax(broken)).toThrow();
    expect(() =>
      backupReplay.decide(broken, {
        route: 'backup_replay',
        alreadyReplayed: false,
        replayCount: 0,
        messageId: 'msg-z',
      }),
    ).toThrow();
  });

  test('backupReplayIdempotencyKey 指名别的键 ⇒ 抛（不拿 message_id 顶替）', () => {
    const broken = clone();
    broken.waitingOnline.backupReplayIdempotencyKey = 'dedupe_id';
    expect(() => backupReplay.idempotencyKeyName(broken)).toThrow();
  });

  test('backupReplayLabel 缺了 ⇒ 抛（补推那一发在记录上必须有个名字）', () => {
    const broken = clone();
    delete broken.waitingOnline.backupReplayLabel;
    expect(() =>
      backupReplay.decide(broken, {
        route: 'backup_replay',
        alreadyReplayed: false,
        replayCount: 0,
        messageId: 'msg-z',
      }),
    ).toThrow();
  });

  test('路线词不属于那两条之一 ⇒ 抛（猜错的方向是提醒两次，或用户什么都收不到）', () => {
    expect(() =>
      backupReplay.decide(contract, {
        route: 'invented_route',
        alreadyReplayed: false,
        replayCount: 0,
        messageId: 'msg-z',
      }),
    ).toThrow();
  });

  test('真要补推却没给 messageId ⇒ 抛（拿空键去重等于没去重）', () => {
    expect(() =>
      backupReplay.decide(contract, {
        route: 'backup_replay',
        alreadyReplayed: false,
        replayCount: 0,
      }),
    ).toThrow();
  });
});
