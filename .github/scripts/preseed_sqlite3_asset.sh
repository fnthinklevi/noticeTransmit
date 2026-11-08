#!/usr/bin/env bash
# 为什么需要这个脚本（2026-11-08 analyze job 实测）：
#   GitHub release 资产 CDN 全站性抖动（间歇 504，ninja 等无关仓库同病）；sqlite3 的
#   build hook 下载预编译库时**不校验 HTTP 状态码**，504 错误页的字节被原样流进
#   sha256 校验 ⇒ "Hash of downloaded file … is bef140a1…, expected …"（bef140a1…
#   正是 GitHub 错误页的 hash，任何文件名都得到同一个值）⇒ exit 255，测试没跑就红。
#
#   对策：带 hash 校验地重试预取，把文件放进 hook 的共享缓存
#   `.dart_tool/hooks_runner/shared/sqlite3/build/download-<sha256前8位>/`。
#   hook 的缓存复用分支会先对已有文件算 sha256，命中即不再联网
#   （见 sqlite3/src/hook/compile/description.dart 的 downloadIntoOutputDirectoryShared）。
#
#   release tag 与期望 hash 都从「本次解析出来的」包内 asset_hashes.dart 现读，
#   上游发新版后本脚本无需改动。
#
# 用法：preseed_sqlite3_asset.sh <release资产名> <缓存内文件名>
#   Linux 宿主测试：preseed_sqlite3_asset.sh libsqlite3.x64.linux.so libsqlite3.so
#   x86_64 模拟器构建：preseed_sqlite3_asset.sh libsqlite3.x64.android.so libsqlite3.so
set -u

ASSET="${1:?usage: preseed_sqlite3_asset.sh <asset> <output-name>}"
OUT="${2:?usage: preseed_sqlite3_asset.sh <asset> <output-name>}"

HASHES_FILE=$(find "${PUB_CACHE:-$HOME/.pub-cache}"/hosted -path '*sqlite3-*/lib/src/hook/asset_hashes.dart' 2>/dev/null | sort -V | tail -1)
if [ -z "$HASHES_FILE" ]; then
  echo "❌ asset_hashes.dart not found under PUB_CACHE —— 本步必须排在 flutter pub get 之后"
  exit 1
fi

TAG=$(grep -oP "releaseTag = '\K[^']+" "$HASHES_FILE")
EXPECT=$(grep -oP "'${ASSET//./\\.}': '\K[0-9a-f]{64}" "$HASHES_FILE")
if [ -z "$TAG" ] || [ -z "$EXPECT" ]; then
  echo "❌ 从 $HASHES_FILE 读不到 tag 或 $ASSET 的期望 hash"
  exit 1
fi

DEST=".dart_tool/hooks_runner/shared/sqlite3/build/download-${EXPECT:0:8}"
mkdir -p "$DEST"
URL="https://github.com/simolus3/sqlite3.dart/releases/download/$TAG/$ASSET"

for i in $(seq 1 20); do
  code=$(curl -sS -L -o "$DEST/.tmp" -w '%{http_code}' "$URL" 2>/dev/null || echo 000)
  if [ "$code" = "200" ] && echo "$EXPECT  $DEST/.tmp" | sha256sum -c - >/dev/null 2>&1; then
    mv "$DEST/.tmp" "$DEST/$OUT"
    echo "✅ $ASSET 第 $i 次尝试取回，hash 校验通过，已放入 hook 缓存"
    exit 0
  fi
  echo "attempt $i: http=$code（GitHub release CDN 抖动中），15s 后重试"
  sleep 15
done

echo "❌ $ASSET 连续 20 次未取到（GitHub release CDN 故障未恢复）"
exit 1
