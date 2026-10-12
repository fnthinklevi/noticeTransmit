import '../l10n/app_localizations.dart';

/// 远程执行那 18 枚动作／设置项**按什么主题归组** —— 唯一作者 = 这个文件
/// （T146，维护者 2026-10-12 裁定 5：「命令清单当前过于杂乱」）。
///
/// ## 为什么这一维住在设备侧而不是契约里
/// 契约加 `category` 要把一份**签过名的封闭词表**从串数组改成对象数组，连带
/// `strings()` 校验、`pairConfirm.itemsVocabularyFrom`、L2/L3 的派生层、服务端两份
/// 词表、跨端向量，以及 `versionOrder: server-first` 的发版次序 —— 换来的只是
/// "分类有一个唯一出处"。可**分类是展示语义，不是协议语义**：对面不关心这台把
/// `volume:up` 归进哪一组，它只解析 `<family>:<verb>/<argument>`。
/// 代价说清楚：这张表与契约漂移时，界面上那一组会**空一格或挤进「未分类」**，
/// 所以 `fnthink_remote_action_categories_test.dart` 判的是**双向差集**
/// （少一项红、多一项也红），与 `kFnthinkRemoteActionLabels` 同一条纪律。
///
/// ## ⚠ 这里不改任何协议形状
/// 键就是线上的动作名（`channel:toggle`、`monitoring` 这些）。
/// 分组只影响"画在哪一栏底下"，`remote-send-action-<契约名>` 那枚 key 一个字都不动 ——
/// 按 key 点 chip 的用例有六处（`remote_execution_pages_test.dart`、
/// `fnthink_send_page_test.dart`），改了它们只会红成"页面坏了"，看不出是分类。
final Map<String, String> kFnthinkRemoteActionCategories = {
  // 监听与转发：这一组的开关决定"这台要不要继续看通知"。
  'listener:start': 'listening',
  'listener:stop': 'listening',
  'monitoring': 'listening',
  'collect_inbox': 'listening',
  // 通道与状态：改的是"往哪儿发、发什么回去"。
  'channel:toggle': 'channels',
  'device_state:push': 'channels',
  'notifications:report': 'channels',
  // 查找内容：三枚都要读本机数据，是这一页里隐私最重的一组。
  'sms:search': 'search',
  'calls:search': 'search',
  'contacts:search': 'search',
  // 设备动作：动的是硬件或前台应用。
  'app:launch': 'device',
  'location:get': 'device',
  'camera:snap': 'device',
  'alert:ring': 'device',
  // 系统与权限：这几枚的"能不能做"其实由系统那一侧决定（`grant` 那四项只能请用户去开）。
  'notification': 'system',
  'exact_alarm': 'system',
  'battery_optimization': 'system',
  'autostart': 'system',
};

/// 组标题的人话。存**取值函数**而不是 ARB 键名 —— 与标签表同一条理由：
/// 少一条词条就编译不过，不必等一条运行时用例去撞。
final Map<String, String Function(AppLocalizations)>
kFnthinkRemoteCategoryTitles = {
  'listening': (l) => l.remoteCategoryListening,
  'channels': (l) => l.remoteCategoryChannels,
  'search': (l) => l.remoteCategorySearch,
  'device': (l) => l.remoteCategoryDevice,
  'system': (l) => l.remoteCategorySystem,

  /// 契约加了新动作而这张表没跟上 ⇒ 归到这里，**看得见**的缺，
  /// 而不是悄悄把它塞进某一组（那的表现是"分组看起来挺整齐，但没人知道它在骗你"）。
  '': (l) => l.remoteCategoryUncategorized,
};

/// 组画出来的先后。不在表里的 slug（包括未分类那一组）排在最后，
/// 这样"漂移"这件事在界面上总是靠后、但一定看得见。
const List<String> kFnthinkRemoteCategoryOrder = [
  'listening',
  'channels',
  'search',
  'device',
  'system',
];

/// 这一项归哪一组。没配过 ⇒ 空串（未分类那一组），并由守卫钉红。
String fnthinkRemoteActionCategory(String action) =>
    kFnthinkRemoteActionCategories[action] ?? '';

/// 一组的标题。
String fnthinkRemoteCategoryTitle(AppLocalizations l10n, String slug) {
  final title = kFnthinkRemoteCategoryTitles[slug];
  return title == null ? kFnthinkRemoteCategoryTitles['']!(l10n) : title(l10n);
}

/// 一组动作：保持调用方给进来的顺序（契约登记序），只把它按主题分堆。
///
/// 返回的 slug 顺序 = [kFnthinkRemoteCategoryOrder]，未分类排最后；
/// 空组**不出现**（画一排只有标题没有 chip 的栏，读起来像"这一档没东西"）。
List<FnthinkRemoteActionGroup> fnthinkRemoteActionGroups(List<String> actions) {
  final bySlug = <String, List<String>>{};
  for (final action in actions) {
    bySlug
        .putIfAbsent(fnthinkRemoteActionCategory(action), () => [])
        .add(action);
  }
  final ordered = <String>[
    ...kFnthinkRemoteCategoryOrder.where((s) => bySlug.containsKey(s)),
    ...bySlug.keys.where((s) => !kFnthinkRemoteCategoryOrder.contains(s)),
  ];
  return [
    for (final slug in ordered)
      FnthinkRemoteActionGroup(slug: slug, actions: bySlug[slug]!),
  ];
}

/// 一栏：标题由 `slug` 决定，chip 由 `actions` 决定。
class FnthinkRemoteActionGroup {
  const FnthinkRemoteActionGroup({required this.slug, required this.actions});

  final String slug;
  final List<String> actions;
}
