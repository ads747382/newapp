import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Apple system palette (iOS 18 / macOS Sonoma) with the hostel's own accent for headers.
const kBlue = Color(0xFF0071E3); // Apple web blue
const kBlueDark = Color(0xFF0A84FF);
const kOk = Color(0xFF248A3D); // systemGreen (light)
const kOkDark = Color(0xFF30D158);
const kWarn = Color(0xFFB25000); // systemOrange, darkened for text
const kBad = Color(0xFFD70015); // systemRed
const kInfo = Color(0xFF5E5CE6); // systemIndigo
const kBrand = Color(0xFF3C1507); // logo brown, used sparingly
const kMuted = Color(0xFF6E6E73); // secondaryLabel

/// Surfaces
const kCanvasLight = Color(0xFFF2F2F7); // systemGroupedBackground
const kCardLight = Color(0xFFFFFFFF);
const kCanvasDark = Color(0xFF000000);
const kCardDark = Color(0xFF1C1C1E);
const kCardDark2 = Color(0xFF2C2C2E);
const kSeparatorLight = Color(0x1F3C3C43);
const kSeparatorDark = Color(0x40545458);

/// Continuous-ish corners, Apple sizing.
const kRadiusCard = 20.0;
const kRadiusControl = 12.0;
const kRadiusSheet = 28.0;
const kFont = 'SFDisplay';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final accent = dark ? kBlueDark : kBlue;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    primary: accent,
    onPrimary: Colors.white,
    surface: dark ? kCardDark : kCardLight,
    error: kBad,
  );
  final base = ThemeData(colorScheme: scheme, brightness: brightness, useMaterial3: true, fontFamily: kFont);
  final label = dark ? Colors.white : const Color(0xFF1D1D1F);
  final label2 = dark ? const Color(0xFF98989F) : kMuted;

  return base.copyWith(
    scaffoldBackgroundColor: dark ? kCanvasDark : kCanvasLight,
    canvasColor: dark ? kCanvasDark : kCanvasLight,
    dividerColor: dark ? kSeparatorDark : kSeparatorLight,
    textTheme: base.textTheme
        .apply(bodyColor: label, displayColor: label, fontFamily: kFont)
        .copyWith(
          // Apple-style large title and tight, confident headings.
          headlineSmall: TextStyle(fontFamily: kFont, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: label),
          titleLarge: TextStyle(fontFamily: kFont, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: label),
          titleMedium: TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: label),
          bodyMedium: TextStyle(fontFamily: kFont, fontSize: 15, height: 1.35, color: label),
          bodySmall: TextStyle(fontFamily: kFont, fontSize: 13, color: label2),
          labelSmall: TextStyle(fontFamily: kFont, fontSize: 11, fontWeight: FontWeight.w600, color: label2, letterSpacing: 0.2),
        ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      // Opaque: an 82% see-through bar without blur let scrolled content show through
      // (resident header chips were visible behind the status bar).
      backgroundColor: dark ? kCanvasDark : kCanvasLight,
      surfaceTintColor: Colors.transparent,
      foregroundColor: label,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: dark ? kSeparatorDark : kSeparatorLight, width: 0.5)),
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 17, fontWeight: FontWeight.w600, color: label, letterSpacing: -0.2),
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? kCardDark : kCardLight,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: dark ? 0 : 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard),
        side: BorderSide(color: dark ? kSeparatorDark : const Color(0x14000000), width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark ? kCardDark2 : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: BorderSide(color: dark ? kSeparatorDark : const Color(0x33000000)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: BorderSide(color: dark ? kSeparatorDark : const Color(0x33000000)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: BorderSide(color: dark ? kSeparatorDark : const Color(0x1A000000)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: const BorderSide(color: kBad, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusControl),
        borderSide: const BorderSide(color: kBad, width: 1.6),
      ),
      labelStyle: TextStyle(color: label2, fontSize: 15),
      floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: label2.withValues(alpha: 0.7)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 50),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusControl)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 50),
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusControl)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: (dark ? kCardDark : Colors.white).withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: 0.14),
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontFamily: kFont, fontSize: 11, fontWeight: FontWeight.w600, color: label2)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? accent : label2)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: label2,
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 16, color: label, letterSpacing: -0.2),
      subtitleTextStyle: TextStyle(fontFamily: kFont, fontSize: 13, color: label2),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: dark ? kCardDark2 : const Color(0xFFEFEFF4),
      side: BorderSide.none,
      labelStyle: TextStyle(fontFamily: kFont, fontSize: 13, fontWeight: FontWeight.w500, color: label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? kCardDark2 : const Color(0xFF1D1D1F),
      contentTextStyle: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusControl)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? kCardDark2 : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet - 6)),
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 18, fontWeight: FontWeight.w700, color: label),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? kCardDark : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet))),
      showDragHandle: true,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (dark ? kCardDark2 : Colors.white) : (dark ? const Color(0xFF1C1C1E) : const Color(0xFFEFEFF4)),
        ),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: kFont, fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(), // iOS-style slide
      },
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// Status colours: green = good, orange = waiting, red = problem, indigo = informational.
Color toneFor(String? key) {
  const ok = {'verified', 'admitted', 'active', 'clear', 'received', 'posted'};
  const warn = {'pending', 'in_progress', 'applied', 'documents_pending', 'under_verification', 'outstanding', 'maintenance', 'mild', 'draft'};
  const bad = {'failed', 'rejected', 'severe', 'void'};
  const info = {'approved', 'advance', 'AC', 'online'};
  if (ok.contains(key)) return kOk;
  if (warn.contains(key)) return kWarn;
  if (bad.contains(key)) return kBad;
  if (info.contains(key)) return kInfo;
  return kMuted;
}

/// Kept so older screens keep compiling; the hostel accent is now Apple blue.
const kPrimary = kBlue;
