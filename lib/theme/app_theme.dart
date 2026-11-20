import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

class AppColors {
  static const Color background = Color(0xFFF8F9FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color navy = Color(0xFF111D2B);
  static const Color orange = Color(0xFFC2410C);
  static const Color orangeLight = Color(0xFFFFF7ED);
  static const Color placeholder = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFE5E7EB);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color success = Color(0xFF15803D);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: GoogleFonts.cairo().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.orange,
        primary: AppColors.orange,
        secondary: AppColors.navy,
        surface: AppColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }
}