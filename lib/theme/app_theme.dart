import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF1B1A18);
  static const bgGradTop = Color(0xFF211F1C);
  static const surface = Color(0xFF262523);
  static const surfaceHigh = Color(0xFF302F2C);
  static const surfaceInput = Color(0xFF2B2A27);
  static const border = Color(0xFF3A3935);
  static const borderSubtle = Color(0xFF2F2E2B);

  static const accent = Color(0xFFD97757);
  static const accentHover = Color(0xFFE08B6F);
  static const accentDim = Color(0xFF8A4E3A);

  static const text = Color(0xFFF2EFE9);
  static const textDim = Color(0xFFA8A299);
  static const textFaint = Color(0xFF6E6A63);

  static const green = Color(0xFF7FB069);
  static const red = Color(0xFFE0685A);
  static const yellow = Color(0xFFE0B05A);
  static const blue = Color(0xFF6FA8D9);
  static const purple = Color(0xFFB08FD9);
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.red,
        onPrimary: Colors.white,
        onSurface: AppColors.text,
      ),
      textTheme: textTheme,
      dividerColor: AppColors.border,
      iconTheme: const IconThemeData(color: AppColors.textDim, size: 18),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.border),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
      ),
    );
  }

  static TextStyle mono({
    double size = 12.5,
    Color color = AppColors.text,
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
    );
  }
}