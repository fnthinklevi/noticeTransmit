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

      setState(() => _busy = true);
      final report = await _backup.restorePayload(
        validPayload,
        overwriteExisting: strategy == 'overwrite',
      );
      if (!mounted) return;
      final skippedNote = report.skippedCategories.isEmpty
          ? ''
          : ' (${l10n.restoreFillGaps}: ${report.skippedCategories.length})';
      _showInfo(
        '${l10n.restoreDoneReTest}$skippedNote'
        '${skippedInvalid > 0 ? ' [https: -$skippedInvalid]' : ''}',
        AppColors.green,
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

  Future<String?> _promptConflictStrategy() {
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        title: Text(
          l10n.restoreConfirmTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: Text(
          l10n.restoreConflictMsg,
          style: TextStyle(fontSize: 14, color: AppColors.primaryLabel(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: AppColors.secondaryLabel(ctx)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'gaps'),
            child: Text(
              l10n.restoreFillGaps,
              style: TextStyle(color: AppColors.secondaryLabel(ctx)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'overwrite'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(
              l10n.restoreOverwriteAll,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<String?> _promptPassword(String title, String hint) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          style: TextStyle(color: AppColors.primaryLabel(ctx)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(ctx),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: IosDialogActions.confirm(
          ctx,
          cancelText: l10n.cancel,
          confirmText: l10n.confirm,
          onConfirm: () => Navigator.pop(ctx, controller.text),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
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
