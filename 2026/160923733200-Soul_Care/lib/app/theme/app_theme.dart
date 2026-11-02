import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_system.dart';

/// SoulCare design system — the single source of visual truth.
///
/// Calm, kinetic, and premium: an Apple-inspired neutral canvas, generous
/// typography, restrained separations. The user's chosen palette seed
/// still drives the accent colors via [ColorScheme.fromSeed]; the surfaces
/// stay deliberately neutral so the accent reads with intent.
class AppTheme {
  // Calm teal-green seed for light, soft and premium
  static const _seedLight = Color(0xFF3E7C6B);

  /// Public brand accent (used by boot chrome that renders before the
  /// theme can.) Same family as `_seedLight`.
  static const brandSeed = _seedLight;
  // Slightly brighter seed for dark mode legibility
  static const _seedDark = Color(0xFF7BC4A8);

  /// Available color palette seeds (name + ARGB). The same seed drives both
  /// brightnesses via [ColorScheme.fromSeed], so dark mode stays designed,
  /// never inverted.
  static const List<(String, int)> palettes = [
    ('Teal', 0xFF3E7C6B),
    ('Ocean', 0xFF3B6EA5),
    ('Violet', 0xFF6D5BA4),
    ('Sage', 0xFF5B8C5A),
    ('Terracotta', 0xFFB4654A),
    ('Rose', 0xFFB44B63),
  ];

  /// Optional display fonts. `null` = system default (always offline).
  /// Named fonts load once from Google Fonts when online, then work offline
  /// from the local cache.
  static const List<String?> fontChoices = [null, 'Nunito', 'Lora', 'Poppins'];

  static String fontLabel(String? family) => family ?? 'System default';

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedLight,
      brightness: Brightness.light,
    );
    return _build(scheme, Brightness.light, null);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedDark,
      brightness: Brightness.dark,
    );
    return _build(scheme, Brightness.dark, null);
  }

  /// Theme for an explicit palette seed + optional font.
  static ThemeData themed({
    required bool dark,
    required Color seed,
    String? fontFamily,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return _build(
      scheme,
      dark ? Brightness.dark : Brightness.light,
      fontFamily,
    );
  }

  static TextTheme _applyFont(String? family, TextTheme base) {
    return switch (family) {
      'Nunito' => GoogleFonts.nunitoTextTheme(base),
      'Lora' => GoogleFonts.loraTextTheme(base),
      'Poppins' => GoogleFonts.poppinsTextTheme(base),
      _ => base,
    };
  }

  /// Premium editorial type scale. Tighter tracking at display sizes,
  /// comfortable line heights for body text.
  static TextTheme _editorial(TextTheme base) {
    return base.copyWith(
      // Hero / magazine numbers & greetings.
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        height: 1.08,
        letterSpacing: -1.2,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -1.0,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.6,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.5,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.3,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 17,
        height: 1.45,
        letterSpacing: -0.1,
      ),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.45),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      ),
    );
  }

  static ThemeData _build(
    ColorScheme scheme,
    Brightness brightness,
    String? fontFamily,
  ) {
    final b = brightness;
    final isDark = b == Brightness.dark;

    // Neutral canvas: the palette still owns the accents, but backgrounds,
    // text and separators follow the fixed design language so layout
    // hierarchy stays identical regardless of palette choice.
    final canvas = DS.background(b);
    final grouped = DS.backgroundSecondary(b);
    final elevated = DS.surfaceElevated(b);
    final onCanvas = DS.textPrimary(b);
    final onCanvasDim = DS.textSecondary(b);
    final separator = DS.divider(b);

    final scheme2 = scheme.copyWith(
      surface: canvas,
      onSurface: onCanvas,
      onSurfaceVariant: onCanvasDim,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: isDark ? grouped : grouped,
      surfaceContainer: isDark ? const Color(0xFF1C1C1E) : grouped,
      surfaceContainerHigh: elevated,
      surfaceContainerHighest: isDark ? elevated : grouped,
      outlineVariant: separator,
    );

    final baseText = _applyFont(fontFamily, _editorial(const TextTheme()));

    final hairline = BorderSide(color: separator.withValues(alpha: 0.55));

    ShapeBorder borderShape(double r) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(r),
      side: BorderSide(color: Colors.transparent),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme2,
      textTheme: baseText,
      scaffoldBackgroundColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onCanvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: b == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: borderShape(DS.rLarge),
        color: scheme2.surfaceContainerLow,
      ),
      dividerTheme: DividerThemeData(
        color: separator.withValues(alpha: 0.6),
        thickness: 0.5,
        space: 0.5,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rPill),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rPill),
          ),
          side: BorderSide(color: separator.withValues(alpha: 0.8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(44, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: grouped,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DS.rMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DS.rMedium),
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DS.rMedium),
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: 0.7),
            width: 1.4,
          ),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: separator.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rPill),
        ),
        labelStyle: baseText.labelMedium,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DS.rPill),
            ),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: separator.withValues(alpha: 0.5)),
          ),
          textStyle: WidgetStatePropertyAll(
            baseText.labelLarge?.copyWith(fontSize: 14),
          ),
          visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 9,
          elevation: 2,
        ),
        showValueIndicator: ShowValueIndicator.never,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateColor.resolveWith((states) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : separator.withValues(alpha: 0.6),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? elevated : onCanvas,
        contentTextStyle: baseText.bodyMedium?.copyWith(
          color: isDark ? onCanvas : canvas,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rPill),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(DS.rXLarge)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : canvas,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rXLarge),
        ),
        titleTextStyle: baseText.titleMedium?.copyWith(color: onCanvas),
        contentTextStyle: baseText.bodyMedium?.copyWith(
          color: onCanvasDim,
          height: 1.5,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: separator.withValues(alpha: 0.4),
        labelStyle: baseText.labelLarge,
        unselectedLabelStyle: baseText.labelLarge?.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: separator.withValues(alpha: 0.5),
        circularTrackColor: separator.withValues(alpha: 0.3),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rMedium),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rLarge),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        labelTextStyle: WidgetStatePropertyAll(
          baseText.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: onCanvas,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : onCanvasDim,
            size: 22,
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[HairlineBorder(hairline)],
    );
  }
}

/// Carries the hairline separator for custom surfaces without forcing a
/// border on every card. Available via `Theme.of(context).extension()`.
class HairlineBorder extends ThemeExtension<HairlineBorder> {
  final BorderSide side;
  const HairlineBorder(this.side);

  @override
  HairlineBorder copyWith({BorderSide? side}) =>
      HairlineBorder(side ?? this.side);

  @override
  HairlineBorder lerp(HairlineBorder? other, double t) => other == null
      ? this
      : HairlineBorder(BorderSide.lerp(side, other.side, t));
}
