import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 文本选择菜单的多机型统一适配（v1.59）。
///
/// Flutter 的文本选择工具栏是**应用自绘**（不走厂商系统样式），但按钮文案来自
/// `MaterialLocalizations`——部分厂商 ROM 上报非常规 locale 时基础解析失败会
/// fallback 英文。本 helper 用**应用内文案**重建按钮（能力过滤、回调与定位
/// 锚点全部沿用框架默认：`contextMenuButtonItems` + `contextMenuAnchors`），
/// 彻底消除对本地化解析的依赖；工具栏容器色已由主题 `colorScheme.surface`
/// 统一为应用卡片色。
///
/// 签名说明（Flutter 3.22 实测）：
/// - `TextField` 与 `SelectableText` 的 `contextMenuBuilder` 类型均为
///   `EditableTextContextMenuBuilder`（SelectableText 内部委托 EditableText），
///   统一用 [editableText]。
/// - [selectableRegion]（SelectableRegionState 版）留给未来 `SelectionArea`
///   场景使用，当前项目无调用方。
class AppTextSelectionMenu {
  AppTextSelectionMenu._();

  /// TextField / SelectableText 通用的编辑态菜单（复制 / 剪切 / 粘贴 / 全选）
  static Widget editableText(BuildContext context, EditableTextState state) {
    return _build(
      context,
      state.contextMenuButtonItems,
      state.contextMenuAnchors,
    );
  }

  /// 只读选择区（SelectionArea）：当前项目暂无使用方，保留备后续接入。
  static Widget selectableRegion(
    BuildContext context,
    SelectableRegionState state,
  ) {
    return _build(
      context,
      state.contextMenuButtonItems,
      state.contextMenuAnchors,
    );
  }

  static Widget _build(
    BuildContext context,
    List<ContextMenuButtonItem> defaultItems,
    TextSelectionToolbarAnchors anchors,
  ) {
    // 文案重建为应用内词条（随应用语言），能力过滤与回调沿用框架默认
    final l10n = AppLocalizations.of(context);
    final items = defaultItems
        .map(
          (item) => item.copyWith(label: _label(item.type, item.label, l10n)),
        )
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: items,
    );
  }

  static String _label(
    ContextMenuButtonType type,
    String? fallback,
    AppLocalizations l10n,
  ) {
    switch (type) {
      case ContextMenuButtonType.copy:
        return l10n.textMenuCopy;
      case ContextMenuButtonType.cut:
        return l10n.textMenuCut;
      case ContextMenuButtonType.paste:
        return l10n.textMenuPaste;
      case ContextMenuButtonType.selectAll:
        return l10n.textMenuSelectAll;
      case ContextMenuButtonType.share:
        return l10n.textMenuShare;
      default:
        return fallback ?? '';
    }
  }
}
