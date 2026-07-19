import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'services/pinned_http_client.dart';
import 'services/platform_channel.dart';
import 'package:permission_handler/permission_handler.dart';

/// SSL 证书固定的 HTTP 客户端。不配置时仅做标准 TLS 验证。
/// 配置示例：{ 'notice.fnthink.top': 'AA:BB:CC:...' }
const _pinnedFingerprints = <String, String>{};
final _updateHttpClient = PinnedHttpClient.create(
  pinnedFingerprints: _pinnedFingerprints,
);

class AppUpdateManager {
  static const String _updateServerUrl = 'https://notice.fnthink.top';
  static const String _githubMirrorUrl =
      'https://xget.fnthink.top/gh/fnthinklevi/noticeTransmit/releases/download';
  static const String _prefsKeyAutoCheck = 'auto_check_update';
  static const String _prefsKeyLastCheckTime = 'last_update_check_time';
  static const String _prefsKeyContentVersion = 'content_version';
  static const String _prefsKeyIgnoredVersion = 'ignored_version';
  static const String _prefsKeyPendingApkPath = 'pending_apk_path';
  static const String _prefsKeyPendingApkVersion = 'pending_apk_version';

  static const String _defaultDownloadDir =
      '/storage/emulated/0/Download/fnthink.notice';

  static const int _checkIntervalHours = 24;

  static AppUpdateManager? _instance;
  static AppUpdateManager get instance => _instance ??= AppUpdateManager._();

  AppUpdateManager._();

  bool _autoCheck = true;
  int _contentVersion = 0;
  String _currentVersion = '1.5.34';
  int _currentBuild = 68;
  String? _lastError;

  String get serverUrl => _updateServerUrl;
  bool get autoCheck => _autoCheck;
  int get contentVersion => _contentVersion;
  String? get lastError => _lastError;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _autoCheck = prefs.getBool(_prefsKeyAutoCheck) ?? true;
    _contentVersion = prefs.getInt(_prefsKeyContentVersion) ?? 0;
    await _updateVersionInfo();
    // 更新完成后（新版本已启动）自动删除上一次下载的安装包
    await _cleanupInstalledApk();
  }

  /// 检测是否已拥有写入公共 Download 目录所需的存储权限
  Future<bool> storagePermissionGranted() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    return false;
  }

  /// 申请存储权限：Android 10 及以下用普通存储权限；Android 11+ 需“所有文件访问”权限
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await storagePermissionGranted()) return true;
    final legacy = await Permission.storage.request();
    if (legacy.isGranted) return true;
    final manage = await Permission.manageExternalStorage.request();
    return manage.isGranted;
  }

  Future<String> resolveDownloadDir() async {
    if (!Platform.isAndroid) {
      return (await getTemporaryDirectory()).path;
    }
    try {
      return await AppChannels.notification.invokeMethod('getDownloadDirectory')
          as String;
    } catch (e) {
      return _defaultDownloadDir;
    }
  }

  /// 更新完成后清理：若当前版本已等于上次下载安装包的目标版本，则删除该安装包
  Future<void> _cleanupInstalledApk() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingPath = prefs.getString(_prefsKeyPendingApkPath);
      final pendingVersion = prefs.getString(_prefsKeyPendingApkVersion);
      if (pendingPath == null || pendingPath.isEmpty) return;
      // 版本已升级（当前版本 == 下载时的目标版本）说明安装成功
      final installed =
          pendingVersion == null || pendingVersion == _currentVersion;
      if (installed) {
        final file = File(pendingPath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('更新后已自动删除安装包: $pendingPath');
        }
        await prefs.remove(_prefsKeyPendingApkPath);
        await prefs.remove(_prefsKeyPendingApkVersion);
      }
    } catch (e) {
      debugPrint('清理已安装包失败: $e');
    }
  }

  Future<void> _updateVersionInfo() async {
    if (Platform.isAndroid) {
      try {
        debugPrint('Calling getAppVersion method channel...');
        final result = await AppChannels.notification.invokeMethod(
          'getAppVersion',
        );
        debugPrint(
          'getAppVersion result: $result, type: ${result.runtimeType}',
        );
        if (result is Map) {
          _currentVersion = result['versionName']?.toString() ?? '1.5.34';
          _currentBuild =
              int.tryParse(result['versionCode']?.toString() ?? '68') ?? 68;
        } else {
          debugPrint('Result is not a Map, using default values');
          _currentVersion = '1.5.34';
          _currentBuild = 68;
        }
        debugPrint(
          'Version from native: $_currentVersion build $_currentBuild',
        );
      } catch (e, stack) {
        debugPrint('Failed to get version from native: $e');
        debugPrint('Stack trace: $stack');
        _currentVersion = '1.5.34';
        _currentBuild = 68;
      }
    } else {
      _currentVersion = '1.5.34';
      _currentBuild = 68;
    }
  }

  Future<void> setAutoCheck(bool value) async {
    _autoCheck = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyAutoCheck, value);
  }

  Future<void> setContentVersion(int version) async {
    _contentVersion = version;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyContentVersion, version);
  }

  String get currentVersion => _currentVersion;
  int get currentBuild => _currentBuild;

  Future<bool> shouldCheckNow() async {
    if (!_autoCheck) return false;
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_prefsKeyLastCheckTime) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final diffHours = (now - lastCheck) / (1000 * 60 * 60);
    return diffHours >= _checkIntervalHours;
  }

  Future<void> _markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefsKeyLastCheckTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<VersionCheckResult?> checkUpdate({bool force = false}) async {
    _lastError = null;
    if (!force && !(await shouldCheckNow())) return null;

    // 1. 尝试 API 模式（Node.js 服务器）
    try {
      final uri = Uri.parse('$_updateServerUrl/api/version/check').replace(
        queryParameters: {
          'version': currentVersion,
          'build': currentBuild.toString(),
          'platform': 'android',
        },
      );
      debugPrint('检查更新：请求地址 $uri');

      final response = await _updateHttpClient
          .get(uri)
          .timeout(const Duration(seconds: 15));
      debugPrint('检查更新：响应状态码 ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          final result = VersionCheckResult.fromJson(data['data']);
          debugPrint(
            '检查更新：最新版本 ${result.latestVersion}，hasUpdate=${result.hasUpdate}',
          );
          await _markChecked();
          return result;
        }
        _lastError = '服务器返回错误：${data['message'] ?? '未知错误'}';
      }
      // 404 等非 200 状态 → 尝试静态模式
      debugPrint('检查更新：API 返回 ${response.statusCode}，尝试静态 JSON 模式');
    } catch (e) {
      // 网络异常 → 尝试静态模式
      debugPrint('检查更新：API 异常 $e，尝试静态 JSON 模式');
    }

    // 2. 回退到静态 JSON 模式（GitHub Pages 等静态部署）
    return _checkUpdateStatic();
  }

  /// 静态 JSON 模式：直接拉取 /api/version.json，客户端做版本比较
  Future<VersionCheckResult?> _checkUpdateStatic() async {
    try {
      final uri = Uri.parse('$_updateServerUrl/api/version.json');
      final response = await _updateHttpClient
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        _lastError = '服务器响应错误：HTTP ${response.statusCode}';
        return null;
      }

      final versionData = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = versionData['latestVersion']?.toString() ?? '0.0.0';
      final latestBuild =
          int.tryParse(versionData['latestBuild']?.toString() ?? '0') ?? 0;

      final hasUpdate =
          _compareVersions(latestVersion, currentVersion) > 0 ||
          latestBuild > currentBuild;

      final needForce =
          (versionData['forceUpdate'] == true) &&
          (_compareVersions(
                    versionData['forceUpdateVersion']?.toString() ??
                        latestVersion,
                    currentVersion,
                  ) >
                  0 ||
              (int.tryParse(
                        versionData['forceUpdateBuild']?.toString() ?? '0',
                      ) ??
                      0) >
                  currentBuild);

      final result = VersionCheckResult(
        hasUpdate: hasUpdate,
        appName: versionData['appName']?.toString() ?? 'notice$latestVersion',
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        forceUpdate: needForce,
        changelog: versionData['changelog']?.toString() ?? '',
        downloadUrl: versionData['downloadUrl']?.toString() ?? '',
        fileSize: int.tryParse(versionData['fileSize']?.toString() ?? '0') ?? 0,
        platform: versionData['platform']?.toString() ?? 'android',
        minSupportedVersion:
            versionData['minSupportedVersion']?.toString() ?? '1.0.0',
      );

      debugPrint('检查更新（静态）：最新版本 ${result.latestVersion}，hasUpdate=$hasUpdate');
      await _markChecked();
      return result;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('检查更新（静态）异常：$e');
      return null;
    }
  }

  /// 比较两个语义化版本号，返回 >0 / 0 / <0
  int _compareVersions(String v1, String v2) {
    List<int> toParts(String v) => v.split('.').map((s) {
      return int.tryParse(s) ?? 0;
    }).toList();
    final parts1 = toParts(v1.isEmpty ? '0' : v1);
    final parts2 = toParts(v2.isEmpty ? '0' : v2);
    final maxLen = parts1.length > parts2.length
        ? parts1.length
        : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  Future<HotfixCheckResult?> checkHotfix({bool force = false}) async {
    // 1. 尝试 API 模式（Node.js 服务器）
    try {
      final uri = Uri.parse('$_updateServerUrl/api/hotfix/check').replace(
        queryParameters: {
          'contentVersion': _contentVersion.toString(),
          'platform': 'android',
        },
      );

      final response = await _updateHttpClient
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          return HotfixCheckResult.fromJson(data['data']);
        }
      }
      // 非 200 → 尝试静态模式
      debugPrint('热更新：API 返回 ${response.statusCode}，尝试静态 JSON 模式');
    } catch (e) {
      debugPrint('热更新：API 异常 $e，尝试静态 JSON 模式');
    }

    // 2. 回退到静态 JSON 模式（GitHub Pages 等静态部署）
    return _checkHotfixStatic();
  }

  /// 静态 JSON 模式：直接拉取 /api/hotfix.json，客户端做版本比较
  Future<HotfixCheckResult?> _checkHotfixStatic() async {
    try {
      final uri = Uri.parse('$_updateServerUrl/api/hotfix.json');
      final response = await _updateHttpClient
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final hotfixData = jsonDecode(response.body) as Map<String, dynamic>;
      final latestContentVersion =
          int.tryParse(hotfixData['latestContentVersion']?.toString() ?? '0') ??
          0;

      final hasUpdate = latestContentVersion > _contentVersion;
      if (!hasUpdate) return null;

      final needForce =
          (hotfixData['forceUpdate'] == true) &&
          (int.tryParse(hotfixData['forceContentVersion']?.toString() ?? '0') ??
                  0) >
              _contentVersion;

      return HotfixCheckResult(
        hasUpdate: true,
        latestContentVersion: latestContentVersion,
        version: hotfixData['version']?.toString() ?? '',
        forceUpdate: needForce,
        changelog: hotfixData['changelog']?.toString() ?? '',
        downloadUrl: hotfixData['downloadUrl']?.toString() ?? '',
        fileSize: int.tryParse(hotfixData['fileSize']?.toString() ?? '0') ?? 0,
        platform: hotfixData['platform']?.toString() ?? 'android',
        minAppVersion: hotfixData['minAppVersion']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('热更新（静态）异常：$e');
      return null;
    }
  }

  Future<String> downloadApk(
    String downloadUrl, {
    int? totalSize,
    Function(double progress)? onProgress,
    Function()? onCancel,
    String? appName,
    String? version,
  }) async {
    if (Platform.isAndroid) {
      final granted = await requestStoragePermission();
      if (!granted) {
        throw Exception('存储权限未授予');
      }
    }

    final downloadDirPath = await resolveDownloadDir();
    final downloadsDir = Directory(downloadDirPath);
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }

    final fileName = 'app_update_${DateTime.now().millisecondsSinceEpoch}.apk';
    final savePath = '${downloadsDir.path}/$fileName';
    final file = File(savePath);

    await _cleanupOldApks(downloadsDir);

    final urls = _buildDownloadUrls(downloadUrl, appName, version);

    for (int i = 0; i < urls.length; i++) {
      try {
        final url = urls[i];
        debugPrint('下载APK：尝试 $url');

        var fileTotalSize = totalSize ?? 0;

        final response = await _updateHttpClient.send(
          http.Request('GET', Uri.parse(url)),
        );

        if (response.statusCode != 200) {
          if (i < urls.length - 1) {
            debugPrint('下载APK：地址 $url 返回 ${response.statusCode}，尝试下一个');
            continue;
          }
          throw Exception('下载失败：HTTP ${response.statusCode}');
        }

        if (fileTotalSize == 0) {
          fileTotalSize = response.contentLength ?? 0;
        }
        final clHeader = response.headers['content-length'];
        if (fileTotalSize == 0 && clHeader != null) {
          fileTotalSize = int.tryParse(clHeader) ?? 0;
        }

        var received = 0;

        await response.stream
            .listen(
              (List<int> bytes) {
                received += bytes.length;
                file.writeAsBytesSync(bytes, mode: FileMode.append);
                if (fileTotalSize > 0 && onProgress != null) {
                  onProgress(received / fileTotalSize);
                }
              },
              onDone: () {},
              onError: (e) {
                throw e;
              },
            )
            .asFuture();

        debugPrint('下载APK：成功，路径 $savePath');
        await _recordPendingApk(savePath, version);
        return savePath;
      } catch (e) {
        debugPrint('下载APK：地址 ${urls[i]} 失败 - $e');
        if (i < urls.length - 1) {
          debugPrint('下载APK：尝试下一个地址');
        } else {
          rethrow;
        }
      }
    }

    throw Exception('所有下载地址均失败');
  }

  List<String> _buildDownloadUrls(
    String downloadUrl,
    String? appName,
    String? version,
  ) {
    final urls = <String>[];

    if (downloadUrl.isNotEmpty) {
      urls.add(_getFullUrl(downloadUrl));
    }

    if (version != null && appName != null) {
      final githubUrl = '$_githubMirrorUrl/$version/$appName.apk';
      urls.add(githubUrl);
    }

    return urls;
  }

  Future<bool> installApk(String filePath) async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          openAppSettings();
          return false;
        }
      }
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      // 不再使用脆弱的定时删除；安装包路径已记录，下次启动时
      // 若检测到版本已升级，会由 _cleanupInstalledApk 自动删除。
      return result.type == ResultType.done;
    } catch (e) {
      return false;
    }
  }

  /// 记录本次下载的安装包路径与目标版本，供更新完成后自动清理
  Future<void> _recordPendingApk(String path, String? version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyPendingApkPath, path);
      if (version != null && version.isNotEmpty) {
        await prefs.setString(_prefsKeyPendingApkVersion, version);
      } else {
        await prefs.remove(_prefsKeyPendingApkVersion);
      }
    } catch (e) {
      debugPrint('记录待安装APK失败: $e');
    }
  }

  Future<void> _cleanupOldApks(Directory downloadsDir) async {
    try {
      final files = downloadsDir.listSync().whereType<File>().toList();
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      for (int i = 1; i < files.length; i++) {
        await files[i].delete();
        debugPrint('清理旧APK文件: ${files[i].path}');
      }
    } catch (e) {
      debugPrint('清理旧APK文件失败: $e');
    }
  }

  Future<String> downloadHotfix(
    String downloadUrl, {
    int? totalSize,
    Function(double progress)? onProgress,
  }) async {
    final fullUrl = _getFullUrl(downloadUrl);
    final dir = await getTemporaryDirectory();
    final fileName = 'hotfix_${DateTime.now().millisecondsSinceEpoch}.zip';
    final savePath = '${dir.path}/$fileName';
    final file = File(savePath);

    var fileTotalSize = totalSize ?? 0;

    final response = await _updateHttpClient.send(
      http.Request('GET', Uri.parse(fullUrl)),
    );

    if (fileTotalSize == 0) {
      fileTotalSize = response.contentLength ?? 0;
    }
    final clHeader = response.headers['content-length'];
    if (fileTotalSize == 0 && clHeader != null) {
      fileTotalSize = int.tryParse(clHeader) ?? 0;
    }

    var received = 0;

    await response.stream
        .listen(
          (List<int> bytes) {
            received += bytes.length;
            file.writeAsBytesSync(bytes, mode: FileMode.append);
            if (fileTotalSize > 0 && onProgress != null) {
              onProgress(received / fileTotalSize);
            }
          },
          onDone: () {},
          onError: (e) {
            throw e;
          },
        )
        .asFuture();

    return savePath;
  }

  Future<bool> applyHotfix(String zipPath, int newVersion) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final appDir = await getApplicationDocumentsDirectory();
      final hotfixDir = Directory('${appDir.path}/hotfix');
      if (await hotfixDir.exists()) {
        await hotfixDir.delete(recursive: true);
      }
      await hotfixDir.create(recursive: true);

      for (final file in archive) {
        if (file.isFile) {
          final name = file.name;
          // Guard against zip-slip: reject entries that escape the hotfix dir.
          if (name.isEmpty ||
              name.startsWith('/') ||
              name.startsWith('\\') ||
              name.startsWith('~') ||
              name.contains('..')) {
            debugPrint('跳过非法热修复条目: $name');
            continue;
          }
          final outFile = File('${hotfixDir.path}/$name');
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }

      await setContentVersion(newVersion);
      return true;
    } catch (e) {
      return false;
    }
  }

  String _getFullUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return '$_updateServerUrl$url';
    }
    return '$_updateServerUrl/$url';
  }

  Future<String?> getHotfixFilePath(String relativePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filePath = '${appDir.path}/hotfix/$relativePath';
    final file = File(filePath);
    if (await file.exists()) {
      return filePath;
    }
    return null;
  }

  Future<void> setIgnoredVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyIgnoredVersion, version);
  }

  Future<String?> getIgnoredVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyIgnoredVersion);
  }
}

class VersionCheckResult {
  final bool hasUpdate;
  final String appName;
  final String latestVersion;
  final int latestBuild;
  final bool forceUpdate;
  final String changelog;
  final String downloadUrl;
  final int fileSize;
  final String platform;
  final String minSupportedVersion;

  VersionCheckResult({
    required this.hasUpdate,
    required this.appName,
    required this.latestVersion,
    required this.latestBuild,
    required this.forceUpdate,
    required this.changelog,
    required this.downloadUrl,
    required this.fileSize,
    required this.platform,
    required this.minSupportedVersion,
  });

  factory VersionCheckResult.fromJson(Map<String, dynamic> json) {
    return VersionCheckResult(
      hasUpdate: json['hasUpdate'] ?? false,
      appName: json['appName'] ?? '',
      latestVersion: json['latestVersion'] ?? '',
      latestBuild: json['latestBuild'] ?? 0,
      forceUpdate: json['forceUpdate'] ?? false,
      changelog: json['changelog'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      fileSize: json['fileSize'] ?? 0,
      platform: json['platform'] ?? 'android',
      minSupportedVersion: json['minSupportedVersion'] ?? '',
    );
  }

  String get fileSizeStr {
    if (fileSize <= 0) return '未知';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class HotfixCheckResult {
  final bool hasUpdate;
  final int latestContentVersion;
  final String version;
  final bool forceUpdate;
  final String changelog;
  final String downloadUrl;
  final int fileSize;
  final String platform;
  final String minAppVersion;

  HotfixCheckResult({
    required this.hasUpdate,
    required this.latestContentVersion,
    required this.version,
    required this.forceUpdate,
    required this.changelog,
    required this.downloadUrl,
    required this.fileSize,
    required this.platform,
    required this.minAppVersion,
  });

  factory HotfixCheckResult.fromJson(Map<String, dynamic> json) {
    return HotfixCheckResult(
      hasUpdate: json['hasUpdate'] ?? false,
      latestContentVersion: json['latestContentVersion'] ?? 0,
      version: json['version'] ?? '',
      forceUpdate: json['forceUpdate'] ?? false,
      changelog: json['changelog'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      fileSize: json['fileSize'] ?? 0,
      platform: json['platform'] ?? 'android',
      minAppVersion: json['minAppVersion'] ?? '',
    );
  }

  String get fileSizeStr {
    if (fileSize <= 0) return '未知';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
