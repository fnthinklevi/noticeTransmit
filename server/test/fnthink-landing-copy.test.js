const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const HTML = path.join(ROOT, 'server', 'public', 'index.html');
const I18N = path.join(ROOT, 'server', 'public', 'i18n.js');

const html = fs.readFileSync(HTML, 'utf8');
const i18n = fs.readFileSync(I18N, 'utf8');

const CJK = /[一-鿿]/;

/** i18n 那一节（id="fnthink"）里的文本节点，**原样**取（不 strip）。 */
function sectionNodes() {
  const m = html.match(/<section id="fnthink">[\s\S]*?<\/section>/);
  if (!m) throw new Error('找不到 id="fnthink" 那一节');
  // 代码块里的中文一个都不许有：i18n 不跳过 <pre>，它唯一的保护是
  // 「文本节点里没有中文就跳过」—— 混进一个汉字，英文模式下这条命令就会被改坏。
  for (const blk of m[0].match(/<pre>[\s\S]*?<\/pre>/g) || []) {
    const bad = blk.match(/[一-鿿]/g);
    if (bad) {
      throw new Error(`代码块里有中文（${bad.slice(0, 3)}）—— 英文模式下命令会被改坏`);
    }
  }
  const prose = m[0].replace(/<pre>[\s\S]*?<\/pre>/g, '');
  const nodes = [];
  for (const raw of prose.matchAll(/>([^<>]+)</g)) {
    const t = raw[1];
    if (!t.trim() || !CJK.test(t)) continue;
    if (!nodes.includes(t)) nodes.push(t);
  }
  return nodes;
}

describe('T70 幻念推送介绍节：双份不许漏', () => {
  test('这一节在页面里，且落在 FAQ 之前', () => {
    expect(html).toContain('id="fnthink"');
    expect(html.indexOf('id="fnthink"')).toBeLessThan(html.indexOf('<!-- FAQ -->'));
  });

  test('三段接入示例都在，且都不含中文（英文模式下命令必须原样）', () => {
    const m = html.match(/<section id="fnthink">[\s\S]*?<\/section>/);
    const pres = m[0].match(/<pre>/g) || [];
    expect(pres.length).toBe(3);
    expect(() => sectionNodes()).not.toThrow();
  });

  test('导航有这一格，且 data-i18n 键与别处同形', () => {
    expect(html).toContain('<a href="#fnthink" data-i18n="nav.fnthink">');
  });

  test('每一句中文在 i18n.js 都有词条（漏一条 = 英文模式下那半句仍是中文）', () => {
    // ⚠ 键必须是**未 strip 的原文**：i18n 的行走器拿 node.textContent 直接匹配
    //   （只用 trim() 判空）。早先在这里 strip 过一遍，于是把「 与 」误报成缺失 ——
    //   那一条其实已经在字典里。判据自己错了，报出来的"缺陷"也是假的。
    const missing = sectionNodes().filter((n) => !i18n.includes(`D['${n}']`));
    expect(missing).toEqual([]);
  });

  test('反向锚点：这一节真的有中文句子（防判据退化成恒真）', () => {
    expect(sectionNodes().length).toBeGreaterThan(10);
  });
});
