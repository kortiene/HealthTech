import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Système de design HealthTech — palette, typographie et composants
/// partagés. Source de vérité : Design Brief HealthTech v1.0 — Juillet 2026.
class AppColors {
  AppColors._();

  static const primary900 = Color(0xFF003D39);
  static const primary700 = Color(0xFF006C67);
  static const primary500 = Color(0xFF00A89E);
  static const primary100 = Color(0xFFE0F5F4);
  static const primary50  = Color(0xFFF0FAFA);

  static const neutral900 = Color(0xFF1A1A1A);
  static const neutral700 = Color(0xFF3D3D3D);
  static const neutral500 = Color(0xFF737373);
  static const neutral200 = Color(0xFFE5E5E5);
  static const neutral100 = Color(0xFFF5F5F5);
  static const white      = Color(0xFFFFFFFF);

  static const accent700 = Color(0xFFD97706);
  static const accent500 = Color(0xFFF59E0B);
  static const accent100 = Color(0xFFFEF3C7);

  static const success   = Color(0xFF059669);
  static const warning   = Color(0xFFD97706);
  static const error     = Color(0xFFDC2626);
  static const errorBg   = Color(0xFFFEF2F2);
  static const allergy   = Color(0xFFB91C1C);
  static const allergyBg = Color(0xFFFFF1F2);
}

class AppRadii {
  AppRadii._();
  static const sm   = 12.0;
  static const md   = 16.0;
  static const lg   = 24.0;
  static const pill = 999.0;
}

class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final textTheme = _textTheme;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary700,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary700,
      onPrimary: AppColors.white,
      secondary: AppColors.accent700,
      onSecondary: AppColors.white,
      error: AppColors.error,
      onError: AppColors.white,
      surface: AppColors.white,
      onSurface: AppColors.neutral900,
      surfaceContainerLowest: AppColors.primary50,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.primary50,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.neutral900,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.neutral200,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.neutral900,
        ),
        shape: const Border(
          bottom: BorderSide(color: AppColors.neutral200, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: const BorderSide(color: AppColors.neutral200, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.neutral100,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: AppColors.neutral500),
        labelStyle: textTheme.labelLarge?.copyWith(color: AppColors.neutral700),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: AppColors.primary500, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary700,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.neutral200,
          disabledForegroundColor: AppColors.neutral500,
          minimumSize: const Size(double.infinity, 52),
          textStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary700,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: AppColors.primary700, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary700,
          minimumSize: const Size(48, 48),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary700,
        foregroundColor: AppColors.white,
        elevation: 3,
        extendedTextStyle:
            textTheme.labelLarge?.copyWith(color: AppColors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.neutral900,
        contentTextStyle:
            textTheme.bodyLarge?.copyWith(color: AppColors.white),
        actionTextColor: AppColors.primary100,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.neutral200,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primary100,
        labelStyle:
            textTheme.labelLarge?.copyWith(color: AppColors.primary900),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        side: BorderSide.none,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary700,
        linearTrackColor: AppColors.primary100,
        circularTrackColor: AppColors.primary100,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
    );
  }

  static TextTheme get _textTheme {
    final base = GoogleFonts.interTextTheme();
    return base.copyWith(
      displaySmall: GoogleFonts.inter(
          fontSize: 32, fontWeight: FontWeight.w700, height: 1.2,
          color: AppColors.neutral900),
      headlineSmall: GoogleFonts.inter(
          fontSize: 24, fontWeight: FontWeight.w700, height: 1.3,
          color: AppColors.neutral900),
      titleLarge: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w600, height: 1.4,
          color: AppColors.neutral900),
      titleSmall: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, height: 1.4,
          color: AppColors.neutral900),
      bodyLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, height: 1.5,
          color: AppColors.neutral900),
      bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, height: 1.5,
          color: AppColors.neutral700),
      labelLarge: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w500, height: 1.4,
          color: AppColors.neutral700),
      bodySmall: GoogleFonts.inter(
          fontSize: 11, fontWeight: FontWeight.w400, height: 1.4,
          color: AppColors.neutral500),
    );
  }
}
