part of 'main_page.dart';

/// 更新域：启动/手动检查更新、更新弹窗与 APK 下载安装流程。
/// R3 拆分：mixin 挂在 _MainPageState 上（同 library），行为与拆分前完全一致。
// 同 library 内有意使用 State 的 protected 成员（setState/mounted/context）
// ignore_for_file: invalid_use_of_protected_member
extension _MainPageUpdate on _MainPageState {
  /// 各方法共用的 l10n（依赖 mounted 的 context，由调用方保证时机）
  AppLocalizations get _l10n => AppLocalizations.of(context);

  Future<void> _checkUpdateOnStartup() async {
    final result = await _updateService.checkUpdate(force: false);
    if (!mounted) return;
    if (result != null && result.hasUpdate) {
      final ignored = await _updateService.getIgnoredVersion();
      if (ignored != result.latestVersion) {
        _showUpdateDialog(result);
      }
    }
  }

  Future<void> _performUpdateCheck({bool isManual = false}) async {
    if (!mounted) return;

    final result = await _updateService.checkUpdate(force: isManual);

    if (!mounted) return;

    if (result != null) {
      if (result.hasUpdate) {
        if (!isManual && !result.forceUpdate) {
          final ignored = await _updateService.getIgnoredVersion();
          if (ignored == result.latestVersion) {
            return;
          }
        }
        _showUpdateDialog(result);
      } else if (isManual) {
        _showInfo(_l10n.updateAlreadyLatest);
      }
    } else if (isManual) {
      final error = _updateService.lastError;
      final errorMsg = error != null && error.isNotEmpty
          ? _l10n.updateCheckFailedWithError(error)
          : _l10n.updateCheckFailed;
      _showInfo(errorMsg);
    }
  }

  Future<void> _manualCheckUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final minWait = Future.delayed(const Duration(milliseconds: 500));
    try {
      await _performUpdateCheck(isManual: true);
    } catch (e) {
      if (mounted) {
        _showInfo(_l10n.updateCheckFailedWithError(e.toString()));
      }
    } finally {
      await minWait;
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showUpdateDialog(VersionCheckResult result) {
    showDialog(
      context: context,
      barrierDismissible: !result.forceUpdate,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Column(
          children: [
            if (result.forceUpdate) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _l10n.updateForceBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              result.forceUpdate
                  ? _l10n.updateForceRequired
                  : _l10n.updateFoundNew,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _l10n.updateLatestVersionLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                Text(
                  'v${result.latestVersion}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _l10n.updateCurrentVersionLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                Text(
                  'v${_updateService.currentVersion}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _l10n.updateFileSizeLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                Text(
                  result.fileSizeStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _l10n.updateChangelogTitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputBg(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    result.changelog.replaceAll('\\n', '\n'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: result.forceUpdate
            ? [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _startDownloadUpdate(result),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _l10n.updateNow,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]
            : [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _updateService.setIgnoredVersion(
                            result.latestVersion,
                          );
                        },
                        child: Text(
                          _l10n.updateIgnore,
                          style: TextStyle(
                            color: AppColors.secondaryLabel(context),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          _l10n.updateLater,
                          style: const TextStyle(color: AppColors.blue),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _startDownloadUpdate(result),
                        child: Text(
                          _l10n.updateButton,
                          style: const TextStyle(
                            color: AppColors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _startDownloadUpdate(VersionCheckResult result) async {
    if (_isDownloading) return;

    // 系统下载器（DownloadManager）下载到公共 Download 目录，无需存储权限
    Navigator.pop(context);
    final progressNotifier = ValueNotifier<double>(0);
    setState(() => _isDownloading = true);

    showDialog(
      context: context,
      barrierDismissible: !result.forceUpdate,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          _l10n.updateDownloading,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    backgroundColor: AppColors.separator(context),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ],
            );
          },
        ),
        actions: result.forceUpdate
            ? []
            : [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _isDownloading = false);
                  },
                  child: Text(
                    _l10n.cancel,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
              ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    _updateService
        .downloadApk(
          result.downloadUrl,
          totalSize: result.fileSize,
          version: result.latestVersion,
          onProgress: (progress) {
            progressNotifier.value = progress;
            if (mounted) setState(() {});
          },
        )
        .then((filePath) async {
          setState(() => _isDownloading = false);
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          if (filePath == null) return;
          final installed = await _updateService.installApk(
            filePath,
            sha256ByAbi: result.sha256,
          );
          if (!mounted || installed) return;
          // 完整性校验（签名不一致 / 版本降级）失败时必须告知用户，
          // 而不是让他只看到一句含糊的"安装失败"
          final reason = _updateService.lastInstallBlockReason;
          if (reason != null && reason.isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(reason)));
          }
        })
        .catchError((e) {
          setState(() => _isDownloading = false);
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_l10n.updateDownloadFailed(e.toString()))),
          );
        });
  }
}
