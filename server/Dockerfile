# 通知转发助手 · 更新服务端生产镜像（T183，2026-10-24）
#
# 纪律：镜像内**零密钥、零状态** —— .env 与 data/ 一律不进镜像（本文件只拷运行时三样 +
# .dockerignore 双保险）；配置全部走运行时环境变量，数据走挂卷。
# 部署/纯净度核查清单见 base.md §14.4；CI 闸门见 .github/workflows/server-docker.yml。

# 与 server/package.json engines.node >=24 一致；CI（analyze.yml）同样以 Node 24 跑契约测试
FROM node:24-alpine

WORKDIR /app

# 依赖层：只拷清单。锁文件不变时该层缓存直接命中；
# ci 而非 install：按 package-lock.json 锁定；dev 依赖（jest/prettier/babel）生产不需要。
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# 应用层：只拷运行时需要的三样。
# 明确不拷：babel.config.js（仅 jest 用）、test/、tools/、data/、.env、node_modules（.dockerignore 一并挡）。
COPY server.js ./
COPY lib ./lib
COPY public ./public

ENV NODE_ENV=production
# 数据目录容器内固定 /app/data；部署方挂卷（compose 已带 ./data:/app/data）。
# 未挂卷时落在容器层 —— 仅用于 CI 自检，生产必须挂卷（数据含 TOTP/会话/封锁表，见 base.md §14.10）。
ENV DATA_DIR=/app/data
RUN mkdir -p /app/data && chown node:node /app/data
VOLUME ["/app/data"]

# 生产不 root：node 镜像自带 uid/gid 1000 的 node 用户。
# 挂载的宿主 data/ 需可写：chown 1000:1000 data 或在 compose 里 user: "1000:1000" 对齐宿主 uid。
USER node

EXPOSE 3456

# /health 在 IP 封锁豁免名单（server/lib/store.js IP_BLOCK_EXEMPT_PREFIXES），无鉴权可探。
# shell 形式让 ${PORT} 参与展开（exec 形式不展开）。
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${PORT:-3456}/health" || exit 1

CMD ["node", "server.js"]
