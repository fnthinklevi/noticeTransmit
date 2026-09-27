#!/usr/bin/env python3
"""version.json 的 sha256 必须与磁盘上的那四个包字节相符。

只查字段形状（64 位小写十六进制）照不出"哈希属于另一次构建"：v1.5.76 第一趟 x86_64 构建
失败后重跑，四包的字节变了，而 94d0cf9 那份已提交的 version.json 里留的是上一趟的哈希 ——
形状检查一路绿。客户端在装包前正是拿这个值校验下载的（N3 传输层校验），发错哈希等于
让用户装不上或装到不匹配的包。

产物在哪算数：优先 server/public/apks/<版本>/（要部署、要上 CDN 的那份），
没有才退回 build/app/outputs/flutter-apk/v<版本>/（刚构建出来、还没归档）。
两处都没有（CI 上就是这样）⇒ 打印"未交叉校验"并退出 0，但绝不静默。
"""

import hashlib
import json
import os
import sys

ARCHES = ("arm64", "arm32", "x86_64", "all")
PREFIX = {"arm64": "notice_arm64_", "arm32": "notice_arm32_", "x86_64": "notice_x86_", "all": "notice_all_"}


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def locate(version):
    archive = os.path.join("server", "public", "apks", version)
    built = os.path.join("build", "app", "outputs", "flutter-apk", "v" + version)
    for root, tag in ((archive, "归档"), (built, "构建产物")):
        if os.path.isdir(root):
            return root, tag
    return None, None


def main():
    vj = sys.argv[1] if len(sys.argv) > 1 else os.path.join("server", "data", "version.json")
    with open(vj, encoding="utf-8") as f:
        data = json.load(f)
    version = data.get("latestVersion") or ""
    declared = data.get("sha256") or {}
    root, tag = locate(version)
    if root is None:
        print(f"⚠ 未做字节级交叉校验：本机没有 v{version} 的归档或构建产物（CI 上是这种情形），"
              f"sha256 字段只检查了形状")
        return 0

    problems, checked = [], 0
    for arch in ARCHES:
        apk = os.path.join(root, f"{PREFIX[arch]}{version}.apk")
        if not os.path.isfile(apk):
            problems.append(f"{arch}: 找不到 {apk}")
            continue
        actual = sha256_of(apk)
        expected = declared.get(arch)
        checked += 1
        if expected != actual:
            problems.append(f"{arch}: version.json={expected} 实际={actual}（{os.path.basename(apk)}）")
    if problems:
        print(f"❌ version.json 的 sha256 与{tag}对不上（{len(problems)} 项，已比对 {checked} 个包）：")
        for p in problems:
            print(f"   {p}")
        return 1
    print(f"sha256 字节级交叉校验通过（{tag}，{checked} 个包）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
