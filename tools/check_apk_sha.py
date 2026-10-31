#!/usr/bin/env python3
"""两站清单的版本/sha256 必须与磁盘上的四个包逐字一致，且两站与旧文件不许各说各话。

T170 之后服务端按站点读清单（`UPDATE_REGION=cn → version.cn.json`，否则 `version.global.json`），
而 `version.json` 只剩一个身份：**按站点文件缺失时的只读兜底**。三份文件同时躺在 data/ 里
就是三份真值——本工具为此而生，管两件事：

1. **字节级**：每份清单里的 `sha256` 必须等于磁盘上那四个包的哈希。只查形状（64 位小写
   十六进制）照不出"哈希属于另一次构建"：v1.5.76 第一趟 x86_64 构建失败后重跑，四包字节
   全变了，而当时已提交的清单里留的是上一趟的哈希——形状检查一路绿，而客户端装包前正是
   拿这个值校验的（N3 传输层校验）。
2. **跨文件**：两站的 `latestVersion`／`latestBuild`／`sha256`／`fileSizes` 等**站点无关
   字段**必须逐字相同（`downloads` 按站不同，是设计）；旧 `version.json` 若还在，也必须
   与按站点文件一致——不一致就是"影子真值"：线上看着正常，一旦按站点文件被删/写坏，
   服务端会静默回落到它，把旧版本号发给所有人。

产物在哪算数：优先 server/public/apks/<版本>/（要部署、要上 CDN 的那份），
没有才退回 build/app/outputs/flutter-apk/v<版本>/（刚构建出来、还没归档）。
两处都没有（CI 上就是这样）⇒ 打印"未交叉校验"并**仍然退出 0**，但绝不静默——跨文件那半
照跑，它是 CI 里唯一能在没有包的时候拦住漂移的东西。
"""

import argparse
import hashlib
import json
import os
import sys
from urllib.parse import urlparse

# Windows 默认控制台是 GBK，ℹ/✅/❌ 会直接把 print 打崩（本仓踩过多次）：
# 能重配就重配成"遇到编不出的字符降级"，编不出也不许因此判"校验没跑"。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except Exception:
        pass

ARCHES = ("arm64", "arm32", "x86_64", "all")
PREFIX = {"arm64": "notice_arm64_", "arm32": "notice_arm32_", "x86_64": "notice_x86_", "all": "notice_all_"}
REGION_FILES = {"cn": "version.cn.json", "global": "version.global.json"}
LEGACY_FILE = "version.json"

# 站点无关字段：两站必须逐字一致（downloads 按站不同，刻意不在其中）
SHARED_FIELDS = (
    "latestVersion",
    "latestBuild",
    "sha256",
    "fileSizes",
    "minSupportedVersion",
    "forceUpdate",
    "forceUpdateVersion",
    "forceUpdateBuild",
)


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


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def check_bytes(data, problems, notes):
    """一份清单 ↔ 磁盘四包。没有包可对时只记一条 note，不判红（CI 上的正常情形）。"""
    version = data.get("latestVersion") or ""
    declared = data.get("sha256") or {}
    root, tag = locate(version)
    if root is None:
        notes.append(
            f"未做字节级交叉校验：本机没有 v{version} 的归档或构建产物（CI 上是这种情形），"
            f"sha256 字段只检查了形状"
        )
        return 0

    downloads = data.get("downloads") or {}

    def apk_candidates(arch):
        """版本号后的构件号是 T66 起的一部分；以清单里的下载名为准，再退回旧命名。"""
        names = []
        url = downloads.get(arch) or ""
        if url:
            base = os.path.basename(urlparse(url).path)
            if base:
                names.append(base)
        legacy = f"{PREFIX[arch]}{version}.apk"
        if legacy not in names:
            names.append(legacy)
        return [os.path.join(root, n) for n in names]

    checked = 0
    for arch in ARCHES:
        apk = next((p for p in apk_candidates(arch) if os.path.isfile(p)), None)
        if apk is None:
            problems.append(f"找不到包：{apk_candidates(arch)}")
            continue
        actual = sha256_of(apk)
        checked += 1
        if declared.get(arch) != actual:
            problems.append(
                f"{arch} 的 sha256 与清单不符：清单={declared.get(arch)} 实际={actual}"
                f"（{os.path.basename(apk)}）"
            )
    notes.append(f"字节级交叉校验通过（{tag}，{checked} 个包）")
    return checked


def main():
    ap = argparse.ArgumentParser(
        description="校验两站清单（cn／global）与磁盘包的版本、sha256 逐字一致，并拦截旧 version.json 漂移",
    )
    ap.add_argument(
        "path",
        nargs="?",
        help="只验单份清单（排障／历史调用用）；不给则按 --region 验按站点文件",
    )
    ap.add_argument("--data-dir", default=os.path.join("server", "data"), help="清单目录（默认 server/data）")
    ap.add_argument(
        "--region",
        choices=("cn", "global", "all"),
        default="all",
        help="验哪一站的清单（默认 all＝两站都验）",
    )
    args = ap.parse_args()

    problems, notes = [], []

    if args.path:
        targets = [(args.path, "单份清单")]
    else:
        names = (
            [REGION_FILES["cn"], REGION_FILES["global"]]
            if args.region == "all"
            else [REGION_FILES[args.region]]
        )
        targets = []
        for name in names:
            p = os.path.join(args.data_dir, name)
            if not os.path.isfile(p):
                problems.append(
                    f"缺按站点清单 {p} —— 该站此刻会退回旧 {LEGACY_FILE} 兜底（或读到空清单），"
                    f"而管理面保存会写到这个路径"
                )
                continue
            targets.append((p, name))

    loaded = []
    for p, label in targets:
        try:
            loaded.append((p, label, load(p)))
        except (OSError, ValueError) as e:
            problems.append(f"{label} 读不动：{e}")

    # ── 跨文件：站点无关字段逐字一致 ──────────────────────────────
    if len(loaded) >= 2:
        base_path, base_label, base = loaded[0]
        for p, label, data in loaded[1:]:
            for field in SHARED_FIELDS:
                if data.get(field) != base.get(field):
                    problems.append(
                        f"{label} 的 {field} 与 {base_label} 不同：{data.get(field)!r} ≠ {base.get(field)!r}"
                    )

    # ── 旧文件：只剩"只读兜底"这一个身份，内容必须与按站点一致 ─────
    legacy_path = os.path.join(args.data_dir, LEGACY_FILE)
    if not args.path and os.path.isfile(legacy_path) and loaded:
        try:
            legacy = load(legacy_path)
        except (OSError, ValueError) as e:
            problems.append(f"{LEGACY_FILE} 读不动：{e}")
            legacy = None
        if legacy is not None:
            base = loaded[0][2]
            drifted = [f for f in SHARED_FIELDS if legacy.get(f) != base.get(f)]
            if drifted:
                problems.append(
                    f"旧文件 {LEGACY_FILE} 与按站点清单不一致（影子真值）：{', '.join(drifted)}"
                    f" —— 它在按站点文件缺失时会被服务端静默读走。确认按站点文件正确后归档它："
                    f"mv {legacy_path} {legacy_path}.legacy-$(date +%Y%m%d)"
                )
            else:
                notes.append(
                    f"旧文件 {LEGACY_FILE} 与按站点清单一致（它已只剩兜底身份，可归档："
                    f"mv {legacy_path} {legacy_path}.legacy-$(date +%Y%m%d)）"
                )

    for p, label, data in loaded:
        check_bytes(data, problems, notes)

    if problems:
        print(f"❌ 版本清单校验失败（{len(problems)} 项）：")
        for p in problems:
            print(f"   {p}")
        return 1

    for n in notes:
        print(f"ℹ {n}")
    fields = "／".join(f for f in ("latestVersion", "latestBuild") if loaded)
    summary = "；".join(
        f"{label}: {(data.get('latestVersion') or '?')}+{data.get('latestBuild') or '?'}"
        for _, label, data in loaded
    )
    if len(loaded) >= 2:
        print(f"✅ 两站清单一致（{summary}；downloads 按站不同是设计）")
    else:
        print(f"✅ 清单通过（{summary or fields}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
