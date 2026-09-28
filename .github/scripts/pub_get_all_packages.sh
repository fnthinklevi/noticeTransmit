#!/bin/bash
# 解析「根包 + 仓库里每一个嵌套包」的依赖。CI 的 analyze / build 步骤都要先跑它。
#
# 为什么嵌套包要在 analyze **之前** 解析（CI 上真翻过车）：
#   `flutter analyze` 不带路径时会走进 packages/** —— 那些 test/*.dart 的 context root
#   是包自己，不是根包。包没 pub get，analyzer 就解析不到 package:test，报出来是一整屏
#   "Target of URI doesn't exist"（本机实测 286 条 error/warning）。
#   跟根包 pub get 成不成功没关系：根 `flutter pub get` **不会**替嵌套包生成 .dart_tool
#   （已实测：跑完根 pub get 后 packages/fnthink_push/.dart_tool 仍然不存在）。
#   本机之所以跑得绿，是因为本地早就在包里 pub get 过 —— 这是"本地绿 CI 红"的教科书成因。
#
# 循环按 git 跟踪到的 pubspec 走：以后新增一个包，不必再来改 workflow。
# 代价是这里对仓库结构有一条假设（只有根包与 packages/* 两类 Dart 包），
# 假设破了就 exit 1 点名，而不是静默漏掉一个包 —— 漏掉的表现正是本次要修的那个假绿。

set -euo pipefail

if [ ! -f pubspec.yaml ]; then
  echo "❌ 本脚本要在仓库根目录运行（当前目录没有 pubspec.yaml）"
  exit 1
fi

flutter pub get

nested=$(git ls-files | grep 'pubspec[.]yaml$' | grep -v '^pubspec[.]yaml$' || true)
for f in $nested; do
  case "$f" in
    packages/*) ;;
    *)
      echo "❌ 跟踪中的 pubspec 不在 packages/ 下：$f"
      echo "   本脚本的假设是「仓库里只有根包与 packages/* 两类包」，破了就回来改这里"
      exit 1
      ;;
  esac
  echo "── dart pub get：$(dirname "$f")"
  (cd "$(dirname "$f")" && dart pub get)
done

echo "✅ 根包与嵌套包都已解析（嵌套包：${nested:-无}）"
