import 'package:flutter/material.dart';

class AppTheme {
  static const Color ink = Color(0xFF121212);
  static const Color muted = Color(0xFF6F6F6F);
  static const Color border = Color(0xFFB7BBC1);
  static const Color canvas = Color(0xFFF0F1F3);

  static const Color brand = Color(0xFF246BCE);
  static const Color brandTeal = Color(0xFF2AB3A6);
  static const Color brandDeep = Color(0xFF1B4F9C);
  static const Color green = Color(0xFF4CAF50);
  static const Color orange = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color red = Color(0xFFE5484D);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandTeal, brand, brandDeep],
  );

  static const LinearGradient tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3BD6C6), Color(0xFF1E9E8F)],
  );

  static const LinearGradient orangeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFB84D), Color(0xFFF59E0B)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9C7BFF), Color(0xFF6C3EE8)],
  );

  static const LinearGradient redGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B6E), Color(0xFFD93840)],
  );

  static const List<Color> tealGradientColors = [Color(0xFF53D8C9), Color(0xFF1B9C8E)];
  static const List<Color> blueGradientColors = [Color(0xFF5B9BF0), Color(0xFF2260BE)];
  static const List<Color> orangeGradientColors = [Color(0xFFFFB84D), Color(0xFFF08A00)];
  static const List<Color> purpleGradientColors = [Color(0xFF9C7BFF), Color(0xFF6C3EE8)];
  static const List<Color> greenGradientColors = [Color(0xFF77DD77), Color(0xFF35A835)];
  static const List<Color> pinkGradientColors = [Color(0xFFF78FB3), Color(0xFFE24D80)];
  static const List<Color> redGradientColors = [Color(0xFFFF8A8C), Color(0xFFE5484D)];

  static const List<List<Color>> avatarGradients = [
    tealGradientColors,
    blueGradientColors,
    orangeGradientColors,
    purpleGradientColors,
    greenGradientColors,
    pinkGradientColors,
  ];

  static LinearGradient avatarGradientFor(String seed) {
    var hash = 0;
    for (final code in seed.codeUnits) {
      hash = (hash + code) % 997;
    }
    final colors = avatarGradients[hash % avatarGradients.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ink,
        brightness: Brightness.light,
        primary: ink,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Arial',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          color: ink,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
        titleLarge: const TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: const TextStyle(
          color: ink,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        hintStyle: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 14),
        labelStyle: const TextStyle(color: ink),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ink, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
        ),
      ),
    );
  }
}
