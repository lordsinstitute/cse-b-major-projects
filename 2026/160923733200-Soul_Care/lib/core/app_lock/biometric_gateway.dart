import 'package:local_auth/local_auth.dart';

/// Test seam for biometrics. Production uses the device sensor;
/// tests inject fakes (available/unavailable, success/failure).
abstract class BiometricGateway {
  Future<bool> canCheck();
  Future<bool> authenticate(String reason);
}

class LocalAuthGateway implements BiometricGateway {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> canCheck() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Always-unavailable gateway (devices without biometrics, and the
/// default in widget tests where plugins have no implementation).
class UnavailableBiometricGateway implements BiometricGateway {
  @override
  Future<bool> canCheck() async => false;

  @override
  Future<bool> authenticate(String reason) async => false;
}
