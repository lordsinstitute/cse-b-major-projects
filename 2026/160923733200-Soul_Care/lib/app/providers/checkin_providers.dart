import 'package:flutter/material.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/utils.dart';
import '../../data/models/checkins.dart';
import '../../data/models/models.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/daily_health_repository.dart';

/// Morning state. Saving also prefills today's sleep hours when nothing
/// was logged yet — never overwrites an existing value.
class MorningProvider extends ChangeNotifier {
  final MorningRepository _repo;
  final DailyHealthRepository? _dailyRepo;

  MorningCheckIn? _today;
  bool _loading = false;
  String? _error;

  MorningProvider(this._repo, {DailyHealthRepository? dailyRepo})
      : _dailyRepo = dailyRepo;

  MorningCheckIn? get today => _today;
  bool get loading => _loading;
  String? get error => _error;
  bool get done => _today != null;

  String get todayKey => formatDateForStorage(DateTime.now());

  Future<void> loadToday() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.getByDate(todayKey);
    res.fold(
      onSuccess: (c) => _today = c,
      onFailure: (e) => _error = e.message,
    );
    _loading = false;
    notifyListeners();
  }

  Future<bool> save(MorningCheckIn checkIn) async {
    final res = await _repo.save(checkIn);
    return res.fold(
      onSuccess: (c) async {
        _today = c;
        _error = null;
        notifyListeners();
        // Prefill today's sleep only when unlogged.
        final dailyRepo = _dailyRepo;
        if (dailyRepo != null && c.sleepHours > 0) {
          final existing = await dailyRepo.getByDate(c.date);
          existing.fold(
            onSuccess: (entry) async {
              if (entry == null || entry.sleepHours <= 0) {
                final base =
                    entry ?? DailyHealthEntry(date: c.date);
                await dailyRepo.save(
                    base.copyWith(sleepHours: c.sleepHours));
              }
            },
            onFailure: (_) {},
          );
        }
        return true;
      },
      onFailure: (e) {
        _error = e is ValidationException
            ? e.message
            : 'Could not save. Please try again.';
        notifyListeners();
        return false;
      },
    );
  }
}

/// Evening reflection state (editable re-saves).
class EveningProvider extends ChangeNotifier {
  final EveningRepository _repo;

  EveningReflection? _today;
  bool _loading = false;
  String? _error;

  EveningProvider(this._repo);

  EveningReflection? get today => _today;
  bool get loading => _loading;
  String? get error => _error;
  bool get done => _today != null;

  String get todayKey => formatDateForStorage(DateTime.now());

  Future<void> loadToday() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.getByDate(todayKey);
    res.fold(
      onSuccess: (r) => _today = r,
      onFailure: (e) => _error = e.message,
    );
    _loading = false;
    notifyListeners();
  }

  Future<bool> save(EveningReflection reflection) async {
    final res = await _repo.save(reflection);
    return res.fold(
      onSuccess: (r) {
        _today = r;
        _error = null;
        notifyListeners();
        return true;
      },
      onFailure: (e) {
        _error = e is ValidationException
            ? e.message
            : 'Could not save. Please try again.';
        notifyListeners();
        return false;
      },
    );
  }
}
