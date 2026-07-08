import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

class AppUpdateManager {
  static const String _updateServerUrl = 'https://notice.fnthink.top';
  static const String _prefsKeyAutoCheck = 'auto_check_update';
  static const String _prefsKeyLastCheckTime = 'last_update_check_time';
  static const String _prefsKeyContentVersion = 'content_version';
  static const String _prefsKeyIgnoredVersion = 'ignored_version';

  static const int _checkIntervalHours = 24;

  static AppUpdateManager? _instance;
  static AppUpdateManager get instance => _instance ??= AppUpdateManager._();

  AppUpdateManager._();

  bool _autoCheck = true;
  int _contentVersion = 0;
  PackageInfo? _packageInfo;
  String? _lastError;

  String get serverUrl => _updateServerUrl;
  bool get autoCheck => _autoCheck;
  int get contentVersion => _contentVersion;
  String? get lastError => _lastError;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _autoCheck = prefs.getBool(_prefsKeyAutoCheck) ?? true;
    _contentVersion = prefs.getInt(_prefsKeyContentVersion) ?? 0;
    _packageInfo = await PackageInfo.fromPlatform();
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

  String get currentVersion => _packageInfo?.version ?? '1.0.0';
  int get currentBuild => int.tryParse(_packageInfo?.buildNumber ?? '1') ?? 1;

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

    try {
      final uri = Uri.parse('$_updateServerUrl/api/version/check').replace(
        queryParameters: {
          'version': currentVersion,
          'build': currentBuild.toString(),
          'platform': 'android',
        },
      );
      debugPrint('检查更新：请求地址 $uri');

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      debugPrint('检查更新：响应状态码 ${response.statusCode}');
      if (response.statusCode != 200) {
        _lastError = '服务器响应错误：HTTP ${response.statusCode}';
        return null;
      }

      final data = jsonDecode(response.body);
      debugPrint('检查更新：响应数据 code=${data['code']}');
      if (data['code'] != 0) {
        _lastError = '服务器返回错误：${data['message'] ?? '未知错误'}';
        return null;
      }

      final result = VersionCheckResult.fromJson(data['data']);
      debugPrint(
        '检查更新：最新版本 ${result.latestVersion}，hasUpdate=${result.hasUpdate}',
      );
      await _markChecked();
      return result;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('检查更新异常：$e');
      return null;
    }
  }

  Future<HotfixCheckResult?> checkHotfix({bool force = false}) async {
    try {
      final uri = Uri.parse('$_updateServerUrl/api/hotfix/check').replace(
        queryParameters: {
          'contentVersion': _contentVersion.toString(),
          'platform': 'android',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data['code'] != 0) return null;

      return HotfixCheckResult.fromJson(data['data']);
    } catch (e) {
      return null;
    }
  }

  Future<String> downloadApk(
    String downloadUrl, {
    int? totalSize,
    Function(double progress)? onProgress,
    Function()? onCancel,
  }) async {
    final fullUrl = _getFullUrl(downloadUrl);
    final dir = await getTemporaryDirectory();
    final fileName = 'app_update_${DateTime.now().millisecondsSinceEpoch}.apk';
    final savePath = '${dir.path}/$fileName';
    final file = File(savePath);

    var fileTotalSize = totalSize ?? 0;

    final response = await http.Client().send(
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
      return result.type == ResultType.done;
    } catch (e) {
      return false;
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

    final response = await http.Client().send(
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
          final outFile = File('${hotfixDir.path}/${file.name}');
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
