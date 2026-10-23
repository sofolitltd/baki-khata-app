import 'package:flutter/material.dart';

import 'ledger.dart';

const appFont = 'AnekBangla';

const brand = Color(0xFF0F766E); // গাঢ় টিল
const bakiColor = Color(0xFFDC2626); // বাকি = লাল
const jomaColor = Color(0xFF059669); // জমা = সবুজ

/// খাতা অনুযায়ী থিম — পাওনা টিল, দেনা ইন্ডিগো।
ThemeData buildTheme(Brightness brightness, [Ledger ledger = Ledger.pabo]) {
  final accent = ledgerAccent(ledger, brightness);
  final cs = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(primary: accent);
  final light = brightness == Brightness.light;
  final radius = BorderRadius.circular(14);
  // খাতার আসল রঙ — অটো-জেনারেটেড প্যালেটের হালকা টোন না
  final navAccent = accent;

  return ThemeData(
    useMaterial3: true,
    fontFamily: appFont,
    colorScheme: cs,
    scaffoldBackgroundColor: light ? const Color(0xFFF4F7F6) : cs.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: light ? const Color(0xFFF4F7F6) : cs.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: appFont,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: light ? Colors.white : cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : cs.surfaceContainerHighest,
      prefixIconColor: cs.onSurfaceVariant,
      hintStyle: TextStyle(fontFamily: appFont, color: cs.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(
          fontFamily: appFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: cs.outlineVariant),
      selectedColor: navAccent.withValues(alpha: light ? .12 : .22),
      checkmarkColor: navAccent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      extendedTextStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: light ? Colors.white : cs.surfaceContainerLow,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light ? Colors.white : cs.surfaceContainer,
      indicatorColor: navAccent.withValues(alpha: light ? .12 : .22),
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? navAccent
              : cs.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: appFont,
          fontSize: 13,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? navAccent
              : cs.onSurfaceVariant,
        ),
      ),
    ),
  );
}
