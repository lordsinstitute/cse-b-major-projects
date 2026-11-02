import 'package:flutter/material.dart';

import '../../data/models/health_snapshot.dart';
import '../../data/repositories/health_snapshot_repository.dart';

/// Health snapshot state: one manual record, editable sections.
class HealthSnapshotProvider extends ChangeNotifier {
  final HealthSnapshotRepository _repo;

  HealthSnapshot? _snapshot;
  bool _loading = false;
  String? _error;

  HealthSnapshotProvider(this._repo);

  HealthSnapshot? get snapshot => _snapshot;
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => _snapshot == null || _snapshot!.isEmpty;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.load();
    res.fold(
      onSuccess: (s) => _snapshot = s,
      onFailure: (e) => _error = e.message,
    );
    _loading = false;
    notifyListeners();
  }

  Future<bool> save(HealthSnapshot next) async {
    final res = await _repo.save(next);
    return res.fold(
      onSuccess: (s) {
        _snapshot = s;
        _error = null;
        notifyListeners();
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> clear() async {
    final res = await _repo.clear();
    return res.fold(
      onSuccess: (_) {
        _snapshot = HealthSnapshot.empty();
        notifyListeners();
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }
}
