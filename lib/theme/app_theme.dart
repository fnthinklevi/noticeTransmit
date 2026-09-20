import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppThemeColors colors,
    required Color switchThumbUnselected,
    required Color switchTrackUnselected,
    required Color indicatorColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.systemBlue,
        brightness: brightness,
        // v1.59：文本选择工具栏容器色取自 colorScheme.surface（Flutter
        // `_TextSelectionToolbarContainer._getColor` 实测），改 surface 才能让
        // 工具栏底色 = 应用卡片色（否则深色模式偏黑 #111318，与卡片 #1C1C1E 不一致）。
        // 影响面：M3 的 Card/Dialog/BottomSheet/Menu 默认取 surfaceContainer* 系列，
        // 项目 83 处容器又显式设了 AppColors.cardBg —— 因此本改动实际只作用于
        // 文本选择工具栏等直接消费 surface 的少数组件。
        surface: colors.cardBg,
        // 其余 M3 浮层（菜单/日期选择器等）同样统一为卡片色
        surfaceContainerHighest: colors.cardBg,
      ),
      // v1.59：文本选择高亮 / 光标 / 手柄统一为应用蓝（各机型渲染一致，
      // Flutter 自绘、不走厂商系统样式）。工具栏容器为 44px 胶囊（圆角 22），
      // 底色见上方 colorScheme.surface。
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colors.systemBlue.withValues(alpha: 0.25),
        cursorColor: colors.systemBlue,
        selectionHandleColor: colors.systemBlue,
      ),
      scaffoldBackgroundColor: colors.bgColor,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bgColor,
        foregroundColor: colors.primaryLabel,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colors.primaryLabel,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minLeadingWidth: 32,
        iconColor: colors.systemBlue,
      ),
      dividerTheme: DividerThemeData(
        color: colors.separator,
        space: 1,
        thickness: 0.5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return switchThumbUnselected;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.systemGreen;
          }
          return switchTrackUnselected;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.cardBg.withValues(alpha: 0.95),
        elevation: 0,
        height: 64,
        indicatorColor: indicatorColor,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.systemBlue,
            );
          }
          return TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colors.secondaryLabel,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colors.systemBlue);
          }
          return IconThemeData(color: colors.secondaryLabel);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.systemBlue),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        isDense: true,
        hintStyle: TextStyle(color: colors.tertiaryLabel),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.cardBg,
        contentTextStyle: TextStyle(color: colors.primaryLabel, fontSize: 14),
        actionTextColor: colors.systemBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 17),
        bodyMedium: TextStyle(fontSize: 15),
        bodySmall: TextStyle(fontSize: 13),
        titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  static ThemeData lightTheme() {
    final colors = AppThemeColors.light();
    return _buildTheme(
      brightness: Brightness.light,
      colors: colors,
      switchThumbUnselected: Colors.grey.shade200,
      switchTrackUnselected: Colors.grey.shade300,
      indicatorColor: colors.systemBlue.withValues(alpha: 0.1),
    );
  }

  static ThemeData darkTheme() {
    final colors = AppThemeColors.dark();
    return _buildTheme(
      brightness: Brightness.dark,
      colors: colors,
      switchThumbUnselected: Colors.grey.shade800,
      switchTrackUnselected: Colors.grey.shade700,
      indicatorColor: colors.systemBlue.withValues(alpha: 0.2),
    );
  }
}
