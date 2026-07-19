// 通知推送助手 - 前端国际化脚本
// 使用方式：HTML 元素添加 data-i18n 属性，值对应下方 T 对象的键
(function () {
  const T = {
    zh: {
      'nav.home': '首页',
      'nav.features': '功能',
      'nav.how': '工作原理',
      'nav.security': '安全',
      'nav.tech': '技术栈',
      'nav.faq': '常见问题',
      'lang.switch': 'English',
      'hero.title': '通知监控 · 智能推送',
      'hero.sub': 'Android 设备通知实时转发至企业微信、钉钉、飞书等平台，支持应用筛选、关键词过滤、规则引擎。',
      'hero.badge': '开源免费 · 本地处理',
      'hero.download': '下载应用',
      'hero.trust': '安全审计 17/18 项通过 · AGP 9.3 · Flutter',
      'stats.apps': '支持应用',
      'stats.apps.desc': '兼容 400+ 应用',
      'stats.push': '累计推送',
      'stats.push.desc': '通知实时转发',
      'stats.platforms': '适配平台',
      'stats.platforms.desc': '企微/钉钉/飞书',
      'features.title': '核心功能',
      'features.notification': '多类型识别',
      'features.notification.desc': '智能识别微信、QQ、短信、来电、系统通知',
      'features.webhook': 'Webhook 多通道',
      'features.webhook.desc': '多平台同时推送，自动适配消息格式',
      'features.filter': '应用筛选',
      'features.filter.desc': '精准选择推送应用，关键词黑白名单过滤',
      'features.rule': '规则引擎',
      'features.rule.desc': 'IF/THEN 可视化配置，内置默认规则',
      'how.title': '工作原理',
      'how.step1': '安装应用',
      'how.step1.desc': '下载 APK 并启用通知访问权限',
      'how.step2': '配置 Webhook',
      'how.step2.desc': '填入企业微信/钉钉/飞书机器人地址',
      'how.step3': '开始接收',
      'how.step3.desc': '通知自动转发到指定平台',
      'security.title': '安全保护',
      'security.encrypt': '数据库加密',
      'security.encrypt.desc': 'AES-256 加密本地存储',
      'security.webhook': '密钥保护',
      'security.webhook.desc': 'AndroidKeyStore 加密',
      'security.https': '传输安全',
      'security.https.desc': 'HTTPS + 证书固定',
      'tech.title': '技术栈',
      'download.title': '下载应用',
      'download.version': '当前最新版',
      'download.history': '全部历史版本',
      'download.size': 'arm64 · Android 7.0+',
      'faq.title': '常见问题',
      'faq.q1': '通知收不到？',
      'faq.a1': '检查通知访问权限、电池优化、厂商自启动设置。',
      'faq.q2': 'Webhook 如何配置？',
      'faq.a2': '在应用设置中填写平台机器人 Webhook 地址即可。',
      'faq.q3': '需要联网吗？',
      'faq.a3': '仅在推送和检查更新时需要网络。通知处理完全在本地完成。',
      'faq.q4': '支持哪些 Android 版本？',
      'faq.a4': 'Android 7.0+，推荐 Android 10+。',
      'footer.desc': 'Android 通知转发工具，支持企微、钉钉、飞书多平台推送。',
    },
    en: {
      'nav.home': 'Home',
      'nav.features': 'Features',
      'nav.how': 'How It Works',
      'nav.security': 'Security',
      'nav.tech': 'Tech Stack',
      'nav.faq': 'FAQ',
      'lang.switch': '中文',
      'hero.title': 'Monitor · Push with Ease',
      'hero.sub': 'Real-time Android notification forwarding to WeCom, DingTalk, Feishu and more. App filtering, keyword filtering, rule engine included.',
      'hero.badge': 'Open Source · Local Processing',
      'hero.download': 'Download',
      'hero.trust': '17/18 Security Audit Passed · AGP 9.3 · Flutter',
      'stats.apps': 'Apps Supported',
      'stats.apps.desc': '400+ compatible apps',
      'stats.push': 'Push Count',
      'stats.push.desc': 'Real-time forwarding',
      'stats.platforms': 'Platforms',
      'stats.platforms.desc': 'WeCom/DingTalk/Feishu',
      'features.title': 'Core Features',
      'features.notification': 'Multi-type Recognition',
      'features.notification.desc': 'Smart recognition of WeChat, QQ, SMS, calls, system notifications',
      'features.webhook': 'Webhook Multi-channel',
      'features.webhook.desc': 'Multi-platform simultaneous push, auto-adapt message format',
      'features.filter': 'App Filtering',
      'features.filter.desc': 'Precise app selection, keyword whitelist/blacklist',
      'features.rule': 'Rule Engine',
      'features.rule.desc': 'Visual IF/THEN configuration with built-in defaults',
      'how.title': 'How It Works',
      'how.step1': 'Install',
      'how.step1.desc': 'Download APK and enable notification access',
      'how.step2': 'Configure Webhook',
      'how.step2.desc': 'Enter WeCom / DingTalk / Feishu bot URL',
      'how.step3': 'Start Receiving',
      'how.step3.desc': 'Notifications auto-forward to configured platform',
      'security.title': 'Security',
      'security.encrypt': 'Database Encryption',
      'security.encrypt.desc': 'AES-256 encrypted local storage',
      'security.webhook': 'Key Protection',
      'security.webhook.desc': 'AndroidKeyStore encryption',
      'security.https': 'Transport Security',
      'security.https.desc': 'HTTPS + Certificate Pinning',
      'tech.title': 'Tech Stack',
      'download.title': 'Download',
      'download.version': 'Latest version',
      'download.history': 'Release history',
      'download.size': 'arm64 · Android 7.0+',
      'faq.title': 'FAQ',
      'faq.q1': 'Not receiving notifications?',
      'faq.a1': 'Check notification access permission, battery optimization, and OEM auto-start settings.',
      'faq.q2': 'How to configure Webhook?',
      'faq.a2': 'Enter your platform bot Webhook URL in the app settings.',
      'faq.q3': 'Does it need internet?',
      'faq.a3': 'Only for pushing and update checks. All notification processing is local.',
      'faq.q4': 'What Android versions are supported?',
      'faq.a4': 'Android 7.0+, recommended Android 10+.',
      'footer.desc': 'Android notification forwarding tool. Supports WeCom, DingTalk, Feishu.',
    },
  };

  let lang = localStorage.getItem('lang') || navigator.language.startsWith('zh') ? 'zh' : 'en';
  if (lang !== 'zh' && lang !== 'en') lang = 'en';

  function applyLang(l) {
    lang = l;
    localStorage.setItem('lang', l);
    document.documentElement.lang = l;
    document.querySelectorAll('[data-i18n]').forEach(el => {
      const key = el.dataset.i18n;
      if (T[l] && T[l][key]) el.textContent = T[l][key];
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
      const key = el.dataset.i18nPlaceholder;
      if (T[l] && T[l][key]) el.placeholder = T[l][key];
    });
    const btn = document.getElementById('langToggle');
    if (btn) btn.textContent = T[l]['lang.switch'];
  }

  window._i18n = { T, applyLang };
  document.addEventListener('DOMContentLoaded', () => applyLang(lang));
})();
