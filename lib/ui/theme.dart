import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const Color brand = Color(0xFFD7263D); // Japanese red
  static const Color ink = Color(0xFF1E1B2E);
  static const Color success = Color(0xFF2E9E6B);
  static const Color successSoft = Color(0xFFE3F5EC);
  static const Color warning = Color(0xFFE8801A);
  static const Color warningSoft = Color(0xFFFFEFDB);
  static const Color gold = Color(0xFFF5B700);
  static const Color lockedGrey = Color(0xFFB9B6C4);
  static const Color premium = Color(0xFF6C4CD9);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.brand,
    brightness: Brightness.light,
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFFAF8FB),
    textTheme: GoogleFonts.notoSansArabicTextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(centerTitle: true),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFEAE6F0)),
      ),
    ),
  );
}
