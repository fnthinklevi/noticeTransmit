import '../update_manager.dart';

class UpdateService {
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  Future<void> init() async {
    await AppUpdateManager.instance.init();
  }

  Future<VersionCheckResult?> checkUpdate({bool force = false}) async {
    return AppUpdateManager.instance.checkUpdate(force: force);
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
    required void Function(double) onProgress,
  }) async {
    _isDownloading = true;
    try {
      return await AppUpdateManager.instance.downloadApk(
        url,
        totalSize: totalSize,
        appName: appName,
        version: version,
        onProgress: onProgress,
      );
    } finally {
      _isDownloading = false;
    }
  }

  /// 安装已下载的安装包。
  /// [sha256ByAbi]：各架构安装包的期望 sha256（version.json 下发，N3 传输层校验）。
  /// 返回是否成功启动安装；失败时可通过 [lastInstallBlockReason] 获取原因
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

  /// 最近一次安装被完整性校验阻止的原因；无则 null
  String? get lastInstallBlockReason =>
      AppUpdateManager.instance.lastInstallBlockReason;

  void setIgnoredVersion(String version) {
    AppUpdateManager.instance.setIgnoredVersion(version);
  }

  Future<String?> getIgnoredVersion() async {
    return AppUpdateManager.instance.getIgnoredVersion();
  }

  bool get forceUpdate => false;

  String get currentVersion => AppUpdateManager.instance.currentVersion;
  int get currentBuild => AppUpdateManager.instance.currentBuild;
  String? get lastError => AppUpdateManager.instance.lastError;
}
