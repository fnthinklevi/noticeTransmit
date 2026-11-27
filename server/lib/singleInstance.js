/**
 * 单实例硬闸（2026-11-27）。
 *
 * 为什么需要：服务端的状态是**进程内 Map + data/*.json**（没有跨进程锁）——
 * SSE 的 waiters / listeners / 一次性票也只活在当前进程。于是 pm2 cluster
 * （`pm2 start server.js -i N`）或手工起第二个指向同一 DATA_DIR 的进程时：
 *   - 消息落在 A、SSE 连在 B ⇒ wake 永远送不到（看起来就像"消息延迟 300 秒"）；
 *   - 两个进程各自读改写同一份 JSON ⇒ 互相覆盖，丢消息/丢限流计数。
 *
 * 这两类故障都不会崩、不会报错，只会"看起来在跑"。所以在启动时 fail-fast：
 * 宁可起不来并说清怎么改，也不要静默跑成一个半残服务。
 *
 * 覆盖面：
 *   ① pm2 cluster worker（NODE_APP_INSTANCE > 0）；
 *   ② 同一 DATA_DIR 的第二个进程（独占锁文件，持有者已死则回收陈旧锁）。
 */
const fs = require('fs');
const path = require('path');

const LOCK_NAME = '.single-instance.lock';

/** pm2 cluster 的非 0 worker 返回原因；fork 的 `0` / 未设置为 null。 */
function pm2ClusterWorker(env = process.env) {
  const raw = env.NODE_APP_INSTANCE;
  if (raw === undefined || raw === '') return null;
  const index = Number(raw);
  if (Number.isInteger(index) && index > 0) {
    return `pm2 cluster worker #${index}`;
  }
  return null;
}

/** PID 是否还活着。EPERM = 进程存在但不属于当前用户（例如服务由 root 启动）。 */
function pidIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return Boolean(e && e.code === 'EPERM');
  }
}

/**
 * 在 dataDir 下拿一把独占锁。
 * 返回 `{ ok, lockPath, holder?, release }`；被占用时 `holder` 是锁里的 pid。
 */
function acquireLock({ dataDir, pid = process.pid, isAlive = pidIsAlive }) {
  fs.mkdirSync(dataDir, { recursive: true });
  const lockPath = path.join(dataDir, LOCK_NAME);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const fd = fs.openSync(lockPath, 'wx');
      fs.writeSync(fd, `${pid}\n`);
      fs.closeSync(fd);
      return {
        ok: true,
        lockPath,
        release() {
          try {
            fs.unlinkSync(lockPath);
          } catch (_) {
            // 已经删了/被清理了都算释放成功。
          }
        },
      };
    } catch (e) {
      if (!e || e.code !== 'EEXIST') throw e;
      let holder = NaN;
      try {
        holder = Number.parseInt(String(fs.readFileSync(lockPath, 'utf8')).trim(), 10);
      } catch (_) {
        // 读不到就当持有者未知，下面按"已死"回收。
      }
      if (isAlive(holder)) return { ok: false, lockPath, holder };
      // 上一次被 kill -9：锁还在但持有者已经没了 ⇒ 清掉重试一次。
      try {
        fs.unlinkSync(lockPath);
      } catch (_) {}
    }
  }
  return { ok: false, lockPath, holder: null };
}

/**
 * 启动时调用。通过返回锁对象（调用方在 exit 时 release）；不通过则打印原因并 exit(1)。
 * [log]/[exit]/[lock] 可注入，便于单测不在真实进程上退出。
 */
function enforceSingleInstance({
  dataDir,
  env = process.env,
  log = console.error,
  exit = (code) => process.exit(code),
  lock = acquireLock,
} = {}) {
  const cluster = pm2ClusterWorker(env);
  if (cluster) {
    log(
      `[single-instance] 拒绝启动：检测到 ${cluster}。` +
        '本服务的数据层是进程内 Map + data/*.json，多 worker 会让消息/票/SSE 订阅分散，' +
        '表现为"消息到了设备不醒"。请改回 fork 单进程：' +
        'pm2 delete update-server && pm2 start server.js --name update-server（不要 -i），再 pm2 save。',
    );
    exit(1);
    return null;
  }
  const acquired = lock({ dataDir });
  if (!acquired.ok) {
    log(
      `[single-instance] 拒绝启动：${acquired.lockPath} 已被 pid=${acquired.holder ?? '未知'} 占用。` +
        '同一个 DATA_DIR 只能有一个服务进程；若是上次被 kill -9 留下的锁，' +
        '确认进程不存在后删除该文件再启动。',
    );
    exit(1);
    return null;
  }
  log(`[single-instance] 检查通过（pid=${process.pid}，锁=${acquired.lockPath}）`);
  return acquired;
}

module.exports = {
  LOCK_NAME,
  pm2ClusterWorker,
  pidIsAlive,
  acquireLock,
  enforceSingleInstance,
};
