import 'package:flutter/material.dart';

/// SPECTRE "electric blue" tasarım dili (v38 paletinden).
abstract final class SpectreColors {
  static const bg = Color(0xFF050B14);
  static const bg2 = Color(0xFF0A1726);
  static const panel = Color(0xFF122737);
  static const panelHi = Color(0xFF1A3348);
  static const accent = Color(0xFF65C5FF);
  static const cyan = Color(0xFF9CDDFF);
  static const ink = Color(0xFFEFF8FF);
  static const muted = Color(0xFFADC6D8);
  static const line = Color(0x2EA3D4F2);
  static const pink = Color(0xFFFF6FAE);
  static const gold = Color(0xFFFFC857);
  static const green = Color(0xFF5BE3A6);
  static const red = Color(0xFFFF6B7A);
  static const amber = Color(0xFFFFB547);
}

abstract final class SpectreMotion {
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 460);
  static const curve = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack;
}

ThemeData buildSpectreTheme() {
  const scheme = ColorScheme.dark(
    primary: SpectreColors.accent,
    onPrimary: Color(0xFF02111E),
    secondary: SpectreColors.pink,
    surface: SpectreColors.panel,
    onSurface: SpectreColors.ink,
    error: SpectreColors.red,
    outline: SpectreColors.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: SpectreColors.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: SpectreColors.ink, displayColor: SpectreColors.ink),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
    }),
    cardTheme: CardTheme(
      color: SpectreColors.panel.withOpacity(0.72),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: SpectreColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.04),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SpectreColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SpectreColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SpectreColors.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Manrope'),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: SpectreColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: SpectreColors.line, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: SpectreColors.panelHi,
      contentTextStyle: const TextStyle(color: SpectreColors.ink, fontFamily: 'Manrope'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: SpectreColors.panelHi,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SpectreColors.line),
      ),
      textStyle: const TextStyle(color: SpectreColors.ink, fontSize: 12),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Color(0x3365C5FF),
      selectedIconTheme: IconThemeData(color: SpectreColors.accent),
      unselectedIconTheme: IconThemeData(color: SpectreColors.muted),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withOpacity(0.04),
      side: const BorderSide(color: SpectreColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: const TextStyle(color: SpectreColors.ink, fontSize: 12),
    ),
  );
}
