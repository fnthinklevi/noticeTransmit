#!/bin/bash
# ㊻ 发版硬闸门：在模拟器上跑「全功能点击 + 备份导入导出往返」集成测试。
#
# 用法：bash .github/scripts/release_emulator.sh [AVD 名]
#   不带参数时按顺序自动挑选：ANDROID_AVD_NAME 环境变量 → flutter_emulator → 第一个可用 AVD
#
# 为什么必须有它：base.md §10.2 的发版流程此前只跑到「单元测试 + 构建 4 包 + 一致性自检」，
# 而集成冒烟（smoke_test）只有主链路那几步（㊼ 起是 4 条独立用例），覆盖不到设置页的逐个入口。
# 真实发版事故恰恰出在没被自动化覆盖的地方：
# 备份导入后设置页打不开（1.5.74 上线后被维护者撞出）。本闸门把「每个页面都点一遍、
# 每条 CRUD 都走一次、备份真的导出再导回来」变成发版前必须绿的一项。
#
# 只做三件事：确保有 AVD → 启动并等 boot 完成 → 跑 integration_test/ 下所有测试文件。
# 不构建 APK（flutter test 自己会构建成 debug 包并装机）。
#
# ⚠ 数据安全：`flutter test integration_test/...` 在**签名不匹配**时会先 `adb uninstall`
#   目标应用（连带清掉它的加密数据库）。所以这条闸门**只允许跑在模拟器上**；
#   脚本文末会拒绝任何非 emulator 的设备 id。
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 2

AVD="${1:-${ANDROID_AVD_NAME:-}}"
# SDK 位置优先级：android/local.properties（本仓库权威，实测装在 D:\fnthinklevi\Android\sdk，
# 且 emulator.exe 不在 PATH 上）→ ANDROID_SDK_ROOT → ANDROID_HOME → 默认用户目录。
sdk_from_local_props() {
    [ -f android/local.properties ] || return 0
    local raw
    raw=$(grep -E '^sdk\.dir=' android/local.properties | head -1 | cut -d= -f2-)
    raw=${raw//\\\\//}                      # Windows 反斜杠转斜杠
    # D:/path → /d/path（Git Bash 挂载写法）
    if printf '%s' "$raw" | grep -qE '^[A-Za-z]:/'; then
        printf '/%s/%s' "$(printf '%s' "${raw:0:1}" | tr 'A-Z' 'a-z')" "${raw:3}"
    else
        printf '%s' "$raw"
    fi
}
SDK="$(sdk_from_local_props || true)"
[ -n "$SDK" ] && [ -d "$SDK" ] || SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}"
EMULATOR="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"
for c in "$EMULATOR" "$EMULATOR.exe"; do [ -x "$c" ] && EMULATOR="$c" && break; done
for c in "$ADB" "$ADB.exe"; do [ -x "$c" ] && ADB="$c" && break; done
command -v emulator > /dev/null 2>&1 || true
[ -x "$EMULATOR" ] || { fail "找不到 emulator（SDK=$SDK；设 ANDROID_SDK_ROOT 后重试）"; exit 1; }
[ -x "$ADB" ] || { fail "找不到 adb（SDK=$SDK）"; exit 1; }

# ── 选 AVD ────────────────────────────────────────────────────────────────
AVD_LIST=$("$EMULATOR" -list-avds 2>/dev/null | tr -d '\r')
if [ -z "$AVD_LIST" ]; then
    fail "本机没有可用 AVD。先建一个（示例）：flutter emulators --create --name flutter_emulator"
    exit 1
fi
if [ -z "$AVD" ]; then
    if printf '%s\n' "$AVD_LIST" | grep -qx "flutter_emulator"; then
        AVD=flutter_emulator
    else
        AVD=$(printf '%s\n' "$AVD_LIST" | head -1)
        warn "未指定 AVD，回落到第一个：$AVD"
    fi
fi
printf '%s\n' "$AVD_LIST" | grep -qx "$AVD" || {
    fail "AVD '$AVD' 不存在。可用：$(printf '%s ' $AVD_LIST)"
    exit 1
}

# ── 启动（未运行时才启动，跑完由本脚本负责关掉自己起的）──────────────────
STARTED_BY_US=0
# ⚠ adb 里的 serial 是 `emulator-5554`，**不含 AVD 名**；要看 AVD 名必须问 `adb emu avd name`。
avd_of_serial() {
    "$ADB" -s "$1" emu avd name 2>/dev/null | tr -d '\r' | head -1
}
running_serial_for() {
    local serial
    for serial in $("$ADB" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1}'); do
        [ "$(avd_of_serial "$serial")" = "$1" ] && { printf '%s' "$serial"; return 0; }
    done
    return 1
}
SERIAL=$(running_serial_for "$AVD" || true)
if [ -z "$SERIAL" ]; then
    ok "启动模拟器 $AVD（headless，无音频、无启动动画；GPU=${GATE_GPU:-auto}）"
    # GATE_GPU=swiftshader_indirect 用来**对齐 CI 的渲染后端**（integration_test.yml 用的是软件渲染，
    # 比本机 -gpu auto 慢）。怀疑"本地绿 CI 红"是设备画像差异时，就按 CI 的画像跑一遍复现。
    ( "$EMULATOR" -avd "$AVD" -no-window -no-audio -no-boot-anim \
        -gpu "${GATE_GPU:-auto}" -no-snapshot-save > /tmp/release_emulator.log 2>&1 & )
    STARTED_BY_US=1
    for _ in $(seq 1 90); do
        SERIAL=$(running_serial_for "$AVD" || true)
        [ -n "$SERIAL" ] && break
        sleep 2
    done
    [ -n "$SERIAL" ] || { fail "180s 内 $AVD 没出现在 adb devices（见 /tmp/release_emulator.log）"; exit 1; }
fi
case "$SERIAL" in
    emulator-*) : ;;
    *) fail "目标设备不是模拟器（$SERIAL）—— 本闸门禁止在真机上跑，会清掉真机数据"; exit 1 ;;
esac
export ANDROID_SERIAL="$SERIAL"
ok "adb 目标：$SERIAL（AVD=$AVD）"

# ── 等 boot_completed ─────────────────────────────────────────────────────
BOOT=""
for _ in $(seq 1 90); do
    BOOT=$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [ "$BOOT" = "1" ] && break
    sleep 2
done
[ "$BOOT" = "1" ] || { fail "180s 内 sys.boot_completed 仍不为 1"; exit 1; }
ok "模拟器已就绪（$SERIAL）"

# ── 跑集成测试 ────────────────────────────────────────────────────────────
# 默认跑 integration_test/ 下全部文件；调试单个文件时可设 GATE_FILES 覆盖。
FILES=${GATE_FILES:-$(ls integration_test/*_test.dart 2>/dev/null | tr '\n' ' ')}
[ -n "$FILES" ] || { fail "integration_test/ 下没有测试文件"; exit 1; }
ok "待跑：$FILES"
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy 2>/dev/null || true
# 构建模式说明：`flutter test` 没有 --release/--profile 开关（实测报
# "Could not find an option named --release"），集成测试只能跑 debug 包。
# ⇒ 这道闸门覆盖的是"功能与页面在所有入口都点得动、导入导出真跑得通"，
#   release 包特有的问题（混淆、tree-shaking、签名、kReleaseMode 分支）仍靠
#   base.md 步骤 6.6 与 ㉚ 的真机人工自检，别把本闸门当成 release 验证。
LOG=/tmp/release_emulator_test.log
flutter test $FILES -d "$SERIAL" > "$LOG" 2>&1
RC=$?
tail -25 "$LOG"
if [ $RC -eq 0 ]; then
    ok "模拟器全功能点击 + 导入导出往返：通过"
else
    fail "集成测试失败（完整日志：$LOG）"
fi

# ── 收尾：只关本脚本自己起的模拟器 ────────────────────────────────────────
if [ "$STARTED_BY_US" = "1" ]; then
    "$ADB" -s "$SERIAL" emu kill > /dev/null 2>&1 || true
    ok "已关闭本脚本启动的模拟器 $AVD（保留快照外的现场请设 ANDROID_AVD_NAME 手动跑）"
fi
exit $RC
