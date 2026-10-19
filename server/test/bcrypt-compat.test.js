'use strict';

// bcryptjs 3 生成的哈希前缀从 $2a$ 变成 $2b$；本仓存量恢复码/管理员令牌是 2.4.3 写的 $2a$。
// 这条用例钉住「升级后旧哈希仍能校验」——没有它，jest 全绿也只能证明新哈希自洽。
const bcrypt = require('bcryptjs');

const PRE_UPGRADE_HASH = '$2a$10$D8hFO8KTDHUSSrq13dtjDu2nk9xeH0yVBmlr8fYZtpU9zUt0tTcs2';

describe('bcryptjs 3 与升级前哈希的兼容性', () => {
  test('$2a$ 旧哈希仍可校验', () => {
    expect(bcrypt.compareSync('pre-upgrade-token', PRE_UPGRADE_HASH)).toBe(true);
    expect(bcrypt.compareSync('wrong-token', PRE_UPGRADE_HASH)).toBe(false);
  });
});
