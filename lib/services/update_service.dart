import '../update_manager.dart';
import 'update_server_regions.dart';

class UpdateService {
  /// [onProbe] 是「这台更新服务器能不能用」的记账出口，装配点在
  /// `lib/di/service_locator.dart`（与幻念协调者的 `recordHealth` 同一形状）。
  /// ⚠ 可空不是摆设：没接的时候更新照常，只是服务器选择页的徽标永远"没测过" ——
  ///   那个缺陷在幻念那一格已经出现过一次，所以这里给装配留了一个编译期看得见的口子。
  UpdateService({this.onProbe});

  final UpdateProbeReport? onProbe;

  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  Future<void> init() async {
    await AppUpdateManager.instance.init();
  }

  Future<VersionCheckResult?> checkUpdate({bool force = false}) async {
    return AppUpdateManager.instance.checkUpdate(
      force: force,
      onProbe: onProbe,
    );
  }

  /// 本机当前该用哪一台更新服务器（界面展示）。
  UpdateServerRegion get region => AppUpdateManager.instance.region;

  /// 主动探一台并把结论记账（打开「更新服务器」那一页时两台各来一次）。
  Future<UpdateServerProbe> probeRegion(UpdateServerRegion region) async {
    final probe = await AppUpdateManager.instance.probeUpdateServer(region);
    await onProbe?.call(probe: probe);
    return probe;
  }

  Future<void> performAutoCheck() async {
    if (!AppUpdateManager.instance.autoCheck) return;
    final shouldCheck = await AppUpdateManager.instance.shouldCheckNow();
    if (!shouldCheck) return;

    await checkUpdate(force: false);
  }

  Future<String?> downloadApk(
    String url, {
    int? totalSize,
    String? appName,
    String? version,
    String? notificationTitle,
    required void Function(double) onProgress,
  }) async {
    _isDownloading = true;
    try {
      return await AppUpdateManager.instance.downloadApk(
        url,
        totalSize: totalSize,
        appName: appName,
        version: version,
        notificationTitle: notificationTitle,
        onProgress: onProgress,
      );
    } finally {
      _isDownloading = false;
    }
  }

  /// 安装已下载的安装包。
  /// [sha256ByAbi]：各架构安装包的期望 sha256（version.json 下发，N3 传输层校验）。
  /// 返回是否成功启动安装；失败时可通过 [lastInstallBlock] 获取原因
  /// （如签名校验不通过、sha256 校验和不匹配、版本降级被拦截），UI 层应展示给用户。
  Future<bool> installApk(
    String filePath, {
    Map<String, String> sha256ByAbi = const {},
  }) async {
    return AppUpdateManager.instance.installApk(
      filePath,
      sha256ByAbi: sha256ByAbi,
    );
  }

  /// 最近一次安装被完整性校验阻止的结论（码 + 原生那句原文）；无则 null。
  /// ⚠ 回的是**码**不是句子：措辞归界面（服务层再拼一份双语，就是 ARB 之外的第二份本地化机制）。
  UpdateInstallBlock? get lastInstallBlock =>
      AppUpdateManager.instance.lastInstallBlock;

  /// 把某一版写进忽略名单（用户按下「忽略」时走这条）。
  /// ⚠ T90 片21：这一层**原来**返回 `void`（对底层的 `Future` 既不 await 也不返回）——
  ///   换件之后调用点要 await 它（弹层 pop 完就该确认写盘），而 `void` 接不住 await。
  ///   顺手把底下那一层补上：原来那行是个**被弃用的 future**，写盘还没开始就返回了
  ///   ⇒ 下一次启动的检查可能在写盘之前读到旧值，「忽略」等于没按。
  Future<void> setIgnoredVersion(String version) async {
    await AppUpdateManager.instance.setIgnoredVersion(version);
  }

  Future<String?> getIgnoredVersion() async {
    return AppUpdateManager.instance.getIgnoredVersion();
  }

  bool get forceUpdate => false;

  String get currentVersion => AppUpdateManager.instance.currentVersion;
  int get currentBuild => AppUpdateManager.instance.currentBuild;
  String? get lastError => AppUpdateManager.instance.lastError;
}
