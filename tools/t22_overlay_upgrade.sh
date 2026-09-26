#!/usr/bin/env bash
#
# roadmap T22：覆盖升级自检 —— 旧构建装好规则 → 覆盖安装当前构建 → 逐项比对。
#
# 为什么要有这个脚本（而不是只跑单元测试）：v12→v13 的迁移在 sqflite_common_ffi 上
# 已经逐条验过，但那条路**没有**真实的 SQLCipher 库、没有 Android Keystore 里的库密钥、
# 也没有原生与 Dart 共用的那份 `FlutterSharedPreferences.xml`。"覆盖升级后设置还在吗"
# 这个问题只有真机/模拟器形状的环境能回答。
#
# 关键手法：**两个包都用 debug 签名**。debug APK 可 `run-as`（release 不行）⇒ 能灌旧形状
# 的数据；而同签名让 `flutter test` 的覆盖安装**保留数据**（不触发 adb uninstall）——
# 覆盖升级的前提正是"数据没被清"，所以签名一旦不同，测的就不是升级而是新装。
#
# 用法：
#   bash tools/t22_overlay_upgrade.sh                 # 需要时自己起 AVD，跑完关掉
#   bash tools/t22_overlay_upgrade.sh --device=emulator-5554
#   OLD_APK=/path/app-debug.apk bash tools/t22_overlay_upgrade.sh
#
# 旧构建 APK 怎么来（T20 之前那版才有"原生也写同一把键"的形状）：
#   git worktree add outputs/_t22_pre cf21deb
#   (cd outputs/_t22_pre && flutter build apk --debug --target-platform android-x64)
# ⚠ 那份 worktree 就是本脚本的夹具，留在 gitignore 的 outputs/ 下别删 —— 重建它要么等
#   gradle 全量编一遍，要么等人想起来 cf21deb 是哪个提交。不想要了就：
#   git worktree remove --force outputs/_t22_pre
#
# ⚠ 只认 emulator-* 序列；不接受真机（这条规则与盖章工具、闸门脚本同一条）。
# ⚠ 不进阶段 6 闸门：它会卸载并重建目标设备上的应用数据（闸门默认清单已排除，有守卫钉）。
#
set -uo pipefail

APP_ID=com.fnthink.notice
AVD="${ANDROID_AVD_NAME:-ci_api34_pixel6}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
ADB="${SDK:+$SDK/platform-tools/adb}"
ADB="${ADB:-adb}"
EMULATOR="${SDK:+$SDK/emulator/emulator}"
EMULATOR="${EMULATOR:-emulator}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD_APK="${OLD_APK:-$ROOT/outputs/_t22_pre/build/app/outputs/flutter-apk/app-debug.apk}"
GPU="${GATE_GPU:-swiftshader_indirect}"
# flutter 可执行文件在入口归一次，后面统一走 run_flutter()：混着写 `"${FLUTTER:-flutter}"`
# 与裸 `"$FLUTTER"` 时，后者在 set -u 下会表现成"脚本半路退出"（架构守卫扫裸用变量钉住这条）。
FLUTTER_BIN="${FLUTTER:-}"
DART="${FLUTTER_DART:-D:/flutter/bin/cache/dart-sdk/bin/dart.exe}"
SNAPSHOT="${FLUTTER_SNAPSHOT:-D:/flutter/bin/cache/flutter_tools.snapshot}"
# 一律**不回退到 PATH 上的 flutter**：PATH 里随便一个别的 flutter，就会让"当前构建"
# 和被测代码不是同一份（闸门脚本同一条理由）。
# ⚠ 改这个脚本时注意两件事：
#   1. 不要在被测设备上跑集成测试（它启动/杀掉的是 com.fnthink.notice，会毁掉现场）；
#   2. 跑起来的同一时间**不要编辑这个文件** —— bash 是按字节偏移边读边执行的，
#      中途改文件会让它从错位处解析出一句语法错误（第五轮就是这么死的）。
run_flutter() {
  if [ -n "$FLUTTER_BIN" ]; then
    "$FLUTTER_BIN" "$@"
  else
    "$DART" "$SNAPSHOT" "$@"
  fi
}

ok()   { printf '\033[0;32m✅ %s\033[0m\n' "$*"; }
warn() { printf '\033[0;33m⚠️  %s\033[0m\n' "$*"; }
fail() { printf '\033[0;31m❌ %s\033[0m\n' "$*" >&2; }

SERIAL=""
for a in "$@"; do
  case "$a" in
    --device=*) SERIAL="${a#--device=}" ;;
    *) fail "不认识的参数：$a（宁可不跑，也不要拼错后回退去自动挑设备）"; exit 2 ;;
  esac
done

booted_here=0
start_emulator() {
  command -v "$EMULATOR" >/dev/null 2>&1 || { fail "找不到 emulator 可执行文件"; exit 1; }
  warn "没有 emulator-* 设备，启动 AVD $AVD（跑完由本脚本关闭）"
  "$EMULATOR" -avd "$AVD" -no-audio -no-boot-anim -gpu "$GPU" >/dev/null 2>&1 &
  booted_here=1
  for _ in $(seq 1 60); do
    if [ "$("$ADB" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      SERIAL=emulator-5554
      return 0
    fi
    sleep 4
  done
  fail "模拟器 240s 内没起来"
  exit 1
}

cleanup() {
  if [ "$booted_here" = 1 ] && [ -n "$SERIAL" ]; then
    ok "关闭本脚本启动的模拟器 $SERIAL"
    "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1
  fi
}
trap cleanup EXIT INT TERM

command -v "$ADB" >/dev/null 2>&1 || { fail "找不到 adb（设 ANDROID_SDK_ROOT 或装 PATH）"; exit 1; }

if [ -z "$SERIAL" ]; then
  found="$( "$ADB" devices | awk '/^[a-zA-Z0-9_-]+[[:space:]]+device$/{print $1}' | grep '^emulator-' || true )"
  count="$(printf '%s' "$found" | grep -c . || true)"
  if [ "$count" = "1" ]; then
    SERIAL="$found"
  elif [ "$found" = "" ]; then
    start_emulator
  else
    fail "多台 emulator 在跑，用 --device= 指定：$found"; exit 1
  fi
fi
case "$SERIAL" in
  emulator-*) : ;;
  *) fail "目标不是模拟器（$SERIAL）：这一步会卸载并重建该设备上的应用数据"; exit 2 ;;
esac
A() { "$ADB" -s "$SERIAL" "$@"; }
RA() { A shell "run-as $APP_ID $*" 2>/dev/null; }

[ -f "$OLD_APK" ] || { fail "找不到旧构建 APK：$OLD_APK（用 git worktree 在 T20 之前的提交上 flutter build apk --debug 生成）"; exit 1; }
NEW_APK="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"

ok "设备：$SERIAL"

# ── 1. 干净起点：卸载旧装（这里**就是要**清掉重来；设备是模拟器，不是任何人的手机）──
A uninstall "$APP_ID" >/dev/null 2>&1 || warn " uninstall 未生效（多半是没装过），继续"

# ── 2. 装 T20 之前的构建，并先放行首屏（隐私弹窗、语言）──
A install -r "$OLD_APK" >/dev/null || { fail "旧构建安装失败"; exit 1; }
ok "已装旧构建：$(basename "$OLD_APK")"
xml() {
  # 刚装完时 shared_prefs/ 还不存在（首版就在这里静默失败了一次：cat 重定向不建目录，
  # 而 `|| warn` 会让它看起来无害）。mkdir -p 之后再写，且写失败**直接停**。
  A shell "run-as $APP_ID mkdir -p /data/data/$APP_ID/shared_prefs" >/dev/null 2>&1
  if ! printf '%s\n' "$1" | A shell "run-as $APP_ID sh -c 'cat > /data/data/$APP_ID/shared_prefs/FlutterSharedPreferences.xml'" 2>/dev/null; then
    fail "灌 prefs 失败（run-as 只对 debug 包有效；确认装的是 debug 构建）"
    exit 1
  fi
  # 回读核实：写进去的东西必须真在文件里，否则后面全部结论都是空的。
  if [ -z "$("$ADB" -s "$SERIAL" shell "run-as $APP_ID cat /data/data/$APP_ID/shared_prefs/FlutterSharedPreferences.xml" 2>/dev/null | tr -d '\r')" ]; then
    fail "prefs 文件回读为空"
    exit 1
  fi
}
xml '<?xml version='"'"'1.0'"'"' encoding='"'"'utf-8'"'"' standalone='"'"'yes'"'"' ?>
<map>
  <boolean name="flutter.privacy_policy_accepted" value="true" />
  <boolean name="flutter.has_launched" value="true" />
  <string name="flutter.app_language">zh</string>
  <string name="flutter.last_system_lang">zh</string>
</map>'

# ── 3. 让旧构建自己跑一次：建 v12 的加密库 + 把库密钥写进安全存储 ──
A shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
ok "旧构建启动，等它建库（25s）"
sleep 25
A shell am force-stop "$APP_ID"
if [ "$(RA "ls /data/data/$APP_ID/databases" | grep -c notice_transmit_encrypted || true)" = "0" ]; then
  fail "旧构建没建出加密库（databases/ 下没有 notice_transmit_encrypted.db）⇒ 这一步没成，后面的比对无意义"
  exit 1
fi
# inode 记下来：覆盖升级必须作用在**同一个库文件**上。若它其实是"打不开→备份重建空库"，
# 规则也可能看起来还在（T20 的补导入分支会救回来），但那样测的就不是迁移了。
DB_BEFORE="$(A shell "run-as $APP_ID ls -i /data/data/$APP_ID/databases/notice_transmit_encrypted.db" | tr -d '\r' | awk '{print $1}')"
ok "旧库 inode=$DB_BEFORE"

# ── 3b. 当前包**先编好**，再灌种子；而且每次都要真编 ──
# 竞态窗口是这样的：旧构建的前台服务是 START_STICKY 的，被杀之后系统随时可能把它拉回来；
# 它一活过来就把读到的镜像按原生那套 `enabled ?: false` 回写一遍——id/类型/阈值都还在，
# 只有"缺 enabled 的那条"被坐实成 false。这正是 T20 拆掉的"两处写同一把键、两套默认值"，
# 所以编包（分钟级）绝不能留在"灌完种子之后"。第三轮红就红在这里。
# 不许"文件在就沿用"：build/ 里躺着的可能是 T20 之前那次编的包，装上它、启动它，
# 测的就不是"当前构建的迁移"，而"覆盖安装当前构建"这句话也会变成假的。
ok "构建当前 debug 包（gradle 增量；分钟级耗时留在竞态窗口之外）"
(cd "$ROOT" && run_flutter build apk --debug --target-platform android-x64) \
  || { fail "当前构建失败"; exit 1; }
[ -f "$NEW_APK" ] || { fail "构建说成功了但 $NEW_APK 不在"; exit 1; }

# ── 4. 灌 v12 时代的规则形状（跑过一次之后再灌，否则旧构建会把它自己那份规范化结果写回来）──
#   三个真实历史形状各自有意：缺 `enabled`（原生按 true 读）、Double 阈值（`as? Int` 会静默
#   取默认值那类）、两个总开关一真一假。整集级别的一致的判据交给 t22_upgrade_test.dart。
xml '<?xml version='"'"'1.0'"'"' encoding='"'"'utf-8'"'"' standalone='"'"'yes'"'"' ?>
<map>
  <boolean name="flutter.privacy_policy_accepted" value="true" />
  <boolean name="flutter.has_launched" value="true" />
  <string name="flutter.app_language">zh</string>
  <string name="flutter.last_system_lang">zh</string>
  <boolean name="flutter.battery_notify_enabled" value="true" />
  <boolean name="flutter.temperature_notify_enabled" value="false" />
  <string name="flutter.battery_rules">[{"id":"low20","type":"level_below","value":20,"enabled":true,"title":"电量低于20%","content":""},{"id":"charging","type":"charging","value":0,"title":"开始充电"},{"id":"full","type":"level_above","value":100.0,"enabled":false,"title":"电量充满","content":""}]</string>
  <string name="flutter.temperature_rules">[{"id":"t1","type":"battery_temp_above","value":45,"enabled":true,"title":"电池过热","content":""},{"id":"t2","type":"device_temp_above","value":60,"enabled":false,"title":"设备过热","content":""}]</string>
</map>'
ok "旧形状 prefs 已灌入（3 条电量 + 2 条温度，含缺 enabled 与 Double 阈值）"

# 核实种子真的落到位了 —— 第三轮就是在这里发现"看起来灌进去了、其实被改写过"：
# 缺 `enabled` 的那条若变成了显式 false，后面所有关于"缺省算启用"的断言都白测。
SEED="$(A shell "run-as $APP_ID cat /data/data/$APP_ID/shared_prefs/FlutterSharedPreferences.xml" | tr -d '\r')"
printf '%s\n' "$SEED" > "$ROOT/outputs/_t22_seed_prefs.xml"
if ! printf '%s' "$SEED" | grep -q '"charging","type":"charging","value":0,"title"'; then
  fail "种子里"缺 enabled 的那条"不在文件里（见 outputs/_t22_seed_prefs.xml）⇒ 停，别拿假数据做比对"
  exit 1
fi
ok "种子已核实：文件里那条 charging 确实没有 enabled 键"

# ── 5. 覆盖安装当前构建：同 debug 签名 ⇒ 数据保留（这一步就是"覆盖升级"）──
A install -r "$NEW_APK" >/dev/null || { fail "覆盖安装失败（签名不同就会走到卸载，那测的就不是升级）"; exit 1; }
ok "已覆盖安装当前构建（数据保留）"

# 旧代码必须**真的**不在了才开始迁移：`install -r` 会顺带杀掉在跑的进程，但 START_STICKY
# 的前台服务可能已经被再次拉起。判据用 pidof，不靠 sleep 赌运气。
for _ in $(seq 1 10); do
  [ -z "$("$ADB" -s "$SERIAL" shell pidof "$APP_ID" 2>/dev/null | tr -d '\r')" ] && break
  A shell am force-stop "$APP_ID"
  sleep 1
done
if [ -n "$("$ADB" -s "$SERIAL" shell pidof "$APP_ID" 2>/dev/null | tr -d '\r')" ]; then
  fail "旧进程杀不掉（pidof 仍有值）⇒ 它随时会按原生默认值回写镜像，比对结果不可信"
  exit 1
fi

# 迁移前最后一道核实：此刻镜像必须还是我灌进去的那个形状。上面那段竞态若真发生了，
# 这里就会看到缺 enabled 的那条被坐实成 false —— 与其让后面的断言红得莫名其妙，
# 不如在这里指名是谁改的（第三轮就是这么定位的）。
PRE="$(A shell "run-as $APP_ID cat /data/data/$APP_ID/shared_prefs/FlutterSharedPreferences.xml" | tr -d '\r')"
printf '%s\n' "$PRE" > "$ROOT/outputs/_t22_prefs_before_migration.xml"
if ! printf '%s' "$PRE" | grep -q '"charging","type":"charging","value":0,"title"'; then
  fail "启动新构建前镜像已被改写（见 outputs/_t22_prefs_before_migration.xml）⇒ 旧代码回写过，停"
  exit 1
fi
ok "迁移前镜像仍是种子原样（旧代码没插手）"

A shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
ok "启动新构建，等 v12→v13 迁移跑完（20s）"
sleep 20
A shell am force-stop "$APP_ID"

# ── 6. 逐项比对 ──
if [ -z "$FLUTTER_BIN" ] && [ ! -f "$SNAPSHOT" ]; then
  fail "既没设 \$FLUTTER，也找不到 flutter_tools 快照：$SNAPSHOT（设 FLUTTER 或 FLUTTER_SNAPSHOT 指向本地 SDK）"
  exit 1
fi
(cd "$ROOT" && run_flutter test --no-pub integration_test/t22_upgrade_test.dart -d "$SERIAL") \
  || { fail "覆盖升级比对失败（见上）"; exit 1; }

# ── 7. 收尾说明 ──
# 这里**不能**再查设备上的库：`flutter test` 跑完会把应用连数据一起卸载
# （第一轮就是这么"红"的 —— 断言取到的是 `run-as: unknown package`）。
# "同一个库文件被升级、而不是打不开后重建空库"这条判据因此搬进了
# integration_test/t22_upgrade_test.dart：它在进程内核对 databases/ 里没有
# .corrupt-* 备份、且 user_version 已是 dbVersion。上面那行 inode 只作日志留痕。
ok "覆盖升级自检通过：规则逐条同序同值、总开关未翻、影子差异环为空（同库升级的判据在测试里）"
