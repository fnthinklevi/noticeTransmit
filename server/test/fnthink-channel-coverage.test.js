// 通道口径守卫（2026-10-06 维护者指令：「幻念推送是自建的独立通道，和 webhook 之类并列 ——
// 前面提到推送通道就得把幻念推送加上」）。
//
// 判的不是措辞而是**完备性契约**：一句话里把 Webhook、自建应用、邮件三族并列出来，读的人就
// 会把它当成通道全集；这一族缺席 ⇒ 用户以为幻念推送不是通道。所以：
//   ① 中文侧：任何同时点名三类（Webhook / 自建应用 / 邮件·SMTP）的文本节点，必须也点名「幻念推送」；
//   ② 英文侧：同一句译出来必须含 'Fnthink Push'（只补一边 = 英文读者读到旧口径，那是跨语言只改一边）；
//   ③ 结构侧：功能矩阵里要有一张幻念推送的卡，平台墙要列它。
//
// ⚠ 这条管不到的两类，如实写着，别读成"官网通道口径已全部有守卫"：
//   · **只说自己那一族的族卡**（"Webhook + 邮件多通道"、"自建应用通道"）是两类并列，不该提幻念推送，
//     所以判据取"≥3 类并列"而不是"≥2"；代价是**把某句从三类删成两类**它就不响了（下面有对照用例）；
//   · `<meta name="description">` 与 og 标签不是文本节点（i18n 不翻它们，搜索引擎读到的是中文原文）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const html = fs.readFileSync(path.join(ROOT, 'server', 'public', 'index.html'), 'utf8');
const i18nSrc = fs.readFileSync(path.join(ROOT, 'server', 'public', 'i18n.js'), 'utf8');

const unesc = (s) => s.replace(/\\'/g, "'").replace(/\\\\/g, '\\');

/** 与 i18n.js / tools/check_site_i18n.py 同口径：只认真词条行，注释里的历史词条不算。 */
function loadDict(src) {
  const map = new Map();
  for (const line of src.split('\n')) {
    if (line.trim().startsWith('//')) continue;
    const re = /D\['((?:[^'\\]|\\.)*)'\]\s*=\s*'((?:[^'\\]|\\.)*)'/g;
    let m;
    while ((m = re.exec(line))) map.set(unesc(m[1]), unesc(m[2]));
  }
  return map;
}

const DICT = loadDict(i18nSrc);

/** 照 i18n.js 的 applyLang：最长 key 优先做子串替换。 */
function translate(text) {
  let out = text;
  for (const k of [...DICT.keys()].sort((a, b) => b.length - a.length)) {
    if (out.includes(k)) out = out.split(k).join(DICT.get(k));
  }
  return out;
}

/** 文本节点（与 fnthink-landing-copy.test.js 同一取法：原样，不 trim） */
function cjkNodes(scope) {
  const body = scope
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '');
  const nodes = [];
  for (const r of body.matchAll(/>([^<>]+)</g)) {
    const t = r[1];
    if (t.trim() && /[一-鿿]/.test(t)) nodes.push(t);
  }
  return nodes;
}

const families = (t) =>
  (t.includes('Webhook') ? 1 : 0) +
  (t.includes('自建应用') ? 1 : 0) +
  (t.includes('邮件') || t.includes('SMTP') ? 1 : 0);

/** 三类并列即视为"通道全集"，必须点名幻念推送 */
function isThreeWay(t) {
  return families(t) >= 3;
}
function needsFnthink(t) {
  return isThreeWay(t) && !t.includes('幻念推送');
}

const nodes = cjkNodes(html.slice(html.indexOf('<body')));
const threeWay = nodes.filter(isThreeWay);

describe('官网通道口径：三类并列必须点名幻念推送（中文侧与英文侧同形）', () => {
  test('反向锚点：这类"三类并列"的句子确实有若干条（判据退化成恒真时这里先红）', () => {
    expect(threeWay.length).toBeGreaterThanOrEqual(8);
  });

  test('中文侧零漏报：每一条三类并列都点名了幻念推送', () => {
    const bad = threeWay.filter(needsFnthink).map((t) => t.trim().slice(0, 40));
    expect(bad).toEqual([]);
  });

  test('英文侧零漏报：同一句译出来仍含 Fnthink Push（只补一边就是跨语言漏改）', () => {
    const bad = threeWay
      .map((t) => translate(t))
      .filter((en) => !/Fnthink Push/.test(en))
      .map((en) => en.slice(0, 60));
    expect(bad).toEqual([]);
  });

  test('结构侧：功能矩阵有一张幻念推送的卡，平台墙列了这一族', () => {
    const features = html.match(/<section id="features">[\s\S]*?<\/section>/);
    expect(features).not.toBeNull();
    expect(/<h3>[^<]*幻念推送[^<]*<\/h3>/.test(features[0])).toBe(true);
    const how = html.match(/<section id="how">[\s\S]*?<\/section>/);
    expect(how).not.toBeNull();
    expect(how[0]).toContain('<b>幻念推送</b>');
  });

  test('判据自证 A：漏报名字的形状必须判得出来（合成样本，不动页面）', () => {
    expect(needsFnthink('通过 Webhook、自建应用通道或 SMTP 邮件实时转发')).toBe(true);
    expect(isThreeWay('通过 Webhook、自建应用通道或 SMTP 邮件实时转发')).toBe(true);
  });

  test('判据自证 B：族卡只说自己那一族，不许被误判成漏报（两类并列不该提幻念推送）', () => {
    expect(needsFnthink('Webhook + 邮件多通道')).toBe(false);
    expect(needsFnthink('12 种 Webhook 通道类型 + SMTP 邮件（465 SSL / 587 STARTTLS）')).toBe(
      false,
    );
    expect(needsFnthink('与 Webhook 并行的独立通道体系：企业微信自建应用 / 飞书自建应用')).toBe(
      false,
    );
  });

  test('词条表不是空的（守卫读的是真字典，取不到词条就等于没有守卫）', () => {
    expect(DICT.size).toBeGreaterThan(200);
  });
});

// ⚠ 这一组是本轮自己造出来的缺陷钉住的（2026-10-06）：把新词条 `lines.concat()` 追到了文件末尾，
// 而文件末尾是 IIFE 的 `})();` **之后** —— `var D` 在闭包里，外面那批赋值运行时根本不存在。
// 后果：英文模式旗舰两节整段掉回中文，而两份现成检查都发现不了 ——
//   · `fnthink-landing-copy.test.js` 与本文件一样用**源码文本**匹配 `D['…']`，写在闭包外照样算"有词条"；
//   · `tools/check_site_i18n.py` 也是正则抽 key，同样作用域盲。
// 浏览器实测把 residue 从 867 打到 0 才定性 ⇒ 读源码的守卫必须补一条**作用域**判据。
describe('词条必须定义在 i18n 的 IIFE 之内（闭包外的赋值运行时读不到）', () => {
  /** 从 `(function ()` 起按花括号配平找到那段函数体的字符区间。 */
  function iifeRange(src) {
    const start = src.indexOf('(function (');
    if (start < 0) throw new Error('i18n.js 里找不到 IIFE 开头 —— 结构变了，先读文件别放宽判据');
    let i = src.indexOf('{', start);
    let depth = 0;
    for (; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') {
        depth--;
        if (depth === 0) return [start, i + 1];
      }
    }
    throw new Error('IIFE 花括号不配平');
  }

  const [lo, hi] = iifeRange(i18nSrc);
  const lines = i18nSrc.split('\n');
  let lineStart = 0;
  const outside = [];
  lines.forEach((line, idx) => {
    const isEntry = /^\s*D\['/.test(line) && !line.trim().startsWith('//');
    if (isEntry && (lineStart < lo || lineStart > hi)) {
      outside.push({ n: idx + 1, key: line.trim().slice(0, 40) });
    }
    lineStart += line.length + 1;
  });

  test('闭包外的词条赋值数 = 0（有几条就点名到行号）', () => {
    expect(outside.map((o) => '第 ' + o.n + ' 行: ' + o.key)).toEqual([]);
  });

  test('反向锚点：判据真的在读赋值行（闭包内至少 200 条，否则这条区间本身可能是假的）', () => {
    const inside = lines.filter((l, idx) => {
      let acc = 0;
      for (let i = 0; i < idx; i++) acc += lines[i].length + 1;
      return /^\s*D\['/.test(l) && !l.trim().startsWith('//') && acc >= lo && acc <= hi;
    }).length;
    expect(inside).toBeGreaterThan(200);
  });
});
