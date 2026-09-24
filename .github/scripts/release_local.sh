#!/bin/bash
# Q4 发版半自动化脚本：固化 base.md §10.2 中已验证的机械化步骤。
#
# 用法：bash .github/scripts/release_local.sh <A.B.C>
#   例：bash .github/scripts/release_local.sh 1.5.64
#
# 覆盖：版本一致性预检 → format/analyze → 4 APK 构建+纯净度验证 → fileSize 回填
#       version.json + 归档同步 → update.md/徽章缺项检查 → CI 等价自检
#       → **模拟器全功能点击 + 备份导入导出往返（阶段 6，硬闸门）** → 汇总报告。
# 不覆盖（人工步骤）：update.md/base.md 文案撰写、官网内容完备性判断、git 操作、部署、
#       真机（实体手机）覆盖升级与真实推送自检。
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
VER="${1:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APKDIR="$ROOT/build/app/outputs/flutter-apk"
PASS=0; FAIL=0

ok()   { echo -e "${GREEN}✅ $*${NC}"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}❌ $*${NC}"; FAIL=$((FAIL+1)); }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
hr()   { echo "────────────────────────────────────────────"; }

# >>> E1 闸门（这两段被 .github/scripts/test_release_gates.sh 按标记原样提取执行，勿改标记）
# update.md 条目必须按**标题行的构件号**匹配。只 grep "v$VER" 时，从 +112 重建到 +113
# 而 update.md 没补 +113 条目也照样通过（v1.5.74 实际发生过），故区分三种红法。
check_update_entry() { # $1=VER $2=BUILD；返回 0=通过，非 0=失败（已打印原因）
    local ver="$1" build="$2" esc
    esc=$(printf '%s' "$ver" | sed 's/\./\\./g')
    if grep -qE "^### v${esc}\+${build}([^0-9]|$)" update.md; then return 0
    elif grep -qE "^### v${esc}\+" update.md; then
        fail "update.md 有 v$ver 的其它构件号、但**没有本次的 +$build**（重建后忘补条目，base.md 步骤 8）"
    else
        fail "update.md 完全没有 v$ver 条目（base.md 步骤 8）"
    fi
    return 1
}
# version.json 回填后的自校验：latestVersion/latestBuild 必须等于本次 pubspec 的 VER+BUILD。
# 回填失败/被 daemon 缓存吞掉时，下载端会继续发旧包与旧 sha256，而脚本一路绿到底。
check_version_json_sync() { # $1=VER $2=BUILD
    local ver="$1" build="$2" vj vjb
    vj=$(grep '"latestVersion"' server/data/version.json | head -1 | grep -oP '"\K[0-9.]+(?=")')
    vjb=$(grep '"latestBuild"' server/data/version.json | head -1 | grep -oP ':\s*\K[0-9]+')
    if [ "$vj" = "$ver" ] && [ "$vjb" = "$build" ]; then return 0; fi
    fail "version.json 为 $vj+$vjb ≠ 本次 $ver+$build（回填未生效：客户端会拿到旧包/旧 sha256）"
    return 1
}
# <<< E1 闸门

[ -d "$ROOT/.git" ] || { echo "请在仓库根目录运行"; exit 2; }
cd "$ROOT"
if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "用法: bash .github/scripts/release_local.sh <A.B.C>  （例: 1.5.64）"; exit 2
fi
BUILD=$(grep -E '^version:' pubspec.yaml | head -1 | cut -d'+' -f2)
VER_FULL="$VER+$BUILD"
hr; echo "🚀 发版流程：v$VER_FULL（build=$BUILD）"; hr

# ── 阶段 0：版本号同步预检（步骤 5/5.1/5.2/5.3 + version.json）──────────────
echo "── 阶段 0：版本号同步预检 ──"
PUBSPEC_V=$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
declare -a CHECK_DOCS=(
    "README.md:badge/Version/$VER/"
    "README-en.md:badge/Version/$VER/"
    "lib/update_manager.dart:_fallbackVersion = '$VER'"
    "android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt:FALLBACK_VERSION = \"$VER\""
)
SYNC_OK=1
if [ "$PUBSPEC_V" != "$VER" ]; then
    fail "pubspec.yaml 版本($PUBSPEC_V) != 目标($VER)。请先完成版本号四处同步（base.md 步骤 5）"; SYNC_OK=0
fi
for entry in "${CHECK_DOCS[@]}"; do
    f="${entry%%:*}"; pat="${entry#*:}"
    if grep -q "$pat" "$f"; then ok "$f 已同步 $VER"; else fail "$f 未同步为 $VER（缺: $pat）"; SYNC_OK=0; fi
done
VJ_V=$(grep '"latestVersion"' server/data/version.json | head -1 | grep -oP '"\K[0-9.]+(?=")')
if [ "$VJ_V" = "$VER" ]; then ok "version.json 已同步 $VER"; else
    warn "version.json 为 $VJ_V ≠ $VER（阶段 3 将自动回填 latestVersion/latestBuild/链接，fileSize 构建后回填）"
fi
check_update_entry "$VER" "$BUILD" || SYNC_OK=0
[ $SYNC_OK -eq 1 ] || { echo -e "${RED}版本号未就绪，先完成 base.md 步骤 5-8 再运行本脚本${NC}"; exit 1; }

# ── 阶段 1：format + analyze（步骤 2/2.1/3）──────────────────────────────
hr; echo "── 阶段 1：format + analyze ──"
dart format lib/ test/ > /dev/null 2>&1
if dart format --set-exit-if-changed lib/ > /dev/null 2>&1; then ok "dart format 幂等"; else fail "dart format 未收敛"; fi
A=$(flutter analyze 2>&1 | tail -1)
if [[ "$A" == *"No issues found"* ]]; then ok "flutter analyze: $A"; else fail "flutter analyze: $A"; fi

# ── 阶段 2：构建 4 个 Release APK（步骤 6，逐构建前停 daemon 防环境残留）──
hr; echo "── 阶段 2：构建 4 个 Release APK ──"
mkdir -p "$APKDIR/v$VER"
build_one() { # $1=flutter target  $2=env 值  $3=归档名
    (cd android && ./gradlew --stop --console=plain > /dev/null 2>&1) || true
    if [ -n "$2" ]; then
        FLUTTER_TARGET_PLATFORM="$2" flutter build apk --release --target-platform "$1" > /tmp/rel_build.log 2>&1
    else
        flutter build apk --release --target-platform "$1" > /tmp/rel_build.log 2>&1
    fi
    local rc=$?
    if [ $rc -ne 0 ]; then fail "$3 构建失败（见 /tmp/rel_build.log）"; return 1; fi
    cp "$APKDIR/app-release.apk" "$APKDIR/v$VER/$3"
    ok "$3 构建完成"
}
build_one "android-arm64" "android-arm64" "notice_arm64_$VER.apk"  || exit 1
build_one "android-arm"   "android-arm"   "notice_arm32_$VER.apk"  || exit 1
build_one "android-x64"   "android-x64"   "notice_x86_$VER.apk"    || exit 1
unset FLUTTER_TARGET_PLATFORM
build_one "android-arm,android-arm64,android-x64" "" "notice_all_$VER.apk" || exit 1

# 纯净度 + versionName 验证（步骤 6.5；Git Bash 无 zip 格式 tar，用 python zipfile）
PY=""; for c in python python3; do p=$(command -v "$c" 2>/dev/null) || p=""; case "$p" in *WindowsApps*) p="" ;; esac; [ -z "$PY" ] && [ -n "$p" ] && PY="$p"; done
echo "── 步骤 6.5：APK 纯净度 + versionName 验证 ──"
if [ -n "$PY" ]; then
    if "$PY" - "$VER" <<'PYEOF'
import glob, os, sys, zipfile
ver = sys.argv[1]
bad = 0
for apk in sorted(glob.glob(f'build/app/outputs/flutter-apk/v{ver}/*.apk')):
    z = zipfile.ZipFile(apk)
    abis = sorted({n.split('/')[1] for n in z.namelist() if n.startswith('lib/') and n.endswith('.so')})
    name = os.path.basename(apk)
    mf = z.read('AndroidManifest.xml').decode('utf-16-le', errors='ignore')
    if 'all' in name:
        good = set(abis) == {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
    else:
        good = len(abis) == 1
    has_ver = f'v{ver}' in mf or ver in mf
    print(('OK ' if good and has_ver else 'BAD ') + name, abis, f'verName={has_ver}')
    bad += 0 if good and has_ver else 1
sys.exit(1 if bad else 0)
PYEOF
    then ok "纯净度与版本验证通过"; else fail "APK 纯净度/版本验证失败"; fi
else
    fail "未找到 python，跳过纯净度验证（base.md 步骤 6.5 须人工执行）"
fi

# ── 阶段 3：fileSize 回填 version.json + 下载链接 + 归档同步（步骤 7/9/10/10.1）──
hr; echo "── 阶段 3：version.json 回填 + 归档同步 ──"
"$PY" - "$VER" <<'PYEOF'
import glob, json, os, shutil, sys
ver = sys.argv[1]
mapping = {'notice_arm64': 'arm64', 'notice_arm32': 'arm32', 'notice_x86': 'x86_64', 'notice_all': 'all'}
sizes, names = {}, {}
for apk in sorted(glob.glob(f'build/app/outputs/flutter-apk/v{ver}/*.apk')):
    base = os.path.basename(apk)
    for pre, key in mapping.items():
        if base.startswith(pre):
            sizes[key] = os.path.getsize(apk); names[key] = base
p = 'server/data/version.json'
d = json.load(open(p, encoding='utf-8'))
import re as _re
m = _re.search(r'^version:\s*\S+\+(\d+)', open('pubspec.yaml', encoding='utf-8').read(), _re.M)
d['latestVersion'], d['latestBuild'] = ver, int(m.group(1))
for k, v in sizes.items():
    d['downloads'][k] = f'https://cdn2.fnthink.top/app/notice/update/{ver}/{names[k]}'
d['fileSizes'] = sizes
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
open(p, 'a', encoding='utf-8').write('\n')
os.makedirs(f'server/public/apks/{ver}', exist_ok=True)
for k, base in names.items():
    shutil.copy2(f'build/app/outputs/flutter-apk/v{ver}/{base}', f'server/public/apks/{ver}/{base}')
print('version.json 回填 + 归档同步完成:', sizes)
PYEOF
"$PY" - "$VER" <<'PYEOF'
import glob, json, os, re, hashlib, sys
ver = sys.argv[1]
mapping = {'notice_arm64': 'arm64', 'notice_arm32': 'arm32', 'notice_x86': 'x86_64', 'notice_all': 'all'}
p = 'server/data/version.json'
d = json.load(open(p, encoding='utf-8'))
# sha256：与 CDN 侧校验值一致（文件字节级 SHA256，十六进制小写）
sha = {}
for apk in sorted(glob.glob(f'build/app/outputs/flutter-apk/v{ver}/*.apk')):
    base = os.path.basename(apk)
    for pre, key in mapping.items():
        if base.startswith(pre):
            h = hashlib.sha256()
            with open(apk, 'rb') as f:
                for chunk in iter(lambda: f.read(1 << 20), b''):
                    h.update(chunk)
            sha[key] = h.hexdigest()
d['sha256'] = sha
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
open(p, 'a', encoding='utf-8').write('\n')
print('sha256 回填完成')
PYEOF
if [ $? -eq 0 ]; then ok "sha256 回填（4 架构）"; else fail "sha256 回填失败"; fi
if [ $? -eq 0 ]; then ok "version.json 与 server/public/apks/$VER 同步"; else fail "version.json 回填/归档失败"; fi

# ── 阶段 4：缺项显式检查（防漏：update.md/徽章/官网动态化说明）────────────
hr; echo "── 阶段 4：文档缺项检查 ──"
check_update_entry "$VER" "$BUILD" && ok "update.md 条目存在（v$VER_FULL）"
check_version_json_sync "$VER" "$BUILD" && ok "version.json latestVersion/latestBuild == v$VER_FULL"
grep -q "badge/Version/$VER/" README.md && grep -q "badge/Version/$VER/" README-en.md && ok "README 双语徽章已同步" || fail "README 徽章未同步"
warn "人工确认项：官网 index.html 是否需要内容/文案更新（版本号已动态化，常规发版免更新）；base.md 审计条目与技术栈校准；隐私政策（如涉数据采集变更）"

# ── 阶段 5：CI 等价自检（步骤 9.1）────────────────────────────────────────
hr; echo "── 阶段 5：CI 等价自检 ──"
T=$(flutter test 2>&1 | tail -1)
[[ "$T" == *"All tests passed"* ]] && ok "flutter test: $T" || fail "flutter test: $T"
(cd android && ./gradlew testDebugUnitTest --console=plain > /tmp/rel_ci.log 2>&1)
[ $? -eq 0 ] && ok "gradlew testDebugUnitTest" || fail "gradlew testDebugUnitTest（见 /tmp/rel_ci.log）"
if bash .github/scripts/check_version_consistency.sh > /tmp/rel_consistency.log 2>&1; then
    ok "check_version_consistency.sh（含 l10n 漏翻）"
else
    fail "check_version_consistency.sh（见 /tmp/rel_consistency.log）"
fi
dart format --set-exit-if-changed lib/ > /dev/null 2>&1 && ok "dart format 幂等" || fail "dart format"
A2=$(flutter analyze 2>&1 | tail -1)
[[ "$A2" == *"No issues found"* ]] && ok "flutter analyze" || fail "flutter analyze: $A2"
NT=$(cd server && npm test 2>&1 | grep "Tests:")
[[ "$NT" == *"passed"* ]] && ok "npm test: $NT" || fail "npm test: $NT"

# ── 阶段 6：模拟器全功能点击 + 导入导出往返（步骤 6.7，硬闸门）────────────
hr; echo "── 阶段 6：模拟器全功能点击 + 备份导入导出往返 ──"
# 为什么不可跳过：1.5.74 上线后"备份导入后打不开 webhook 设置页"是维护者手点撞出来的，
# 而当时前 5 个阶段全绿。单测/构建/一致性自检都覆盖不到"每个页面进去一次、导入导出真做一次"。
# GATE_ALLOW_FAIL=1 是**显式**的临时放行口子（调试本闸门自身时用）；正式发版不得设置。
if bash .github/scripts/release_emulator.sh; then
    ok "模拟器全功能闸门通过"
elif [ "${GATE_ALLOW_FAIL:-0}" = "1" ]; then
    warn "模拟器闸门失败，但 GATE_ALLOW_FAIL=1 ⇒ 本项被显式放行（**这不是发布许可**）"
else
    fail "模拟器全功能闸门失败 —— 按 base.md §10.2，任何一步失败都不允许发布"
fi

# ── 汇总 ──────────────────────────────────────────────────────────────────
hr
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}🎉 v$VER 发版机械步骤全部通过（$PASS 项）${NC}"
    echo "剩余人工步骤：base.md 审计条目/官网完备性确认 → git 提交打 tag → 部署 server/public"
    # E7（口径已定：tag 一律带 v 前缀）。build-apk.yml 的过滤器是 on.push.tags: ['v*']，
    # 而现存 tag 全部无前缀（1.5.71…1.5.74）⇒ 打 tag 从未触发过 release 构建，全靠手动。
    if git rev-parse -q --verify "refs/tags/v$VER" >/dev/null; then
        ok "tag v$VER 已存在（会触发 build-apk.yml）"
    else
        warn "下一步请打 **带 v 前缀** 的 tag：git tag v$VER && git push --tags"
        warn "  打成 \"$VER\"（无前缀）不会触发 build-apk.yml，release 构建就得手动点。"
    fi
    exit 0
else
    echo -e "${RED}共 $FAIL 项失败、$PASS 项通过。按 base.md §10.2：任何一步失败都不允许发布${NC}"
    exit 1
fi
