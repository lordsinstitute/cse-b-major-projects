import 'package:flutter/foundation.dart';

import 'ai_models.dart';
import 'ai_provider.dart';

/// Connection lifecycle with a short status cache: checks run on screen
/// open, on manual request, and before generation when stale — never on a
/// poll loop. Works against any [AiProvider]; switching providers rebinds
/// the manager without touching history or settings.
class AiConnectionManager extends ChangeNotifier {
  AiProvider _provider;
  final Duration Function() _ttlOf;

  AiConnectionResult? _state;
  bool _checking = false;
  int _requestCount = 0;
  String? _lastError;

  AiConnectionManager({
    required AiProvider provider,
    required Duration Function() ttlOf,
  })  : _provider = provider,
        _ttlOf = ttlOf;

  void rebind(AiProvider provider) {
    _provider = provider;
    _state = null;
    _lastError = null;
    notifyListeners();
  }

  AiConnectionResult? get state => _state;
  bool get checking => _checking;
  int get requestCount => _requestCount;
  String? get lastError => _lastError;

  bool get isConnected => _state?.ok ?? false;

  bool get isStale {
    final s = _state;
    if (s == null) return true;
    return DateTime.now().difference(s.checkedAt) > _ttlOf();
  }

  /// Cached unless [force] or stale.
  Future<AiConnectionResult> status({bool force = false}) async {
    if (!force && !isStale && _state != null) return _state!;
    return checkNow();
  }

  Future<AiConnectionResult> checkNow() async {
    if (_checking) {
      return _state ??
          AiConnectionResult(
              ok: false, checkedAt: DateTime.now());
    }
    _checking = true;
    notifyListeners();
    try {
      _state = await _provider.testConnection();
      _lastError = _state!.ok ? null : _state!.error;
      return _state!;
    } catch (_) {
      _lastError = AiErrors.serverUnreachable;
      _state = AiConnectionResult(
          ok: false,
          checkedAt: DateTime.now(),
          error: AiErrors.serverUnreachable);
      return _state!;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  void noteRequest() {
    _requestCount++;
    notifyListeners();
  }

  void noteError(String e) {
    _lastError = e;
    notifyListeners();
  }
}
