import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/health_snapshot.dart';

/// Single-record snapshot storage. Manual, local, never uploaded.
class HealthSnapshotRepository {
  const HealthSnapshotRepository();

  static const _key = 'snapshot';

  Future<Result<HealthSnapshot>> load() async {
    try {
      final raw = LocalDatabase.snapshotBox.get(_key);
      if (raw == null) return Success(HealthSnapshot.empty());
      return Success(HealthSnapshot.fromJson(
          Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load the snapshot.',
          originalError: e));
    }
  }

  Future<Result<HealthSnapshot>> save(HealthSnapshot snapshot) async {
    try {
      if (snapshot.bloodGroup != null &&
          !bloodGroups.contains(snapshot.bloodGroup)) {
        return const Failure(
            ValidationException('Unknown blood group.'));
      }
      for (final a in snapshot.allergies) {
        if (!allergySeverities.contains(a.severity)) {
          return const Failure(
              ValidationException('Unknown allergy severity.'));
        }
      }
      final cleaned = HealthSnapshot(
        bloodGroup: snapshot.bloodGroup,
        allergies: snapshot.allergies
            .where((a) => a.name.trim().isNotEmpty)
            .toList(),
        medications: snapshot.medications
            .where((m) => m.name.trim().isNotEmpty)
            .toList(),
        supplements: snapshot.supplements
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        conditions: snapshot.conditions
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        emergencyName: snapshot.emergencyName,
        emergencyPhone: snapshot.emergencyPhone,
        provider: snapshot.provider,
        notes: snapshot.notes,
        createdAt: snapshot.createdAt,
        updatedAt: DateTime.now(),
      );
      await LocalDatabase.snapshotBox.put(_key, cleaned.toJson());
      return Success(cleaned);
    } catch (e) {
      return Failure(PersistenceException('Could not save the snapshot.',
          originalError: e));
    }
  }

  Future<Result<void>> clear() async {
    try {
      await LocalDatabase.snapshotBox.delete(_key);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not clear the snapshot.',
          originalError: e));
    }
  }
}
