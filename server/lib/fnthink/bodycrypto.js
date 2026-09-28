// 未送达消息正文的静态加密（T34-B）。
//
// 契约在这里只说了一件事：`privacy.serverStoresBodyPlaintext = false` 且
// `retention.whilePending = "static_encrypted"`。本模块就是那条的落地，
// 算法 / IV 长度 / 派生 info 全部从契约 `retention.bodyAtRest` 读，不在代码里写死。
//
// ⚠ 与既有 TOTP 加密路径**刻意不同**：`store.encryptSecret` 在没有 ENCRYPTION_KEY 时
// 退回明文（`{plain: ...}` + 一条 warn）—— 那是"运维少配一个环境变量不该被锁在门外"的取舍。
// 正文不能照抄：那是当场违反协议。所以这里没有密钥就**抛**，调用方拒绝入队。

'use strict';

const crypto = require('crypto');

const MIN_KEY_CHARS = 16;

function atRestConfig(contract) {
  const cfg = (contract.retention || {}).bodyAtRest;
  if (!cfg || typeof cfg !== 'object') {
    throw new Error('契约缺 retention.bodyAtRest（正文静态加密的参数必须由契约定）');
  }
  return cfg;
}

/// 由 ENCRYPTION_KEY 派生正文专用密钥（HKDF-SHA256，info 取自契约 keyInfo）。
///
/// 派生而不是直接用，是为了**域分离**：同一个环境变量既保护 TOTP secret 又保护消息正文时，
/// 一处密钥管理出错不该顺手把另一处也打开。info 写在契约里，换 info 等于换协议（旧密文解不开）。
function deriveBodyKey(contract, envKey) {
  const cfg = atRestConfig(contract);
  if (typeof envKey !== 'string' || envKey.trim().length < MIN_KEY_CHARS) {
    // 不返回"明文模式"，也不降级：让调用方拿到一个明确的错误。
    throw new Error(
      `未配置（或过短）ENCRYPTION_KEY ⇒ 拒绝存储消息正文。` +
        `契约要求 whilePending=${(contract.retention || {}).whilePending}，` +
        `而 bodyAtRest.refuseWithoutKey=${cfg.refuseWithoutKey}`,
    );
  }
  const info = String(cfg.keyInfo || '');
  if (!info) throw new Error('retention.bodyAtRest.keyInfo 不能为空（它是域分离的标签）');
  return Buffer.from(
    crypto.hkdfSync(
      'sha256',
      Buffer.from(envKey, 'utf8'),
      Buffer.alloc(0),
      Buffer.from(info, 'utf8'),
      32,
    ),
  );
}

/// 正文密文的**唯一形状**：`v1.<base64(iv)>.<base64(data)>.<base64(tag)>`。
///
/// 为什么不是一个 `{iv, data, tag}` 对象、也不用十六进制：写咽喉上有一道"值长得像口令就拒绝落盘"
/// 的闸门（`table.assertNoPlaintextSecrets`），而 GCM 的 tag 是 16 字节 = **32 个十六进制字符**，
/// 正好等于契约里端点长期口令的位数 —— 用 hex 存的每一条正常密文都会被那道闸门判成"一把口令"。
/// 用 `.` 连接的 base64 段就不可能落进 Crockford 字母表，闸门与密文从此互不干扰；
/// 顺带把版本号写进串里（换信封格式时旧的能识别出来，而不是解出一堆乱码）。
function encodeEnvelope(iv, data, tag) {
  return ['v1', iv.toString('base64'), data.toString('base64'), tag.toString('base64')].join('.');
}

function decodeEnvelope(text) {
  const parts = String(text).split('.');
  if (parts.length !== 4 || parts[0] !== 'v1') {
    throw new Error(
      `正文密文不是 v1 信封形状（拒绝按明文读，也不猜别的格式）：${String(text).slice(0, 12)}…`,
    );
  }
  return {
    iv: Buffer.from(parts[1], 'base64'),
    data: Buffer.from(parts[2], 'base64'),
    tag: Buffer.from(parts[3], 'base64'),
  };
}

/// 加密正文，返回一个字符串（每次调用都用新 IV —— 同一条正文被 dedupe 覆盖两次
/// 会得到两份不同密文，这正是要的性质）。
function encryptBody(contract, envKey, plaintext) {
  const cfg = atRestConfig(contract);
  if (cfg.algorithm !== 'aes-256-gcm') throw new Error(`不支持的正文加密算法：${cfg.algorithm}`);
  const ivBytes = Number(cfg.ivBytes);
  if (ivBytes !== 12) throw new Error(`GCM 的 IV 长度必须是 12 字节，契约为 ${cfg.ivBytes}`);
  const key = deriveBodyKey(contract, envKey);
  const text = plaintext === null || plaintext === undefined ? '' : String(plaintext);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const data = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return encodeEnvelope(iv, data, cipher.getAuthTag());
}

/// 解密正文。**没有明文回退分支**：盘上出现不是密文信封的正文，说明写入路径被绕过，
/// 这时抛错比"尽力解出来"有用 —— 后者会把缺陷读成正常数据。
function decryptBody(contract, envKey, envelope) {
  const key = deriveBodyKey(contract, envKey);
  const { iv, data, tag } = decodeEnvelope(envelope);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}

module.exports = {
  MIN_KEY_CHARS,
  decodeEnvelope,
  decryptBody,
  deriveBodyKey,
  encodeEnvelope,
  encryptBody,
};
