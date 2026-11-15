#!/usr/bin/env python3
"""从 update.md 提取指定版本的 changelog（完整版本块：中文 + --- + 英文），输出到 stdout。"""
import re, sys

if len(sys.argv) != 2:
    print("用法: extract_release_notes.py <ver>", file=sys.stderr)
    sys.exit(1)

ver = sys.argv[1]

with open('update.md', encoding='utf-8') as f:
    content = f.read()

pattern = rf'### v{re.escape(ver)}[^#]*?(?=\n### v|\Z)'
m = re.search(pattern, content, re.DOTALL)
if not m:
    print(f'Changelog for v{ver} not found in update.md', file=sys.stderr)
    sys.exit(1)

block = m.group(0).strip()

# 末尾加一段 changelog / 更新日志 引导
block += "\n\n---\n\n**更新日志 | Changelog:** 更多详情请查看 [update.md](https://github.com/fnthinklevi/noticeTransmit/blob/main/update.md)"

print(block)
