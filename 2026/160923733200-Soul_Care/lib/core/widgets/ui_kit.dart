import 'package:flutter/material.dart';

import '../../app/theme/design_system.dart';
import 'app_widgets.dart';

/// Premium shared presentation components. Nothing here contains business
/// logic — pure visual vocabulary so screens stay consistent.

/// Editorial page header: large title + quiet subtitle (Apple.com style).
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const PageHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: DS.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: DS.textSecondary(theme.brightness),
            ),
          ),
        ],
      ],
    );
  }
}

/// iOS-style inset grouped list: one rounded surface containing [rows],
/// separated by hairlines. Rows must be [ListRow]-compatible widgets.
class ListGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const ListGroup({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: padding,
      decoration: BoxDecoration(
        color: DS.backgroundSecondary(isDark ? Brightness.dark : Brightness.light),
        borderRadius: BorderRadius.circular(DS.rLarge),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 56, thickness: 0.5, height: 0.5),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One tappable row inside a [ListGroup]. Small leading icon, headline,
/// quiet detail, trailing chevron — all with 44pt min touch height.
class ListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dim = DS.textSecondary(theme.brightness);
    return PressableScale(
      onTap: onTap,
      borderRadius: DS.rMedium,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DS.l,
          vertical: DS.m + 2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 22, color: scheme.primary),
            ),
            const SizedBox(width: DS.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyLarge),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                    ),
                ],
              ),
            ),
            const SizedBox(width: DS.s),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right,
                size: 22,
                color: scheme.outline.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}

/// Animated progress ring — the signature wellness indicator. Rounded
/// stroke, quick ease-out, optional label in the middle.
class ProgressRing extends StatelessWidget {
  /// 0..1. Values are clamped by the painter.
  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? child;

  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 96,
    this.stroke = 9,
    Color? track,
    this.child,
  }) : assert(size > stroke * 2),
       track = track ?? const Color(0x22707070);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: DS.durSlow + const Duration(milliseconds: 200),
      curve: DS.curveEntrance,
      builder: (context, v, _) => CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(
          value: v,
          color: color,
          track: track,
          stroke: stroke,
        ),
        child: _SizedSquare(size, child: child),
      ),
    );
  }
}

// A tiny helper so the ring child centers without extra imports.
class _SizedSquare extends StatelessWidget {
  final double side;
  final Widget? child;
  const _SizedSquare(this.side, {this.child});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: side, height: side, child: child);
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 6.28318530718, false, trackPaint);

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (value > 0) {
      canvas.drawArc(
        rect,
        -1.57079632679,
        6.28318530718 * value,
        false,
        valuePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Home-screen entry tile to a feature: icon on a tinted lozenge,
/// headline + one-line invitation. Used in rows and grids.
class EntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? tint;
  final Widget? trailing;

  const EntryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.tint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(DS.l),
        decoration: BoxDecoration(
          color: DS.backgroundSecondary(theme.brightness),
          borderRadius: BorderRadius.circular(DS.rLarge),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (tint ?? scheme.primary).withValues(alpha: 0.14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 21, color: tint ?? scheme.primary),
            ),
            const SizedBox(width: DS.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: DS.textSecondary(theme.brightness),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: DS.xs),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.outline.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}

/// Quiet metric chip used in progress strips.
class MetricChip extends StatelessWidget {
  final String label;
  final String? value;
  final bool done;
  final Color? color;

  const MetricChip({
    super.key,
    required this.label,
    this.done = false,
    this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        color ??
        (done ? theme.colorScheme.primary : DS.textTertiary(theme.brightness));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: done
            ? accent.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DS.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check : Icons.radio_button_unchecked,
            size: 13,
            color: accent,
          ),
          const SizedBox(width: 5),
          Text(
            value != null ? '$label · $value' : label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: done ? accent : DS.textSecondary(theme.brightness),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated single-metric number: slides from 0 and fades in once.
class AnimatedNumber extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String Function(num)? formatter;

  const AnimatedNumber({
    super.key,
    required this.value,
    required this.style,
    this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: DS.curveEntrance,
      builder: (context, v, _) {
        final shown = formatter?.call(v) ?? v.round().toString();
        return Text(shown, style: style);
      },
    );
  }
}
