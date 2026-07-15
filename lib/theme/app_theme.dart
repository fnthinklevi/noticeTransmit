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
