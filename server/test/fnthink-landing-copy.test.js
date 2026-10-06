const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const HTML = path.join(ROOT, 'server', 'public', 'index.html');
const I18N = path.join(ROOT, 'server', 'public', 'i18n.js');

const html = fs.readFileSync(HTML, 'utf8');
const i18n = fs.readFileSync(I18N, 'utf8');

const CJK = /[一-鿿]/;

// ⚠ **两节共用这一份实现**（fnthink 与 remote）。原来把 id 写死成 "fnthink"，
// 于是后加的 remote 节整节漏翻也照样全绿 —— 新节不受管的守卫等于没有守卫。
const LANDING_SECTIONS = ['fnthink', 'remote'];

/** 指定那一节里的文本节点，**原样**取（不 strip）。 */
function sectionNodes(id) {
  const re = new RegExp('<section id="' + id + '">[\\s\\S]*?<\\/section>');
  const m = html.match(re);
  if (!m) throw new Error('找不到 id="' + id + '" 那一节');
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

describe('落地页两个核心功能节（幻念推送 / 远程控制）：双份不许漏', () => {
  for (const id of LANDING_SECTIONS) {
    test(`${id} 这一节在页面里，且落在 FAQ 之前`, () => {
      expect(html).toContain(`id="${id}"`);
      expect(html.indexOf(`id="${id}"`)).toBeLessThan(html.indexOf('<!-- FAQ -->'));
    });

    test(`${id} 导航有这一格，且 data-i18n 键与别处同形`, () => {
      expect(html).toContain(`<a href="#${id}" data-i18n="nav.${id}">`);
    });

    test(`${id} 每一句中文在 i18n.js 都有词条（漏一条 = 英文模式下那半句仍是中文）`, () => {
    // ⚠ 键必须是**未 strip 的原文**：i18n 的行走器拿 node.textContent 直接匹配
    //   （只用 trim() 判空）。早先在这里 strip 过一遍，于是把「 与 」误报成缺失 ——
    //   那一条其实已经在字典里。判据自己错了，报出来的"缺陷"也是假的。
      const missing = sectionNodes(id).filter((n) => !i18n.includes(`D['${n}']`));
      expect(missing).toEqual([]);
    });

    test(`${id} 代码块里没有中文（英文模式下命令必须原样）`, () => {
      const m = html.match(new RegExp('<section id="' + id + '">[\\s\\S]*?<\\/section>'));
      const pres = m[0].match(/<pre>[\s\S]*?<\/pre>/g) || [];
      for (const blk of pres) {
        expect(blk.match(/[\u4e00-\u9fff]/g)).toBeNull();
      }
    });

    test(`${id} 反向锚点：这一节真的有中文句子（防判据退化成恒真）`, () => {
      expect(sectionNodes(id).length).toBeGreaterThan(10);
    });
  }

  test('幻念推送那一节的三段接入示例都在（远程控制那节没有代码块）', () => {
    const m = html.match(/<section id="fnthink">[\s\S]*?<\/section>/);
    expect((m[0].match(/<pre>/g) || []).length).toBe(3);
  });
});
