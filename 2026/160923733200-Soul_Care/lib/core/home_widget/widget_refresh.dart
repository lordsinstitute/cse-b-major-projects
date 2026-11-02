import 'package:home_widget/home_widget.dart';

import 'widget_data.dart';

/// Writes widget data + requests a native refresh. Every plugin call is
/// guarded: if widgets are unavailable (wrong platform, tests, no widget
/// installed), the main app is completely unaffected.
class WidgetRefresh {
  /// Visible for tests: write prefs without touching the plugin.
  static Future<void> Function(String key, dynamic value)? writerOverride;

  /// Visible for tests: observe refresh requests without the plugin.
  static Future<void> Function()? updateOverride;

  static const String androidProviderName = 'SoulCareWidgetProvider';

  static Future<void> refresh({
    required int score,
    required int done,
    required int total,
    required String dateKey,
    required String greeting,
  }) async {
    try {
      final payload = buildWidgetPayload(
        score: score,
        done: done,
        total: total,
        dateKey: dateKey,
        greeting: greeting,
      );
      final writer = writerOverride ?? _write;
      for (final entry in payload.entries) {
        await writer(entry.key, entry.value);
      }
      final update = updateOverride ?? _update;
      await update();
    } catch (_) {
      // Widget unavailable — app continues normally (fallback).
    }
  }

  static Future<void> _write(String key, dynamic value) async {
    try {
      if (value is int) {
        await HomeWidget.saveWidgetData<int>(key, value);
      } else {
        await HomeWidget.saveWidgetData<String>(key, '$value');
      }
    } catch (_) {}
  }

  static Future<void> _update() async {
    try {
      await HomeWidget.updateWidget(
          androidName: androidProviderName);
    } catch (_) {}
  }
}
