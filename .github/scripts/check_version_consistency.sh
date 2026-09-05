#!/bin/bash
# 检查项目中所有版本号常量是否一致
# 在 CI 中运行，不一致则失败阻止合入

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

errors=0

# 提取 pubspec.yaml 中的版本号
PUBSPEC_VERSION=$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
PUBSPEC_BUILD=$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f2 | sed 's/build-//')

echo "pubspec.yaml:  version=$PUBSPEC_VERSION  build=$PUBSPEC_BUILD"

# 提取 update_manager.dart 中的回退版本
UM_VERSION=$(grep "_fallbackVersion" lib/update_manager.dart | head -1 | grep -oP "'(1\.[0-9]+\.[0-9]+)'" | tr -d "'")
UM_BUILD=$(grep "_fallbackBuild" lib/update_manager.dart | head -1 | grep -oP '=\s*(\d+)' | grep -oP '\d+')

echo "update_manager.dart:  version=$UM_VERSION  build=$UM_BUILD"

# 提取 MainActivity.kt 中的回退版本
MA_VERSION=$(grep "FALLBACK_VERSION" android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt | head -1 | grep -oP '"(1\.[0-9]+\.[0-9]+)"' | tr -d '"')
MA_BUILD=$(grep "FALLBACK_BUILD" android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt | head -1 | grep -oP '=\s*(\d+)' | grep -oP '\d+')

echo "MainActivity.kt:  version=$MA_VERSION  build=$MA_BUILD"

# 提取 version.json 中的版本
VJ_VERSION=$(grep '"latestVersion"' server/data/version.json | grep -oP '"(1\.[0-9]+\.[0-9]+)"' | tr -d '"')
VJ_BUILD=$(grep '"latestBuild"' server/data/version.json | grep -oP ':\s*(\d+)' | grep -oP '\d+')

echo "version.json:  version=$VJ_VERSION  build=$VJ_BUILD"

# 比对
echo ""
echo "--- 一致性检查 ---"

if [ "$PUBSPEC_VERSION" != "$UM_VERSION" ]; then
    echo -e "${RED}❌ pubspec.yaml ($PUBSPEC_VERSION) != update_manager.dart ($UM_VERSION)${NC}"
    ((errors++))
fi
if [ "$PUBSPEC_VERSION" != "$MA_VERSION" ]; then
    echo -e "${RED}❌ pubspec.yaml ($PUBSPEC_VERSION) != MainActivity.kt ($MA_VERSION)${NC}"
    ((errors++))
fi
if [ "$PUBSPEC_VERSION" != "$VJ_VERSION" ]; then
    echo -e "${RED}❌ pubspec.yaml ($PUBSPEC_VERSION) != version.json ($VJ_VERSION)${NC}"
    ((errors++))
fi

if [ "$PUBSPEC_BUILD" != "$UM_BUILD" ]; then
    echo -e "${RED}❌ pubspec.yaml build ($PUBSPEC_BUILD) != update_manager.dart ($UM_BUILD)${NC}"
    ((errors++))
fi
if [ "$PUBSPEC_BUILD" != "$MA_BUILD" ]; then
    echo -e "${RED}❌ pubspec.yaml build ($PUBSPEC_BUILD) != MainActivity.kt ($MA_BUILD)${NC}"
    ((errors++))
fi
if [ "$PUBSPEC_BUILD" != "$VJ_BUILD" ]; then
    echo -e "${RED}❌ pubspec.yaml build ($PUBSPEC_BUILD) != version.json ($VJ_BUILD)${NC}"
    ((errors++))
fi

# ===== 文档一致性：README 标注须与服务端依赖 / 实际运行参数同步 =====

# otplib 版本：README 中的标注须与 server/package.json 声明一致
OTPLIB_DECLARED=$(grep -E '"otplib"' server/package.json | head -1 | grep -oP '\^\d+\.\d+\.\d+' || true)
if [ -n "$OTPLIB_DECLARED" ]; then
    if ! grep -q "otplib ($OTPLIB_DECLARED)" README.md || ! grep -q "otplib ($OTPLIB_DECLARED)" README-en.md; then
        echo -e "${RED}❌ README otplib 版本标注与 server/package.json ($OTPLIB_DECLARED) 不一致${NC}"
        errors=$((errors+1))
    fi
fi

# 封禁参数：README 不得再出现「3 次 / 240 小时」旧值（现行为 5 次 / 1 小时，以 server/lib/store.js 为准）
if grep -qE "240 ?小时|240 hours" README.md README-en.md 2>/dev/null; then
    echo -e "${RED}❌ README 仍存在过期封禁参数「3 次/240 小时」，应为「5 次/1 小时」${NC}"
    errors=$((errors+1))
fi

if [ $errors -eq 0 ]; then
    echo -e "${GREEN}✅ 版本号与文档一致性检查全部通过${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}发现 $errors 处不一致，请在发版前同步更新所有文件${NC}"
    exit 1
fi