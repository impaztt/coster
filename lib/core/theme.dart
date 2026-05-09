import 'package:flutter/material.dart';

class AppColors {
  static const coral = Color(0xFFFF8A65);
  static const mint = Color(0xFF80CBC4);
  static const yellow = Color(0xFFFFD54F);
  static const cream = Color(0xFFFFF8E1);
  static const softBrown = Color(0xFF8D6E63);
  static const deepCoral = Color(0xFFE65100);
  static const blade = Color(0xFFCFD8DC);
  static const bladeShadow = Color(0xFF90A4AE);
  static const handle = Color(0xFF6D4C41);
  static const outline = Color(0xFF3E2723);

  // Dark surfaces tuned to keep the coral/mint accents readable.
  static const darkBackground = Color(0xFF1B1A22);
  static const darkSurface = Color(0xFF262632);
  static const darkSurfaceAlt = Color(0xFF2F2F3D);
}

class AppRadii {
  static const card = 10.0;
  static const control = 8.0;
  static const chip = 8.0;
}

ThemeData buildAppTheme({bool highContrast = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: highContrast ? AppColors.deepCoral : AppColors.coral,
    brightness: Brightness.light,
  ).copyWith(
    primary: highContrast ? AppColors.deepCoral : AppColors.coral,
    secondary: highContrast ? const Color(0xFF00695C) : AppColors.mint,
    tertiary: highContrast ? const Color(0xFF8D6E00) : AppColors.yellow,
    surface: Colors.white,
    onSurface: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: highContrast ? Colors.white : AppColors.cream,
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w900),
      headlineLarge: TextStyle(fontWeight: FontWeight.w800),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontWeight: FontWeight.w500),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.coral.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    ),
  );
}

ThemeData buildDarkTheme({bool highContrast = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: highContrast ? AppColors.yellow : AppColors.coral,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.coral,
    secondary: highContrast ? Colors.cyanAccent : AppColors.mint,
    tertiary: highContrast ? Colors.amberAccent : AppColors.yellow,
    surface: highContrast ? const Color(0xFF111111) : AppColors.darkSurface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        highContrast ? const Color(0xFF000000) : AppColors.darkBackground,
    cardColor: highContrast ? const Color(0xFF111111) : AppColors.darkSurface,
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w900),
      headlineLarge: TextStyle(fontWeight: FontWeight.w800),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontWeight: FontWeight.w500),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      indicatorColor: AppColors.coral.withValues(alpha: 0.22),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    ),
  );
}
