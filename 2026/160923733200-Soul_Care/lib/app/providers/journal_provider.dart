import 'package:flutter/material.dart';

import '../../core/utils/utils.dart';
import '../../data/models/journal.dart';
import '../../data/repositories/journal_repository.dart';

/// Journal state: list, local search + filters, CRUD. Bodies never leave
/// the device and are never written to logs.
class JournalProvider extends ChangeNotifier {
  final JournalRepository _repo;

  List<JournalEntry> _all = [];
  String _query = '';
  final Set<String> _tagFilters = {};
  String? _dateFilter;
  int? _moodFilter;
  bool _loading = false;
  String? _error;

  JournalProvider(this._repo);

  List<JournalEntry> get entries => _filtered();
  List<JournalEntry> get all => List.unmodifiable(_all);
  String get query => _query;
  Set<String> get tagFilters => Set.unmodifiable(_tagFilters);
  String? get dateFilter => _dateFilter;
  int? get moodFilter => _moodFilter;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.getAll();
    res.fold(
      onSuccess: (list) => _all = list,
      onFailure: (e) => _error = e.message,
    );
    _loading = false;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void toggleTag(String tag) {
    if (_tagFilters.contains(tag)) {
      _tagFilters.remove(tag);
    } else {
      _tagFilters.add(tag);
    }
    notifyListeners();
  }

  void setDateFilter(String? date) {
    _dateFilter = date;
    notifyListeners();
  }

  void setMoodFilter(int? mood) {
    _moodFilter = mood;
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _tagFilters.clear();
    _dateFilter = null;
    _moodFilter = null;
    notifyListeners();
  }

  List<JournalEntry> _filtered() {
    final q = _query.trim().toLowerCase();
    return _all.where((e) {
      if (_tagFilters.isNotEmpty &&
          !e.tags.any((t) => _tagFilters.contains(t))) {
        return false;
      }
      if (_dateFilter != null && e.date != _dateFilter) return false;
      if (_moodFilter != null && e.mood != _moodFilter) return false;
      if (q.isEmpty) return true;
      final hay = '${e.title ?? ''} ${e.body} ${e.tags.join(' ')}'
          .toLowerCase();
      return q.split(RegExp(r'\s+')).every((w) => hay.contains(w));
    }).toList();
  }

  Future<JournalEntry?> save(JournalEntry entry) async {
    final res = await _repo.save(entry);
    return res.fold(
      onSuccess: (saved) {
        final i = _all.indexWhere((e) => e.id == saved.id);
        if (i >= 0) {
          _all[i] = saved;
        } else {
          _all = [saved, ..._all];
          _all.sort((a, b) {
            final d = b.date.compareTo(a.date);
            return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
          });
        }
        _error = null;
        notifyListeners();
        return saved;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return null;
      },
    );
  }

  Future<bool> remove(String id) async {
    final res = await _repo.delete(id);
    return res.fold(
      onSuccess: (_) {
        _all.removeWhere((e) => e.id == id);
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

  static String todayKey() => formatDateForStorage(DateTime.now());
}
