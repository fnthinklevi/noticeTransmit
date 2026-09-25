import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/channel_descriptor_service.dart';
import '../theme/app_colors.dart';
import 'app_text_selection_menu.dart';
import 'channel_visuals.dart';

/// 按描述符 schema 渲染通道配置字段（第 5 步：表单字段只有一处定义 —— 原生描述符）。
///
/// 三件防事故的设计：
/// 1. [ensureControllers] 由**字段清单**创建控制器，不是由人抄一遍 key 列表。
///    此前 `_bindControllers` 手抄 6 个 key，漏一个就表现为"输入框空白 +
///    保存把该字段写空"（本仓库真出过凭据被清空的同类事故）。
/// 2. [collect] 从**已有 config 出发合并**，不是重建。描述符没拉到（原生未就绪）时
///    也只是"没有额外字段可编辑"，不会把已保存的 corpid/app_id 抹掉。
/// 3. [missingRequired] 用 schema 的 required 做校验：以前应用通道的必填项
///    在 Dart 侧完全不校验，靠原生 `require()` 抛错，用户只看到一句"保存失败"。
///
/// [keyPrefix] 用于同一页面上多条通道共用一个控制器 Map（应用通道设置页就是这种形态），
/// 前缀只是存储键拼法，字段清单仍来自描述符。
class ChannelFormRenderer extends StatelessWidget {
  const ChannelFormRenderer({
    required this.descriptor,
    required this.controllers,
    this.keyPrefix = '',
    super.key,
  });

  final ChannelDescriptor descriptor;

  /// key = [keyPrefix] + FieldSpec.key
  final Map<String, TextEditingController> controllers;
  final String keyPrefix;

  String _controllerKey(String fieldKey) => '$keyPrefix$fieldKey';

  /// 为 schema 里的每个字段准备好控制器（幂等，不覆盖已有文本）。
  static Map<String, TextEditingController> ensureControllers(
    ChannelDescriptor descriptor,
    Map<String, TextEditingController> into, {
    required Map<String, dynamic> existingConfig,
    String keyPrefix = '',
  }) {
    for (final f in descriptor.fields) {
      into['$keyPrefix${f.key}'] ??= TextEditingController(
        text: existingConfig[f.key]?.toString() ?? '',
      );
    }
    return into;
  }

  /// 必填但未填的字段 key（空 = 校验通过）。
  /// 有 defaultValue 的字段不算必填（留空即落默认值，不是错误）。
  static List<String> missingRequired(
    ChannelDescriptor descriptor,
    Map<String, TextEditingController> controllers, {
    String keyPrefix = '',
  }) {
    return descriptor.fields
        .where(
          (f) =>
              f.required &&
              (controllers['$keyPrefix${f.key}']?.text.trim().isEmpty ??
                  true) &&
              (f.defaultValue ?? '').isEmpty,
        )
        .map((f) => f.key)
        .toList(growable: false);
  }

  /// 收集成落库 config：**保留未知键**，只覆盖 schema 声明过的字段。
  static Map<String, dynamic> collect(
    ChannelDescriptor descriptor,
    Map<String, TextEditingController> controllers,
    Map<String, dynamic> existing, {
    String keyPrefix = '',
  }) {
    final config = Map<String, dynamic>.of(existing);
    for (final f in descriptor.fields) {
      final text = controllers['$keyPrefix${f.key}']?.text.trim() ?? '';
      if (text.isEmpty) {
        final fallback = f.defaultValue;
        if (fallback == null) {
          config[f.key] = '';
        } else if (f.isNumber) {
          config[f.key] = int.tryParse(fallback) ?? fallback;
        } else {
          config[f.key] = fallback;
        }
        continue;
      }
      config[f.key] = f.isNumber ? (int.tryParse(text) ?? text) : text;
    }
    return config;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (descriptor.fields.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in descriptor.fields)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              contextMenuBuilder: AppTextSelectionMenu.editableText,
              controller: controllers[_controllerKey(f.key)],
              keyboardType: f.isNumber ? TextInputType.number : null,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
              ),
              decoration: _fieldDecoration(
                context,
                channelLabelFor(l10n, f.labelKey),
              ),
            ),
          ),
      ],
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context,
    String label,
  ) => InputDecoration(
    // 与设置页其余输入框同一形态（占位文案，不是浮动 label）
    hintText: label,
    hintStyle: TextStyle(fontSize: 12, color: AppColors.tertiaryLabel(context)),
    isDense: true,
    filled: true,
    fillColor: AppColors.inputBg(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.separator(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.separator(context)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.blue),
    ),
  );
}

/// 描述符引用的**表单文本**（字段标签 / 输入提示 / 预置档位名与正文）→ 译文。
///
/// 为什么要有这张表：第 5 步起表单只发 **ARB 资源名**，译文必须有个地方按名字取。
/// 通道名的资源名走 `channelLabelFor`（那是通道身份表的一部分，含 appChannel*Label）；
/// 这里只登记**表单专属**的词条 —— 邮件族的 9 个字段标签、7 条提示、9 个档位名、
/// 10 条预置正文（T08-C）。
///
/// ⚠ 漏登记的表现是"输入框显示资源名原文"（不是崩溃、不是报错），所以
/// `channel_descriptor_export_contract_test` 会拿导出快照逐键核对：快照里出现的每个
/// labelKey/hintKey/preset key 都必须在这里或 `channelLabelFor` 解析得出来，
/// 且两份 ARB 都有该词条。**别凭印象增删，改表就重跑那条守卫。**
final Map<String, String Function(AppLocalizations)> _channelFormText = {
  // 字段标签
  'smtpHost': (l) => l.smtpHost,
  'smtpPort': (l) => l.smtpPort,
  'useSSL': (l) => l.useSSL,
  'smtpAccount': (l) => l.smtpAccount,
  'smtpPassword': (l) => l.smtpPassword,
  'fromEmail': (l) => l.fromEmail,
  'toEmail': (l) => l.toEmail,
  'subjectTemplate': (l) => l.subjectTemplate,
  'bodyTemplate': (l) => l.bodyTemplate,
  // 输入提示
  'emailHintHostExample': (l) => l.emailHintHostExample,
  'emailHintAddressExample': (l) => l.emailHintAddressExample,
  'emailHintPort': (l) => l.emailHintPort,
  'emailHintPassword': (l) => l.emailHintPassword,
  'emailHintRecipients': (l) => l.emailHintRecipients,
  'emailHintSubject': (l) => l.emailHintSubject,
  'emailHintBody': (l) => l.emailHintBody,
  // 预置档位名
  'presetDefault': (l) => l.presetDefault,
  'presetSimple': (l) => l.presetSimple,
  'presetDetailed': (l) => l.presetDetailed,
  'presetTime': (l) => l.presetTime,
  'presetCode': (l) => l.presetCode,
  'presetDevice': (l) => l.presetDevice,
  'presetStandard': (l) => l.presetStandard,
  'presetComplete': (l) => l.presetComplete,
  'presetMinimal': (l) => l.presetMinimal,
  // 预置档位正文（语言跟着界面走 —— 这正是 T08-C 要修掉的那条缺陷）
  'emailPresetSubjectDefault': (l) => l.emailPresetSubjectDefault,
  'emailPresetSubjectSimple': (l) => l.emailPresetSubjectSimple,
  'emailPresetSubjectDetailed': (l) => l.emailPresetSubjectDetailed,
  'emailPresetSubjectTime': (l) => l.emailPresetSubjectTime,
  'emailPresetSubjectCode': (l) => l.emailPresetSubjectCode,
  'emailPresetSubjectDevice': (l) => l.emailPresetSubjectDevice,
  'emailPresetBodyStandard': (l) => l.emailPresetBodyStandard,
  'emailPresetBodyComplete': (l) => l.emailPresetBodyComplete,
  'emailPresetBodyCode': (l) => l.emailPresetBodyCode,
  'emailPresetBodyMinimal': (l) => l.emailPresetBodyMinimal,
};

/// 按 ARB 资源名取表单文本；两处登记表都查不到才退回原文（并让守卫红）。
String channelFormText(AppLocalizations l10n, String key) =>
    _channelFormText[key]?.call(l10n) ?? channelLabelFor(l10n, key);

/// 预置档位的正文；`valueKey == null` 是显式语义 = **清空该字段**（交回运行时默认）。
String channelPresetText(AppLocalizations l10n, ChannelFieldPreset preset) =>
    preset.valueKey == null ? '' : channelFormText(l10n, preset.valueKey!);

/// 「新增通道」类型选择弹层（iOS 风格底部弹层）。
///
/// 第 5 步统一入口：原来三种新增形态各写一套（行内追加空行 / 先选类型 / 全屏编辑器），
/// 应用通道页的弹层还把类型名与图标**硬编码**成两个 ListTile —— 新增一个应用通道
/// 只改原生表的话，界面上根本选不到它。现在列表来自描述符。
Future<String?> showChannelPickerSheet(
  BuildContext context, {
  required List<ChannelDescriptor> descriptors,
  String? title,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Material(
      // ⚠ 用 Material 而不是「带背景色的 Container」：后者会让 ListTile 的 ink
      // 画在背景之下，触发 "ink splashes may be invisible" 调试断言（引导弹层同坑）。
      color: AppColors.cardBg(sheetContext),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                  color: AppColors.separator(sheetContext),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            for (final d in descriptors)
              ListTile(
                leading: Icon(
                  channelVisual(d.iconKey).icon,
                  color: channelVisual(d.iconKey).color,
                ),
                title: Text(
                  channelNameOf(l10n, d),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, d.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
