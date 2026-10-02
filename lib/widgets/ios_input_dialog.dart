import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/app_text_selection_menu.dart';

/// 「打一行字 + 取消 / 保存」那一类弹层的**全站唯一装配点**（T90 片7）。
///
/// 为什么收成一件组件：与 `IosDialogActions`（确认框）、`showIosOptionPicker`（选档）同一条理由 ——
/// 各页自己搭，输入框圆角、占位色、按钮文案、以及**"校验没过就不许关框"这条行为**就会各页一份。
/// 最后那一条是这里唯一的真风险：设备名那一格今天就是"空值时点保存什么都不发生"，
/// 而自定义优先级那一格是"就地提示 0-500 后把框留着"。这两支都只有在这里写一次才不会被抄丢。
///
/// ⚠ 与 `showIosOptionPicker` 同族的一条坑：`showCupertinoDialog` 的 `barrierDismissible`
/// **默认 false**，这里显式打开 —— 输入弹层没有"清空并退出"的入口，点外面是唯一的不改口的出路。
Future<String?> showIosInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String initialText = '',
  String? hintText,
  bool obscureText = false,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  String? confirmText,
  String? cancelText,
  bool requiredField = false,
  String? Function(String value)? validate,
  // 下面四个参数每个都由本仓一处真实调用点要求，不是给"以后"留的口子：
  // `fieldKeyValue` —— 幻念推送那格的用例按 `ValueKey('fnthink-host-input')` 点它；
  // `autocorrect: false` —— 主机名不该被自动纠错改成别的词；
  // `maxLines` —— 拉黑关键词那条是三行输入；
  // `supportingText` —— 同一条的提示写在输入框**下面**（`message` 写在上面）。
  String? fieldKeyValue,
  bool autocorrect = true,
  int maxLines = 1,
  String? supportingText,
  // ⚠ 默认**不 trim**，与各枚旧对话框逐字一致：口令那两格（备份口令、模板口令）里
  //   首尾空格是口令的一部分 —— 悄悄 trim 会做出"口令明明对，却解不开文件"这种最难查的 bug。
  //   需要去空格的调用点（设备名、自定义优先级）显式写 `trim: true`，别拿默认值赌。
  bool trim = false,
}) {
  final l10n = AppLocalizations.of(context);
  return showCupertinoDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _IosInputDialog(
      title: title,
      message: message,
      initialText: initialText,
      hintText: hintText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      confirmText: confirmText ?? l10n.save,
      cancelText: cancelText ?? l10n.cancel,
      requiredField: requiredField,
      validate: validate,
      fieldKey: fieldKeyValue == null
          ? const ValueKey('ios-input-field')
          : ValueKey(fieldKeyValue),
      autocorrect: autocorrect,
      maxLines: maxLines,
      supportingText: supportingText,
      trim: trim,
    ),
  );
}

class _IosInputDialog extends StatefulWidget {
  const _IosInputDialog({
    required this.title,
    required this.message,
    required this.initialText,
    required this.hintText,
    required this.obscureText,
    required this.keyboardType,
    required this.inputFormatters,
    required this.confirmText,
    required this.cancelText,
    required this.requiredField,
    required this.validate,
    required this.fieldKey,
    required this.autocorrect,
    required this.maxLines,
    required this.supportingText,
    required this.trim,
  });

  final String title;
  final String? message;
  final String initialText;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String confirmText;
  final String cancelText;
  final bool requiredField;
  final String? Function(String value)? validate;
  final Key fieldKey;
  final bool autocorrect;
  final int maxLines;
  final String? supportingText;
  final bool trim;

  @override
  State<_IosInputDialog> createState() => _IosInputDialogState();
}

class _IosInputDialogState extends State<_IosInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text;
    final value = widget.trim ? raw.trim() : raw;
    final error = widget.validate?.call(value);
    if (error != null) {
      // 就地提示且不关框：这一支的红不是"弹层坏了"，是"用户还没改对"。
      setState(() => _error = error);
      return;
    }
    if (widget.requiredField && value.isEmpty) {
      // 与换根组件之前一致：空值时点保存什么都不发生（这一格没有专门的提示文案，
      // 编一句要动 ARB ⇒ 那是维护者的措辞决定，不在这一片顺手替它定）。
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.message!,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ],
          const SizedBox(height: 10),
          CupertinoTextField(
            key: widget.fieldKey,
            controller: _controller,
            autofocus: true,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            autocorrect: widget.autocorrect,
            maxLines: widget.maxLines,
            // 长按选择后的浮动菜单走共享那份（中文工具栏、浅色深色都对），与 Material 时代一致。
            contextMenuBuilder: AppTextSelectionMenu.editableText,
            placeholder: widget.hintText,
            placeholderStyle: TextStyle(
              color: AppColors.tertiaryLabel(context),
            ),
            style: TextStyle(
              fontSize: 16,
              color: AppColors.primaryLabel(context),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.inputBg(context),
              border: Border.all(color: AppColors.separator(context)),
              borderRadius: BorderRadius.circular(10),
            ),
            onChanged: (_) {
              // 改一个字就把旧错误擦掉：留着会让人以为"还是不行"，于是停在已改对的值上不敢保存。
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          // 提示写在框**下面**那一支（拉黑关键词：告诉你这一条会被拿去干什么）：
          // 与 `message`（框上面那段说明）不是一个位置，合并会让"哪句话在解释这一格"含糊掉。
          if (widget.supportingText != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.supportingText!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error,
              key: const ValueKey('ios-input-error'),
              style: const TextStyle(fontSize: 12, color: AppColors.red),
            ),
          ],
        ],
      ),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('ios-input-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelText),
        ),
        CupertinoDialogAction(
          key: const ValueKey('ios-input-confirm'),
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
