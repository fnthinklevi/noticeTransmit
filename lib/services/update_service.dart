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

  Future<bool> storagePermissionGranted() async {
    return AppUpdateManager.instance.storagePermissionGranted();
  }

  Future<bool> requestStoragePermission() async {
    return AppUpdateManager.instance.requestStoragePermission();
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

  void installApk(String filePath) {
    AppUpdateManager.instance.installApk(filePath);
  }

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
