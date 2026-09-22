#!/usr/bin/env bash
# 代码格式校验统一入口：本地与 CI 跑同一支脚本，避免「本地过了 CI 红」。
#
# 覆盖三路：
#   1) Dart      —— dart format（Flutter SDK 自带，已在 CI 单独有一步，这里一并纳入本地一键）
#   2) Kotlin    —— ktlint 独立 CLI（不侵入 build.gradle.kts；规则见仓库根 .editorconfig）
#   3) 服务端 JS —— prettier（配置 server/.prettierrc，作用域见 .prettierignore）
#
# 用法：
#   bash .github/scripts/check_format.sh            # 只校验（不改文件），有违规 exit 1
#   bash .github/scripts/check_format.sh --fix      # 就地格式化（等价各工具的 --format / --write）
#
# 依赖：
#   - Java 17+（Kotlin 校验用；Android Studio 自带 JBR 即可）
#   - 首次运行会把 ktlint 的 fat jar（约 70MB）下到 ~/.cache/ktlint，之后离线可用
#     来源固定为 Maven Central 的 com.pinterest.ktlint:ktlint-cli（版本见 KTLINT_VER）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

KTLINT_VER="1.8.0"
KTLINT_JAR="${KTLINT_JAR:-$HOME/.cache/ktlint/ktlint-cli-$KTLINT_VER-all.jar}"
KTLINT_URL="https://repo1.maven.org/maven2/com/pinterest/ktlint/ktlint-cli/$KTLINT_VER/ktlint-cli-$KTLINT_VER-all.jar"
KOTLIN_GLOBS=("android/app/src/**/*.kt")

MODE="check"
if [[ "${1:-}" == "--fix" ]]; then MODE="fix"; fi

# ---- 解析 java / dart 可执行文件（Windows 与 Linux 通用）----
find_bin() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then echo "$name"; return 0; fi
  local hint="$2"
  if [[ -n "$hint" && -x "$hint" ]]; then echo "$hint"; return 0; fi
  return 1
}

JAVA_BIN="$(find_bin java "${JAVA_HOME:-}/bin/java")" || {
  echo "[format] 跳过：找不到 java（可设 JAVA_HOME，例：Android Studio 的 jbr 目录）"
  JAVA_BIN=""
}
DART_BIN="$(find_bin dart "D:/flutter/bin/cache/dart-sdk/bin/dart.exe")" || DART_BIN="$(find_bin flutter)" || {
  echo "[format] 失败：找不到 dart/flutter" >&2; exit 2
}

rc=0

# ---- 1) Dart ----
echo "── Dart: dart format"
if [[ "$MODE" == "fix" ]]; then
  "$DART_BIN" format lib test >/dev/null
  echo "   已格式化"
else
  if "$DART_BIN" format --output=none --set-exit-if-changed lib test; then
    echo "   OK"
  else
    echo "   ✗ 有文件未格式化（跑 dart format lib test 或本脚本 --fix）"; rc=1
  fi
fi

# ---- 2) Kotlin: ktlint ----
if [[ -n "$JAVA_BIN" ]]; then
  echo "── Kotlin: ktlint $KTLINT_VER"
  if [[ ! -f "$KTLINT_JAR" ]]; then
    mkdir -p "$(dirname "$KTLINT_JAR")"
    echo "   首次运行：下载 ktlint fat jar → $KTLINT_JAR"
    curl -sSL --max-time 600 -o "$KTLINT_JAR" "$KTLINT_URL"
  fi
  if [[ "$MODE" == "fix" ]]; then
    "$JAVA_BIN" -jar "$KTLINT_JAR" --format "${KOTLIN_GLOBS[@]}"
    echo "   已格式化"
  else
    if "$JAVA_BIN" -jar "$KTLINT_JAR" "${KOTLIN_GLOBS[@]}"; then
      echo "   OK"
    else
      echo "   ✗ 有 Kotlin 文件不符合 .editorconfig（跑本脚本 --fix）"; rc=1
    fi
  fi
else
  rc=1
fi

# ---- 3) 服务端 JS: prettier ----
echo "── Server JS: prettier"
# 复用 server/package.json 的 scripts（单一真值来源：作用域与配置都在那边）
if [[ "$MODE" == "fix" ]]; then JS_NPM_SCRIPT="format"; else JS_NPM_SCRIPT="format:check"; fi
if ( cd server && npm run --silent "$JS_NPM_SCRIPT" >/dev/null ); then
  [[ "$MODE" == fix ]] && echo "   已格式化" || echo "   OK"
else
  echo "   ✗ 有 JS 未格式化（cd server && npm run format）"; rc=1
fi

echo
if [[ "$rc" == 0 ]]; then
  echo "✅ 格式校验全部通过（Dart / Kotlin / 服务端 JS）"
else
  echo "❌ 存在格式违规：跑 bash .github/scripts/check_format.sh --fix 后复查"
fi
exit "$rc"
