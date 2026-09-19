#!/usr/bin/env python3
"""官网 i18n 覆盖检查器（发版规范守卫）。

模拟 server/public/i18n.js 的英文替换逻辑（最长 key 优先的子串替换），
对 index.html 中所有含中文的文本节点与 title/aria-label/placeholder/alt
属性做「英文模式残留中文」检测：替换后仍含中文即视为未覆盖。

背景：i18n.js 按中文原文精确子串匹配翻译，官网新增中文内容若未同步
登记英文词条，英文用户将看到中英混排。本检查让该问题在 CI 阶段暴露。
用法：python tools/check_site_i18n.py（退出码 0=通过，1=存在残留）。
"""
import io
import re
import sys
from html.parser import HTMLParser

I18N_PATH = 'server/public/i18n.js'
HTML_PATH = 'server/public/index.html'


def load_dict_keys(src):
    """提取 i18n.js 中所有 D['...'] = '...' 的 key（等号后的 value 不参与检测）。
    忽略注释行（// 开头）中的历史词条。"""
    keys = []
    pattern = re.compile(r"D\['((?:[^'\\]|\\.)*)'\]\s*=")
    for line in src.splitlines():
        stripped = line.strip()
        if stripped.startswith('//'):
            continue
        for m in pattern.finditer(line):
            keys.append(m.group(1).replace("\\'", "'"))
    return keys


class TextCollector(HTMLParser):
    """收集文本节点与可翻译属性（跳过 script/style 内的文本）。"""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.nodes = []
        self.attrs = []

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.skip_depth += 1
        for (name, value) in attrs:
            if name in ('title', 'aria-label', 'placeholder', 'alt') and value:
                self.attrs.append(value)

    def handle_endtag(self, tag):
        if tag in ('script', 'style') and self.skip_depth > 0:
            self.skip_depth -= 1

    def handle_data(self, data):
        if self.skip_depth == 0 and data:
            self.nodes.append(data)


def has_chinese(text):
    return re.search('[\u4e00-\u9fff]', text) is not None


def main():
    dict_keys = load_dict_keys(io.open(I18N_PATH, encoding='utf-8').read())
    dict_keys.sort(key=len, reverse=True)  # 与 i18n.js 相同：最长 key 优先替换

    parser = TextCollector()
    parser.feed(io.open(HTML_PATH, encoding='utf-8').read())
    parser.close()

    candidates = parser.nodes + parser.attrs
    chinese_nodes = [t for t in candidates if has_chinese(t)]

    bad = []
    for text in chinese_nodes:
        replaced = text
        for key in dict_keys:
            if key in replaced:
                replaced = replaced.replace(key, '·')  # 已翻译段打点
        if has_chinese(replaced):
            bad.append(text.strip()[:100])

    total = len(chinese_nodes)
    if bad:
        print('官网 i18n 覆盖检查失败：以下中文文本在英文模式下无法被字典完整翻译')
        for b in bad:
            print('  -', b)
        return 1
    print('官网 i18n 覆盖检查通过（{} 个中文文本节点/属性，全部有英文词条覆盖）'.format(total))
    return 0


if __name__ == '__main__':
    sys.exit(main())
