// Jest 专用 Babel 配置：@otplib 依赖链中的 @scure/base / @noble/hashes 为纯 ESM 包，
// Jest 默认模块系统无法解析，需经 babel-jest 转译为 CJS（仅测试时生效，不影响 node 运行）。
module.exports = {
  presets: [
    ['@babel/preset-env', { targets: { node: 'current' } }]
  ]
};
