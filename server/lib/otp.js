/**
 * OTP（TOTP）验证逻辑：otplib v13 插件配置与 verify 封装
 *
 * 从 server.js 拆分而来，保持原有行为不变。
 */

const { generateSecret, generateURI, verify, createGuardrails, NobleCryptoPlugin, ScureBase32Plugin } = require('otplib');
// otplib v13：需显式提供 crypto / base32 插件
const otpCrypto = new NobleCryptoPlugin();
const otpBase32 = new ScureBase32Plugin();

// v13 默认要求 secret 至少 16 字节(128bit)。旧版本生成的 16 字符 base32 secret 仅 10 字节，
// 验证时需放宽 MIN_SECRET_BYTES guardrail，否则会抛 SecretTooShortError。
function buildOtpVerifyOptions(secret) {
  const decodedBytes = Math.floor(String(secret).replace(/=+$/, '').length * 5 / 8);
  const opts = { secret, crypto: otpCrypto, base32: otpBase32, epochTolerance: 30 };
  if (decodedBytes < 16) {
    opts.guardrails = createGuardrails({ MIN_SECRET_BYTES: decodedBytes });
  }
  return opts;
}

// v13 的 verify 返回 Promise<{ valid, delta, ... }>，统一封装为 boolean
async function verifyOtp(secret, token) {
  try {
    const result = await verify({ ...buildOtpVerifyOptions(secret), token });
    return !!result.valid;
  } catch (e) {
    console.error('OTP 验证异常:', e.message);
    return false;
  }
}

module.exports = {
  verifyOtp,
  generateSecret,
  generateURI,
};
