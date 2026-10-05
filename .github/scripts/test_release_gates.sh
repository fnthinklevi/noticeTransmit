#!/usr/bin/env bash
# E1 闸门的行为测试（反证用，可进 CI）。
#
# 为什么是「从 release_local.sh 里按标记原样提取函数」而不是把 grep 表达式抄一份到这里：
# 抄过来的表达式不是同一份，改了真脚本这里照样绿 ⇒ 典型假绿。提取后一旦标记被挪走或
# 函数被改名，本测试直接以「未取到函数」失败，而不是静默什么都不测。
set -u
SRC=.github/scripts/release_local.sh
command -v grep >/dev/null || { echo "no grep"; exit 1; }
echo "$SRC" | grep -q . || { echo "run from repo root"; exit 2; }
[ -f "$SRC" ] || { echo "MISSING $SRC"; exit 2; }

BLOCK=$(awk '/# >>> E1 闸门/,/# <<< E1 闸门/' "$SRC")
if ! printf '%s' "$BLOCK" | grep -q 'check_update_entry'; then
    echo "FAIL: 未从 $SRC 取到 E1 标记块（标记被改名或删掉了？）"
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
mkdir -p server/data
# 提取来的函数里的 update.md / server/data/version.json 相对路径都落在本临时目录。
eval "$BLOCK"

FAILURES=0
FAILMSG=""
fail() { FAILMSG="$*"; }

check() { # $1=用例名 $2=期望rc(0|nonzero) $3=期望包含的子串(可空) $4..=命令
    local name="$1" want="$2" wantsub="$3"; shift 3
    FAILMSG=""
    local rc=0
    "$@" || rc=$?
    if [ "$want" = "0" ] && [ "$rc" -ne 0 ]; then
        echo "RED  $name: 期望通过，实际 rc=$rc ($FAILMSG)"; FAILURES=$((FAILURES + 1)); return
    fi
    if [ "$want" != "0" ] && [ "$rc" -eq 0 ]; then
        echo "RED  $name: 期望变红，实际却通过了"; FAILURES=$((FAILURES + 1)); return
    fi
    if [ -n "$wantsub" ] && ! printf '%s' "$FAILMSG" | grep -qF "$wantsub"; then
        echo "RED  $name: 红了但原因不对，期望包含「$wantsub」，实际「$FAILMSG」"
        FAILURES=$((FAILURES + 1)); return
    fi
    echo "ok   $name"
}

cat > update.md <<'EOF'
# 版本更新记录

### v1.5.74+113 - 2026-09-21
- 正文
EOF
printf '{"latestVersion": "1.5.74", "latestBuild": 113}\n' > server/data/version.json

echo "── E1 闸门行为 ──"
check "条目齐全 → 通过" 0 "" check_update_entry 1.5.74 113
# 这正是 v1.5.74 实际漏掉的那一类：版本号有、本次构件号没有。
check "重建到 +114 而 update.md 未补 → 红并点名构件号" 1 "没有本次的 +114" check_update_entry 1.5.74 114
check "该版本完全没条目 → 红并说没条目" 1 "完全没有" check_update_entry 1.5.99 113
# 前缀陷阱：+1130 不得被当成 +113。
printf '\n### v1.5.75+1130 - 2026-09-22\n' >> update.md
check "+1130 不算 +113（前缀不串）" 1 "没有本次的 +113" check_update_entry 1.5.75 113
check "version.json 同步 → 通过" 0 "" check_version_json_sync 1.5.74 113
printf '{"latestVersion": "1.5.74", "latestBuild": 999}\n' > server/data/version.json
check "latestBuild 滞后 → 红" 1 "version.json 为" check_version_json_sync 1.5.74 113
printf '{"latestVersion": "1.5.73", "latestBuild": 113}\n' > server/data/version.json
check "latestVersion 滞后 → 红" 1 "version.json 为" check_version_json_sync 1.5.74 113

echo "── 发布说明取自哪一版（check_release_notes）──"
# 更新弹窗里那段说明读的是 version.json 的 changelog。它整段沿用上一版文案时阶段 0–5 全绿也
# 照不出来 —— v1.5.76 实际发生过：四包重构建、sha256 回填都对了，说明还是 1.5.75 那一批的话。
cat > update.md <<'EOF'
# 版本更新记录

### v1.5.74+113 - 2026-09-21

**送达状态判定修正 + 备份恢复兼容**

- 正文

---

**Delivery-status fix + backup restore compatibility**
EOF
# T61：changelog / changelogEn 两份都要能写出来。"-" = 压根不给那个字段
# （"不给"与"给了但是空串"在这条闸门里是同一件事：都按"没有"报）。
notes_json() { # $1 = changelog 首行  $2 = changelogEn 首行（"-" 表示不给）
    if [ "$1" = "-" ]; then
        printf '{"latestVersion":"1.5.74","latestBuild":113}\n' > server/data/version.json
    elif [ "$2" = "-" ]; then
        printf '{"latestVersion":"1.5.74","latestBuild":113,"changelog":"%s\\n\\n正文"}\n' \
            "$1" > server/data/version.json
    else
        printf '{"latestVersion":"1.5.74","latestBuild":113,"changelog":"%s\\n\\n正文",' \
            "$1" > server/data/version.json
        printf '"changelogEn":"%s\\n\\nbody"}\n' "$2" >> server/data/version.json
    fi
}
ZH="送达状态判定修正 + 备份恢复兼容"
EN="Delivery-status fix + backup restore compatibility"
notes_json "$ZH" "$EN"
check "中英首行都取自本次条目 → 通过" 0 "" check_release_notes 1.5.74 113
notes_json "$ZH 与表单统一" "$EN"
check "中文首行与标题行差几个字 → 红并点名不符" 1 "与本次条目不符" check_release_notes 1.5.74 113
notes_json "$ZH" "$EN and form unification"
check "英文首行与条目差几个字 → 红并点名不符" 1 "changelogEn 首行与本次条目不符" check_release_notes 1.5.74 113
notes_json "$ZH" "-"
check "压根没有 changelogEn → 红（英文系统下仍是中文）" 1 "没有 changelogEn" check_release_notes 1.5.74 113
notes_json "-" "$EN"
check "压根没有 changelog 字段 → 红" 1 "没有 changelog" check_release_notes 1.5.74 113
notes_json "$ZH" "$EN"
check "update.md 没有本次条目 → 红并说无从核对" 1 "无从核对" check_release_notes 1.5.99 113
cat > update.md <<'EOF'
### v1.5.74+113 - 2026-09-21

- 正文直接开始，没有加粗标题
EOF
check "条目第一行不是加粗标题 → 红并说没有可对照的标题行" 1 "不是加粗标题" check_release_notes 1.5.74 113
cat > update.md <<'EOF'
### v1.5.74+113 - 2026-09-21

**只有中文标题，没有英文那一条**

- 正文
EOF
notes_json "$ZH" "$EN"
check "条目没有英文标题行 → 红并说无从核对 changelogEn" 1 "没有英文标题行" check_release_notes 1.5.74 113

# 反向自检：闸门表达式本身不能退化成「永远返回 0」的空壳。
if printf '%s' "$BLOCK" | grep -q 'return 1'; then
    echo "ok   提取到的块含失败分支（不是空壳）"
else
    echo "RED  提取到的块没有失败分支 ⇒ 本测试已失去意义"; FAILURES=$((FAILURES + 1))
fi

echo "────────────────────"
if [ "$FAILURES" -eq 0 ]; then echo "PASS E1 gates"; exit 0; fi
echo "FAIL E1 gates: $FAILURES case(s)"
exit 1
