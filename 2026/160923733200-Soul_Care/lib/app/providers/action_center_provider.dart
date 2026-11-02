import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../core/utils/utils.dart';

/// Dismissed action-center items, scoped per calendar day so a dismissed
/// suggestion returns tomorrow instead of nagging harder. An ignored
/// reminder is NEVER escalated — dismissal is the end of it for today.
class ActionCenterProvider extends ChangeNotifier {
  static const String _boxName = 'action_center';
  static const String _keyPrefix = 'dismissed_';

  Set<String> _dismissed = {};
  String _loadedDay = '';

  Set<String> get dismissed => Set.unmodifiable(_dismissed);

  static String _todayKey() =>
      formatDateForStorage(DateTime.now());

  Future<void> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  Future<void> loadToday() async {
    try {
      await _box();
      final today = _todayKey();
      _loadedDay = today;
      final raw = Hive.box(_boxName).get('$_keyPrefix$today');
      _dismissed = raw is List
          ? raw.map((e) => e.toString()).toSet()
          : <String>{};
    } catch (_) {
      _dismissed = {};
    }
    notifyListeners();
  }

  Future<void> dismiss(String dismissKey) async {
    _dismissed.add(dismissKey);
    notifyListeners();
    try {
      await _box();
      final today = _loadedDay.isEmpty ? _todayKey() : _loadedDay;
      await Hive.box(_boxName)
          .put('$_keyPrefix$today', _dismissed.toList());
    } catch (_) {}
  }
}
