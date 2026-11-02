import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/core/home_widget/widget_data.dart';
import 'package:soul_care/core/home_widget/widget_refresh.dart';

GoRouter _testRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const SizedBox()),
        GoRoute(path: '/today', builder: (c, s) => const SizedBox()),
        GoRoute(
            path: '/home/morning',
            builder: (c, s) => const SizedBox()),
        GoRoute(path: '/home', builder: (c, s) => const SizedBox()),
      ],
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    WidgetLink.pendingRoute = null;
    WidgetRefresh.writerOverride = null;
    WidgetRefresh.updateOverride = null;
  });

  group('payload', () {
    test('builds exact plugin keys with clamping + defaults', () {
      final p = buildWidgetPayload(
        score: 74,
        done: 3,
        total: 5,
        dateKey: '2026-09-30',
        greeting: 'Good evening',
      );
      expect(p[WidgetKeys.score], 74);
      expect(p[WidgetKeys.done], 3);
      expect(p[WidgetKeys.total], 5);
      expect(p[WidgetKeys.date], '2026-09-30');
      expect(p[WidgetKeys.greeting], 'Good evening');

      final clamped = buildWidgetPayload(
          score: 140, done: 9, total: 5, dateKey: 'x', greeting: 'y');
      expect(clamped[WidgetKeys.score], 100);
      expect(clamped[WidgetKeys.done], 5);

      final fallback = buildWidgetPayload(
          score: 0, done: 0, total: 0, dateKey: 'x', greeting: 'y');
      expect(fallback[WidgetKeys.total], 5);
    });

    test('updated values replace stale ones deterministically', () {
      final a = buildWidgetPayload(
          score: 60, done: 1, total: 5, dateKey: 'd1', greeting: 'g');
      final b = buildWidgetPayload(
          score: 82, done: 4, total: 5, dateKey: 'd2', greeting: 'g');
      expect(a, isNot(b));
      expect(b[WidgetKeys.score], 82);
      expect(b[WidgetKeys.done], 4);
    });
  });

  group('tap routing', () {
    test('each action resolves; garbage resolves to null', () {
      expect(resolveWidgetRoute(Uri.parse('soulcare://widget?action=today')),
          '/today');
      expect(resolveWidgetRoute(Uri.parse('soulcare://widget?action=water')),
          '/today');
      expect(resolveWidgetRoute(Uri.parse('soulcare://widget?action=mood')),
          '/today');
      expect(resolveWidgetRoute(
          Uri.parse('soulcare://widget?action=checkin')),
          '/home/morning');
      expect(resolveWidgetRoute(Uri.parse('soulcare://widget?action=score')),
          '/home');
      expect(
          resolveWidgetRoute(Uri.parse('soulcare://widget?action=nuke')),
          isNull);
      expect(resolveWidgetRoute(Uri.parse('soulcare://widget')),
          isNull);
      expect(resolveWidgetRoute(null), isNull);
      expect(resolveWidgetRoute(Uri.tryParse('not a uri %%%')), isNull);
    });

    test('no attached app stores pending route (app not running)', () {
      WidgetLink.pendingRoute = null;
      expect(
          WidgetLink.handleTap(
              Uri.parse('soulcare://widget?action=water')),
          '/today');
      expect(WidgetLink.pendingRoute, '/today');
    });

    test('attach delivers pending; detach clears', () {
      final router = _testRouter();
      WidgetLink.pendingRoute = '/today';
      WidgetLink.attach(router);
      expect(WidgetLink.pendingRoute, isNull);
      expect(WidgetLink.router, isNotNull);
      WidgetLink.detach(router);
      expect(WidgetLink.router, isNull);
    });
  });

  group('refresh service', () {
    test('saves all keys then requests update', () async {
      final written = <String, dynamic>{};
      var updates = 0;
      WidgetRefresh.writerOverride = (k, v) async {
        written[k] = v;
      };
      WidgetRefresh.updateOverride = () async {
        updates++;
      };
      await WidgetRefresh.refresh(
          score: 74,
          done: 3,
          total: 5,
          dateKey: '2026-09-30',
          greeting: 'Hi');
      expect(written[WidgetKeys.score], 74);
      expect(written[WidgetKeys.done], 3);
      expect(written[WidgetKeys.total], 5);
      expect(written[WidgetKeys.date], '2026-09-30');
      expect(updates, 1);
    });

    test('plugin failures never escape (fallback: app unaffected)',
        () async {
      WidgetRefresh.writerOverride = (k, v) async {
        throw Exception('no plugin');
      };
      WidgetRefresh.updateOverride = () async {
        throw Exception('no provider');
      };
      await WidgetRefresh.refresh(
          score: 1, done: 1, total: 5, dateKey: 'x', greeting: 'y');
      // Reaching here without throwing IS the assertion.
    });

    test('widget data persists for offline display when app closed',
        () async {
      final written = <String, dynamic>{};
      WidgetRefresh.writerOverride = (k, v) async {
        written[k] = v;
      };
      WidgetRefresh.updateOverride = () async {};
      await WidgetRefresh.refresh(
          score: 74,
          done: 3,
          total: 5,
          dateKey: '2026-09-30',
          greeting: 'Hi');
      // What the native side reads later is exactly what was saved.
      expect(written.length, 5);
      expect(written.values.every((v) => v is int || v is String),
          isTrue);
    });
  });
}
