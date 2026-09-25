part of 'webhook_settings_page.dart';

// R3 拆分：通道卡片构建巨型方法迁出（extension 共享 State 私有成员）
// ignore_for_file: invalid_use_of_protected_member

extension _WebhookFormMethods on _WebhookSettingsPageState {
  /// 本条通道的编辑卡（T07-B 起是**单通道**详情页的唯一一张卡）。
  ///
  /// ⚠ 与平铺页时代最大的差别：这里没有 `index`。以前一行对应九条并行列表的同一个
  /// 下标，删一行要九处同步收缩，漏一处就"行串台"；现在字段都是本页的标量，
  /// 结构上不可能错位。
  Widget _buildChannelCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visual = _typeVisual(_effectiveSlug);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(visual.icon, size: 18, color: visual.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _channelTypeLabel(context, _effectiveSlug),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 健康徽标：形状在共用的 ChannelHealthBadge 里，三态判定在
                // channelHealthState 里 —— 都只有一个来源（T04）。
                ChannelHealthBadge(health: _healthInfo),
              ],
            ),
            const SizedBox(height: 12),
            _buildFieldLabel(context, l10n.channelNameOptional),
            TextField(
              contextMenuBuilder: AppTextSelectionMenu.editableText,
              controller: _nameController,
              decoration: _inputDecoration(
                context,
                hint: l10n.channelNameOptional,
              ),
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primaryLabel(context),
              ),
              onChanged: (_) {
                // 标题跟着名字走：不重绘就还是"新增 Webhook 通道"
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            _buildFieldLabel(context, l10n.webhookUrlPlaceholder),
            TextField(
              contextMenuBuilder: AppTextSelectionMenu.editableText,
              controller: _urlController,
              decoration: _inputDecoration(
                context,
                hint: l10n.webhookUrlPlaceholder,
                dense: false,
              ),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.primaryLabel(context),
              ),
              maxLines: 1,
              onChanged: (_) {
                // 「自动识别」的类型、能力位（要不要密钥框、能不能选格式）都随 URL 变
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
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
                Expanded(child: _buildChannelTypeSelector(context)),
              ],
            ),
            if (_supportsSigning) ...[
              const SizedBox(height: 12),
              _buildFieldLabel(context, l10n.webhookSecretLabel),
              TextField(
                contextMenuBuilder: AppTextSelectionMenu.editableText,
                controller: _secretController,
                obscureText: !_secretVisible,
                decoration: _inputDecoration(
                  context,
                  hint: channelSigningHintFor(l10n, visual),
                  dense: false,
                  suffix: IconButton(
                    icon: Icon(
                      _secretVisible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: AppColors.tertiaryLabel(context),
                    ),
                    onPressed: _toggleSecretVisible,
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
            // 该通道的实发正文不吃自定义格式/模板（能力位 customTemplate=false）时，
            // 连整排选择器一起收掉：以前给了入口也毫无作用，用户以为设置了其实没有。
            if (_supportsCustomTemplate) ...[
              const SizedBox(height: 12),
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
                          final selected = _messageFormat == fmt;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _messageFormat = fmt;
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
              if (_messageFormat == WebhookMessageFormat.markdown &&
                  (_urlController.text.toLowerCase().contains('feishu') ||
                      _urlController.text.toLowerCase().contains(
                        'larksuite',
                      ))) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
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
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 模板编辑器：仅当 format != default 时显示
              if (_messageFormat != WebhookMessageFormat.defaultFormat) ...[
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
                          backgroundColor: AppColors.blue.withValues(
                            alpha: 0.08,
                          ),
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _insertTemplateVar(v),
                        );
                      }).toList(),
                ),
                const SizedBox(height: 6),
                TextField(
                  contextMenuBuilder: AppTextSelectionMenu.editableText,
                  controller: _templateController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: _inputDecoration(
                    context,
                    hint: _templateHintFor(_messageFormat),
                    mono: true,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryLabel(context),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            _buildWebhookTypeHint(_urlController.text, context),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              _buildTestResultBox(context),
            ],
          ],
        ),
      ),
    );
  }

  /// 把模板变量插到光标处（没有光标就追加到末尾）。
  void _insertTemplateVar(String v) {
    final sel = _templateController.selection;
    final text = _templateController.text;
    final newText = sel.start >= 0
        ? text.replaceRange(sel.start, sel.end >= 0 ? sel.end : sel.start, v)
        : text + v;
    _templateController.text = newText;
    _templateController.selection = TextSelection.collapsed(
      offset: (sel.start >= 0 ? sel.start : text.length) + v.length,
    );
    setState(() {});
  }

  String _templateHintFor(WebhookMessageFormat fmt) {
    if (fmt == WebhookMessageFormat.json) {
      return '{"title":"%title%","content":"%content%"}';
    }
    if (fmt == WebhookMessageFormat.xml) {
      return '<notification><title>%title%</title></notification>';
    }
    return '## %title%\n%content%';
  }

  Widget _buildFieldLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.secondaryLabel(context),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hint,
    bool dense = true,
    bool mono = false,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: mono ? 12 : 13,
        color: AppColors.tertiaryLabel(context),
        fontFamily: mono ? 'monospace' : null,
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
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: dense ? 10 : 12,
      ),
      isDense: true,
      filled: true,
      fillColor: AppColors.inputBg(context),
      suffixIcon: suffix,
    );
  }

  /// 测试结论框（成功绿 / 失败红，附「已签名」标）。
  /// 以前它按 `_testIndex == index` 决定画在哪张卡上 —— 单通道形态下没有这件事。
  Widget _buildTestResultBox(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ok = _testSuccess ?? false;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (ok ? AppColors.green : AppColors.red).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error,
            color: ok ? AppColors.green : AppColors.red,
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
                    color: ok ? AppColors.green : AppColors.red,
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
    );
  }

  /// 消息格式本地化名称（品牌/格式名无需翻译）
  String _messageFormatLabel(BuildContext context, WebhookMessageFormat fmt) {
    final l10n = AppLocalizations.of(context);
    switch (fmt) {
      case WebhookMessageFormat.defaultFormat:
        return l10n.msgFormatDefault;
      case WebhookMessageFormat.text:
        return l10n.msgFormatText;
      case WebhookMessageFormat.markdown:
        return 'Markdown';
      case WebhookMessageFormat.json:
        return 'JSON';
      case WebhookMessageFormat.xml:
        return 'XML';
    }
  }

  /// 渠道类型选择器：iOS 风格输入框样式 + 弹窗选择（替代 Material DropdownButton）
  Widget _buildChannelTypeSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuto = _channelType.isEmpty || _channelType == 'auto';
    final detectedSlug = WebhookChannel.detectTypeFromUrl(
      _urlController.text,
    ).value;
    final display = isAuto
        ? (detectedSlug == 'generic'
              ? l10n.channelTypeAuto
              : l10n.channelTypeAutoWith(
                  _channelTypeLabel(context, detectedSlug),
                ))
        : _channelTypeLabel(context, _channelType);
    final visual = _typeVisual(isAuto ? detectedSlug : _channelType);

    return InkWell(
      onTap: () => _showChannelTypePicker(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.inputBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.separator(context)),
        ),
        child: Row(
          children: [
            Icon(visual.icon, size: 16, color: visual.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                display,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.tertiaryLabel(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 类型下拉的候选项：**描述符列表**（原生表为准）。
  /// 描述符没拉到时退回 Dart 枚举，保证离线也能改类型。
  List<String> _typeSlugs() {
    final descriptors = _descriptors.webhook;
    if (descriptors.isNotEmpty) {
      return descriptors.map((d) => d.key).toList(growable: false);
    }
    return WebhookChannelType.values
        .map((t) => t.value)
        .toList(growable: false);
  }

  /// 渠道类型选择弹窗（与主题/语言选择同款 iOS 风格）
  void _showChannelTypePicker(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detectedSlug = WebhookChannel.detectTypeFromUrl(
      _urlController.text,
    ).value;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          l10n.selectChannelType,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                _buildTypeOption(
                  context,
                  icon: Icons.auto_awesome,
                  color: AppColors.blue,
                  label: detectedSlug == 'generic'
                      ? l10n.channelTypeAuto
                      : l10n.channelTypeAutoWith(
                          _channelTypeLabel(context, detectedSlug),
                        ),
                  selected: _channelType.isEmpty || _channelType == 'auto',
                  onTap: () {
                    setState(() => _channelType = 'auto');
                    Navigator.pop(dialogContext);
                  },
                ),
                ..._typeSlugs().map((slug) {
                  final visual = _typeVisual(slug);
                  return _buildTypeOption(
                    context,
                    icon: visual.icon,
                    color: visual.color,
                    label: _channelTypeLabel(context, slug),
                    selected: _channelType == slug,
                    onTap: () {
                      setState(() => _channelType = slug);
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildTypeOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(fontSize: 15, color: AppColors.primaryLabel(context)),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: AppColors.blue)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  /// URL 识别提示区。
  /// 尊重手动指定的通道类型（自建 ntfy/Gotify 服务器 host 不可枚举，
  /// 纯 URL 探测会把手动选择的类型误显示为「通用 Webhook」，误导用户）；
  /// 仅当处于「自动识别」模式时才按 URL host 探测。
  Widget _buildWebhookTypeHint(String urlStr, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = urlStr.trim();
    if (url.isEmpty) {
      // 未填 URL：没有类型可识别，用中性样式（不冒充某个平台的名字和颜色）
      return _typeHintChip(
        context,
        name: l10n.urlEmpty,
        desc: l10n.urlPlaceholder,
        icon: Icons.link_off,
        color: const Color(0xFF8E8E93),
      );
    }
    final visual = _typeVisual(_effectiveSlug);
    return _typeHintChip(
      context,
      name: channelHintNameFor(l10n, visual),
      desc: channelDescFor(l10n, visual),
      icon: visual.icon,
      color: visual.color,
    );
  }

  /// 「URL 识别」提示卡片：图标 + 平台名 + 一句说明。
  Widget _typeHintChip(
    BuildContext context, {
    required String name,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
