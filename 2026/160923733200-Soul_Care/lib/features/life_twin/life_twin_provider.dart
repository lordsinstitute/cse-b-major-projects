import 'package:flutter/material.dart';

import '../../data/models/checkins.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/stress_repository.dart';
import 'life_twin_engine.dart';

/// Life Twin state holder. All calculations happen locally on-device from
/// logged records; nothing leaves the device. Read-only: never writes.
class LifeTwinProvider extends ChangeNotifier {
  final DailyHealthRepository _dailyRepo;
  final StressRepository _stressRepo;
  final MorningRepository _morningRepo;
  final EveningRepository _eveningRepo;

  LifeTwinProvider({
    DailyHealthRepository? dailyRepo,
    StressRepository? stressRepo,
    MorningRepository? morningRepo,
    EveningRepository? eveningRepo,
  })  : _dailyRepo = dailyRepo ?? DailyHealthRepository(),
        _stressRepo = stressRepo ?? StressRepository(),
        _morningRepo = morningRepo ?? MorningRepository(),
        _eveningRepo = eveningRepo ?? EveningRepository();

  int _rangeDays = 30;
  int get rangeDays => _rangeDays;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  LifeTwinState? _state;
  LifeTwinState? get state => _state;

  Future<void> load({int? rangeDays}) async {
    if (rangeDays != null) _rangeDays = rangeDays;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final from = today.subtract(Duration(days: _rangeDays - 1));
      final prevFrom = from.subtract(Duration(days: _rangeDays));

      final dailyRes = await _dailyRepo.getRange(prevFrom, today);
      final stressRes = await _stressRepo.getRange(prevFrom, today);
      final daily = dailyRes.fold(
        onSuccess: (v) => v,
        onFailure: (_) => <DailyHealthEntry>[],
      );
      final stress = stressRes.fold(
        onSuccess: (v) => v,
        onFailure: (_) => <StressEntry>[],
      );

      final dailyByDate = {for (final e in daily) e.date: e};
      final moodsByDate = <String, List<int>>{};
      for (final s in stress) {
        moodsByDate.putIfAbsent(s.date, () => []).add(s.mood.score);
      }

      // Check-ins expose single-date reads only; walk the window locally.
      final totalDays = _rangeDays * 2;
      final morningByDate = <String, MorningCheckIn>{};
      final eveningByDate = <String, EveningReflection>{};
      for (var i = 0; i < totalDays; i++) {
        final d = today.subtract(Duration(days: i));
        final key =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final m = await _morningRepo.getByDate(key);
        m.fold(
          onSuccess: (v) {
            if (v != null) morningByDate[key] = v;
          },
          onFailure: (_) {},
        );
        final e = await _eveningRepo.getByDate(key);
        e.fold(
          onSuccess: (v) {
            if (v != null) eveningByDate[key] = v;
          },
          onFailure: (_) {},
        );
      }

      final currentDates = windowDates(days: _rangeDays, now: now);
      final prevDates = [
        for (var i = _rangeDays * 2 - 1; i >= _rangeDays; i--)
          today.subtract(Duration(days: i)),
      ];
      final current = buildLifeTwinDays(
        windowDays: currentDates,
        dailyByDate: dailyByDate,
        stressMoodsByDate: moodsByDate,
        morningByDate: morningByDate,
        eveningByDate: eveningByDate,
      );
      final previous = buildLifeTwinDays(
        windowDays: prevDates,
        dailyByDate: dailyByDate,
        stressMoodsByDate: moodsByDate,
        morningByDate: morningByDate,
        eveningByDate: eveningByDate,
      );
      _state = summarizeLifeTwin(
        days: current,
        previous: previous,
        daysInWindow: _rangeDays,
      );
    } catch (e) {
      _error = 'Could not build your twin right now. Please try again.';
      _state = null;
    }
    _loading = false;
    notifyListeners();
  }
}
