import 'package:flutter/material.dart';

/// Palette tirée des logos CVAV et Externat Sainte Famille.
class AppColors {
  static const primary = Color(0xFF1A9AD6); // bleu CVAV
  static const primaryDark = Color(0xFF0B5E8E);
  static const navy = Color(0xFF0B3A57);
  static const gold = Color(0xFFF2B544); // auréole
  static const background = Color(0xFFF3F8FC);
  static const surface = Colors.white;
  static const success = Color(0xFF1E9E6A);
  static const danger = Color(0xFFD64545);
  static const warning = Color(0xFFE59A12);
  static const muted = Color(0xFF6B7F8E);

  static const headerGradient = LinearGradient(
    colors: [Color(0xFF1A9AD6), Color(0xFF0B5E8E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.gold,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.apply(bodyColor: AppColors.navy, displayColor: AppColors.navy),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navy),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE3EDF4)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD5E3EC))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD5E3EC))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? AppColors.primaryDark : AppColors.muted,
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primaryDark,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.primary,
      labelStyle: TextStyle(fontWeight: FontWeight.w700),
      tabAlignment: TabAlignment.start,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
