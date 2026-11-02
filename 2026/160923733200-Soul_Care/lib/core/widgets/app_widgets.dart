import 'package:flutter/material.dart';

import '../../app/theme/design_system.dart';

/// Consistent loading indicator.
class AppLoading extends StatelessWidget {
  final String? message;
  const AppLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          if (message != null) ...[
            const SizedBox(height: DS.m),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: DS.textSecondary(Theme.of(context).brightness),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Consistent empty state.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DS.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerLow,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 32,
                color: DS.textTertiary(theme.brightness),
              ),
            ),
            const SizedBox(height: DS.xl),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: DS.s),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: DS.textSecondary(theme.brightness),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: DS.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent error state — never shows raw exceptions.
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AppErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DS.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.error.withValues(alpha: 0.08),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.error_outline,
                size: 32,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: DS.xl),
            Text(
              'Something didn\u2019t go as planned',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: DS.s),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DS.textSecondary(theme.brightness),
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: DS.xl),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The core surface of the design language: a quiet, grouped surface
/// (no border, no shadow) that organizes content through fill and
/// whitespace. Rises gently on press.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DS.xl),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return _Pressable(
      onTap: onTap,
      borderRadius: DS.rLarge,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: DS.backgroundSecondary(brightness),
          borderRadius: BorderRadius.circular(DS.rLarge),
        ),
        child: child,
      ),
    );
  }
}

/// Press feedback shared by every interactive surface: scale-to-0.98 with
/// a quick ease-out — the signature physical motion of the app.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final bool reduceMotion;

  const _Pressable({
    required this.child,
    required this.borderRadius,
    this.onTap,
    this.reduceMotion = false,
  });

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    // Honors the OS "reduce motion" setting so vestibular-sensitive users
    // get instant state without animation on press.
    final honorReduce = DS.reduceMotion(context);
    final scale = honorReduce
        ? 1.0
        : _down
        ? 0.98
        : 1.0;
    final duration = honorReduce ? Duration.zero : DS.durFast;

    final inner = AnimatedScale(
      scale: scale,
      duration: duration,
      curve: honorReduce ? Curves.linear : Curves.easeOut,
      child: widget.child,
    );
    if (widget.onTap == null) return inner;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: inner,
    );
  }
}

/// Public press-feedback wrapper for tiles and rows across the app.
class PressableScale extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = DS.rLarge,
  });

  @override
  Widget build(BuildContext context) => _Pressable(
    onTap: onTap,
    borderRadius: borderRadius,
    reduceMotion: DS.reduceMotion(context),
    child: child,
  );
}

/// Section header: quiet overline-style label with generous optics.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(height: 1)),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: Text(
              actionLabel!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// No internet connection state — calm, non-alarming, with a clear retry.
class AppNoConnectionState extends StatelessWidget {
  final VoidCallback? onRetry;
  const AppNoConnectionState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerLow,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.wifi_off_rounded,
                size: 32,
                color: DS.textTertiary(theme.brightness),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'You appear to be offline',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Some features need a connection. Your saved data is still available on this device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DS.textSecondary(theme.brightness),
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Permission not granted state — explains why and offers a clear next step.
class AppPermissionState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const AppPermissionState({
    super.key,
    this.title = 'Permission not granted',
    this.subtitle =
        'This feature needs your permission to continue. You can change this in Settings at any time.',
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerLow,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock_outline,
                size: 32,
                color: DS.textTertiary(theme.brightness),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DS.textSecondary(theme.brightness),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Missing profile information — gentle prompt, never blocking.
class AppProfileIncompleteState extends StatelessWidget {
  final VoidCallback? onComplete;
  const AppProfileIncompleteState({super.key, this.onComplete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerLow,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.person_outline,
                size: 32,
                color: DS.textTertiary(theme.brightness),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add a little context',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Optional profile details help SoulCare personalise suggestions. Everything stays on this device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DS.textSecondary(theme.brightness),
              ),
              textAlign: TextAlign.center,
            ),
            if (onComplete != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onComplete,
                child: const Text('Complete profile'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Failed synchronisation state — honest, recoverable.
class AppSyncFailedState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const AppSyncFailedState({
    super.key,
    this.message = 'Something didn\u2019t go as planned.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.error.withValues(alpha: 0.08),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.sync_problem_rounded,
                size: 32,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sync didn\u2019t finish',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DS.textSecondary(theme.brightness),
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One widget so branding stays consistent on every surface.
class SoulCareMark extends StatelessWidget {
  final double size;
  final double radius;
  const SoulCareMark({super.key, this.size = 48, double? radius})
    : radius = radius ?? size * 0.28;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/icons/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, e, stack) => Icon(
          Icons.spa_outlined,
          size: size * 0.7,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
