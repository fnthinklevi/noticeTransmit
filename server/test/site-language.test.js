const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const I18N = path.join(ROOT, 'server', 'public', 'i18n.js');

const src = fs.readFileSync(I18N, 'utf8');

/**
 * 从真源码里按花括号配平取出某个函数体。
 * 判据一律作用在**函数体**上，不作用在整份文件上：文档性注释里提到一个词
 * 不等于代码读了它（早先那条 `navigator.languages` 断言就栽在自家注释上）。
 */
function extractFunction(name) {
  const start = src.indexOf('function ' + name + '(');
  if (start < 0) throw new Error('i18n.js 里找不到 ' + name + ' —— 该规则被删了');
  let i = src.indexOf('{', start);
  let depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) break;
    }
  }
  if (depth !== 0) throw new Error(name + ' 花括号不配平 —— 提取到的不是完整函数');
  return src.slice(start, i + 1);
}

const domainLangSrc = extractFunction('domainLang');
const detectLangSrc = extractFunction('detectLang');

// 执行真实现，而不是在这里抄一份期望表：抄一份的话，判据与实现各改一处就会静默分叉。
const domainLang = new Function(`${domainLangSrc}; return domainLang;`)();

describe('官网默认语言按域名定', () => {
  test('.top 结尾默认英文', () => {
    expect(domainLang('push.fnthink.top')).toBe('en');
    expect(domainLang('www.example.top')).toBe('en');
    expect(domainLang('a.b.c.top')).toBe('en');
  });

  test('.com 结尾默认中文', () => {
    expect(domainLang('fnthink.com')).toBe('zh');
    expect(domainLang('www.example.com')).toBe('zh');
  });

  test('其余后缀与无 host 一律缺省中文', () => {
    for (const h of ['example.cn', 'example.io', 'example.net', 'localhost', '', null, undefined]) {
      expect(domainLang(h)).toBe('zh');
    }
  });

  test('大小写与"看起来像"都不许骗过它', () => {
    expect(domainLang('EXAMPLE.TOP')).toBe('en'); // 主机名大小写不敏感
    expect(domainLang('nottop')).toBe('zh'); // 没有点，不是 .top
    expect(domainLang('a.top.example.com')).toBe('zh'); // 真后缀是 .com
    expect(domainLang('top')).toBe('zh');
  });
});

describe('域名规则不被浏览器 locale 覆盖', () => {
  test('detectLang 的实现里不再读 navigator', () => {
    // 用户要的是"部署在哪个域名就默认哪种语言"，不是"访客浏览器是什么语言"。
    // 只要实现里还认 navigator，这条就会被悄悄改回去。
    expect(detectLangSrc).not.toMatch(/navigator/);
  });

  test('detectLang 确实把 hostname 交给了 domainLang', () => {
    expect(detectLangSrc).toMatch(/domainLang\(/);
    expect(detectLangSrc).toMatch(/hostname/);
  });

  test('用户自己选过的语言仍然优先于域名（localStorage 在前）', () => {
    const readAt = src.indexOf("localStorage.getItem('lang')");
    const detectAt = src.indexOf('if (!lang) lang = detectLang();');
    expect(readAt).toBeGreaterThanOrEqual(0);
    expect(detectAt).toBeGreaterThanOrEqual(0);
    // 读在前、判在后 ⇒ 有存档就压根不会走到域名规则
    expect(readAt).toBeLessThan(detectAt);
  });
});
