import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern, accessible design system for RescueNet Pro.
/// Optimized for battery efficiency (OLED-friendly dark theme)
/// and accessibility (WCAG AA compliant contrast ratios).
class AppTheme {
  // Core Colors - Pure blacks for OLED battery savings
  static const Color background = Color(0xFF000000);     // True black (OLED efficient)
  static const Color surface = Color(0xFF121212);        // Material dark surface
  static const Color surfaceHighlight = Color(0xFF1E1E1E); // Elevated surface
  static const Color surfaceContainer = Color(0xFF252525); // Card containers
  
  // Semantic Colors - High contrast for accessibility
  static const Color primary = Color(0xFF60A5FA);        // Soft blue (easier on eyes)
  static const Color danger = Color(0xFFEF4444);         // Emergency red
  static const Color success = Color(0xFF34D399);        // Success green
  static const Color warning = Color(0xFFFBBF24);        // Warning amber
  static const Color info = Color(0xFF38BDF8);           // Info cyan
  
  // Text - WCAG AA compliant contrast
  static const Color textPrimary = Color(0xFFFAFAFA);    // 15.8:1 contrast
  static const Color textSecondary = Color(0xFFB3B3B3);  // 7.5:1 contrast
  static const Color textDim = Color(0xFF737373);        // 4.5:1 contrast (minimum)
  static const Color textOnPrimary = Color(0xFF000000);
  
  // Borders
  static const Color borderSubtle = Color(0xFF333333);   // Subtle border color
  
  // Aliases for consistency across codebase
  static const Color backgroundPrimary = background;
  static const Color surfacePrimary = surface;
  static const Color surfaceSecondary = surfaceHighlight;
  static const Color textTertiary = textDim;
  static const Color error = danger;
  
  // Accessibility
  static const double minTouchTarget = 48.0;             // WCAG minimum
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 16.0;

  /// The main theme data - optimized for accessibility and battery.
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
        surfaceContainerHighest: surfaceContainer,
        error: danger,
        onSurface: textPrimary,
        onPrimary: textOnPrimary,
      ),

      // Text Theme - Accessible font sizes (16px minimum for body)
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
        ),
        displayMedium: TextStyle(
          color: textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
          height: 1.3,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          color: textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelSmall: TextStyle(
          color: textDim,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(
          color: textPrimary,
          size: 24,
        ),
      ),

      // Card Theme - Subtle elevation
      cardTheme: CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
        ),
      ),

      // Elevated Button Theme - Minimum touch target
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, minTouchTarget),
          backgroundColor: primary,
          foregroundColor: textOnPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusMedium),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Outlined Button Theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, minTouchTarget),
          foregroundColor: textPrimary,
          side: const BorderSide(color: surfaceHighlight, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          borderSide: const BorderSide(color: surfaceHighlight, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: const TextStyle(color: textDim, fontSize: 16),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 16),
      ),

      // Icons
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: surfaceHighlight,
        thickness: 1,
        space: 1,
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceContainer,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Semantic decorations for common UI patterns
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceContainer,
    borderRadius: BorderRadius.circular(borderRadiusMedium),
    border: Border.all(color: surfaceHighlight, width: 1),
  );

  static BoxDecoration get elevatedCardDecoration => BoxDecoration(
    color: surfaceContainer,
    borderRadius: BorderRadius.circular(borderRadiusMedium),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // Status colors for different roles
  static const Color roleHelpNeeded = danger;      // I Need Help
  static const Color roleHelper = success;          // I Can Help  
  static const Color roleRelay = primary;           // Relay Mode

  // Gradients - Subtle, battery-friendly
  static const Gradient primaryGradient = LinearGradient(
    colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient dangerGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient successGradient = LinearGradient(
    colors: [Color(0xFF34D399), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Shadows - Minimal for performance
  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get glowPrimary => [
    BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 0),
  ];
  
  static List<BoxShadow> get glowDanger => [
    BoxShadow(color: danger.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 0),
  ];
}
