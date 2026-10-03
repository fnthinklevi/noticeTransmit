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
        _showInfo(_l10n.updateCheckFailedWithError(_failureText(e)));
      }
    } finally {
      await minWait;
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  /// 「有更新」那一枚弹层。
  ///
  /// T90 片21：外壳收进 `IosDialogActions` 的两个入口（`showUpdatePrompt` 三颗档位 /
  /// `showForceUpdatePrompt` 只有一颗），**弹层里的内容仍留在这里** ——
  /// 徽标、三行版本号和那块可滚的更新日志是这一屏的私有形状，硬塞进共享件只会长出一个
  /// 带一堆可选口的假通用组件（与 `IosFormDialog`「字段由调用方给」同一条规矩）。
  ///
  /// ⚠ 换件时三件必须原样保留的东西：
  /// ① `barrierDismissible: !result.forceUpdate` —— 强推那版点外面**不许**关（唯一出路是
  ///    立刻更新），非强推点外面 = 先不更新；
  /// ② 「忽略」要**写进忽略名单**（旧代码里那颗 `TextButton` 就是这么写的），它不是关框；
  /// ③ 点外面关掉回 `null` = 什么都不做，与旧 `showDialog` 行为一致。
  Future<void> _showUpdateDialog(VersionCheckResult result) async {
    final l10n = _l10n;
    final choice = result.forceUpdate
        ? await IosDialogActions.showForceUpdatePrompt(
            context,
            title: l10n.updateForceRequired,
            updateText: l10n.updateNow,
            titleBadge: _forceUpdateBadge(),
            body: _updateDialogBody(result),
          )
        : await IosDialogActions.showUpdatePrompt(
            context,
            title: l10n.updateFoundNew,
            ignoreText: l10n.updateIgnore,
            laterText: l10n.updateLater,
            updateText: l10n.updateButton,
            body: _updateDialogBody(result),
          );
    if (!mounted) return;
    if (choice == UpdateChoice.ignore) {
      // ⚠ 旧形状那颗「忽略」是 `TextButton` 里的 `setIgnoredVersion(...)`（**没 await**），
      //   换件后这里补上 await：它写的是 SharedPreferences，不等它写完就返回，
      //   下一次启动的检查可能在写盘之前就读到旧值 ⇒ 「忽略」等于没按。
      await _updateService.setIgnoredVersion(result.latestVersion);
    } else if (choice == UpdateChoice.update) {
      // ⚠ 这一颗**已经**把弹层 pop 掉了（`Navigator.pop(ctx, UpdateChoice.update)`），
      //   所以 `_startDownloadUpdate` 里不能再 pop —— 那会把刚弹出来的进度框关掉。
      await _startDownloadUpdate(result);
    }
    // `later` 与点外面关掉（null）都什么都不做。
  }

  /// 标题上方那枚红标（只在强推时给）。
  Widget? _forceUpdateBadge() {
    if (_l10n.updateForceBadge.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      );
    }
    return null;
  }

  /// 三行版本号 + 可滚的更新日志。
  Widget _updateDialogBody(VersionCheckResult result) {
    final l10n = _l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(l10n.updateLatestVersionLabel, 'v${result.latestVersion}'),
        _infoRow(
          l10n.updateCurrentVersionLabel,
          'v${_updateService.currentVersion}',
        ),
        _infoRow(
          l10n.updateFileSizeLabel,
          result.fileSizeStr ?? l10n.updateSizeUnknown,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.updateChangelogTitle,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.inputBg(context),
            borderRadius: BorderRadius.circular(8),
          ),
          // ⚠ 这里**不套**滚动：`CupertinoAlertDialog` 已把 content 放在有界且可滚的位置里
          // （与 `IosFormDialog` / `showIosOptionPicker` 同一课，反证 PK5/FM1 都验过）。
          child: Text(
            result.changelog.replaceAll('\\n', '\n'),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.primaryLabel(context),
            ),
          ),
        ),
      ],
    );
  }

  /// 「标签 + 值」一行（版本号 / 文件大小三处共用）。
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownloadUpdate(VersionCheckResult result) async {
    if (_isDownloading) return;

    // ⚠ T90 片21：**这里不再 `Navigator.pop`**。旧形状里那颗「立即更新 / 更新」是 `AlertDialog`
    //   actions 里的一颗 TextButton，按下时弹层还开着，所以 `_startDownloadUpdate` 自己 pop 一次
    //   去关它。换到 `showUpdatePrompt` 之后，按下那颗**已经先把弹层 pop 了**
    //   （`Navigator.pop(ctx, UpdateChoice.update)`），再 pop 一次就是**把刚弹出来的进度框关掉** ——
    //   用户会看到进度条一闪就没了，而下载还在后台跑。
    final progressNotifier = ValueNotifier<double>(0);
    setState(() => _isDownloading = true);

    // T90 片17：这枚下载进度框换进共享外壳 `IosProgressDialog`。
    // ⚠ 三件必须原样保留的东西：**强推不可取消**（actions 为空、且 barrierDismissible 跟着
    //   forceUpdate 走）、**非强推可取消**（那颗红色「取消」要连 setState 一起撤 _isDownloading）、
    //   以及 `progress > 0 ? progress : null` —— 0 表示"服务器还没给总大小"，那时要的是不确定态。
    showDialog(
      context: context,
      barrierDismissible: !result.forceUpdate,
      builder: (context) => ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) {
          return IosProgressDialog(
            title: _l10n.updateDownloading,
            progress: progress > 0 ? progress : null,
            percentText: '${(progress * 100).toStringAsFixed(0)}%',
            cancelText: result.forceUpdate ? null : _l10n.cancel,
            onCancel: result.forceUpdate
                ? null
                : () {
                    Navigator.pop(context);
                    setState(() => _isDownloading = false);
                  },
          );
        },
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
          final block = _updateService.lastInstallBlock;
          final reason = block == null ? null : _installBlockText(block);
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
            SnackBar(
              content: Text(_l10n.updateDownloadFailed(_failureText(e))),
            ),
          );
        });
  }

  /// 更新流程失败的那一句（**码在 service，词在这里**）。
  ///
  /// ⚠ 五档穷尽、没有 default：加一档而这里没接就编译红。此前页面直接把
  /// `e.toString()` 塞进 l10n 模板，而那个 exception 的文本是服务层拼的中文句子
  /// ⇒ 英文界面下「英文模板 + 中文句子」混排。
  String _failureText(Object e) {
    if (e is! UpdateFailureException) return e.toString();
    final detail = e.detail;
    return switch (e.code) {
      UpdateFailure.allUrlsFailed => _l10n.updateFailAllUrls,
      UpdateFailure.downloaderStartFailed => _l10n.updateFailDownloaderStart,
      UpdateFailure.progressQueryFailed => _l10n.updateFailProgressQuery,
      UpdateFailure.downloaderFailed => _l10n.updateFailDownloader(
        detail == null || detail.isEmpty ? '' : '（$detail）',
      ),
      UpdateFailure.httpStatus => _l10n.updateFailHttpStatus(e.status ?? 0),
    };
  }

  /// 安装被完整性校验阻止时，给用户的那一句。
  ///
  /// ⚠ 原生自己按 App 语言出文案，它给了就优先用；没给才走 ARB。
  /// **三档穷尽、没有 default**：加第四档而这里没接，编译就红 ——
  /// 合成一句含糊的「安装失败」正是这片要消灭的形状：签名不匹配（可能被换包）、
  /// 校验和不匹配（下载被截断）、校验通道不可用（我们没法判断），用户下一步该做的事各不相同。
  String _installBlockText(UpdateInstallBlock block) {
    final detail = block.nativeDetail;
    if (detail != null && detail.isNotEmpty) return detail;
    return switch (block.code) {
      UpdateInstallBlockReason.integrityFailed =>
        _l10n.updateBlockIntegrityFailed,
      UpdateInstallBlockReason.checksumMismatch =>
        _l10n.updateBlockChecksumMismatch,
      UpdateInstallBlockReason.unverifiable => _l10n.updateBlockUnverifiable,
    };
  }
}
