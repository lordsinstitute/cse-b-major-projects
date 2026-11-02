import 'package:flutter/material.dart';

import '../../core/health/health_gateway.dart';
import '../../data/models/health_import.dart';
import '../../data/repositories/health_import_repository.dart';

/// Connection status for the optional platform integration.
enum HealthLinkStatus { unknown, unsupported, denied, connected }

/// Optional Health Connect integration. Read-only, explicit, local.
/// The app stays fully functional at every other status.
class HealthImportProvider extends ChangeNotifier {
  final HealthImportRepository _repo;
  final HealthGateway _gateway;

  HealthLinkStatus _status = HealthLinkStatus.unknown;
  Map<String, ImportedDay> _days = {};
  int _totalPoints = 0;
  DateTime? _lastSync;
  bool _busy = false;
  String? _error;

  HealthImportProvider(this._repo, {HealthGateway? gateway})
      : _gateway = gateway ?? HealthConnectGateway();

  HealthLinkStatus get status => _status;
  Map<String, ImportedDay> get days => Map.unmodifiable(_days);
  int get totalPoints => _totalPoints;
  DateTime? get lastSync => _lastSync;
  bool get busy => _busy;
  String? get error => _error;

  ImportedDay? dayFor(String dateKey) => _days[dateKey];

  Future<void> refresh() async {
    _busy = true;
    notifyListeners();
    try {
      final connected = await _repo.isConnected();
      if (!connected) {
        _status = HealthLinkStatus.unknown;
        _days = {};
        _totalPoints = 0;
        _lastSync = null;
        return;
      }
      if (!await _gateway.isAvailable()) {
        _status = HealthLinkStatus.unsupported;
        return;
      }
      if (!await _gateway.hasAccess()) {
        _status = HealthLinkStatus.denied;
        return;
      }
      _status = HealthLinkStatus.connected;
      await _reloadLocal();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Explicit user action: check platform → request → sync.
  /// Denial leaves everything untouched and functional.
  Future<bool> connect() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (!await _gateway.isAvailable()) {
        _status = HealthLinkStatus.unsupported;
        _error = 'Health data integration is unavailable on this device.';
        return false;
      }
      final granted = await _gateway.requestAccess();
      if (!granted || !await _gateway.hasAccess()) {
        _status = HealthLinkStatus.denied;
        _error =
            'Permission was not granted. Manual logging keeps working normally.';
        return false;
      }
      await _repo.setConnected(true);
      final synced = await sync();
      if (synced) _status = HealthLinkStatus.connected;
      return synced;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Pulls the last 14 days (inside the platform's 30-day window).
  /// Returns true on success. Repeated syncs add only new records.
  Future<bool> sync() async {
    try {
      final now = DateTime.now();
      final points = await _gateway.fetch(
        from: now.subtract(const Duration(days: 14)),
        to: now,
      );
      final saved = await _repo.saveAll(points);
      return saved.fold(
        onSuccess: (_) {
          _error = null;
          return true;
        },
        onFailure: (e) {
          _error = e.message;
          return false;
        },
      );
    } catch (_) {
      _error = 'Sync failed. Your manual logs are unaffected.';
      return false;
    } finally {
      await _reloadLocal();
    }
  }

  /// Disconnects: revokes platform permission and removes local
  /// imported copies. Manual logs are never touched.
  Future<void> disconnect() async {
    try {
      await _gateway.revokeAccess();
    } catch (_) {}
    await _repo.clearImported();
    _status = HealthLinkStatus.unknown;
    _days = {};
    _totalPoints = 0;
    _lastSync = null;
    _error = null;
    notifyListeners();
  }

  Future<void> _reloadLocal() async {
    final days = await _repo.daysByDate();
    final all = await _repo.getAll();
    final synced = await _repo.lastSyncedAt();
    days.fold(onSuccess: (m) => _days = m, onFailure: (_) {});
    all.fold(onSuccess: (l) => _totalPoints = l.length,
        onFailure: (_) {});
    _lastSync = synced;
  }
}
