import 'package:flutter/material.dart';

import '../../data/models/user_profile.dart';
import '../../data/repositories/profile_repository.dart';

/// Personal profile state. Everything optional — an unset profile is a
/// fully valid state and the app never blocks on it.
class ProfileProvider extends ChangeNotifier {
  final ProfileRepository _repo;
  UserProfile? _profile;
  bool _loading = false;
  String? _error;

  ProfileProvider(this._repo);

  UserProfile? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  bool get isUnset => _profile == null || _profile!.isUnset;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.load();
    res.fold(
      onSuccess: (p) => _profile = p,
      onFailure: (e) => _error = e.message,
    );
    _loading = false;
    notifyListeners();
  }

  Future<bool> save(UserProfile next) async {
    final res = await _repo.save(next);
    return res.fold(
      onSuccess: (p) {
        _profile = p;
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
}
