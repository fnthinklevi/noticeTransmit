#!/bin/bash
# P1-1：四类稳定性场景的发版前回归闸门。
#
# 背景：1.6.3～1.6.7 的更新日志集中在同一族问题 —— 数据库打不开/锁死、长后台卡在
# 「加载通知记录」、离线队列丢历史、启动页无界等待。这些只在「长锁屏 / 弱网 / 低内存 /
# 进程被杀」这几种设备状态下出现，单测与页面点击闸门都覆盖不到。
#
# 用法：bash .github/scripts/release_matrix.sh [APK 路径]
#   - 不传 APK：优先取 build/app/outputs/flutter-apk/v*/notice_all_*.apk，
#     其次取 x86_64 包；都没有时构建 debug x64 包（只验逻辑，不代表 release 包）。
#   - release_local.sh 的阶段 6.5 会带着本版通用包路径调用本脚本。
#
# 只做四件事：起模拟器 → 装包 → 按场景制造状态 → 断言「首帧/进程/前台/无崩溃」。
# 过夜锁屏、真实弱网、厂商杀后台等自动化替代不了的项见 docs/release_regression_matrix.md。
#
# ⚠ 本脚本会卸载/覆盖安装被测应用（applicationId com.fnthink.notice）。
#   因此**只允许操作 emulator-***；发现真机 serial 直接停，不清任何数据、不发任何广播。
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}❌ $*${NC}"; FAIL=$((FAIL+1)); }
skip() { echo -e "${YELLOW}⏭️  $*${NC}"; SKIP=$((SKIP+1)); }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
note() { echo -e "${CYAN}   $*${NC}"; }
hr()   { echo "────────────────────────────────────────────"; }

PASS=0; FAIL=0; SKIP=0
PKG=com.fnthink.notice
# release 清单移除了 MainActivity 上的 MAIN/LAUNCHER，线上启动组件是默认中文图标别名；
# debug 包里这两条路都能走，所以统一显式启动这个别名，两种包行为一致。
ACTIVITY=.LauncherDefaultZh
LOCK_SECONDS=${MATRIX_LOCK_SECONDS:-30}
SETTLE_SECONDS=${MATRIX_SETTLE_SECONDS:-10}
START_TIMEOUT=${MATRIX_START_TIMEOUT:-60}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 2

TMP=$(mktemp -d 2>/dev/null || true)
[ -n "${TMP:-}" ] || TMP="/tmp/release_matrix.$$"
mkdir -p "$TMP"
LOG="$TMP/matrix.log"
: > "$LOG"

# ── 定位 SDK / adb / emulator（与 release_emulator.sh 同一优先级）────────────
sdk_from_local_props() {
    [ -f android/local.properties ] || return 0
    local raw
    raw=$(grep -E '^sdk\.dir=' android/local.properties | head -1 | cut -d= -f2-)
    raw=${raw//\\\\//}
    if printf '%s' "$raw" | grep -qE '^[A-Za-z]:/'; then
        printf '/%s/%s' "$(printf '%s' "${raw:0:1}" | tr 'A-Z' 'a-z')" "${raw:3}"
    else
        printf '%s' "$raw"
    fi
}
SDK="$(sdk_from_local_props || true)"
[ -n "${SDK:-}" ] && [ -d "$SDK" ] || SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}"
EMULATOR="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"
for c in "$EMULATOR" "$EMULATOR.exe"; do [ -x "$c" ] && EMULATOR="$c" && break; done
for c in "$ADB" "$ADB.exe"; do [ -x "$c" ] && ADB="$c" && break; done
[ -x "$EMULATOR" ] || { fail "找不到 emulator（SDK=$SDK；设 ANDROID_SDK_ROOT 后重试）"; exit 1; }
[ -x "$ADB" ] || { fail "找不到 adb（SDK=$SDK）"; exit 1; }

# ── 选 AVD ────────────────────────────────────────────────────────────────
AVD="${MATRIX_AVD:-${ANDROID_AVD_NAME:-}}"
AVD_LIST=$("$EMULATOR" -list-avds 2>/dev/null | tr -d '\r')
[ -n "$AVD_LIST" ] || {
    fail "本机没有可用 AVD。先建一个（示例）：flutter emulators --create --name flutter_emulator"
    exit 1
}
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

ashell() { "$ADB" -s "$SERIAL" shell "$@" < /dev/null 2>&1; }
PID_RE='^[0-9]+$'
process_pid() {
    ashell pidof "$PKG" | tr -d '\r' | tr -s ' ' '\n' | grep -E "$PID_RE" | head -1
}
PKG_RE=${PKG//./\\.}
foreground_ok() {
    ashell dumpsys activity activities \
        | grep -aE "(mResumedActivity|topResumedActivity).*${PKG_RE}/" > /dev/null
}

NETWORK_THROTTLED=0
restore_network() {
    [ "${NETWORK_THROTTLED:-0}" = "1" ] || return 0
    timeout 10 "$ADB" -s "$SERIAL" emu network delay none > /dev/null 2>&1 || true
    timeout 10 "$ADB" -s "$SERIAL" emu network speed full > /dev/null 2>&1 || true
    ashell svc wifi enable > /dev/null 2>&1 || true
    ashell svc data enable > /dev/null 2>&1 || true
    NETWORK_THROTTLED=0
}
cleanup_emulator() {
    restore_network || true
    case "${SERIAL:-}" in
        emulator-*) : ;;
        *) return 0 ;;
    esac
    if [ "${STARTED_BY_US:-0}" = "1" ]; then
        "$ADB" -s "$SERIAL" emu kill > /dev/null 2>&1 || true
        echo "已关闭本脚本启动的模拟器 $AVD（$SERIAL）"
    fi
}
trap cleanup_emulator EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ── 启动（已在运行则复用，且**不**负责关闭别人起的模拟器）──────────────────
STARTED_BY_US=0
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
    echo "启动模拟器 $AVD（headless，无音频、无启动动画；GPU=${MATRIX_GPU:-auto}）"
    ( "$EMULATOR" -avd "$AVD" -no-window -no-audio -no-boot-anim \
        -gpu "${MATRIX_GPU:-auto}" -no-snapshot-save > "$TMP/emulator.log" 2>&1 & )
    STARTED_BY_US=1
    for _ in $(seq 1 90); do
        SERIAL=$(running_serial_for "$AVD" || true)
        [ -n "$SERIAL" ] && break
        sleep 2
    done
    [ -n "$SERIAL" ] || { fail "180s 内 $AVD 没出现在 adb devices（见 $TMP/emulator.log）"; exit 1; }
else
    warn "复用已在运行的模拟器 $AVD（$SERIAL）：本轮会覆盖安装被测应用"
fi
case "$SERIAL" in
    emulator-*) : ;;
    *) fail "目标设备不是模拟器（$SERIAL）—— 本闸门禁止在真机上跑，会清掉真机数据"; exit 1 ;;
esac
export ANDROID_SERIAL="$SERIAL"

BOOT=""
for _ in $(seq 1 90); do
    BOOT=$(ashell getprop sys.boot_completed | tr -d '\r')
    [ "$BOOT" = "1" ] && break
    sleep 2
done
[ "$BOOT" = "1" ] || { fail "180s 内 sys.boot_completed 仍不为 1"; exit 1; }
ok "模拟器已就绪（$SERIAL，AVD=$AVD）"

# ── 选 APK 并安装 ────────────────────────────────────────────────────────
APK="${1:-${MATRIX_APK:-}}"
if [ -z "$APK" ]; then
    APK=$(ls -t build/app/outputs/flutter-apk/v*/notice_all_*.apk 2>/dev/null | head -1)
    [ -n "$APK" ] || APK=$(ls -t build/app/outputs/flutter-apk/v*/notice_x86_64_*.apk 2>/dev/null | head -1)
fi
if [ -z "$APK" ]; then
    note "没有找到发版 APK ⇒ 构建 debug x64 包用于矩阵（只验逻辑，不代表 release 包）"
    if ! FLUTTER_TARGET_PLATFORM=android-x64 flutter build apk --debug \
            --target-platform android-x64 > "$TMP/build.log" 2>&1; then
        fail "debug APK 构建失败（见 $TMP/build.log）"
        exit 1
    fi
    APK="build/app/outputs/flutter-apk/app-debug.apk"
fi
[ -f "$APK" ] || { fail "APK 不存在：$APK"; exit 1; }
note "被测 APK：$APK"

if ! "$ADB" -s "$SERIAL" install -r -t "$APK" > "$TMP/install.log" 2>&1; then
    warn "覆盖安装失败（签名不一致或包残留）⇒ 卸载后重装（仅模拟器）"
    "$ADB" -s "$SERIAL" uninstall "$PKG" > /dev/null 2>&1 || true
    if ! "$ADB" -s "$SERIAL" install -t "$APK" >> "$TMP/install.log" 2>&1; then
        fail "APK 安装失败（见 $TMP/install.log）"
        exit 1
    fi
fi
if ashell pm list packages | tr -d '\r' | grep -qx "package:$PKG"; then
    ok "已安装 $PKG"
else
    fail "安装后找不到包 $PKG"
    exit 1
fi

# ── 场景断言工具 ─────────────────────────────────────────────────────────
# 冷启动到「首帧画出」：ActivityTaskManager 的 Displayed 行 = 系统承认这一屏已经画出来，
# 比 mResumedActivity 更接近用户看到的「启动页有没有卡住」。
wait_displayed() { # $1=标签 $2=超时秒（可选）
    local label="$1" limit="${2:-$START_TIMEOUT}" i line
    ashell logcat -c > /dev/null 2>&1 || true
    ashell am force-stop "$PKG" > /dev/null 2>&1 || true
    sleep 1
    if ! timeout 30 "$ADB" -s "$SERIAL" shell am start -W -n "$PKG/$ACTIVITY" \
            < /dev/null > "$TMP/start.log" 2>&1; then
        fail "$label：am start 失败（见 $TMP/start.log）"
        return 1
    fi
    for i in $(seq 1 "$limit"); do
        line=$(ashell logcat -d | grep -a "Displayed $PKG/" | tail -1 || true)
        [ -n "$line" ] && break
        sleep 1
    done
    if [ -z "${line:-}" ]; then
        fail "$label：${limit}s 内没有画出首帧（logcat 无 Displayed $PKG/）"
        return 1
    fi
    ok "$label：首帧已画出（${line}）"
    sleep "$SETTLE_SECONDS"
    return 0
}

assert_process_alive() { # $1=标签
    local pid
    pid=$(process_pid || true)
    if [ -n "$pid" ]; then
        ok "$1：进程存活（pid=$pid）"
        return 0
    fi
    fail "$1：进程已不在（系统或崩溃把它带走了）"
    return 1
}

assert_foreground() { # $1=标签
    if foreground_ok; then
        ok "$1：应用仍在前台"
        return 0
    fi
    fail "$1：应用不在前台（可能被系统回收或卡在启动页之外）"
    ashell dumpsys activity activities | grep -aE "mResumedActivity|topResumedActivity" | tail -2
    return 1
}

assert_no_crash() { # $1=标签
    local out
    out=$(ashell logcat -d || true)
    if printf '%s' "$out" | grep -aqE "FATAL EXCEPTION|ANR in ${PKG_RE}"; then
        fail "$1：logcat 出现崩溃/ANR"
        printf '%s' "$out" | grep -aE "FATAL EXCEPTION|ANR in ${PKG_RE}" | tail -6
        return 1
    fi
    if printf '%s' "$out" | grep -aqiE "database is locked|unable to open database file"; then
        note "$1：logcat 出现数据库锁/打开失败关键词（首帧与前台判据已单独判定）"
        printf '%s' "$out" | grep -aiE "database is locked|unable to open database file" | tail -3
    fi
    ok "$1：无 FATAL/ANR"
    return 0
}

# ── 场景 0：基线（装包后必须能冷启动并稳定停留）────────────────────────────
hr; echo "── 场景 0/4：基线冷启动 ──"
if wait_displayed "基线冷启动"; then
    assert_process_alive "基线" || true
    assert_foreground "基线" || true
    assert_no_crash "基线" || true
fi

# ── 场景 1：进程被杀 ─────────────────────────────────────────────────────
hr; echo "── 场景 1/4：进程被杀后重新打开 ──"
if wait_displayed "进程被杀-首次启动"; then
    ashell input keyevent KEYCODE_HOME > /dev/null 2>&1 || true
    sleep 2
    ashell am kill "$PKG" > /dev/null 2>&1 || true
    sleep 2
    if [ -n "$(process_pid || true)" ]; then
        warn "am kill 没有终止进程（可能被前台服务/系统绑定保护）⇒ 用 am force-stop 模拟更强的终止"
        ashell am force-stop "$PKG" > /dev/null 2>&1 || true
        sleep 1
    else
        ok "进程已被 am kill 终止"
    fi
    if wait_displayed "进程被杀-重新打开"; then
        assert_process_alive "进程被杀-重新打开" || true
        assert_foreground "进程被杀-重新打开" || true
        assert_no_crash "进程被杀-重新打开" || true
    fi
fi

# ── 场景 2：低内存 ───────────────────────────────────────────────────────
hr; echo "── 场景 2/4：低内存裁剪 ──"
if wait_displayed "低内存-启动"; then
    pid=$(process_pid || true)
    if [ -z "$pid" ]; then
        fail "低内存：拿不到 pid，无法触发裁剪"
    else
        trim_out=$(ashell am send-trim-memory "$pid" RUNNING_CRITICAL || true)
        if printf '%s' "$trim_out" | grep -qiE "error|unknown|usage"; then
            fail "低内存：am send-trim-memory 调用失败：$trim_out"
        else
            ok "已对 pid=$pid 发送 RUNNING_CRITICAL 内存裁剪"
            sleep 3
            assert_process_alive "低内存-裁剪后" || true
            assert_foreground "低内存-裁剪后" || true
            ashell input keyevent KEYCODE_HOME > /dev/null 2>&1 || true
            sleep 1
            ashell am start -n "$PKG/$ACTIVITY" > /dev/null 2>&1 || true
            sleep 2
            assert_foreground "低内存-回到前台" || true
            assert_no_crash "低内存" || true
        fi
    fi
fi

# ── 场景 3：弱网 ─────────────────────────────────────────────────────────
hr; echo "── 场景 3/4：弱网冷启动 ──"
NETWORK_THROTTLED=1
if timeout 10 "$ADB" -s "$SERIAL" emu network delay gprs > "$TMP/net.log" 2>&1 \
        && grep -qi '^OK' "$TMP/net.log"; then
    timeout 10 "$ADB" -s "$SERIAL" emu network speed gsm >> "$TMP/net.log" 2>&1 || true
    ok "模拟器网络已限到 GPRS/GSM（弱网）"
    if wait_displayed "弱网-冷启动"; then
        assert_process_alive "弱网-冷启动" || true
        assert_foreground "弱网-冷启动" || true
        assert_no_crash "弱网-冷启动" || true
    fi
    restore_network
    ok "网络已恢复（delay=none / speed=full）"
    if wait_displayed "弱网-恢复网络后重开"; then
        assert_process_alive "弱网-恢复网络后重开" || true
        assert_no_crash "弱网-恢复网络后重开" || true
    fi
else
    warn "模拟器控制台限速不可用（见 $TMP/net.log）⇒ 退回断网模拟"
    ashell svc wifi disable > /dev/null 2>&1 || true
    ashell svc data disable > /dev/null 2>&1 || true
    sleep 2
    if ashell ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; then
        skip "弱网：模拟器无法切断默认网络（ping 仍通）⇒ 必须在真机补做弱网项（见矩阵文档）"
    else
        ok "已断开模拟器网络（ping 不通）"
        if wait_displayed "断网-冷启动"; then
            assert_process_alive "断网-冷启动" || true
            assert_foreground "断网-冷启动" || true
            assert_no_crash "断网-冷启动" || true
        fi
    fi
    restore_network
    ok "网络已恢复"
fi

# ── 场景 4：长锁屏（短时）────────────────────────────────────────────────
hr; echo "── 场景 4/4：长锁屏（${LOCK_SECONDS}s）──"
if wait_displayed "长锁屏-启动"; then
    ashell input keyevent KEYCODE_POWER > /dev/null 2>&1 || true
    note "已熄屏，保持 ${LOCK_SECONDS}s（过夜锁屏 ≥8h 是人工项）"
    sleep "$LOCK_SECONDS"
    ashell input keyevent KEYCODE_POWER > /dev/null 2>&1 || true
    sleep 2
    ashell wm dismiss-keyguard > /dev/null 2>&1 || ashell input keyevent KEYCODE_MENU > /dev/null 2>&1 || true
    sleep 1
    ashell am start -n "$PKG/$ACTIVITY" > /dev/null 2>&1 || true
    sleep 2
    assert_process_alive "长锁屏-唤醒" || true
    assert_foreground "长锁屏-唤醒" || true
    assert_no_crash "长锁屏-唤醒" || true
fi

# ── 汇总 ─────────────────────────────────────────────────────────────────
hr
echo "稳定性回归矩阵汇总：PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
echo "日志：$LOG（完整 logcat 见 $TMP）"
echo "人工必须补做（docs/release_regression_matrix.md）："
echo "  · 真机过夜锁屏 ≥8 小时"
echo "  · 真实弱网/断网恢复（地铁、电梯）"
echo "  · 厂商后台清理（小米/华为/OPPO/vivo）"
echo "  · 低内存真机（开发者选项 → 后台进程限制）"
echo "  · 覆盖安装升级 + 迁移失败回滚演练"
if [ "$FAIL" -gt 0 ]; then
    if [ "${MATRIX_ALLOW_FAIL:-0}" = "1" ]; then
        warn "有 $FAIL 项红，但 MATRIX_ALLOW_FAIL=1 ⇒ 本项被显式放行（**这不是发布许可**）"
        exit 0
    fi
    echo -e "${RED}稳定性矩阵失败：任何一类场景红都不允许发布${NC}"
    exit 1
fi
if [ "$SKIP" -gt 0 ]; then
    if [ "${MATRIX_ALLOW_SKIP:-0}" = "1" ]; then
        warn "有 $SKIP 项因环境限制没跑成，但 MATRIX_ALLOW_SKIP=1 ⇒ 显式放行（人工项仍必须补做）"
        exit 0
    fi
    echo -e "${RED}稳定性矩阵有 $SKIP 项没跑成：不许把「没跑」当成「通过」；请换环境复跑或按文档人工补做${NC}"
    exit 1
fi
echo -e "${GREEN}稳定性矩阵（自动化部分）全部通过${NC}"
exit 0
