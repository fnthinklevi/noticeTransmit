# -*- coding: utf-8 -*-
"""读数单一来源（T182，2026-10-24）。

公开文档（README / CONTRIBUTING 中英四份）里的测试例数、文件数、LOC、版本号等
读数曾经手工复制维护，每轮迭代后要专门做一次「校平批次」（T169–T180 那种）。
本脚本把它们收敛为一个作者：

  采集：--collect（便宜读数：LOC / 版本 / l10n 键数 / 测试文件数）
        --dart-log/--push-log/--jest-log/--kotlin-xml（测试例数，来自已跑完的套件产物；
        本脚本自己不跑测试套件 —— 跑套件是 CI 步骤 / 维护者闸门的事）
  输出：--emit [--lang zh|en] 打印 <!-- readings:v1 --> 标记块（粘贴进文档）
  校验：--check FILE... [--strict] 比对文档里的标记块与当前读数，漂移即红

CI（analyze.yml）：末步 --check --strict 四份公开文档，并把各步产物喂给本脚本的解析器
（--dart-log / --push-log / --jest-log / --kotlin-xml）—— 这三个解析器是例数的**唯一作者**。
READINGS_<KEY> 环境变量仍占最高优先，但**只用于本地手工覆盖**；CI 不再 export 它们：
两份作者口径不一致时会互相盖住，2026-10-24 为此连踩两次（kotlin 的相对路径 glob 恒 0；
dart 的 grep 只取 `+N` 不含 `~S`，有用例被 skip 就把 3417 盖成 3413）。

数字的单位后缀（例 / 个 / 行 / 类 / 套件）只在展示层；比较前剥成纯值。
"""
import argparse
import glob
import json
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# 读数键与标签（en 文档用英文标签，键完全一致）
# ---------------------------------------------------------------------------
LABELS_ZH = {
    'dart_tests': 'App 全量测试（flutter test）',
    'dart_test_files': 'App 测试文件数（test/）',
    'push_tests': '幻念推送包测试（fnthink_push）',
    'kotlin_tests': 'Kotlin JVM 单元测试',
    'kotlin_classes': 'Kotlin 测试类数',
    'jest_tests': '服务端契约测试（jest）',
    'jest_suites': '服务端测试套件数',
    'l10n_keys': 'l10n 词条（zh；en 同数锁定）',
    'dart_loc_lib': 'Dart 源码行数（lib/）',
    'dart_loc_test': 'Dart 测试行数（test/）',
    'kotlin_loc_main': 'Kotlin 源码行数（android main）',
    'kotlin_loc_test': 'Kotlin 测试行数（android test）',
    'app_version': '应用版本（pubspec）',
    'db_version': '数据库 schema 版本',
    'flutter_version': 'Flutter（CI pin）',
    'dart_sdk': 'Dart SDK 地板（pubspec）',
    'agp': 'Android Gradle Plugin',
    'gradle': 'Gradle（wrapper）',
    'node_engine': 'Node.js（server engines）',
}
LABELS_EN = {
    'dart_tests': 'Dart unit tests (flutter test)',
    'dart_test_files': 'Dart test files (test/)',
    'push_tests': 'fnthink_push package tests',
    'kotlin_tests': 'Kotlin JVM unit tests',
    'kotlin_classes': 'Kotlin test classes',
    'jest_tests': 'Server contract tests (jest)',
    'jest_suites': 'Server test suites',
    'l10n_keys': 'l10n keys (zh; en locked to same count)',
    'dart_loc_lib': 'Dart lines (lib/)',
    'dart_loc_test': 'Dart test lines (test/)',
    'kotlin_loc_main': 'Kotlin lines (android main)',
    'kotlin_loc_test': 'Kotlin test lines (android test)',
    'app_version': 'App version (pubspec)',
    'db_version': 'Database schema version',
    'flutter_version': 'Flutter (CI pin)',
    'dart_sdk': 'Dart SDK floor (pubspec)',
    'agp': 'Android Gradle Plugin',
    'gradle': 'Gradle (wrapper)',
    'node_engine': 'Node.js (server engines)',
}
# 展示单位（仅用于 --emit；校验只看数字/字符串本体）
UNIT_ZH = {
    'dart_tests': '例', 'dart_test_files': '个', 'push_tests': '例',
    'kotlin_tests': '例', 'kotlin_classes': '类', 'jest_tests': '例',
    'jest_suites': '套件', 'l10n_keys': '条', 'dart_loc_lib': '行',
    'dart_loc_test': '行', 'kotlin_loc_main': '行', 'kotlin_loc_test': '行',
    'db_version': 'v', 'flutter_version': '', 'dart_sdk': '', 'agp': '',
    'gradle': '', 'node_engine': '', 'app_version': '',
}
INT_KEYS = set(UNIT_ZH) - {
    'app_version', 'flutter_version', 'dart_sdk', 'agp', 'gradle', 'node_engine'}

BLOCK_BEGIN = '<!-- readings:v1'
BLOCK_END = '<!-- /readings -->'


# ---------------------------------------------------------------------------
# 便宜读数（不跑任何测试）
# ---------------------------------------------------------------------------
def count_lines(pattern):
    total = 0
    for f in glob.glob(str(REPO / pattern), recursive=True):
        try:
            with open(f, 'rb') as fh:
                total += sum(1 for _ in fh)
        except OSError:
            pass
    return total


def collect_cheap():
    r = {}
    pubspec = (REPO / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version:\s*(\S+)', pubspec, re.M)
    r['app_version'] = m.group(1) if m else ''
    m = re.search(r'^\s*sdk:\s*\^?([\d.]+)', pubspec, re.M)
    r['dart_sdk'] = m.group(1) if m else ''
    helper = (REPO / 'lib/database/database_helper.dart').read_text(encoding='utf-8')
    m = re.search(r'dbVersion\s*=\s*(\d+)', helper)
    r['db_version'] = m.group(1) if m else ''
    wf = (REPO / '.github/workflows/analyze.yml').read_text(encoding='utf-8')
    m = re.search(r"flutter-version:\s*'([\d.]+)'", wf)
    r['flutter_version'] = m.group(1) if m else ''
    settings = (REPO / 'android/settings.gradle.kts').read_text(encoding='utf-8')
    m = re.search(r'com\.android\.application"\)\s*version\s*"([^"]+)"', settings)
    r['agp'] = m.group(1) if m else ''
    wrapper = (REPO / 'android/gradle/wrapper/gradle-wrapper.properties').read_text(encoding='utf-8')
    m = re.search(r'gradle-([\d.]+)-', wrapper)
    r['gradle'] = m.group(1) if m else ''
    engines = json.loads((REPO / 'server/package.json').read_text(encoding='utf-8'))
    r['node_engine'] = engines.get('engines', {}).get('node', '')
    arb = json.loads((REPO / 'lib/l10n/arb/app_zh.arb').read_text(encoding='utf-8'))
    r['l10n_keys'] = sum(1 for k in arb if not k.startswith('@') and k != '@@locale')
    r['dart_loc_lib'] = count_lines('lib/**/*.dart')
    r['dart_loc_test'] = count_lines('test/**/*.dart')
    r['kotlin_loc_main'] = count_lines('android/app/src/main/**/*.kt')
    r['kotlin_loc_test'] = count_lines('android/app/src/test/**/*.kt')
    r['dart_test_files'] = len(glob.glob(str(REPO / 'test/**/*_test.dart'), recursive=True))
    return r


# ---------------------------------------------------------------------------
# 套件读数（从既有产物解析；本脚本不启动测试）
# ---------------------------------------------------------------------------
def parse_flutter_log(path):
    """compact 末行的**三种**措辞都要认，且 skipped 计入总数：
      `+N: All tests passed!`           无 skip 无失败
      `+N ~S: All other tests passed!`  有 skip（本机实测，见下）
      `+N -F: Some tests failed.`       有失败
    ⚠ 上一版只认第 1 与第 3 种 ⇒ 仓库里一旦出现 `skip:` 的用例，末行变成
    `All other tests passed!`，本函数返回 None，`--dart-log` 那条腿**静默失效**、
    退回 shell grep 取的 `+N`（不含 ~S）⇒ 读数凭空少掉被 skip 的那几条。
    2026-10-24 实测：roadmap 形状守卫那 4 条在 CI 上 skip ⇒ CI 取 3413、本机取 3417。
    返回的是**声明的用例总数** = passed + failed + skipped，与某环境是否 skip 无关。
    """
    text = Path(path).read_text(encoding='utf-8', errors='replace').replace('\r', '\n')
    matches = re.findall(
        r'\+(\d+)(?:\s+-(\d+))?(?:\s+~(\d+))?: '
        r'(All tests passed|All other tests passed|Some tests failed)',
        text,
    )
    if not matches:
        return None
    passed, failed, skipped, _ = matches[-1]
    return int(passed) + int(failed or 0) + int(skipped or 0)


def parse_jest_log(path):
    text = Path(path).read_text(encoding='utf-8', errors='replace')
    t = re.findall(r'Tests:\s+(.*)', text)
    s = re.findall(r'Test Suites:\s+(.*)', text)
    tests = suites = None
    if t:
        m = re.search(r'(\d+)\s+total', t[-1])
        tests = int(m.group(1)) if m else None
    if s:
        m = re.search(r'(\d+)\s+total', s[-1])
        suites = int(m.group(1)) if m else None
    return tests, suites


def parse_kotlin_xml(directory):
    """sum(tests) 与 xml 文件数（每个测试类一份报告）。"""
    import xml.etree.ElementTree as ET
    tests = classes = 0
    for f in sorted(glob.glob(str(Path(directory) / '*.xml'))):
        root = ET.parse(f).getroot()
        tests += int(root.get('tests', 0))
        classes += 1
    return tests, classes


def collect_suite(args):
    r = {}
    if args.dart_log:
        v = parse_flutter_log(args.dart_log)
        if v is not None:
            r['dart_tests'] = v
    if args.push_log:
        v = parse_flutter_log(args.push_log)
        if v is not None:
            r['push_tests'] = v
    if args.jest_log:
        tests, suites = parse_jest_log(args.jest_log)
        if tests is not None:
            r['jest_tests'] = tests
        if suites is not None:
            r['jest_suites'] = suites
    kotlin_xml = args.kotlin_xml or str(REPO / 'build/app/test-results/testDebugUnitTest')
    if Path(kotlin_xml).is_dir():
        tests, classes = parse_kotlin_xml(kotlin_xml)
        if tests:
            r['kotlin_tests'] = tests
            r['kotlin_classes'] = classes
    # CI 环境变量最高优先（analyze.yml 各步 export 的 READINGS_*）
    for key in LABELS_ZH:
        env = os.environ.get('READINGS_' + key.upper())
        if env:
            r[key] = int(env) if key in INT_KEYS else env
    return r


# ---------------------------------------------------------------------------
# 标记块：emit 与 check 共用同一种行格式
#   | 标签 | 值 <!--k:key--> |
# ---------------------------------------------------------------------------
def fmt_value(key, value, lang):
    unit = (UNIT_ZH if lang == 'zh' else {}) or {}
    u = unit.get(key, '')
    if key in INT_KEYS:
        return '%s%s' % (value, ((' ' + u) if u else ''))
    return str(value)


def render_block(readings, lang):
    labels = LABELS_ZH if lang == 'zh' else LABELS_EN
    lines = [BLOCK_BEGIN + '（tools/gen_readings.py 生成与校验；手改会被 CI --check 拦下）'
             if lang == 'zh' else BLOCK_BEGIN + ' (generated & checked by tools/gen_readings.py; CI --check blocks manual edits)']
    lines.append('| ' + ('读数' if lang == 'zh' else 'Reading') + ' | '
                 + ('值' if lang == 'zh' else 'Value') + ' |')
    lines.append('|---|---|')
    for key, label in labels.items():
        if key not in readings:
            continue
        lines.append('| %s | %s <!--k:%s--> |' % (label, fmt_value(key, readings[key], lang), key))
    lines.append(BLOCK_END)
    return '\n'.join(lines)


def parse_blocks(text):
    """返回 [(key, raw_value)] 列表；找不到块返回 []。"""
    out = []
    for m in re.finditer(re.escape(BLOCK_BEGIN) + r'.*?' + re.escape(BLOCK_END), text, re.S):
        for line in m.group(0).split('\n'):
            km = re.search(r'<!--k:([a-z0-9_]+)-->', line)
            if not km:
                continue
            cell = line.split('|')
            if len(cell) < 3:
                continue
            raw = re.sub(r'<!--k:[a-z0-9_]+-->', '', cell[2]).strip()
            out.append((km.group(1), raw))
    return out


def norm(key, raw):
    raw = raw.strip()
    if key in INT_KEYS:
        digits = re.sub(r'[^\d]', '', raw)
        return int(digits) if digits else None
    return raw


def cmd_check(files, readings, strict):
    errors = 0
    compared = 0
    nosource = 0
    for path in files:
        text = Path(path).read_text(encoding='utf-8')
        pairs = parse_blocks(text)
        if not pairs:
            print('⚠ %s：未找到 readings 标记块' % path)
            continue
        for key, raw in pairs:
            # ⚠ 计数只在**真的比对了**之后才 +1。上一版把 checked += 1 放在 key 存在性
            # 判断之前，于是"无采集来源"的键也算进分母、末行还说"全部一致" ——
            # 非 strict 下这会直接报假绿（2026-10-25 实测：4 个键无来源，末行仍是
            # "19 项全部一致"）。compare 与 no-source 必须分开报。
            if key not in readings:
                nosource += 1
                msg = '❌ %s：<!--k:%s--> 当前无采集来源（CI-only？本地需提供对应 --*-log / 环境变量）' % (path, key)
                if strict:
                    print(msg)
                    errors += 1
                else:
                    print('… ' + msg[2:] + '（非 strict，仅提示）')
                continue
            compared += 1
            want = norm(key, readings[key] if isinstance(readings[key], str) else str(readings[key]))
            got = norm(key, raw)
            if want != got:
                print('❌ %s：<!--k:%s--> 文档=%r 实收=%r' % (path, key, raw, readings[key]))
                errors += 1
    tail = '' if not nosource else '；另有 %d 项无采集来源、**未比对**' % nosource
    if errors:
        print('readings check：%d 处漂移（比对 %d 项%s）—— 手工校平批次就该由这道闸门替代'
              % (errors, compared, tail))
        return 1
    print('✅ readings check：比对 %d 项全部一致%s' % (compared, tail))
    return 0


def main():
    ap = argparse.ArgumentParser(description='读数单一来源（T182）')
    ap.add_argument('--collect', action='store_true', help='打印全部可采集读数')
    ap.add_argument('--emit', action='store_true', help='打印标记块（粘贴进文档）')
    ap.add_argument('--check', nargs='+', metavar='FILE', help='校验文档中的标记块')
    ap.add_argument('--strict', action='store_true', help='check 时把「无采集来源」也判红（CI 用）')
    ap.add_argument('--lang', choices=['zh', 'en'], default='zh')
    ap.add_argument('--dart-log', help='flutter test 输出日志（根工程）')
    ap.add_argument('--push-log', help='fnthink_push 测试输出日志')
    ap.add_argument('--jest-log', help='npm test 输出日志')
    ap.add_argument('--kotlin-xml', help='testDebugUnitTest 的 XML 结果目录（默认 build/app/test-results/testDebugUnitTest）')
    args = ap.parse_args()

    readings = {}
    readings.update(collect_cheap())
    readings.update(collect_suite(args))

    if args.collect:
        for key in LABELS_ZH:
            if key in readings:
                print('%s=%s' % (key, readings[key]))
        return 0
    if args.emit:
        print(render_block(readings, args.lang))
        return 0
    if args.check:
        sys.exit(cmd_check(args.check, readings, args.strict))
    ap.print_help()


if __name__ == '__main__':
    main()
