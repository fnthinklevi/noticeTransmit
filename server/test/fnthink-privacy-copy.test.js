// T56 隐私边界（片2）：落地页 index.html 的隐私文案 + i18n.js 词条守卫。
//
// 钉的全是"公开文案与真实行为对不上"这一类静默缺陷 —— 幻念推送上线后，
// "通知内容会不会经服务器"这件事不再是单一答案。旧文案三处都写死了"通知不上云 /
// 不会上传到任何服务器"，那是开启幻念推送之前的口径，如今配上中转就是**公开页面对用户说假话**。
// 这片要求：① 那几条绝对性声明必须没了；② 三情形（①②③）说清、且把"经服务器需一次性显式同意 /
// 最长 7 天 / 审计只存元数据"讲到位；③ 新中文句子在 i18n.js 里有对应词条（否则英文模式漏译，
// 比中文页面更糟：那是一半中文一半英文的公开页面）。
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '../public/index.html'), 'utf8');
const i18n = fs.readFileSync(path.join(__dirname, '../public/i18n.js'), 'utf8');

describe('落地页隐私文案：开启幻念推送中转之后，公开口径必须诚实', () => {
  test('旧的绝对性"不上云/不上传任何服务器"声明已撤（它们只在没有中转时成立）', () => {
    for (const stale of [
      '通知不上云',
      '不会上传到任何服务器',
      '所有通知与短信内容仅在设备本地处理与推送',
    ]) {
      expect(html).not.toContain(stale);
    }
  });

  test('三情形逐条说清，且把中转的边界讲到位（不是含糊一句"可能上传"）', () => {
    expect(html).toContain('① 不使用「幻念推送」');
    expect(html).toContain('② 只用本软件转发通知');
    expect(html).toContain('③ 使用「幻念推送」');
    // 这三句是 T56 定稿的边界，缺任何一句，用户在页面上就看不出"同意之后到底存什么"
    expect(html).toContain('一次性显式同意');
    expect(html).toContain('加密暂存');
    expect(html).toContain('最长保留 7 天');
    expect(html).toContain('审计只保存元数据（不含正文）');
    expect(html).toContain('配对口令与身份私钥不上传');
  });

  test('第四情形说清官方实例与自行部署的边界（T92）', () => {
    // 只写"自部署也可以"是不够的：用户真正要判断的是**谁在运营那台机器**。
    // 而"谁能看到正文"两者是一样的（契约 privacy.serverStoresBodyPlaintext=false）——
    // 把它写成"自部署更私密"是**不实陈述**，会让用户以为官方侧能看到明文。
    for (const fact of [
      '④ 官方实例与自行部署',
      'push.fnthink.top',
      'push.fnthink.com',
      '既不运营也不接触',
      '没有官方侧的限流与风控兜底',
      '服务器不落明文正文',
    ]) {
      expect(html).toContain(fact);
    }
    // 英文侧必须同形：只补中文 ⇒ 英文模式的用户读到的是没有第四情形的旧口径
    expect(i18n).toContain('(4) Official instance vs self-hosting');
    expect(i18n).toContain('the server never stores plaintext bodies');
  });

  test('新增的三处中文句子都在 i18n.js 里有词条（漏一条 = 英文模式漏译）', () => {
    const zh = [
      '通知默认在本机处理、管理后台二步验证、敏感数据加密',
      '通知，默认留在你自己的设备上',
      '默认情况下，通知与短信内容只在你的设备本地处理',
      '不会——除非你启用「幻念推送」并显式同意',
    ];
    for (const s of zh) {
      expect(i18n).toContain(`D['${s}`);
    }
  });

  test('旧文案的英文词条不留在字典里冒充当前口径（撤声明就得撤译文）', () => {
    // 这些旧 key 的中文已从页面消失；若 i18n.js 还留着它们，说明改文案只改了 html 没同步字典，
    // 或者更糟——字典与页面各说一套。
    expect(i18n).not.toContain("D['通知不上云'");
    expect(i18n).not.toContain('不会上传到任何服务器');
  });
});
