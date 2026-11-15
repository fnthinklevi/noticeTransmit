#!/usr/bin/env python3
"""从 update.md 提取指定版本的 changelog（中文）+ changelogEn（英文）。

update.md 格式（本脚本严格按此解析）：
  ### v{A}.{B}.{C}+{BUILD} - YYYY-MM-DD
  **中文加粗标题行**
  中文正文...
  ---
  **英文加粗标题行**
  英文正文...
  ### 下一版本...

输出：
  --dry-run     打印到 stdout（changelog 和 changelogEn 分两行标注）
  --write PATH  直接 merge 进 version.json（只覆盖 changelog/changelogEn，保留其他所有字段）
  （不带 --write 时等价于 --dry-run）

退出码：
  0 = 成功
  1 = update.md 没找到该版本条目
  2 = 条目里缺中文/英文标题行（update.md 格式不对）
  3 = 写 version.json 失败
"""
import argparse, json, re, sys


def extract(text: str, ver: str, build: str) -> dict:
    """从 update.md 文本提取指定版本的双语 changelog。

    先定位版本头区块（避免全页扫描误匹配），再在区块内切分中/英两段。
    """
    # ① 定位版本头区块（锚点 = 精确版本头；终点 = 下一版本头或文件末）
    #    必须带 +BUILD —— 防止重建同一版本号不同 build 时匹配到别的条目
    header_pat = rf'### v{re.escape(ver)}\+{re.escape(build)}\b[^\n]*'
    # 也接受不带 build 的宽松匹配（版本号没变但没填 build 的老条目）
    header_pat_loose = rf'### v{re.escape(ver)}\b[^\n]*'
    # 先用精确版，找不到再用宽松版（并告警）
    m = re.search(header_pat, text)
    loose_warning = False
    if not m:
        m = re.search(header_pat_loose, text)
        loose_warning = True
    if not m:
        raise KeyError(f'update.md 里没找到 v{ver}（连宽松匹配也没）')

    # ② 切到版本头之后、下一版本头之前的局部
    block_start = m.end()
    # 下一个 ### v 开头的行（不带当前这一行）
    next_header = re.search(r'^### v', text[m.end():], re.MULTILINE)
    block_end = m.end() + next_header.start() if next_header else len(text)
    block = text[block_start:block_end].strip()

    # ③ 在局部里找 --- 分隔符
    sep = re.search(r'^---\s*$', block, re.MULTILINE)
    if not sep:
        raise KeyError(f'v{ver} 条目里没有 --- 分隔符（update.md 双语约定）')

    zh_block = block[:sep.start()].strip()
    en_block = block[sep.end():].strip()

    # ④ 切分标题行（必须是加粗 **xxx**）和正文
    def _parse(b: str, label: str) -> tuple[str, str]:
        # 第一行非空 = 加粗标题行
        lines = b.splitlines()
        title = ''
        body_start = 0
        for i, ln in enumerate(lines):
            t = ln.strip()
            if not t:
                continue
            # 必须 **...** 形态
            bold = re.match(r'^\*\*(.+?)\*\*\s*$', t)
            if bold:
                title = bold.group(1).strip()
                body_start = i + 1
                break
            else:
                # 不是加粗标题行 = 格式不对
                raise ValueError(
                    f'v{ver} {label}段落 第一行不是加粗标题行：{t[:40]!r}...'
                )
        if not title:
            raise ValueError(f'v{ver} {label}段落 空')

        # 正文：跳过空行后把剩余行合并（保持换行，但去掉首尾空行）
        body_lines = []
        for ln in lines[body_start:]:
            body_lines.append(ln.rstrip())
        body_text = '\n'.join(body_lines).strip()

        # 返回："标题\n\n正文" —— version.json 里就是这个样子
        if body_text:
            return title + '\n\n' + body_text
        return title

    zh = _parse(zh_block, '中文')
    en = _parse(en_block, '英文')

    if loose_warning:
        print(
            f'⚠ update.md 里 v{ver}+{build} 没找到精确版本头，用了宽松匹配 v{ver}。'
            f'建议补上 +{build} 防止歧义。',
            file=sys.stderr,
        )

    return {'changelog': zh, 'changelogEn': en}


def main():
    ap = argparse.ArgumentParser(description='从 update.md 提取指定版本的双语 changelog')
    ap.add_argument('--from', dest='update_md', default='update.md',
                    help='update.md 路径（默认 update.md）')
    ap.add_argument('--version', required=True, help='版本号（例 1.6.6）')
    ap.add_argument('--build', required=True, help='构建号（例 166）')
    ap.add_argument('--write', default=None,
                    help='把结果 merge 进指定 JSON 文件（只覆盖 changelog/changelogEn）')
    ap.add_argument('--dry-run', action='store_true',
                    help='打印结果到 stdout，不写文件')
    args = ap.parse_args()

    with open(args.update_md, encoding='utf-8') as f:
        text = f.read()

    try:
        result = extract(text, args.version, args.build)
    except KeyError as e:
        print(f'❌ {e}', file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        print(f'❌ {e}', file=sys.stderr)
        sys.exit(2)

    if args.dry_run or not args.write:
        print('=== changelog (中文) ===')
        print(result['changelog'])
        print()
        print('=== changelogEn (English) ===')
        print(result['changelogEn'])
        return

    # merge 进 version.json（保留其他所有字段，只覆盖 changelog/changelogEn）
    try:
        with open(args.write, encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f'❌ 读 {args.write} 失败：{e}', file=sys.stderr)
        sys.exit(3)

    data['changelog'] = result['changelog']
    data['changelogEn'] = result['changelogEn']

    try:
        with open(args.write, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write('\n')
    except OSError as e:
        print(f'❌ 写 {args.write} 失败：{e}', file=sys.stderr)
        sys.exit(3)

    zh_title_line = result['changelog'].split('\n', 1)[0]
    en_title_line = result['changelogEn'].split('\n', 1)[0]
    print(f'✅ 已写入 {args.write}')
    print(f'   changelog   首行：{zh_title_line}')
    print(f'   changelogEn 首行：{en_title_line}')


if __name__ == '__main__':
    main()
