import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFFAB47BC);
  static const primaryLight = Color(0xFFCE93D8);
  static const primaryLighter = Color(0xFFB39DDB);
  static const primaryBg = Color(0xFFF5F0FA);
  static const aiBubbleBorder = Color(0xFFE1BEE7);
  static const accentGreen = Color(0xFFE8F5E9);
  static const userBubble = Color(0xFFCE93D8);

  AppColors._();
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.primary,
        scaffoldBackgroundColor: AppColors.primaryBg,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      );

  AppTheme._();
}
