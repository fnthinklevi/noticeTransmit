import 'permission_service.dart';

/// 厂商自启动这一族的**唯一分流表**（T140 (b) ②「自启动引导补齐」的真正落点）。
///
/// 为什么值得单独成文件：这一族的词面匹配今天在三处各写了一份，而且**三份口径不同** ——
/// ㊀ L3 `autostart` 那一发（原 `lib/di/service_locator.dart`）只认 `xiaomi/meizu/huawei/oppo/vivo`
///     五个词，红米／荣耀／真我／一加／iQOO 这些机器上**什么都不做**（落进"都对不上"那一支）；
/// ㊁ 权限设置页认全套变体（`redmi`／`mi `／`honor`／`realme`／`oneplus`／`iqoo`）⇒ 同一台机器上
///     磁贴能跳、远端那一发不跳；
/// ㊂ 小组件引导页认全套变体但**没有魅族**那一支。
/// 三份表的下场正是台账写的那句「某一台只在一处被引导」：用户与运维各拿一份说不清的账 ——
/// 界面上"这台能跳"，L3 的审计里"这台没跳"，而两边的日志都写着自己没错。
///
/// ⚠ 匹配用**小写包含**而不是相等：各家在 `Build.MANUFACTURER` 里写的串并不统一
///   （`Xiaomi` / `Xiaomi Inc.` / `Redmi` / `MI 8`…），相等匹配的表现是
///   "这台明明是小米、却说这不是小米"。
/// ⚠ 都对不上 ⇒ [FnthinkVendorFamily.stock]，而 stock **不给跳**（只给通用文字引导）：
///   弹一个别家的自启动页比不弹更糟 —— 用户被送进一个无关页面，还以为自己已经设置了。
enum FnthinkVendorFamily {
  xiaomi,
  meizu,
  huawei,
  oppo,
  vivo,
  samsung,
  stock;

  /// 厂商词表按**本枚举的声明顺序**匹配（顺序就是优先级）。
  ///
  /// ⚠ 一条厂商串同时命中两家（`"huawei vivo"` 这种脏值）时，赢的是先声明的那一家，
  ///   而**全仓只有这里在决定这件事**；把表抄到第二处，第二处的顺序就是第二个答案。
  List<String> get _words => switch (this) {
    FnthinkVendorFamily.xiaomi => const ['xiaomi', 'redmi', 'mi '],
    FnthinkVendorFamily.meizu => const ['meizu'],
    FnthinkVendorFamily.huawei => const ['huawei', 'honor'],
    FnthinkVendorFamily.oppo => const ['oppo', 'realme', 'oneplus'],
    FnthinkVendorFamily.vivo => const ['vivo', 'iqoo'],
    FnthinkVendorFamily.samsung => const ['samsung'],
    // 原生／模拟器：认这两枚词，但**不认成任何一家厂商**。
    FnthinkVendorFamily.stock => const ['google', 'android'],
  };
}

/// 这台机器算哪一家（唯一作者）。空串与认不出的串都归 [FnthinkVendorFamily.stock]。
///
/// 全表按**同一个优先级顺序**判（含 stock 那两枚原生词），所以"哪家都不是"与
/// "是 Pixel／模拟器"给的是同一档答复 —— 合成一挡不说谎（两档都是"通用文字引导、不给跳"），
/// 也少一处只有作者知道的例外。
FnthinkVendorFamily fnthinkVendorFamilyOf(String manufacturer) {
  final maker = manufacturer.toLowerCase();
  for (final family in FnthinkVendorFamily.values) {
    if (family._words.any(maker.contains)) return family;
  }
  return FnthinkVendorFamily.stock;
}

/// 这一族**有没有**可跳的自启动入口，以及跳哪一发。
///
/// 返回 null = 不给跳（三星与原生今天只有文字引导；厂商那一页的入口名没有公开口径，
/// 猜一个 ComponentName 就是把用户送进无关页面）。派发只认这一处，别处不许再按族名 `if` 一遍。
Future<void> Function(PermissionService)? fnthinkAutostartJumpFor(
  FnthinkVendorFamily family,
) => switch (family) {
  FnthinkVendorFamily.xiaomi => (p) => p.requestXiaomiAutoStart(),
  FnthinkVendorFamily.meizu => (p) => p.requestMeizuBackground(),
  FnthinkVendorFamily.huawei => (p) => p.requestHuaweiLaunch(),
  FnthinkVendorFamily.oppo => (p) => p.requestOppoBackground(),
  FnthinkVendorFamily.vivo => (p) => p.requestVivoBackground(),
  FnthinkVendorFamily.samsung => null,
  FnthinkVendorFamily.stock => null,
};

/// 「本机自启动引导」那一发的完整派发（L3 `autostart` 与任何别的使用者都走这里）。
///
/// 无返回值、不给理由：这一族**读不到状态**（六厂商都不给公开读数），所以它的结论只有
/// "跳出去了"与"这台没有可跳的入口"两种，而后者不是失败、是真话 —— 界面上那一行由
/// `l3StateUnreadable` 那一句负责说清，不在这里发明第二种说法。
Future<void> fnthinkRequestVendorAutoStart({
  required String manufacturer,
  required PermissionService permissions,
}) async {
  final jump = fnthinkAutostartJumpFor(fnthinkVendorFamilyOf(manufacturer));
  if (jump == null) return;
  await jump(permissions);
}
