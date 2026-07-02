import 'package:flutter/material.dart';

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color bgColor;
  final Color cardBg;
  final Color separator;
  final Color primaryLabel;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color inputBg;
  final Color systemBlue;
  final Color systemGreen;
  final Color systemOrange;
  final Color systemRed;
  final Color systemPurple;
  final Color systemCyan;
  final Color systemYellow;

  const AppThemeColors({
    required this.bgColor,
    required this.cardBg,
    required this.separator,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.inputBg,
    required this.systemBlue,
    required this.systemGreen,
    required this.systemOrange,
    required this.systemRed,
    required this.systemPurple,
    required this.systemCyan,
    required this.systemYellow,
  });

  factory AppThemeColors.light() {
    return const AppThemeColors(
      bgColor: Color(0xFFF2F2F7),
      cardBg: Color(0xFFFFFFFF),
      separator: Color(0xFFE5E5EA),
      primaryLabel: Color(0xFF000000),
      secondaryLabel: Color(0xFF8E8E93),
      tertiaryLabel: Color(0xFFC7C7CC),
      inputBg: Color(0xFFF2F2F7),
      systemBlue: Color(0xFF007AFF),
      systemGreen: Color(0xFF34C759),
      systemOrange: Color(0xFFFF9500),
      systemRed: Color(0xFFFF3B30),
      systemPurple: Color(0xFFAF52DE),
      systemCyan: Color(0xFF5AC8FA),
      systemYellow: Color(0xFFFFCC00),
    );
  }

  factory AppThemeColors.dark() {
    return const AppThemeColors(
      bgColor: Color(0xFF000000),
      cardBg: Color(0xFF1C1C1E),
      separator: Color(0xFF38383A),
      primaryLabel: Color(0xFFFFFFFF),
      secondaryLabel: Color(0xFF8E8E93),
      tertiaryLabel: Color(0xFF48484A),
      inputBg: Color(0xFF2C2C2E),
      systemBlue: Color(0xFF0A84FF),
      systemGreen: Color(0xFF30D158),
      systemOrange: Color(0xFFFF9F0A),
      systemRed: Color(0xFFFF453A),
      systemPurple: Color(0xFFBF5AF2),
      systemCyan: Color(0xFF64D2FF),
      systemYellow: Color(0xFFFFD60A),
    );
  }

  @override
  ThemeExtension<AppThemeColors> copyWith({
    Color? bgColor,
    Color? cardBg,
    Color? separator,
    Color? primaryLabel,
    Color? secondaryLabel,
    Color? tertiaryLabel,
    Color? inputBg,
    Color? systemBlue,
    Color? systemGreen,
    Color? systemOrange,
    Color? systemRed,
    Color? systemPurple,
    Color? systemCyan,
    Color? systemYellow,
  }) {
    return AppThemeColors(
      bgColor: bgColor ?? this.bgColor,
      cardBg: cardBg ?? this.cardBg,
      separator: separator ?? this.separator,
      primaryLabel: primaryLabel ?? this.primaryLabel,
      secondaryLabel: secondaryLabel ?? this.secondaryLabel,
      tertiaryLabel: tertiaryLabel ?? this.tertiaryLabel,
      inputBg: inputBg ?? this.inputBg,
      systemBlue: systemBlue ?? this.systemBlue,
      systemGreen: systemGreen ?? this.systemGreen,
      systemOrange: systemOrange ?? this.systemOrange,
      systemRed: systemRed ?? this.systemRed,
      systemPurple: systemPurple ?? this.systemPurple,
      systemCyan: systemCyan ?? this.systemCyan,
      systemYellow: systemYellow ?? this.systemYellow,
    );
  }

  @override
  ThemeExtension<AppThemeColors> lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      bgColor: Color.lerp(bgColor, other.bgColor, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      primaryLabel: Color.lerp(primaryLabel, other.primaryLabel, t)!,
      secondaryLabel: Color.lerp(secondaryLabel, other.secondaryLabel, t)!,
      tertiaryLabel: Color.lerp(tertiaryLabel, other.tertiaryLabel, t)!,
      inputBg: Color.lerp(inputBg, other.inputBg, t)!,
      systemBlue: Color.lerp(systemBlue, other.systemBlue, t)!,
      systemGreen: Color.lerp(systemGreen, other.systemGreen, t)!,
      systemOrange: Color.lerp(systemOrange, other.systemOrange, t)!,
      systemRed: Color.lerp(systemRed, other.systemRed, t)!,
      systemPurple: Color.lerp(systemPurple, other.systemPurple, t)!,
      systemCyan: Color.lerp(systemCyan, other.systemCyan, t)!,
      systemYellow: Color.lerp(systemYellow, other.systemYellow, t)!,
    );
  }
}

class AppColors {
  static AppThemeColors of(BuildContext context) {
    return Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light();
  }

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color bgColor(BuildContext context) => of(context).bgColor;
  static Color cardBg(BuildContext context) => of(context).cardBg;
  static Color separator(BuildContext context) => of(context).separator;
  static Color primaryLabel(BuildContext context) => of(context).primaryLabel;
  static Color secondaryLabel(BuildContext context) => of(context).secondaryLabel;
  static Color tertiaryLabel(BuildContext context) => of(context).tertiaryLabel;
  static Color inputBg(BuildContext context) => of(context).inputBg;
  static Color systemBlue(BuildContext context) => of(context).systemBlue;
  static Color systemGreen(BuildContext context) => of(context).systemGreen;
  static Color systemOrange(BuildContext context) => of(context).systemOrange;
  static Color systemRed(BuildContext context) => of(context).systemRed;
  static Color systemPurple(BuildContext context) => of(context).systemPurple;
  static Color systemCyan(BuildContext context) => of(context).systemCyan;
  static Color systemYellow(BuildContext context) => of(context).systemYellow;
}
