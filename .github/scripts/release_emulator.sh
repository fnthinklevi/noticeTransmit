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
# 出口约定：只要模拟器是本脚本起的，**boot 超时 / 测试失败 / Ctrl-C 都要关掉它**（EXIT trap），
# 不许把它留在后台 —— 这是维护者的硬性要求（2026-09-25）。手动起的模拟器脚本不会碰。
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
# 闸门：拿到 serial 就登记清理，**任何出口**（boot 超时、测试失败、Ctrl-C）都不把模拟器留在后台。
cleanup_emulator() {
    case "${SERIAL:-}" in
        emulator-*) : ;;                       # 只接受模拟器 serial，绝不碰真机
        *) return 0 ;;
    esac
    if [ "$STARTED_BY_US" = "1" ]; then
        "$ADB" -s "$SERIAL" emu kill > /dev/null 2>&1 || true
        ok "已关闭本脚本启动的模拟器 $AVD（$SERIAL）"
    fi
}
trap cleanup_emulator EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
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

# ── 起跑前清空被测应用的数据 ──────────────────────────────────────────────
# AVD 的 /data 是**跨启动保留**的，`flutter test` 也只是覆盖安装：上一次跑完（或被 Ctrl-C
# 掐断的那一次）留下的通道/规则会原封不动留在库里。后果有两面：
#   ① 假红 —— 本次跑到"仅测试不许落库"时看见的是上次建的通道（2026-09-26 实测撞到）；
#   ② 更危险的假绿 —— 后面的分节可能靠上次的残留才"点得动"，闸门于是测的已经不是这份代码。
# 包名与 android/app/build.gradle 的 applicationId 同源（debug 无 suffix）。
# 分三种情形说清楚，别把"没装过"报成"清不掉"：装过却清不掉就是本轮结论不可信，宁可停。
case "$SERIAL" in
    emulator-*)
        if "$ADB" -s "$SERIAL" shell pm list packages com.fnthink.notice \
                2>/dev/null | tr -d '\r' | grep -q com.fnthink.notice; then
            "$ADB" -s "$SERIAL" shell pm clear com.fnthink.notice > /dev/null 2>&1 \
                && ok "已清空被测应用数据（com.fnthink.notice）" \
                || { fail "pm clear 失败：残留会让本轮结论失真（可能是上一轮建的通道帮它点过去的）"; exit 1; }
        else
            ok "被测应用尚未安装：无残留可清"
        fi
        ;;
    *) fail "目标设备不是模拟器（$SERIAL）—— 清数据这一步禁止对真机执行"; exit 1 ;;
esac

# ── 跑集成测试 ────────────────────────────────────────────────────────────
# 默认跑 integration_test/ 下全部文件；调试单个文件时可设 GATE_FILES 覆盖。
# ⚠ 但 t09_stamp_test.dart **必须**排除在默认清单外：它一个原生方法都不 mock，
#   被闸门跑起来就等于"每次发版往用户配置的真实群 / 邮箱发一轮测试消息"，而且它的
#   结论要人在收件端看一眼才有意义（闸门里没人能替它答）。盖章走：
#   dart tools/t09_stamp.dart send
#   t22_upgrade_test.dart 同理排除：它会卸载应用、灌旧形状数据（那是覆盖升级自检，不是
#   一次回归），而本闸门起跑前刚 pm clear 过 —— 两者互相拆台，各跑各的。
FILES=${GATE_FILES:-$(ls integration_test/*_test.dart 2>/dev/null | grep -vE '(t09_stamp_test|t22_upgrade_test)\.dart' | tr '\n' ' ')}
[ -n "$FILES" ] || { fail "integration_test/ 下没有测试文件"; exit 1; }
ok "待跑：$FILES"
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy 2>/dev/null || true
# 构建模式说明：`flutter test` 没有 --release/--profile 开关（实测报
# "Could not find an option named --release"），集成测试只能跑 debug 包。
# ⇒ 这道闸门覆盖的是"功能与页面在所有入口都点得动、导入导出真跑得通"，
#   release 包特有的问题（混淆、tree-shaking、签名、kReleaseMode 分支）仍靠
#   base.md 步骤 6.6 与 ㉚ 的真机人工自检，别把本闸门当成 release 验证。
LOG=/tmp/release_emulator_test.log
# ── 三层时间口径必须成序（2026-09-26 一天四轮 GATE_RC=124 逼出来的）──────────
#   节内预算 3′ ×2 ≤ 每条用例超时（walkthrough 四条：6/6/7/6 ⇒ Σ=25′）
#   ≤ 单次调用回退上限 GATE_CASE_TIMEOUT（最重的 7′ + 装机/splash 4′）
#   ≤ 整轮（四条 + smoke）+ 构建 ≤ CI job 60′
# 谁掉链子都会把"功能红"和"超时红"混成一团：
#   整轮 > 用例 ⇒ 用例级那条永远轮不到说话，挂住只剩一个 124（四轮都是这个形状）；
#   整轮 < 用例 + smoke ⇒ 挂住的那条被超时判掉后，smoke 还没跑完就被掐（第 6 轮实测 24:22 +3 −1）。
GATE_TEST_TIMEOUT=${GATE_TEST_TIMEOUT:-900}
GATE_CASE_TIMEOUT=${GATE_CASE_TIMEOUT:-660}
# ── 逐条用例分**独立调用**跑（第 16 轮实测出来的）─────────────────────────────
# 为什么四条用例不能在一个进程里跑完：某一节的 body 挂住之后**取消不掉**（`_step` 的超时
# 只能把它记成红，不能让它停下来），它继续占着 flutter_test binding 的 test zone ⇒ 同一文件
# 里**后面的用例**一秒都跑不了，全死在 `binding.dart 3056 '!inTest': is not true`。
# 第 16 轮实测：2/4 挂住并被点名之后，3/4 与 4/4 连一条断言都没执行就一起红了 —— 那两条正是
# "规则与更多页"和"备份往返"（1.5.74 事故那一类）的覆盖。isolate 之间不共享这个 zone，
# 所以按用例名分几次调用才是真隔离；代价是每次多一分钟左右的重装与启动。
# 用例名从测试文件里**派生**，不在脚本里再抄一份 ⇒ 两边各写各的、朝同一方向写错，
# 就是本项目反复撞过的"守卫自己成了第二份拷贝"。数不到名字时**判红**而不是退回整档一次。
WALK=integration_test/release_walkthrough_test.dart
GATE_CASES=""
if [ -z "${GATE_FILES:-}" ] && [ -f "$WALK" ]; then
    GATE_CASES=$(grep -oE "'闸门 [0-9]+/[0-9]+" "$WALK" | tr -d "'" | sort -u)
    [ -n "$GATE_CASES" ] || {
        fail "从 $WALK 里数不到「闸门 n/4」用例名 ⇒ 用例改名或合回去了：逐条隔离会静默退化成整档一次"
        exit 1
    }
    ok "逐条隔离：$(echo "$GATE_CASES" | tr '\n' ' ')"
fi
RC=0
: > "$LOG"

# 每次独立调用之前都清一遍设备数据。⚠ 这条是"重试"能不能成立的前提：
# 挂住的那条用例是在**跑的中途**被打断的 —— 它已经建好的规则/通道留在了库里，
# 而 `_assemble` 只擦三族通道与历史记录（引擎规则与关键词没擦，拆前后都一样）。
# 于是重跑 3/4 时，5.4a 那条 `hasLength(2)` 会数到上一趟留下的两条 ⇒ **假的"功能红"**。
# ⚠ `< /dev/null` 不是装饰：这两条命令都跑在 `while read` 循环里，而 `adb shell` 与
# `flutter test` 都会从 stdin 读 —— 第 20 轮实测它们把循环剩下的三个用例名**吃掉**了，
# 整轮只跑了 1/4 就退出（是靠"缺 GATE-DIFF-RING 判红"当场逮住的，不是靠人看）。
clear_app_data() {
    # 装过就必须清得掉：`|| true` 会把"这一步没做成"咽掉 —— 报告里看不见，而下一档测试的
    # 干净起点是否成立就没人核对过。
    # ⚠ 别把它读成"曾因此跑出过假红"：v1.5.76 第一趟 smoke 2/4 找不到「共 1 条记录」时，
    #   这里写的归因是"闸门 4/4 留下的历史没清掉"，**那个归因已被否证** —— 第 24/25 轮每次调用
    #   前 `pm list packages` 都报"尚未安装"（`flutter test` 跑完会卸载应用，历史就在应用自己的
    #   库里 ⇒ 跨档残留没有通道）。那次失败的原因因此回到未知（同码在别的轮次四条全绿）。
    if "$ADB" -s "$SERIAL" shell pm list packages com.fnthink.notice < /dev/null 2>&1 \
            | tr -d '\r' | grep -q com.fnthink.notice; then
        "$ADB" -s "$SERIAL" shell pm clear com.fnthink.notice < /dev/null > /dev/null 2>&1 \
            || { fail "pm clear 失败：残留会让本轮结论失真（可能是上一轮建的通道帮它点过去的）"; return 9; }
        ok "已清空被测应用数据（本次独立调用之前）"
    else
        ok "被测应用尚未安装：无残留可清"
    fi
}

run_case() {  # $1=日志标签，其余=flutter test 的文件与参数
    local label="$1"
    shift
    echo "──── 独立调用：$label" >> "$LOG"
    clear_app_data || return 1
    timeout "$GATE_CASE_TIMEOUT" flutter test "$@" -d "$SERIAL" \
        < /dev/null >> "$LOG" 2>&1
    local rc=$?
    echo "──── 结束：$label rc=$rc" >> "$LOG"
    return $rc
}

# 这条用例这段日志里，是不是**只有挂住**（没有功能红）？只有挂住才允许重跑一次。
# 判据用 `GATE-STEP-FAIL` 那行的异常名，不用"有没有 Expected:"：`_verdict` 把挂住也
# 汇总成一条 `Expected: empty`，看 Expected 会把挂住误判成功能红 ⇒ 永远不重试。
# 反向也一样：只看"非挂住"的 GATE-STEP-FAIL，一条断言失败就把重试的门关掉。
case_hang_only() {  # $1=日志标签
    local seg hangs funcs
    seg=$(awk -v n="──── 独立调用：$1" '
        index($0, n) == 1 { f = 1 }
        f { print }
        f && /^──── 结束：/ { exit }
    ' "$LOG")
    hangs=$(printf '%s' "$seg" | grep -ac \
        'GATE-STEP-FAIL.*\(TimeoutException\|Guarded function conflict\)')
    funcs=$(printf '%s' "$seg" | grep -a 'GATE-STEP-FAIL' | grep -avc \
        'TimeoutException\|Guarded function conflict')
    [ "${hangs:-0}" -gt 0 ] && [ "${funcs:-0}" -eq 0 ]
}

# 一节挂住之后，同一用例剩下的节会被跳过（见 walkthrough 的 `_step`），所以一条用例挂住
# 大约只花 3′ —— 重跑它是划算的。**默认只重试一次**（这是 2026-09-27 定下的口径），
# 想多给一次机会就显式设 `GATE_HANG_RETRIES=2`：本机今天实测四处挂住分布在 5.3/5.4a/5.5/
# 5.8/第 6 节/第 7 节上。同一节连挂两次出现过一次（第 23 轮的 5.8 首次与重试都挂），
# 但定向实验里同一节第二次就绿了（第 24 轮：先挂 5.5、再跑整条通过）⇒ 挂住不是确定性的，
# 多给一次机会的边际收益是真的，只是每多一次就多 3–4 分钟。
GATE_HANG_RETRIES=${GATE_HANG_RETRIES:-1}

if [ -n "$GATE_CASES" ]; then
    # 其余测试文件（smoke 等）仍一次跑完；walkthrough 按用例名拆开跑
    OTHERS=$(printf '%s\n' $FILES | grep -v "^$WALK\$" | tr '\n' ' ')
    while IFS= read -r case_name; do
        [ -n "$case_name" ] || continue
        run_case "$case_name" "$WALK" --plain-name "$case_name"
        case_rc=$?
        attempt=0
        while [ "$case_rc" -ne 0 ] && [ "$attempt" -lt "$GATE_HANG_RETRIES" ] \
                && case_hang_only "$case_name"; do
            attempt=$((attempt + 1))
            warn "$case_name 首次是**挂住**（无功能红）⇒ 按口径重跑这一条一次（第 $attempt/$GATE_HANG_RETRIES 次重试）"
            run_case "$case_name 重跑$attempt" "$WALK" --plain-name "$case_name"
            case_rc=$?
            [ "$case_rc" -eq 0 ] && ok "$case_name 第 $attempt 次重试通过（挂点见上面的 GATE-STEP-FAIL）"
        done
        # RC 只记"有没有红"（0/1）：某条被回退上限掐掉时 124 已经逐条说过了，
        # 再把它当"整轮超时"复述一遍会在报告里出现两个互相矛盾的结论。
        [ "$case_rc" -eq 0 ] || RC=1
        if [ "$case_rc" -eq 124 ]; then
            fail "$case_name 跑满单次回退上限（${GATE_CASE_TIMEOUT}s）被 timeout 掐掉 ⇒ 不是功能红，是没返回"
        fi
    done <<< "$GATE_CASES"
    # 跑没跑到，比跑成什么颜色更基本：数一下每条用例的收尾行。
    # （第 20 轮实测：`while read` 的循环体里 `adb shell` / `flutter test` 从 stdin 把
    #  剩下的三个用例名吃掉了，循环"成功地跑完"却只执行了 1/4 —— 那种轮次看起来全绿。）
    # 数的是**去重之后的用例名**（重跑那一次不算第二条）：否则"1/4 没跑、3/4 跑了两遍"
    # 也会凑够四条，这条检查就成了摆设。
    ran=$(grep -a '^──── 结束：' "$LOG" | grep -av '重跑' \
        | sed 's/^──── 结束：//; s/ rc=[0-9]*$//' | sort -u | grep -c '闸门 [0-9]*/[0-9]*$')
    planned=$(printf '%s\n' "$GATE_CASES" | grep -c .)
    if [ "$ran" -lt "$planned" ]; then
        fail "闸门只跑了 $ran/$planned 条用例 ⇒ 有用例**根本没执行**（循环被循环体读走 stdin 就是这个形状）"
        RC=1
    else
        ok "四条用例都跑到了（$ran/$planned 条独立调用有收尾行）"
    fi
    if [ -n "${OTHERS// /}" ]; then
        echo "──── 独立调用：$OTHERS" >> "$LOG"
        # 清不掉就不跑：这一档的干净起点没人核对过，跑出来的结论不能算数
        if clear_app_data; then
            timeout "$GATE_TEST_TIMEOUT" flutter test $OTHERS -d "$SERIAL" \
                < /dev/null >> "$LOG" 2>&1
            [ "$?" -eq 0 ] || RC=1
        else
            fail "smoke 这一档没有跑：清数据失败 ⇒ 它的干净起点无人核对，宁可不跑"
            RC=1
        fi
    fi
else
    timeout "$GATE_TEST_TIMEOUT" flutter test $FILES -d "$SERIAL" > "$LOG" 2>&1
    RC=$?
fi
if [ $RC -eq 124 ]; then
    tail -25 "$LOG"
    fail "整轮超时（${GATE_TEST_TIMEOUT}s）被 timeout 掐掉 ⇒ 这不是功能红，是某一节没返回"
    echo "    先看上面的 GATE-STEP-FAIL / GATE-MARK：节内预算会把挂住的那节点名出来"
    echo "    若一条 FAIL 都没有，说明挂在没被 _step 包住的裸段（见 walkthrough 的 _mark 痕迹）"
else
    tail -25 "$LOG"
fi
if [ $RC -eq 0 ]; then
    ok "模拟器全功能点击 + 导入导出往返：通过"
else
    fail "集成测试失败（完整日志：$LOG）"
fi

# ── 影子差异出口（T72 的第一步）───────────────────────────────────────────
# 「差异清零才切主路径」是 T21 定的门槛，而那个环住在设备 prefs 里，此前**没有任何
# 发版侧出口**读它 ⇒ 这句话没人能核对。闸门末尾无条件打一行 `GATE-DIFF-RING ▸ n=…`，
# 这里把它接进报告。**缺这一行 = 出口自己坏了**（"清零了"与"没人打印"在报告里长得
# 一模一样，正是本仓库反复撞过的那类空转），所以默认清单下判红。
RING=$(grep -a "GATE-DIFF-RING" "$LOG" | tail -1 || true)
if [ -n "${RING:-}" ]; then
    ok "$RING"
    # 锚在标记上取第一个数字：`s/.*n=\([0-9]*\)` 是贪婪匹配，而差异明细里就可能出现
    # "库=n=55 镜像=3" 这种文本 —— 抓到那个数，报告里的 n 对不上真实差异，人还看不出来。
    N=$(printf '%s' "$RING" | sed -n 's/.*GATE-DIFF-RING[^0-9]*\([0-9][0-9]*\).*/\1/p')
    if [ "${N:-0}" -gt 0 ]; then
        warn "影子差异 n=${N}（>0）⇒ T21 的切换门槛未满足：先按 kind 排查再谈切主路径（本项不另判成败）"
    fi
elif [ -n "${GATE_FILES:-}" ]; then
    warn "本轮跑的是 GATE_FILES 子集 ⇒ 没核对影子差异出口（正式发版必须跑默认清单）"
elif [ $RC -eq 0 ]; then
    fail "闸门没有打印 GATE-DIFF-RING ⇒ 差异出口失效，『差异清零才切主路径』无从核对（日志：$LOG）"
    RC=1
else
    warn "本轮集成测试本就失败，未再核对差异出口（先修上面的红）"
fi

# ── 收尾：关模拟器由上面的 EXIT trap 负责（含失败与中断路径）────────────────
exit $RC
