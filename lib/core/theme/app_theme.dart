import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The "Tactical Dark" design system for RescueNet Pro.
class AppTheme {
  // Core Colors
  static const Color background = Color(0xFF05050A); // Deepest Black/Blue
  static const Color surface = Color(0xFF10121B);    // Panel Background
  static const Color surfaceHighlight = Color(0xFF1E2235); // Card Highlight
  
  // Accents
  static const Color primary = Color(0xFF2979FF);    // Electric Blue (Active/Safe)
  static const Color danger = Color(0xFFFF1744);     // Alert Red (SOS)
  static const Color success = Color(0xFF00E676);    // Teal (Connectivity)
  static const Color warning = Color(0xFFFFC400);    // Amber (Caution)
  
  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA0A5B9);
  static const Color textDim = Color(0xFF505565);

  /// The main theme data.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      
      // Color Scheme
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: success,
        surface: surface,
        error: danger,
        onSurface: textPrimary,
      ),

      // Text Theme (Monospaced numbers for technical feel)
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16, 
          height: 1.5,
        ),
        bodyMedium: TextStyle(
            color: textSecondary,
            fontSize: 14,
            height: 1.4,
        ),
        labelSmall: TextStyle(
          color: textDim,
          fontSize: 11,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 2.0,
          color: textPrimary,
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4), // Shallower rounding for tech feel
          side: const BorderSide(color: surfaceHighlight, width: 1),
        ),
      ),

      // Icons
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),
    );
  }

  // Gradients
  static const Gradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2979FF), Color(0xFF1565C0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF1744), Color(0xFFD50000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const Gradient glassGradient = LinearGradient(
    colors: [Color(0x1AFFFFFF), Color(0x05FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Shadows
  static List<BoxShadow> get glowPrimary => [
    BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 0),
  ];
  
  static List<BoxShadow> get glowDanger => [
    BoxShadow(color: danger.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 0),
  ];
}
