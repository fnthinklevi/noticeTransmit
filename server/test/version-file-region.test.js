/**
 * T170：两站各读自己那份 version.json。
 *
 * 钉三件事：
 *  ① 选中哪一份由 UPDATE_REGION 决定（cn → version.cn.json / global 与不设 → version.global.json）；
 *  ② 写成别的值不猜：进程直接报错退出（写错站点会把用户送去另一站的 CDN）；
 *  ③ 两份数据文件的下载主机各自正确（大陆 cdn.fnthink.com / 海外 cdn2.fnthink.top），
 *     不再出现「.com 站把用户送去 .top 的 CDN」。
 */
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

process.env.ADMIN_TOKEN_HASH = require('bcryptjs').hashSync(
  'test-admin-token-for-version-region',
  10,
);

const SERVER_DIR = path.join(__dirname, '..');

function childEnv(region) {
  const env = { ...process.env };
  delete env.UPDATE_REGION;
  if (region !== undefined) env.UPDATE_REGION = region;
  return env;
}

function selectedFile(region) {
  const result = spawnSync(
    process.execPath,
    ['-e', "process.stdout.write(require('./lib/store').VERSION_FILE)"],
    { cwd: SERVER_DIR, env: childEnv(region), encoding: 'utf8' },
  );
  if (result.status !== 0) {
    throw new Error(`子进程没跑起来（region=${region}）：${result.stderr}`);
  }
  return path.basename(result.stdout);
}

test('UPDATE_REGION=cn 读 version.cn.json', () => {
  expect(selectedFile('cn')).toBe('version.cn.json');
});

test('UPDATE_REGION=global 读 version.global.json', () => {
  expect(selectedFile('global')).toBe('version.global.json');
});

test('不设 UPDATE_REGION 默认 global（与拆分前行为一致）', () => {
  expect(selectedFile(undefined)).toBe('version.global.json');
});

test('UPDATE_REGION 写成别的值 → 启动即失败且点名这个变量', () => {
  const result = spawnSync(process.execPath, ['-e', "require('./lib/store')"], {
    cwd: SERVER_DIR,
    env: childEnv('asia'),
    encoding: 'utf8',
  });
  expect(result.status).not.toBe(0);
  expect(result.stderr).toContain('UPDATE_REGION');
});

test('大陆那份的 downloads 全在 cdn.fnthink.com', () => {
  const data = JSON.parse(
    fs.readFileSync(path.join(SERVER_DIR, 'data', 'version.cn.json'), 'utf8'),
  );
  for (const url of Object.values(data.downloads)) {
    expect(new URL(url).hostname).toBe('cdn.fnthink.com');
  }
});

test('海外那份的 downloads 全在 cdn2.fnthink.top', () => {
  const data = JSON.parse(
    fs.readFileSync(path.join(SERVER_DIR, 'data', 'version.global.json'), 'utf8'),
  );
  for (const url of Object.values(data.downloads)) {
    expect(new URL(url).hostname).toBe('cdn2.fnthink.top');
  }
});
