#!/usr/bin/env python3
"""一次性迁移工具：手写 app_localizations.dart → ARB 文件（R2 重构）。

解析 lib/l10n/app_localizations.dart 中手写的 _zh/_en 字符串表，
生成 lib/l10n/arb/app_zh.arb / app_en.arb（flutter gen-l10n 输入）。

规则：
- Dart 字面量转义（\\n、\\'、\\"、\\\\）先还原为真实字符，再按 JSON 规则序列化；
- 值中含 {placeholder} 的词条按 ICU 语法处理：单引号转义为 ''，并生成
  @key metadata（placeholders 均为 int，与手写签名一致）；
- 迁移完成后校验键数与手写 getter/方法数一致，两语言键集合一致。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'tools' / 'app_localizations_legacy.dart.txt'
OUT_DIR = ROOT / 'lib' / 'l10n' / 'arb'


def dart_unescape(s: str) -> str:
    placeholder = '\x00'
    s = s.replace('\\\\', placeholder)
    s = s.replace('\\n', '\n').replace("\\'", "'").replace('\\"', '"').replace('\\t', '\t')
    return s.replace(placeholder, '\\')


def extract_map(src: str, name: str) -> dict:
    m = re.search(r"static const " + name + r" = <String, String>\{(.*?)\n  \};", src, re.S)
    if not m:
        raise SystemExit(f'未找到 {name} 字符串表')
    body = m.group(1)
    pairs = re.findall(r"'([^'\n]+?)':\s*'((?:[^'\\]|\\.)*)'", body)
    return {k: dart_unescape(v) for k, v in pairs}


def extract_param_types(src: str) -> dict:
    """从手写方法签名提取 {方法名: {参数名: 类型}}，占位符名与参数名一一对应。"""
    types = {}
    for m in re.finditer(r'String (\w+)\(([^)]*)\) *(?:=>|\\{)', src):
        method, params = m.group(1), m.group(2)
        mapping = {}
        for p in params.split(','):
            parts = p.strip().split()
            if len(parts) == 2:
                mapping[parts[1]] = parts[0]
        if mapping:
            types[method] = mapping
    return types


def main() -> int:
    src = SRC.read_text(encoding='utf-8')
    zh = extract_map(src, '_zh')
    en = extract_map(src, '_en')
    param_types = extract_param_types(src)

    # 一致性校验：两语言键集合一致
    if set(zh) != set(en):
        only_zh = sorted(set(zh) - set(en))
        only_en = sorted(set(en) - set(zh))
        print(f'键集合不一致！仅 zh: {only_zh}；仅 en: {only_en}')
        return 1

    # 与手写 getter/方法数量对账（String get + String xxx( 形式）
    declared = set(re.findall(r'String get (\w+)', src)) | set(re.findall(r'String (\w+)\(', src))
    declared.discard('dart_unescape')
    missing = declared - set(zh)
    if missing:
        print(f'警告：以下 {len(missing)} 个声明词条未在 map 中找到: {sorted(missing)}')

    placeholder_re = re.compile(r'\{(\w+)\}')
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for locale, table in (('zh', zh), ('en', en)):
        arb: dict = {}
        for key, value in table.items():
            placeholders = placeholder_re.findall(value)
            if placeholders:
                # ICU：含占位符的消息中单引号需转义为 ''
                value = value.replace("'", "''")
                arb[key] = value
                # 占位符类型取自手写方法签名（int/String，默认 int）
                sig = param_types.get(key, {})
                arb[f'@{key}'] = {
                    'placeholders': {
                        p: {'type': sig.get(p, 'int')} for p in placeholders
                    }
                }
            else:
                arb[key] = value
        out = OUT_DIR / f'app_{locale}.arb'
        out.write_text(json.dumps(arb, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'{out.name}: {len(table)} 词条（含 @metadata 总键 {len(arb)}）')
    print(f'键集合一致：{len(zh)} 词条迁移完成')
    return 0


if __name__ == '__main__':
    sys.exit(main())
