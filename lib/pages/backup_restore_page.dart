import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';

import '../l10n/app_localizations.dart';
import '../services/backup_service.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/ios_input_dialog.dart';

/// P1 配置备份与恢复页。
///
/// 备份：收集全部配置 → 口令派生密钥（PBKDF2 210k）→ AES-256-GCM 加密 →
///       经原生 saveFile 通道保存 .nbackup 文件。
/// 恢复：file_picker 选取 .nbackup → 口令解密 → 字段级校验（非法 webhook 跳过）→
///       冲突策略（覆盖全部 / 仅导入空缺项）→ 走既有保存链路（自动同步原生）。
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final BackupService _backup = BackupService();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupRestoreTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildSectionCard(
            context,
            icon: Icons.backup,
            iconColor: AppColors.blue,
            title: l10n.backupSectionTitle,
            desc: l10n.backupSectionDesc,
            buttonLabel: l10n.backupCreate,
            onTap: _busy ? null : _createBackup,
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            icon: Icons.restore,
            iconColor: AppColors.green,
            title: l10n.restoreSectionTitle,
            desc: l10n.restoreSectionDesc,
            buttonLabel: l10n.restorePick,
            onTap: _busy ? null : _restoreBackup,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required String buttonLabel,
    required VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.separator(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            desc,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: iconColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 备份 ──────────────────────────────────────────────────────────────

  Future<void> _createBackup() async {
    final l10n = AppLocalizations.of(context);
    final password = await _promptPassword(
      l10n.backupPasswordTitle,
      l10n.backupPasswordHint,
    );
    if (password == null || password.isEmpty) return;
    if (password.length < BackupService.minPasswordLength) {
      _showInfo(l10n.backupTooShort, AppColors.orange);
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await _backup.collectBackupData();
      final container = await _backup.encryptBackup(data, password);
      final now = DateTime.now();
      final fileName =
          'notice_backup_${now.year}${_two(now.month)}${_two(now.day)}.nbackup';
      final result = await AppChannels.notification.invokeMethod('saveFile', {
        'fileName': fileName,
        'content': jsonEncode(container),
      });
      final ok = result is Map && result['success'] == true;
      _showInfo(
        ok
            ? l10n.backupOk
            : '${l10n.backupFailed}${result is Map ? result['message'] ?? '' : ''}',
        ok ? AppColors.green : AppColors.red,
      );
    } on FormatException catch (e) {
      _showInfo('${l10n.backupFailed}${e.message}', AppColors.red);
    } catch (e) {
      _showInfo('${l10n.backupFailed}$e', AppColors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 恢复 ──────────────────────────────────────────────────────────────

  Future<void> _restoreBackup() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final path = picked?.files.single.path;
      if (path == null) return; // 用户取消
      final text = await File(path).readAsString();
      final dynamic container = jsonDecode(text);
      if (container is! Map<String, dynamic>) {
        _showInfo(l10n.restoreInvalidFile, AppColors.red);
        return;
      }
      // 容器结构预校验（口令之前）：错误归为无效文件
      try {
        _backup.validateContainer(container);
      } on FormatException {
        _showInfo(l10n.restoreInvalidFile, AppColors.red);
        return;
      }
      final password = await _promptPassword(
        l10n.restorePasswordTitle,
        l10n.backupPasswordHint,
      );
      if (password == null || password.isEmpty) return;
      // 口令长度在解密前就判：否则 decryptBackup 的 FormatException 会被外层
      // 统一映射成「不是有效的备份文件」，用户看到的是错误的结论。
      if (password.length < BackupService.minPasswordLength) {
        _showInfo(l10n.backupTooShort, AppColors.orange);
        return;
      }

      Map<String, dynamic> payload;
      try {
        payload = await _backup.decryptBackup(container, password);
      } on SecretBoxAuthenticationError {
        _showInfo(l10n.restoreWrongPassword, AppColors.red);
        return;
      }
      final (validPayload, skippedInvalid) = _backup.validatePayload(payload);

      // 冲突策略：无现有配置直接恢复；有则三选
      final existing = await _backup.detectExisting();
      final hasExisting = existing.values.any((v) => v);
      String? strategy = 'overwrite';
      if (hasExisting) {
        strategy = await _promptConflictStrategy();
      }
      if (strategy == null) return;
      // 冲突策略那个对话框也是 await 出来的：用户可能在弹窗期间退出本页，
      // 而下面整段 restore 全程读 context 与 _busy。
      if (!mounted) return;

      setState(() => _busy = true);
      final report = await _backup.restorePayload(
        validPayload,
        overwriteExisting: strategy == 'overwrite',
      );
      if (!mounted) return;
      final lines = <String>[
        l10n.restoreDoneReTest,
        if (report.skippedCategories.isNotEmpty)
          '(${l10n.restoreFillGaps}: ${report.skippedCategories.length})',
        if (skippedInvalid > 0) l10n.restoreSkippedInvalid(skippedInvalid),
        if (report.failedCategories.isNotEmpty) l10n.restorePartialFailed,
      ];
      // 类别名与异常原文不进 SnackBar（用户读不懂也无处反馈），只落 logcat 供排查
      report.failedCategories.forEach((category, error) {
        debugPrint('BackupRestore: 类别 $category 恢复失败: $error');
      });
      _showInfo(
        lines.join('\n'),
        report.failedCategories.isEmpty ? AppColors.green : AppColors.orange,
      );
    } on SecretBoxAuthenticationError {
      _showInfo(l10n.restoreWrongPassword, AppColors.red);
    } on FormatException {
      _showInfo(l10n.restoreInvalidFile, AppColors.red);
    } catch (e) {
      _showInfo('${l10n.restoreFailed}$e', AppColors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 恢复冲突的三选一。T90 片25：收进 `IosDialogActions.askThreeWay`。
  ///
  /// ⚠ 为什么不能接 [askConfirm] / [askEitherWay]：那两枚的「取消」都是「什么都不做」，
  /// 而这一枚的中间那档（仅导入空缺项）**也是一个真的决策** —— 它也会写盘。
  /// 拆成「二选一」会让「取消」在同一参数位上既是「什么都不做」又可能是「它」。
  ///
  /// ⚠ **两个值与旧字面量一一对应**：旧的 `Navigator.pop(ctx, 'gaps'|'overwrite')`
  /// 字面量它还在下面那段被当字符串比质（`strategy == 'overwrite'`）——
  /// 本片不改那一比较（改了就是“覆盖 / 仅导入空缺项”两条路径共用一个字面量之外的新字面量），
  /// 不过 `ConflictChoice` 把「选哪个」返回去再在调用点映射成那两个字面量。
  Future<String?> _promptConflictStrategy() async {
    final l10n = AppLocalizations.of(context);
    final choice = await IosDialogActions.askThreeWay(
      context,
      title: l10n.restoreConfirmTitle,
      message: l10n.restoreConflictMsg,
      cancelText: l10n.cancel,
      fillGapsText: l10n.restoreFillGaps,
      overwriteText: l10n.restoreOverwriteAll,
    );
    return switch (choice) {
      ConflictChoice.fillGaps => 'gaps',
      ConflictChoice.overwrite => 'overwrite',
      null => null,
    };
  }

  Future<String?> _promptPassword(String title, String hint) {
    final l10n = AppLocalizations.of(context);
    // T90 片7/8：走单字段输入弹层的唯一装配点。**不 trim**（默认就是不 trim）——
    // 口令两端的空格是口令的一部分，悄悄去掉会做出"口令对却解不开"那种最难查的 bug。
    return showIosInputDialog(
      context,
      title: title,
      hintText: hint,
      obscureText: true,
      confirmText: l10n.confirm,
    );
  }

  void _showInfo(String message, Color color) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
