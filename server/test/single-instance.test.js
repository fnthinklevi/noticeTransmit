const fs = require('fs');
const os = require('os');
const path = require('path');

const {
  LOCK_NAME,
  pm2ClusterWorker,
  acquireLock,
  enforceSingleInstance,
} = require('../lib/singleInstance');

describe('单实例硬闸', () => {
  let dir;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nt-single-'));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  test('pm2 cluster 非 0 worker 被点名；fork 的 0 / 未设置放行', () => {
    expect(pm2ClusterWorker({ NODE_APP_INSTANCE: '2' })).toBe('pm2 cluster worker #2');
    expect(pm2ClusterWorker({ NODE_APP_INSTANCE: '0' })).toBeNull();
    expect(pm2ClusterWorker({})).toBeNull();
  });

  test('同一 DATA_DIR 的第二个进程拿不到锁；释放后可以再拿', () => {
    const first = acquireLock({ dataDir: dir, pid: process.pid });
    expect(first.ok).toBe(true);
    expect(fs.readFileSync(path.join(dir, LOCK_NAME), 'utf8').trim()).toBe(String(process.pid));

    const second = acquireLock({ dataDir: dir, pid: process.pid + 1 });
    expect(second.ok).toBe(false);
    expect(second.holder).toBe(process.pid);

    first.release();
    const third = acquireLock({ dataDir: dir, pid: 333 });
    expect(third.ok).toBe(true);
    third.release();
  });

  test('陈旧锁（持有者已死）会被清掉并重新拿到', () => {
    fs.writeFileSync(path.join(dir, LOCK_NAME), '999999\n');
    const got = acquireLock({ dataDir: dir, pid: 444, isAlive: () => false });
    expect(got.ok).toBe(true);
    expect(fs.readFileSync(path.join(dir, LOCK_NAME), 'utf8').trim()).toBe('444');
    got.release();
  });

  test('enforce：cluster 直接拒绝启动，并给出改回 fork 的命令', () => {
    const logs = [];
    const exits = [];
    const result = enforceSingleInstance({
      dataDir: dir,
      env: { NODE_APP_INSTANCE: '1' },
      log: (m) => logs.push(m),
      exit: (code) => exits.push(code),
    });

    expect(result).toBeNull();
    expect(exits).toEqual([1]);
    const text = logs.join('\n');
    expect(text).toContain('pm2 cluster worker #1');
    expect(text).toContain('pm2 start server.js');
    expect(text).toContain('不要 -i');
  });

  test('enforce：DATA_DIR 已被活进程占用时拒绝启动', () => {
    // 用当前测试进程的 pid：它一定活着，才会命中"活进程占用"而不是"陈旧锁回收"。
    const held = acquireLock({ dataDir: dir, pid: process.pid });
    expect(held.ok).toBe(true);
    const logs = [];
    const exits = [];
    try {
      const result = enforceSingleInstance({
        dataDir: dir,
        env: {},
        log: (m) => logs.push(m),
        exit: (code) => exits.push(code),
      });
      expect(result).toBeNull();
      expect(exits).toEqual([1]);
      expect(logs.join('\n')).toContain(`已被 pid=${process.pid} 占用`);
    } finally {
      held.release();
    }
  });

  test('enforce：正常时返回锁并写入当前 pid（调用方在 exit 时 release）', () => {
    const result = enforceSingleInstance({
      dataDir: dir,
      env: {},
      log: () => {},
      exit: () => {
        throw new Error('正常路径不应退出');
      },
    });
    expect(result && result.ok).toBe(true);
    expect(fs.readFileSync(path.join(dir, LOCK_NAME), 'utf8').trim()).toBe(String(process.pid));
    result.release();
    expect(fs.existsSync(path.join(dir, LOCK_NAME))).toBe(false);
  });

  test('server.js 真的接上了硬闸，并且在 listen 之前', () => {
    const src = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
    expect(src).toContain("require('./lib/singleInstance')");
    expect(src).toContain('enforceSingleInstance({ dataDir: store.DATA_DIR })');
    expect(src).toContain('instanceLock.release');
    expect(src.indexOf('enforceSingleInstance({ dataDir: store.DATA_DIR })')).toBeLessThan(
      src.indexOf('app.listen(PORT'),
    );
  });
});
