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
