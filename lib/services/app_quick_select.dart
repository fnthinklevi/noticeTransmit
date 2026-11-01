/// T209：应用快速选择的**唯一目录作者**。
///
/// 这份目录原本长在 `rule_edit_page.dart` 里（四张私有常量），于是"快速选择"这件事
/// 只有规则编辑页够得着，而更多页的应用筛选与远程触发的可触发应用都只能逐个点。
/// 抽到这里的不是几个包名，是**一份口径**：哪几组、每组认哪些包、组内按什么顺序排。
library;

/// 快速选择的分组。顺序即界面顺序（短信 → 电话 → 通讯 → 邮箱）。
enum AppQuickGroup { sms, phone, comm, mail }

/// 组的固定顺序（导出给界面与用例读同一份）。
const List<AppQuickGroup> appQuickGroups = [
  AppQuickGroup.sms,
  AppQuickGroup.phone,
  AppQuickGroup.comm,
  AppQuickGroup.mail,
];

/// 组 → 包名目录（**顺序即组内展示顺序**）。
///
/// ⚠ 这里不许出现"某页专用"的额外条目：三处页面读同一份，多一条就是那三处各出现一次
/// 不同结果。要加一个平台，改这里一处、三处同时生效。
const Map<AppQuickGroup, List<String>> appQuickPackages = {
  // 系统短信类（信息/短信应用 + 短信存储）。多个系统组件在界面上聚合为一行「短信」。
  AppQuickGroup.sms: [
    'com.android.mms',
    'com.android.messaging',
    'com.google.android.apps.messaging',
    'com.samsung.android.messaging',
    'com.miui.sms',
    'com.coloros.mms',
    'com.heytap.mms',
    'com.vivo.mms',
    'com.huawei.message',
    'com.android.providers.telephony', // 短信存储
  ],
  // 系统电话类（拨号器 + 通话界面 + 电话服务）。界面上聚合为一行「电话」。
  AppQuickGroup.phone: [
    'com.android.dialer',
    'com.android.incallui',
    'com.google.android.dialer',
    'com.samsung.android.dialer',
    'com.android.phone',
    'com.android.server.telecom',
  ],
  // 第三方即时通讯/社交/办公类（顺序即展示顺序）。
  AppQuickGroup.comm: [
    // 国内即时通讯/办公
    'com.tencent.mm', // 微信
    'com.tencent.mobileqq', // QQ
    'com.tencent.tim', // TIM
    'com.tencent.wework', // 企业微信
    'com.ss.android.lark', // 飞书
    'com.larksuite.suite', // Lark
    'com.alibaba.android.rimet', // 钉钉
    // 国际即时通讯/社交
    'org.telegram.messenger', // Telegram
    'org.telegram.messenger.web', // Telegram X
    'com.twitter.android', // X
    'com.whatsapp', // WhatsApp
    'com.whatsapp.w4b', // WhatsApp Business
    'com.facebook.orca', // Messenger
    'com.instagram.android', // Instagram
    'jp.naver.line.android', // LINE
    'org.thoughtcrime.securesms', // Signal
    'com.viber.voip', // Viber
    'com.skype.raider', // Skype
    'com.discord', // Discord
    'com.Slack', // Slack
    'com.zing.zalo', // Zalo
    'com.kakao.talk', // KakaoTalk
    'com.snapchat.android', // Snapchat
  ],
  // 主流邮箱类。
  AppQuickGroup.mail: [
    'com.google.android.gm', // Gmail
    'com.microsoft.office.outlook', // Outlook
    'com.tencent.androidqqmail', // QQ 邮箱
    'com.netease.mail', // 网易邮箱大师
    'com.netease.mobimail', // 网易邮箱
    'com.samsung.android.email.provider', // Samsung Email
    'com.yahoo.mobile.client.android.mail', // Yahoo Mail
    'ch.protonmail.android', // Proton Mail
    'readdle.com.sparkmailinbox', // Spark
    'net.thunderbird.android', // Thunderbird
    'me.bluemail.mail', // BlueMail
    'com.easilydo.mail', // Edison Mail
    'com.ninefolders.hd3', // Nine
  ],
};

final Map<String, AppQuickGroup> _groupOf = {
  for (final group in appQuickGroups)
    for (final pkg in appQuickPackages[group]!) pkg.toLowerCase(): group,
};

final Map<AppQuickGroup, Map<String, int>> _orderOf = {
  for (final group in appQuickGroups)
    group: {
      for (var i = 0; i < appQuickPackages[group]!.length; i++)
        appQuickPackages[group]![i].toLowerCase(): i,
    },
};

/// 这个包属于哪一组；不在任何目录里 ⇒ null（那一页按"其他应用"处理）。
///
/// 入参大小写不敏感：ROM 回传的包名偶有 `com.Slack` 这种大写，而目录里是同一串——
/// 让调用方各自 `toLowerCase` 一次就是三处各写一遍同一条判据。
AppQuickGroup? appQuickGroupOf(String package) =>
    _groupOf[package.toLowerCase()];

/// 组内序号（用于把已安装的命中项按目录顺序排）；不在目录里 ⇒ null。
int? appQuickOrderOf(AppQuickGroup group, String package) =>
    _orderOf[group]?[package.toLowerCase()];

/// 这一页装着的应用里，各组各有哪些，**按目录顺序、值用设备上的原始包名**。
///
/// 值的"原始"很要紧：选中集合存的是页面拿到的那个串（`_selectedPackages` 下同），
/// 这里若统一降成小写，点一下就会加进一个页面里不存在的包名。
Map<AppQuickGroup, List<String>> appQuickGroupsOfInstalled(
  Iterable<String> installedPackages,
) {
  final byLower = <String, String>{
    for (final pkg in installedPackages) pkg.toLowerCase(): pkg,
  };
  final out = <AppQuickGroup, List<String>>{};
  for (final group in appQuickGroups) {
    final packages = <String>[
      for (final pkg in appQuickPackages[group]!)
        if (byLower[pkg.toLowerCase()] != null) byLower[pkg.toLowerCase()]!,
    ];
    if (packages.isNotEmpty) out[group] = packages;
  }
  return out;
}
