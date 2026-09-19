import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/notification_rule.dart';
import '../services/platform_channel.dart';
import '../services/rule_template_service.dart';
import '../theme/app_colors.dart';

/// 规则模板库（P2）：预设模板 + 用户模板 + 文件导入导出。
///
/// 入口：规则列表页 AppBar 模板图标。「存为模板」在规则卡片的操作行（与编辑/删除并列）。
class RuleTemplateSheet extends StatefulWidget {
  /// 导入回调：追加到规则列表并持久化（由规则列表页提供保存链路）
  final void Function(List<NotificationRule> imported) onImport;

  /// 「存为模板」数据源：当前全部规则（长按菜单入口在卡片上，这里提供删除管理）
  final List<NotificationRule> currentRules;

  const RuleTemplateSheet({
    super.key,
    required this.onImport,
    required this.currentRules,
  });

  @override
  State<RuleTemplateSheet> createState() => _RuleTemplateSheetState();
}

class _RuleTemplateSheetState extends State<RuleTemplateSheet> {
  final RuleTemplateService _service = RuleTemplateService();
  List<NotificationRule> _userTemplates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final templates = await _service.getUserTemplates();
    if (!mounted) return;
    setState(() {
      _userTemplates = templates;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 560),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.separator(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.ruleTemplateTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            const SizedBox(height: 4),
            _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )
                : Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        _sectionHeader(context, l10n.ruleTemplatePreset),
                        for (final t in RuleTemplateService.presetTemplates())
                          _templateTile(context, t, deletable: false),
                        _sectionHeader(context, l10n.ruleTemplateMine),
                        if (_userTemplates.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: Text(
                              l10n.ruleTemplateMineEmpty,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.secondaryLabel(context),
                              ),
                            ),
                          )
                        else
                          for (final t in _userTemplates)
                            _templateTile(context, t, deletable: true),
                      ],
                    ),
                  ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _importFromFile,
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: Text(
                        l10n.ruleTemplateImport,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _exportToFile,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: Text(
                        l10n.ruleTemplateExport,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }

  Widget _templateTile(
    BuildContext context,
    NotificationRule template, {
    required bool deletable,
  }) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      dense: true,
      leading: Icon(
        deletable ? Icons.bookmark : Icons.auto_awesome,
        size: 22,
        color: deletable ? AppColors.blue : AppColors.systemOrange(context),
      ),
      title: Text(
        template.name,
        style: TextStyle(fontSize: 15, color: AppColors.primaryLabel(context)),
      ),
      subtitle: Text(
        template.description.isNotEmpty
            ? template.description
            : l10n.ruleNoCondition,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.secondaryLabel(context),
        ),
      ),
      trailing: deletable
          ? IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.systemRed(context),
              onPressed: () async {
                await _service.deleteUserTemplate(template.id);
                await _load();
              },
            )
          : null,
      onTap: () {
        final imported = _service.instantiate([template]);
        Navigator.pop(context);
        widget.onImport(imported);
      },
    );
  }

  void _showToast(String message, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: ok ? AppColors.green : AppColors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _importFromFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final text = await File(path).readAsString();
      List<NotificationRule> templates;
      try {
        templates = await _service.parseImportContent(text, null);
      } on TemplatePasswordRequired {
        final password = await _promptPassword(l10n);
        if (password == null) return;
        templates = await _service.parseImportContent(text, password);
      }
      if (templates.isEmpty) {
        _showToast(l10n.ruleTemplateImportEmpty);
        return;
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onImport(_service.instantiate(templates));
    } on TemplateDecryptException catch (e) {
      _showToast(e.message);
    } on FormatException {
      _showToast(l10n.ruleTemplateInvalidFile);
    } catch (_) {
      _showToast(l10n.unknownError);
    }
  }

  Future<void> _exportToFile() async {
    final l10n = AppLocalizations.of(context);
    if (_userTemplates.isEmpty) {
      _showToast(l10n.ruleTemplateMineEmpty);
      return;
    }
    try {
      final password = await _promptPassword(l10n, optional: true);
      final content = await _service.buildExportContent(
        _userTemplates,
        password,
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final result = await AppChannels.notification.invokeMethod('saveFile', {
        'fileName': 'rule_templates_$ts.json',
        'content': content,
      });
      final ok = result is Map && result['success'] == true;
      if (!mounted) return;
      _showToast(ok ? l10n.ruleTemplateExportOk : l10n.unknownError, ok: ok);
    } on FormatException {
      _showToast(l10n.ruleTemplateInvalidFile);
    } catch (_) {
      _showToast(l10n.unknownError);
    }
  }

  /// 口令弹窗。导出场景 [optional] = true（留空 = 明文导出）；导入场景必填。
  Future<String?> _promptPassword(
    AppLocalizations l10n, {
    bool optional = false,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          optional
              ? l10n.ruleTemplateExportPasswordTitle
              : l10n.ruleTemplateImportPasswordTitle,
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
          decoration: InputDecoration(
            hintText: optional
                ? l10n.ruleTemplateExportPasswordHint
                : l10n.ruleTemplateImportPasswordHint,
            hintStyle: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(ctx),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
            child: Text(
              l10n.confirm,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
