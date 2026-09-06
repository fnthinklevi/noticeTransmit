part of 'webhook_settings_page.dart';

// R3 拆分：通道卡片构建（_buildChannelItem）巨型方法迁出（extension 共享 State 私有成员）
// ignore_for_file: invalid_use_of_protected_member

extension _WebhookFormMethods on _WebhookSettingsPageState {
  Widget _buildChannelItem(int index, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.channelN(index + 1),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Switch(
                value: _webhookEnabled[index],
                onChanged: (_) => _toggleWebhookEnabled(index),
              ),
              if (_webhookControllers.length > 1)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColors.red,
                  ),
                  onPressed: () => _removeWebhookField(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameControllers[index],
            decoration: InputDecoration(
              hintText: l10n.channelNameOptional,
              hintStyle: TextStyle(
                fontSize: 13,
                color: AppColors.tertiaryLabel(context),
              ),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
            style: TextStyle(
              fontSize: 14,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _webhookControllers[index],
            decoration: InputDecoration(
              hintText: l10n.webhookUrlPlaceholder,
              hintStyle: TextStyle(color: AppColors.tertiaryLabel(context)),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              isDense: true,
              filled: true,
              fillColor: AppColors.inputBg(context),
            ),
            style: TextStyle(
              fontSize: 15,
              color: AppColors.primaryLabel(context),
            ),
            maxLines: 1,
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                l10n.channelTypeLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildChannelTypeSelector(index, context)),
            ],
          ),
          if (_supportsSigning(index)) ...[
            const SizedBox(height: 10),
            Text(
              l10n.webhookSecretLabel,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _secretControllers[index],
              obscureText: !_secretVisible[index],
              decoration: InputDecoration(
                hintText: _signingHint(context, _effectiveType(index)),
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.tertiaryLabel(context),
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.inputBg(context),
                suffixIcon: IconButton(
                  icon: Icon(
                    _secretVisible[index]
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.tertiaryLabel(context),
                  ),
                  onPressed: () => _toggleSecretVisible(index),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.primaryLabel(context),
              ),
              maxLines: 1,
            ),
          ],
          const SizedBox(height: 10),
          // 消息格式选择器：default / text / markdown / json / xml
          Row(
            children: [
              Text(
                l10n.webhookFormatLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: WebhookMessageFormat.values.map((fmt) {
                      final selected = _messageFormats[index] == fmt;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _messageFormats[index] = fmt;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.blue.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selected
                                    ? AppColors.blue
                                    : AppColors.separator(context),
                              ),
                            ),
                            child: Text(
                              _messageFormatLabel(context, fmt),
                              style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? AppColors.blue
                                    : AppColors.secondaryLabel(context),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          // 飞书 markdown 降级提示
          if (_messageFormats[index] == WebhookMessageFormat.markdown &&
              (_webhookControllers[index].text.toLowerCase().contains(
                    'feishu',
                  ) ||
                  _webhookControllers[index].text.toLowerCase().contains(
                    'larksuite',
                  ))) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.feishuMarkdownDowngradeHint,
                      style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 模板编辑器：仅当 format != default 时显示
          if (_messageFormats[index] != WebhookMessageFormat.defaultFormat) ...[
            const SizedBox(height: 10),
            Text(
              l10n.webhookTemplateLabel,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.webhookTemplateHint} %appName% %title% %content% %subText% %time% %deviceName% %packageName% %notifyType% %simInfo% %sender% %phoneNumber% %durationStr% %callState% %timestamp%',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.tertiaryLabel(context),
              ),
            ),
            const SizedBox(height: 6),
            // 变量插入按钮
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children:
                  [
                    '%appName%',
                    '%title%',
                    '%content%',
                    '%time%',
                    '%deviceName%',
                    '%notifyType%',
                  ].map((v) {
                    return ActionChip(
                      label: Text(
                        v,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.blue,
                        ),
                      ),
                      backgroundColor: AppColors.blue.withValues(alpha: 0.08),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final controller = _templateControllers[index];
                        final sel = controller.selection;
                        final text = controller.text;
                        final newText = sel.start >= 0
                            ? text.replaceRange(
                                sel.start,
                                sel.end >= 0 ? sel.end : sel.start,
                                v,
                              )
                            : text + v;
                        controller.text = newText;
                        controller.selection = TextSelection.collapsed(
                          offset:
                              (sel.start >= 0 ? sel.start : text.length) +
                              v.length,
                        );
                        setState(() {});
                      },
                    );
                  }).toList(),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _templateControllers[index],
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: _messageFormats[index] == WebhookMessageFormat.json
                    ? '{"title":"%title%","content":"%content%"}'
                    : _messageFormats[index] == WebhookMessageFormat.xml
                    ? '<notification><title>%title%</title></notification>'
                    : '## %title%\n%content%',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.tertiaryLabel(context),
                  fontFamily: 'monospace',
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.inputBg(context),
              ),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildWebhookTypeHint(
                  _webhookControllers[index].text,
                  context,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: TextButton.icon(
                  onPressed: (_isTesting && _testIndex == index)
                      ? null
                      : () => _testWebhook(index),
                  icon: (_isTesting && _testIndex == index)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(
                    (_isTesting && _testIndex == index)
                        ? l10n.testing
                        : l10n.test,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_testResult != null && _testIndex == index) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_testSuccess ?? false)
                    ? AppColors.green.withValues(alpha: 0.1)
                    : AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testSuccess == true ? Icons.check_circle : Icons.error,
                    color: _testSuccess == true
                        ? AppColors.green
                        : AppColors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _testSuccess == true
                                ? AppColors.green
                                : AppColors.red,
                          ),
                        ),
                        if (_testSigned == true) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_user_outlined,
                                  size: 11,
                                  color: AppColors.blue,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  l10n.webhookSigned,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.blue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
