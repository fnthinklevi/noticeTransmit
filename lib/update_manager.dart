import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'services/pinned_http_client.dart';
import 'services/platform_channel.dart';
import 'package:permission_handler/permission_handler.dart';

/// SSL 证书固定（默认关闭）
///
/// 指纹通过 `--dart-define` 注入，格式（与原生 NetworkClient 统一用 CERT_PINS 名）：
/// ```
/// --dart-define=CERT_PINS="notice.fnthink.top=AA:BB:CC:...;xget.fnthink.top=DD:EE:..."
/// ```
/// 未注入或为空时仅做标准 TLS 验证。获取方式与多 pin/轮换策略见 base.md「3.5 证书固定」。
///
/// ⚠️ 本项目使用 Cloudflare CDN，边缘证书由 Cloudflare 自动管理、指纹不固定，
/// 直接固定叶子证书指纹会导致证书续期后 App 全体断连——启用前务必确认证书策略
/// （推荐固定源站证书 + 至少 2 个备份 pin）。
final _pinnedFingerprints = certPinsFromEnvironment();
final _updateHttpClient = PinnedHttpClient.create(
  pinnedFingerprints: _pinnedFingerprints,
);

class AppUpdateManager {
  static const String _updateServerUrl = 'https://notice.fnthink.top';
  static const String _githubMirrorUrl =
      'https://xget.fnthink.top/gh/fnthinklevi/noticeTransmit/releases/download';
  static const String _githubDirectUrl =
      'https://github.com/fnthinklevi/noticeTransmit/releases/download';
  static const String _prefsKeyAutoCheck = 'auto_check_update';
  static const String _prefsKeyLastCheckTime = 'last_update_check_time';
  static const String _prefsKeyIgnoredVersion = 'ignored_version';
  static const String _prefsKeyPendingApkPath = 'pending_apk_path';
  static const String _prefsKeyPendingApkVersion = 'pending_apk_version';

  /// 回退版本号：仅当 native getAppVersion 调用失败时使用。
  /// 发版时同步更新为当前版本号。
  static const String _fallbackVersion = '1.5.61';
  static const int _fallbackBuild = 96;

  static const String _defaultDownloadDir =
      '/storage/emulated/0/Download/FnthinkNotice';

  static const int _checkIntervalHours = 24;

  static AppUpdateManager? _instance;
  static AppUpdateManager get instance => _instance ??= AppUpdateManager._();

  AppUpdateManager._();

  bool _autoCheck = true;
  String _currentVersion = _fallbackVersion;
  int _currentBuild = _fallbackBuild;
  String? _lastError;

  /// 最近一次系统下载器（DownloadManager）任务的 downloadId，安装回退时使用
  String? _lastDownloadId;

  String get serverUrl => _updateServerUrl;
  bool get autoCheck => _autoCheck;
  String? get lastError => _lastError;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _autoCheck = prefs.getBool(_prefsKeyAutoCheck) ?? true;
    await _updateVersionInfo();
    // 更新完成后（新版本已启动）自动删除上一次下载的安装包
    await _cleanupInstalledApk();
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
          _currentVersion =
              result['versionName']?.toString() ?? _fallbackVersion;
          _currentBuild =
              int.tryParse(
                result['versionCode']?.toString() ?? '$_fallbackBuild',
              ) ??
              _fallbackBuild;
        } else {
          debugPrint('Result is not a Map, using fallback values');
          _currentVersion = _fallbackVersion;
          _currentBuild = _fallbackBuild;
        }
        debugPrint(
          'Version from native: $_currentVersion build $_currentBuild',
        );
      } catch (e, stack) {
        debugPrint('Failed to get version from native: $e');
        debugPrint('Stack trace: $stack');
        _currentVersion = _fallbackVersion;
        _currentBuild = _fallbackBuild;
      }
    } else {
      _currentVersion = _fallbackVersion;
      _currentBuild = _fallbackBuild;
    }
  }

  Future<void> setAutoCheck(bool value) async {
    _autoCheck = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyAutoCheck, value);
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

    // 1. 尝试 API 模式（Node.js 服务器），失败后指数退避重试一次
    //    （403 系 Cloudflare 评分抖动导致，重试通常可恢复）
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse('$_updateServerUrl/api/version/check').replace(
          queryParameters: {
            'version': currentVersion,
            'build': currentBuild.toString(),
            'platform': 'android',
          },
        );
        debugPrint('检查更新：请求地址 $uri（第 ${attempt + 1} 次）');

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
        // Cloudflare/CDN 拦截（Bot Fight Mode / WAF）→ 静态端点同域同防护，
        // 不再尝试必然失败的静态回退，直接给出可操作提示。
        if (_isCloudflareBlocked(response.statusCode, response.headers)) {
          _lastError =
              '检查更新被 CDN 拦截（HTTP ${response.statusCode}），'
              '请稍后重试，或访问 GitHub Releases 手动下载最新版';
          debugPrint('检查更新：被 CDN 拦截，跳过静态回退');
          return null;
        }
        // 404 等非 200 状态 → 尝试静态模式
        debugPrint('检查更新：API 返回 ${response.statusCode}，尝试静态 JSON 模式');
        break;
      } catch (e) {
        // 网络异常 → 重试一次后仍失败再尝试静态模式
        debugPrint('检查更新：API 异常（第 ${attempt + 1} 次）$e');
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      }
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
        if (_isCloudflareBlocked(response.statusCode, response.headers)) {
          _lastError =
              '检查更新被 CDN 拦截（HTTP ${response.statusCode}），'
              '请稍后重试，或访问 GitHub Releases 手动下载最新版';
        } else {
          _lastError = '服务器响应错误：HTTP ${response.statusCode}';
        }
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

      // 解析 downloads（v1.5.47+） / 兼容旧 downloadUrl
      final downloads = Map<String, String>.from(
        versionData['downloads'] as Map? ?? {},
      );
      final fileSizes = Map<String, int>.from(
        (versionData['fileSizes'] as Map? ?? {}).map(
          (k, v) =>
              MapEntry(k.toString(), int.tryParse(v?.toString() ?? '0') ?? 0),
        ),
      );
      final abiKey = await _getRealAbi();
      final downloadUrl =
          downloads[abiKey] ??
          downloads['all'] ??
          versionData['downloadUrl']?.toString() ??
          '';
      final fileSize = fileSizes[abiKey] ?? fileSizes['all'] ?? 0;

      final result = VersionCheckResult(
        hasUpdate: hasUpdate,
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        forceUpdate: needForce,
        changelog: versionData['changelog']?.toString() ?? '',
        downloadUrl: downloadUrl,
        fileSize: fileSize,
        minSupportedVersion:
            versionData['minSupportedVersion']?.toString() ?? '1.0.0',
        downloads: downloads,
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

  /// 判断 HTTP 响应是否为 Cloudflare/CDN 拦截（Bot Fight Mode / WAF 等）。
  ///
  /// Cloudflare 拦截特征：状态码 403/429 + 响应头含 `cf-ray`，或
  /// `server` 头为 cloudflare。命中时静态回退端点（同域同防护）大概率同样被拦，
  /// 应直接给出可操作提示而非继续尝试。
  bool _isCloudflareBlocked(int statusCode, Map<String, String> headers) {
    if (statusCode != 403 && statusCode != 429) return false;
    final lower = headers.map((k, v) => MapEntry(k.toLowerCase(), v));
    return lower.containsKey('cf-ray') ||
        (lower['server']?.toLowerCase().contains('cloudflare') ?? false);
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

  /// 获取当前设备 ABI 标识
  static String get deviceAbi {
    if (Platform.isAndroid) {
      // android-arm → armeabi-v7a, android-arm64 → arm64-v8a,
      // android-x64 → x86_64, android → 融合包
      return Platform.isAndroid ? 'arm64' : 'all'; // Flutter TARGET_PLATFORM
    }
    return 'all';
  }

  /// 获取真实设备 ABI（通过 MethodChannel 从原生获取）
  static Future<String> _getRealAbi() async {
    try {
      final abis = await AppChannels.notification.invokeMethod(
        'getSupportedAbis',
      );
      if (abis is List && abis.isNotEmpty) {
        for (final abi in abis) {
          final s = abi.toString();
          if (s.startsWith('arm64')) return 'arm64';
          if (s.startsWith('armeabi')) return 'arm32';
          if (s.startsWith('x86_64')) return 'x86_64';
        }
      }
    } catch (_) {}
    return 'arm64'; // 默认 arm64
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
      // Android：调用系统下载器（DownloadManager），无需存储权限，
      // 后台下载不中断，通知栏自动显示进度（各品牌系统下载器接管）。
      return _downloadWithSystemDownloader(
        downloadUrl,
        totalSize: totalSize,
        onProgress: onProgress,
        appName: appName,
        version: version,
      );
    }
    // 桌面等其他平台：保持原有自实现下载（保存到临时目录）
    return _downloadLegacy(
      downloadUrl,
      totalSize: totalSize,
      onProgress: onProgress,
      onCancel: onCancel,
      appName: appName,
      version: version,
    );
  }

  /// 系统下载器（DownloadManager）下载实现。
  ///
  /// 下载源按优先级依次尝试（共三个）：
  /// 1. CDN（cdn2.fnthink.top，主源）
  /// 2. GitHub 国内加速镜像（xget.fnthink.top）
  /// 3. GitHub 官方直链（github.com）
  /// 后两个均按设备 ABI 取对应安装包。备用地址先做 HEAD 探测，
  /// 可用才交给系统下载器；主地址失败或中途失败自动切换下一个。
  /// 下载到公共 Download/FnthinkNotice 目录，返回本地文件路径；
  /// 路径获取失败时返回空字符串（安装时回退系统安装器 content uri）。
  Future<String> _downloadWithSystemDownloader(
    String downloadUrl, {
    int? totalSize,
    Function(double progress)? onProgress,
    String? appName,
    String? version,
  }) async {
    final abiKey = await _getRealAbi();
    final candidates = _buildCandidateUrls(downloadUrl, version, abiKey);
    String? lastError;
    final errors = <String>[];
    for (int i = 0; i < candidates.length; i++) {
      final url = candidates[i];
      if (i > 0) {
        // 备用地址先探测可用性，避免系统下载器进入失败态
        final ok = await _probeUrl(url);
        if (!ok) {
          errors.add('$url → 探测不可用');
          debugPrint('系统下载器：备用地址不可用，跳过 $url');
          continue;
        }
      }
      final fileName =
          '${appName ?? 'noticeTransmit'}_${version ?? 'update'}'
          '${i == 0 ? '' : '_retry$i'}.apk';
      try {
        final path = await _downloadSingleWithSystem(
          url,
          fileName: fileName,
          version: version,
          onProgress: onProgress,
        );
        return path;
      } catch (e) {
        errors.add('$url → $e');
        lastError = e.toString();
        debugPrint('系统下载器：地址 $url 失败 - $e');
      }
    }
    if (errors.isNotEmpty) {
      debugPrint('下载源全部失败，明细：\n${errors.join('\n')}');
    }
    throw Exception(lastError ?? '所有下载地址均失败');
  }

  /// 使用系统下载器下载单个地址并轮询进度，失败时抛异常
  Future<String> _downloadSingleWithSystem(
    String downloadUrl, {
    required String fileName,
    String? version,
    Function(double progress)? onProgress,
  }) async {
    final id = await AppChannels.notification.invokeMethod(
      'startSystemDownload',
      {'url': downloadUrl, 'fileName': fileName, 'title': '通知推送助手更新'},
    );
    if (id == null || id.toString().isEmpty) {
      throw Exception('无法启动系统下载器');
    }
    _lastDownloadId = id.toString();

    // DownloadManager 状态码：1 等待 / 2 下载中 / 4 暂停 / 8 完成 / 16 失败
    const statusSuccessful = 8;
    const statusFailed = 16;

    var lastProgress = -1.0;
    while (true) {
      await Future.delayed(const Duration(milliseconds: 600));
      Map<Object?, Object?> info;
      try {
        info =
            await AppChannels.notification.invokeMethod(
                  'getSystemDownloadProgress',
                  {'downloadId': _lastDownloadId},
                )
                as Map<Object?, Object?>;
      } catch (e) {
        throw Exception('获取下载进度失败');
      }
      final status = (info['status'] as int?) ?? -1;
      if (status == statusSuccessful) {
        onProgress?.call(1.0);
        final path = await _getSystemDownloadedPath();
        await _recordPendingApk(path ?? '', version);
        return path ?? '';
      }
      if (status == statusFailed) {
        final reason = (info['reason'] as int?) ?? 0;
        final reasonText = info['reasonText']?.toString() ?? '未知';
        debugPrint(
          '系统下载器失败：$downloadUrl status=$status reason=$reason($reasonText)'
          '${await _httpStatusDiagnosis(downloadUrl)}',
        );
        throw Exception('系统下载器下载失败（$reasonText）');
      }
      final progress = ((info['progress'] as num?) ?? 0).toDouble();
      if (progress != lastProgress) {
        lastProgress = progress;
        onProgress?.call(progress);
      }
    }
  }

  /// 构建下载候选 URL 列表（按优先级排序，共三个下载源）：
  /// 1. CDN 主地址（cdn2.fnthink.top，version.json 下发，已按 ABI 匹配）
  /// 2. GitHub 国内加速镜像（xget.fnthink.top，按设备 ABI 取包）
  /// 3. GitHub 官方直链（github.com，按设备 ABI 取包）
  List<String> _buildCandidateUrls(
    String downloadUrl,
    String? version,
    String abiKey,
  ) {
    final urls = <String>[];
    void add(String u) {
      final s = u.trim();
      if (s.isNotEmpty && !urls.contains(s)) urls.add(s);
    }

    // ABI → 安装包平台名（release 资产命名规范 notice_{平台}_{版本}.apk）
    final platform = switch (abiKey) {
      'arm32' => 'arm32',
      'x86_64' => 'x86',
      _ => 'arm64',
    };

    add(downloadUrl);
    if (version != null && version.isNotEmpty) {
      add('$_githubMirrorUrl/$version/notice_${platform}_$version.apk');
      add('$_githubDirectUrl/$version/notice_${platform}_$version.apk');
    }
    return urls;
  }

  /// HEAD 探测 URL 是否可下载（返回 true 表示 HTTP 200）。
  /// 失败时打印状态码与关键响应头，便于排查 404 等下载源问题。
  Future<bool> _probeUrl(String url) async {
    try {
      final response = await _updateHttpClient
          .send(http.Request('HEAD', Uri.parse(url)))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) return true;
      debugPrint(
        '探测下载源失败：$url → HTTP ${response.statusCode} '
        'content-type=${response.headers['content-type'] ?? '-'} '
        'content-length=${response.headers['content-length'] ?? '-'}',
      );
      return false;
    } catch (e) {
      debugPrint('探测下载源异常：$url → $e');
      return false;
    }
  }

  /// 对下载地址做一次 HEAD 请求，返回 HTTP 状态码与关键响应头诊断信息。
  /// 用于系统下载器失败后补充打印，定位是 404 / 重定向 / 限流等问题。
  Future<String> _httpStatusDiagnosis(String url) async {
    try {
      final response = await _updateHttpClient
          .send(http.Request('HEAD', Uri.parse(url)))
          .timeout(const Duration(seconds: 6));
      final headers = response.headers;
      return '；HTTP ${response.statusCode} '
          'content-type=${headers['content-type'] ?? '-'} '
          'content-length=${headers['content-length'] ?? '-'} '
          'location=${headers['location'] ?? '-'} '
          'server=${headers['server'] ?? '-'}';
    } catch (e) {
      return '；HTTP 请求异常 $e';
    }
  }

  Future<String?> _getSystemDownloadedPath() async {
    try {
      final path = await AppChannels.notification.invokeMethod(
        'getDownloadedApkPath',
        {'downloadId': _lastDownloadId},
      );
      return path?.toString();
    } catch (_) {
      return null;
    }
  }

  /// 自实现下载（仅非 Android 平台使用）
  Future<String> _downloadLegacy(
    String downloadUrl, {
    int? totalSize,
    Function(double progress)? onProgress,
    Function()? onCancel,
    String? appName,
    String? version,
  }) async {
    // 优先公共下载目录，失败时回退到应用私有目录
    late String downloadDirPath;
    try {
      downloadDirPath = await resolveDownloadDir();
    } catch (_) {
      final appDir = await getApplicationDocumentsDirectory();
      downloadDirPath = '${appDir.path}/downloads';
    }

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
        // 使用 RandomAccessFile 异步写入，避免 sync I/O 阻塞
        final raf = await file.open(mode: FileMode.write);
        try {
          await for (final bytes in response.stream) {
            await raf.writeFrom(bytes);
            received += bytes.length;
            if (fileTotalSize > 0 && onProgress != null) {
              onProgress(received / fileTotalSize);
            }
          }
        } finally {
          await raf.close();
        }

        debugPrint('下载APK：成功，路径 $savePath');
        await _recordPendingApk(savePath, version);
        return savePath;
      } catch (e) {
        debugPrint('下载APK：地址 ${urls[i]} 失败 - $e');
        // 清理未完成的文件
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
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
      // GitHub Release 资产按项目命名规范为 notice_{平台}_{版本}.apk，
      // 这里统一回退到全平台融合包（notice_all_{version}.apk）。
      final githubUrl = '$_githubMirrorUrl/$version/notice_all_$version.apk';
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
        // 系统下载器下载的文件：本地路径获取失败时（如 content uri 无法转路径），
        // 由原生通过系统安装器直接安装（content uri + FLAG_GRANT_READ_URI_PERMISSION）。
        if (filePath.isEmpty && _lastDownloadId != null) {
          final ok = await AppChannels.notification.invokeMethod(
            'installSystemDownload',
            {'downloadId': _lastDownloadId},
          );
          return ok == true;
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

  String _getFullUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return '$_updateServerUrl$url';
    }
    return '$_updateServerUrl/$url';
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
  final String latestVersion;
  final int latestBuild;
  final bool forceUpdate;
  final String changelog;
  final String downloadUrl;
  final int fileSize;
  final String minSupportedVersion;
  final Map<String, String> downloads;

  VersionCheckResult({
    required this.hasUpdate,
    required this.latestVersion,
    required this.latestBuild,
    required this.forceUpdate,
    required this.changelog,
    required this.downloadUrl,
    required this.fileSize,
    required this.minSupportedVersion,
    this.downloads = const {},
  });

  factory VersionCheckResult.fromJson(Map<String, dynamic> json) {
    final downloads = Map<String, String>.from(json['downloads'] as Map? ?? {});
    final fileSizes = Map<String, int>.from(
      (json['fileSizes'] as Map? ?? {}).map(
        (k, v) =>
            MapEntry(k.toString(), int.tryParse(v?.toString() ?? '0') ?? 0),
      ),
    );
    // API 模式兼容：优先取直接字段，缺失时从 downloads/fileSizes map 回退（默认 arm64）
    final downloadUrl = (json['downloadUrl'] as String?)?.isNotEmpty == true
        ? json['downloadUrl'] as String
        : (downloads['arm64'] ?? downloads['all'] ?? '');
    final fileSize = ((json['fileSize'] as int?) ?? 0) > 0
        ? (json['fileSize'] as int)
        : (fileSizes['arm64'] ?? fileSizes['all'] ?? 0);
    return VersionCheckResult(
      hasUpdate: json['hasUpdate'] ?? false,
      latestVersion: json['latestVersion'] ?? '',
      latestBuild: json['latestBuild'] ?? 0,
      forceUpdate: json['forceUpdate'] ?? false,
      changelog: json['changelog'] ?? '',
      downloadUrl: downloadUrl,
      fileSize: fileSize,
      minSupportedVersion: json['minSupportedVersion'] ?? '',
      downloads: downloads,
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
