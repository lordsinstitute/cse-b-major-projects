import 'package:flutter/material.dart';

/// SoulCare design system tokens.
///
/// The visual language: Apple-grade typography and restraint over a calm
/// canvas, with the user's chosen palette providing the accent.
/// Widgets should consume tokens instead of hand-picking values so the
/// whole app stays coherent in light and dark themes.
abstract final class DS {
  // ── Spacing scale ────────────────────────────────────────────────────
  /// 4, 8, 12, 16, 20, 24, 32, 40, 48, 64.
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double massive = 48;
  static const double colossal = 64;

  /// Default horizontal page padding (Apple-style generous margins).
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 20);

  // ── Corner radii ─────────────────────────────────────────────────────
  static const double rSmall = 10;
  static const double rMedium = 16;
  static const double rLarge = 22;
  static const double rXLarge = 28;
  static const double rPill = 999;

  // ── Motion ───────────────────────────────────────────────────────────
  /// Fast, natural micro-interactions. Nothing bouncy.
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durMedium = Duration(milliseconds: 240);
  static const Duration durSlow = Duration(milliseconds: 360);

  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEntrance = Curves.easeOut;

  // ── Neutral canvas (Apple-inspired, theme-aware) ─────────────────────
  /// Light: white canvas, #F5F5F7 grouping. Dark: true black with
  /// #1C1C1E / #2C2C2E elevation steps. Never a flat color inversion.
  static const int _bgLight = 0xFFFFFFFF;
  static const int _bgSecondaryLight = 0xFFF5F5F7;
  static const int _textPrimaryLight = 0xFF1D1D1F;
  static const int _textSecondaryLight = 0xFF6E6E73;
  static const int _textTertiaryLight = 0xFFA1A1A6;
  static const int _textTertiaryDark = 0xFF98989D;
  static const int _dividerLight = 0xFFD2D2D7;

  static const int _bgDark = 0xFF000000;
  static const int _bgSecondaryDark = 0xFF1C1C1E;
  static const int _bgElevatedDark = 0xFF2C2C2E;
  static const int _textPrimaryDark = 0xFFF5F5F7;
  static const int _textSecondaryDark = 0xFF98989D;
  static const int _dividerDark = 0xFF38383A;

  static Color background(Brightness b) =>
      b == Brightness.light ? const Color(_bgLight) : const Color(_bgDark);

  static Color backgroundSecondary(Brightness b) => b == Brightness.light
      ? const Color(_bgSecondaryLight)
      : const Color(_bgSecondaryDark);

  static Color surfaceElevated(Brightness b) => b == Brightness.light
      ? const Color(_bgLight)
      : const Color(_bgElevatedDark);

  static Color textPrimary(Brightness b) => b == Brightness.light
      ? const Color(_textPrimaryLight)
      : const Color(_textPrimaryDark);

  static Color textSecondary(Brightness b) => b == Brightness.light
      ? const Color(_textSecondaryLight)
      : const Color(_textSecondaryDark);

  static Color textTertiary(Brightness b) => b == Brightness.light
      ? const Color(_textTertiaryLight)
      : const Color(_textTertiaryDark);

  static Color divider(Brightness b) => b == Brightness.light
      ? const Color(_dividerLight)
      : const Color(_dividerDark);

  /// Honors the OS "reduce motion" setting. All entrance/micro animations
  /// should consult this so vestibular-sensitive users get instant state.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  // ── Semantic wellness colors ─────────────────────────────────────────
  // Used only where they communicate something real (a metric, a domain).
  // Muted by design — never decoration.
  static Color metric(Brightness b, MetricDomain domain) {
    if (b == Brightness.dark) {
      return switch (domain) {
        MetricDomain.activity => const Color(0xFF6FCF8E),
        MetricDomain.mood => const Color(0xFFB3A5E8),
        MetricDomain.sleep => const Color(0xFF8E9BE8),
        MetricDomain.heart => const Color(0xFFE89289),
        MetricDomain.hydration => const Color(0xFF7FB8E8),
        MetricDomain.nutrition => const Color(0xFFE8B774),
      };
    }
    return switch (domain) {
      MetricDomain.activity => const Color(0xFF3E9B5F),
      MetricDomain.mood => const Color(0xFF7C68C4),
      MetricDomain.sleep => const Color(0xFF5B6BC0),
      MetricDomain.heart => const Color(0xFFD1665C),
      MetricDomain.hydration => const Color(0xFF3E86C4),
      MetricDomain.nutrition => const Color(0xFFC58A3E),
    };
  }
}

enum MetricDomain { activity, mood, sleep, heart, hydration, nutrition }

/// Subtle entrance animation for content appearing on first paint.
/// Content fades in and drifts up a few pixels; [stagger] offsets the
/// start (0 = immediate, 1 = last) so sections gently cascade in.
class EntranceFader extends StatelessWidget {
  final Widget child;
  final int index;
  final int count;

  const EntranceFader({
    super.key,
    required this.child,
    this.index = 0,
    this.count = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (DS.reduceMotion(context)) {
      return child;
    }
    final start = (count <= 1 ? 0.0 : (0.55 * index / (count - 1)));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Interval(start.clamp(0, 0.85), 1, curve: DS.curveEntrance),
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
