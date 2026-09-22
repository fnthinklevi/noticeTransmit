#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
APK 架构纯净度验证器（noticeTransmit 发版专用）

背景：base.md §6.5 曾写 `tar -tf ... | grep "lib/"`，但 APK 是 ZIP 不是 tar，
      tar 无法列出内容（会报错或输出空），必须用 zipfile。

判定：
  - 单架构包：lib/ 下只能出现唯一一种 ABI 目录
  - 融合包：  lib/ 下必须 arm64-v8a + armeabi-v7a + x86_64 三者齐全
用法：python verify_apk_purity.py <apk路径> <期望模式: arm64|arm32|x86|all>
退出码：0=通过，1=不通过
"""
import sys
import zipfile
from collections import defaultdict

EXPECT = {
    "arm64": (["arm64-v8a"], "only"),
    "arm32": (["armeabi-v7a"], "only"),
    "x86": (["x86_64"], "only"),
    "all": (["arm64-v8a", "armeabi-v7a", "x86_64"], "atleast"),
}


def main():
    if len(sys.argv) != 3:
        print("用法: python verify_apk_purity.py <apk> <arm64|arm32|x86|all>")
        return 2
    apk_path, mode = sys.argv[1], sys.argv[2].lower()
    if mode not in EXPECT:
        print(f"未知模式: {mode}")
        return 2

    try:
        zf = zipfile.ZipFile(apk_path)
    except zipfile.BadZipFile as e:
        print(f"[FAIL] 不是合法 ZIP/APK: {e}")
        return 1

    abis = defaultdict(list)
    for name in zf.namelist():
        if name.startswith("lib/"):
            parts = name.split("/")
            if len(parts) >= 3:
                abis[parts[1]].append(name)
    zf.close()

    if not abis:
        print("[FAIL] lib/ 下未发现任何 .so —— 包可能异常")
        return 1

    found = sorted(abis.keys())
    want, rule = EXPECT[mode]
    print(f"  实际 ABI 目录: {found}")
    for a in found:
        print(f"    - {a}: {len(abis[a])} 个文件")

    ok = True
    if rule == "only":
        if found != want:
            print(f"[FAIL] 期望仅含 {want}，实际 {found}")
            ok = False
    else:
        missing = [w for w in want if w not in found]
        if missing:
            print(f"[FAIL] 融合包缺架构: {missing}")
            ok = False

    print("[PASS] 纯净度校验通过" if ok else "[FAIL] 纯净度校验未通过")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
