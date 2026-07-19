// 通知推送助手 - 中文/English 国际化
// 遍历正文文本节点，用字典替换所有中文 → English，反之亦然
(function () {
  // ── 完整翻译字典：中文原文 → 英文译文 ──
  var D = {};
  D['通知推送助手 · 让每条通知，抵达每个平台'] = 'Notification Push Helper';
  D['通知推送助手'] = 'Notification Push Helper';
  D['让每条通知，<br><span class="grad">抵达每个平台</span>'] = 'Every Notification, Every Platform';
  D['让每条通知，'] = 'Every notification,';
  D['抵达每个平台'] = 'every platform.';
  D['通知推送助手是一款 Android 通知监听与 Webhook 推送工具。把手机上的任意通知，实时转发到企业微信、钉钉、飞书——支持应用筛选、关键词过滤、可视化规则引擎与自定义电量提醒。'] = 'A Flutter-based Android app that listens to system notifications and forwards them to WeCom, DingTalk, Feishu and more. App filtering, keyword filtering, visual rule engine and custom battery reminders included.';
  D['开源免费 · 本地处理'] = 'Open Source · Local Processing';
  D['立即下载'] = 'Download Now';
  D['在 GitHub 查看源码'] = 'View on GitHub';
  D['MIT 开源'] = 'MIT Open Source';
  D['Flutter 构建'] = 'Built with Flutter';
  D['无广告 · 无追踪'] = 'No Ads · No Tracking';
  D['通知推送'] = 'Notification Push';
  D['监听中'] = 'Listening';
  D['已推送'] = 'Sent';
  D['已拦截'] = 'Blocked';
  D['微信'] = 'WeChat';
  D['电量提醒'] = 'Battery Alert';
  D['短信验证码'] = 'SMS Code';
  D['来电结束'] = 'Call Ended';
  D['营销广告'] = 'Marketing Ad';
  D['【项目群】发布会 15:00 开始'] = '[Project] Event starts 15:00';
  D['电量已降至 20%，请及时充电'] = 'Battery at 20%, please charge';
  D['验证码 928311，优先推送'] = 'OTP 928311, push priority';
  D['与 138****6021 通话 3 分钟'] = 'Call with 138****6021, 3 min';
  D['已被夜间免打扰规则拦截'] = 'Blocked by DND rule';
  D['企业微信'] = 'WeCom';
  D['钉钉'] = 'DingTalk';
  D['飞书'] = 'Feishu';
  D['主流推送平台'] = 'Platforms Supported';
  D['种通知智能识别'] = 'Notification Types';
  D['款可选应用图标'] = 'App Icon Options';
  D['通知本地处理'] = 'Local Processing';
  D['一个应用，管好所有通知'] = 'One App for All Notifications';
  D['从监听、过滤到推送，每个环节都可精细掌控。为效率而生的完整功能矩阵。'] = 'From listening to filtering to delivery — full control at every stage. A complete toolkit built for efficiency.';
  D['功能'] = 'Features';
  D['工作原理'] = 'How It Works';
  D['安全'] = 'Security';
  D['技术栈'] = 'Tech Stack';
  D['常见问题'] = 'FAQ';
  D['全量通知监听'] = 'Full Notification Listening';
  D['监听系统所有应用的通知栏消息，智能识别微信、QQ、短信、来电、系统等 5 类通知类型。'] = 'Monitors all app notifications, intelligently identifying WeChat, QQ, SMS, calls, system — 5 notification types.';
  D['Webhook 多通道'] = 'Webhook Multi-channel';
  D['同时配置多个 Webhook 地址，每个通道独立开关，自动适配企业微信 / 钉钉 / 飞书消息格式。'] = 'Configure multiple Webhook URLs, each independently toggleable, auto-adapting to WeCom / DingTalk / Feishu message formats.';
  D['可视化规则引擎'] = 'Visual Rule Engine';
  D['IF 条件组合 + THEN 动作配置，内置验证码优先、广告拦截、夜间免打扰等默认规则，开箱即用。'] = 'IF condition + THEN action, built-in rules for OTP priority, ad blocking, nighttime DND — ready out of the box.';
  D['关键词过滤'] = 'Keyword Filtering';
  D['白名单 + 黑名单双模式关键词过滤，精准控制哪些内容推送、哪些内容拦截。'] = 'Whitelist + blacklist dual-mode keyword filtering for precise push control.';
  D['应用筛选'] = 'App Filtering';
  D['自定义选择需要推送的应用，支持「通知 / 不通知」双模式与一键全选、反选。'] = 'Select apps to push, with Notify/Do Not Notify modes, Select All and Invert.';
  D['自定义电量提醒'] = 'Custom Battery Alerts';
  D['充电 / 断开 / 指定电量阈值全自定义规则，息屏 Doze 下依然可靠推送，可增删改。'] = 'Full custom rules for charging, disconnecting, and battery thresholds. Reliable push even in Doze mode.';
  D['历史记录'] = 'History';
  D['本地保存推送历史，支持搜索、详情查看与导出，随时回溯每一条通知去向。'] = 'Locally saved push history with search, detail view, and export. Track every notification.';
  D['深色模式'] = 'Dark Mode';
  D['浅色 / 深色 / 跟随系统三种主题，Cupertino 设计语言，界面简洁优雅。'] = 'Light / Dark / System three themes. Cupertino design language. Clean, elegant interface.';
  D['后台保活 · 在线更新'] = 'Background Persistence & Updates';
  D['前台服务 + 电量白名单 + 开机自启，稳定常驻；支持版本更新，无需重装。'] = 'Foreground service + battery whitelist + auto-start for reliable persistence. OTA updates supported.';
  D['通知，如何抵达你想要的地方'] = 'How Notifications Reach You';
  D['一条通知从产生到推送，只需毫秒级的四步流转。'] = 'From notification to delivery — four steps in milliseconds.';
  D['捕获通知'] = 'Capture';
  D['系统通知栏产生消息，监听服务实时捕获'] = 'System notification bar generates message, listener captures in real time';
  D['识别分类'] = 'Identify';
  D['解析来源应用与类型，标记微信、短信、来电等'] = 'Parse source app and type, tag WeChat, SMS, calls, etc.';
  D['规则过滤'] = 'Filter';
  D['经规则引擎 + 关键词 + 应用筛选层层判定'] = 'Processed through rule engine + keywords + app filter';
  D['多通道推送'] = 'Push';
  D['按格式封装，并行推送至各 Webhook 通道'] = 'Packaged per format, pushed in parallel to all Webhook channels';
  D['送达确认'] = 'Confirm';
  D['推送结果记入历史，成功失败一目了然'] = 'Push results logged to history, success/failure clearly shown';
  D['群机器人 Webhook'] = 'Group Bot Webhook';
  D['自定义机器人'] = 'Custom Bot';
  D['群自定义机器人'] = 'Group Custom Bot';
  D['自定义 Webhook'] = 'Custom Webhook';
  D['任意兼容平台'] = 'Any compatible platform';
  D['把安全，做进每一层'] = 'Security at Every Layer';
  D['通知不上云、管理后台二步验证、敏感数据加密——隐私与安全，从设计之初就被认真对待。'] = 'Notifications stay local, admin 2FA, sensitive data encrypted. Privacy and security taken seriously from day one. Minimal crash logs collected via Bugly for bugfixing.';
  D['二步验证（TOTP）'] = 'Two-Factor Auth (TOTP)';
  D['管理后台登录启用 2FA，兼容 Google Authenticator，防止凭据泄露。'] = 'Admin login with 2FA, compatible with Google Authenticator, prevents credential leaks.';
  D['bcrypt 哈希'] = 'bcrypt Hashing';
  D['Token 使用 bcrypt 哈希验证，抵御暴力破解与彩虹表攻击。'] = 'Tokens verified with bcrypt hashing, resistant to brute-force and rainbow table attacks.';
  D['IP 智能封锁'] = 'IP Intelligent Blocking';
  D['10 分钟内验证码错误 3 次自动封锁 IP，阻断自动化爆破。'] = 'Auto-block IP after 3 wrong code attempts in 10 minutes, stopping automated attacks.';
  D['恢复码机制'] = 'Recovery Codes';
  D['生成 8 个一次性恢复码，设备丢失时安全找回账户。'] = 'Generate 8 one-time recovery codes for safe account recovery if device is lost.';
  D['AES-256-GCM 加密'] = 'AES-256-GCM Encryption';
  D['TOTP secret 等敏感数据加密存储，密钥泄露也无法直接读取。'] = 'Sensitive data like TOTP secrets are encrypted. Even with a leaked key, data remains unreadable.';
  D['通知不上云'] = 'Stay Local';
  D['所有通知、短信、通讯录仅在本地处理与推送，不会上传到任何服务器。推送只经你自己配置的 Webhook 发出。仅崩溃统计（腾讯 Bugly）会采集必要的崩溃堆栈、设备型号、系统版本用于修复问题。'] = 'All notifications, SMS, contacts processed locally. Push goes only through your Webhook. Only Bugly collects minimal crash data (stack trace, device model, OS version) for bugfixing.';
  D['现代、可靠的工程底座'] = 'Modern, Reliable Engineering Foundation';
  D['跨端 Flutter + 原生 Kotlin 后台服务 + Node.js 更新服务，全链路开源可审计。'] = 'Cross-platform Flutter + native Kotlin background service + Node.js update server. Full-stack open source, fully auditable.';
  D['现在，就让通知流动起来'] = 'Let Notifications Flow';
  D['下载最新版 APK，几分钟完成配置，再也不错过任何一条重要消息。'] = 'Download the latest APK, configure in minutes, never miss an important message again.';
  D['下载 Android APK'] = 'Download Android APK';
  D['下载 APK'] = 'Download APK';
  D['全部历史版本'] = 'All Releases';
  D['Android 通知监听与 Webhook 推送工具。开源、免费、本地处理，让每条通知抵达每个平台。由 幻念团队 fnthinklevi 打造。'] = 'Android notification listener & Webhook push tool. Open source, free, local processing. Every notification to every platform. Built by fnthinklevi.';
  D['产品'] = 'Product';
  D['功能特性'] = 'Features';
  D['安全加固'] = 'Security';
  D['下载'] = 'Download';
  D['资源'] = 'Resources';
  D['GitHub 仓库'] = 'GitHub Repository';
  D['贡献指南'] = 'Contributing Guide';
  D['安全政策'] = 'Security Policy';
  D['反馈问题'] = 'Report Issue';
  D['© 2026 幻念团队 fnthinklevi · 通知推送助手'] = '© 2026 fnthinklevi · Notification Push Helper';
  D['打开菜单'] = 'Open Menu';
  D['关闭菜单'] = 'Close Menu';
  D['返回顶部'] = 'Back to Top';
  // FAQ
  D['它会不会上传我的通知或短信内容？'] = 'Does it upload my notifications or SMS?';
  D['不会。所有通知、短信、通讯录仅在本地监听、处理与推送，不会上传到任何服务器。推送只通过你自行配置的 Webhook 地址发出，开发者不存储任何推送内容。仅崩溃统计（腾讯 Bugly）会采集崩溃堆栈用于修复问题。'] = 'No. All notifications, SMS, contacts are only listened to, processed, and pushed locally. Nothing is uploaded to any server. Push only goes through your configured Webhook — the developer stores zero content. Only crash logs (Tencent Bugly) are collected for bugfixing.';
  D['支持哪些推送平台？'] = 'Which platforms are supported?';
  D['内置适配企业微信群机器人、钉钉自定义机器人、飞书群机器人的消息格式；也支持任意自定义 Webhook 地址，可对接兼容的第三方平台或你自己的服务端。'] = 'Built-in message format support for WeCom group bots, DingTalk custom bots, and Feishu group bots. Also supports any custom Webhook URL for third-party services or your own backend.';
  D['为什么有时候收不到推送？'] = 'Why do I sometimes miss pushes?';
  D['请依次检查：① 通知访问权限是否开启；② 是否已忽略电池优化（应用会在首次启用时引导）；③ 前台服务是否运行；④ 厂商自启动 / 后台权限是否放行；⑤ Webhook 地址是否正确（设置页可测试）；⑥ 是否被应用筛选或关键词过滤拦截。'] = 'Check: ① Notification access granted; ② Battery optimization ignored; ③ Foreground service running; ④ OEM auto-start / background permissions allowed; ⑤ Webhook URL correct (test in settings); ⑥ Not filtered by app selection or keywords.';
  D['需要 root 或特殊权限吗？'] = 'Does it require root?';
  D['无需 root。仅需授予通知监听权限，并按需开启短信 / 来电识别、忽略电池优化、开机自启等常规权限即可稳定运行。'] = 'No root needed. Only notification listener permission is required, plus optional SMS/call permissions, battery optimization ignore, and auto-start for stable operation.';
  D['是免费的吗？开源吗？'] = 'Is it free? Open source?';
  D['完全免费，且在 GitHub 开源（MIT 许可，供学习交流使用）。欢迎提交 Issue 与 Pull Request 参与共建。'] = 'Completely free and open source on GitHub (MIT License). Issues and Pull Requests welcome!';

  // lang toggle 按钮文字
  D['English'] = '中文';

  // ── 当前语言 ──
  var lang = localStorage.getItem('lang');
  if (!lang) lang = (navigator.language || '').startsWith('zh') ? 'zh' : 'en';

  // ── 存储原始文本用于恢复中文 ──
  // 用 Map 而非普通对象：对象 key 会被 toString 强转（Text 节点都是 "[object Text]"），
  // 导致 originals[node] 互相覆盖，所有节点最终还原成同一个值
  var originals = new Map();

  function walkTextNodes(root, fn) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
    var node;
    while (node = walker.nextNode()) {
      // 跳过 script/style 标签内的文本
      if (node.parentNode && (node.parentNode.tagName === 'SCRIPT' || node.parentNode.tagName === 'STYLE')) continue;
      fn(node);
    }
  }

  function applyLang(l) {
    lang = l;
    localStorage.setItem('lang', l);
    document.documentElement.lang = l === 'zh' ? 'zh-CN' : 'en';

    if (l === 'en') {
      // 切换到英文：遍历所有文本节点，用字典替换
      walkTextNodes(document.body, function(node) {
        var text = node.textContent;
        if (!text || !text.trim()) return;
        // 跳过纯数字/符号/空格
        if (!/[\u4e00-\u9fff]/.test(text)) return;
        // 保存原始文本
        if (!originals.has(node)) originals.set(node, text);
        // 按字符数降序排列键（先匹配长句，避免短字符串提前替换）
        var keys = Object.keys(D).sort(function(a,b){return b.length - a.length;});
        var replaced = text;
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          if (replaced.indexOf(k) !== -1) {
            replaced = replaced.split(k).join(D[k]);
          }
        }
        node.nodeValue = replaced;
      });
    } else {
      // 切换到中文：恢复原始文本
      walkTextNodes(document.body, function(node) {
        if (originals.has(node)) {
          node.nodeValue = originals.get(node);
        }
      });
    }

    // 更新语言切换按钮文字
    var btn = document.getElementById('langToggle');
    if (btn) btn.textContent = l === 'zh' ? 'English' : '中文';

    // 更新 <title> 和 <meta> description
    document.title = l === 'zh'
      ? '通知推送助手 · 让每条通知，抵达每个平台'
      : 'Notification Push Helper';
    var metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc) {
      metaDesc.content = l === 'zh'
        ? '通知推送助手 —— Android 通知监听与 Webhook 推送工具。支持企业微信 / 钉钉 / 飞书多平台，具备应用筛选、关键词过滤、可视化规则引擎、电量提醒、二步验证等功能。开源、免费、本地处理。'
        : 'Notification Push Helper — Android notification listener & Webhook push tool. Supports WeCom, DingTalk, Feishu. Features app filtering, keyword filtering, visual rule engine, battery alerts, and 2FA. Open source, free, local processing.';
    }
  }

  function toggleLang() {
    applyLang(lang === 'zh' ? 'en' : 'zh');
  }

  window._i18n = { applyLang: applyLang, toggleLang: toggleLang };
  document.addEventListener('DOMContentLoaded', function() { applyLang(lang); });
})();
