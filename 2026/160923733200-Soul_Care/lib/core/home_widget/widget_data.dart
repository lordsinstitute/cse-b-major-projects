import 'package:go_router/go_router.dart';

/// Keys shared between Dart (writer) and the native provider (reader).
/// Values are primitives in plugin-managed prefs — offline by design.
class WidgetKeys {
  static const String score = 'soulcare_score';
  static const String done = 'soulcare_done';
  static const String total = 'soulcare_total';
  static const String date = 'soulcare_date';
  static const String greeting = 'soulcare_greeting';
}

/// Tap actions coming from the widget. URIs look like:
/// `soulcare://widget?action=water`.
enum WidgetAction { today, water, mood, checkin, score }

/// Builds the exact key/value payload written for the native widget.
/// Pure + deterministic (testable without a device).
Map<String, dynamic> buildWidgetPayload({
  required int score,
  required int done,
  required int total,
  required String dateKey,
  required String greeting,
}) {
  int clamp(int v, int lo, int hi) =>
      v < lo ? lo : (v > hi ? hi : v);
  return {
    WidgetKeys.score: clamp(score, 0, 100),
    WidgetKeys.done: clamp(done, 0, total <= 0 ? done : total),
    WidgetKeys.total: total <= 0 ? 5 : total,
    WidgetKeys.date: dateKey,
    WidgetKeys.greeting: greeting,
  };
}

/// Deep-link target for a widget tap. Logging actions land on the fast
/// logging screen (/today); check-in opens the morning flow; anything
/// unknown or empty resolves to null (app just opens Home).
String? resolveWidgetRoute(Uri? uri) {
  final action = uri?.queryParameters['action'];
  switch (action) {
    case 'today':
    case 'water':
    case 'mood':
      return '/today';
    case 'checkin':
      return '/home/morning';
    case 'score':
      return '/home';
    default:
      return null;
  }
}

/// Registry bridging widget taps to the RUNNING app's router instance
/// (the app uses per-instance routers, so a global static is the only
/// safe handoff). Tests attach/detach freely; an empty registry means
/// "no app instance" (e.g. cold start pending or tests).
class WidgetLink {
  static GoRouter? _router;
  static String? pendingRoute;

  static void attach(GoRouter router) {
    _router = router;
    final pending = pendingRoute;
    if (pending != null) {
      pendingRoute = null;
      try {
        router.go(pending);
      } catch (_) {}
    }
  }

  static void detach(GoRouter router) {
    if (identical(_router, router)) _router = null;
  }

  static GoRouter? get router => _router;

  /// Routes a widget tap URI. Returns the resolved route or null.
  static String? handleTap(Uri? uri) {
    final route = resolveWidgetRoute(uri);
    if (route == null) return null;
    final router = _router;
    if (router == null) {
      pendingRoute = route; // app not up yet — deliver on attach
      return route;
    }
    try {
      router.go(route);
    } catch (_) {}
    return route;
  }
}
