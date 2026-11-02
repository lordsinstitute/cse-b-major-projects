import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/checkins.dart';

/// Morning check-ins: exactly one record per date (upsert by date key).
class MorningRepository {
  Future<Result<MorningCheckIn?>> getByDate(String date) async {
    try {
      final raw = LocalDatabase.morningBox.get(date);
      if (raw == null) return const Success(null);
      return Success(
          MorningCheckIn.fromJson(Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load the check-in.',
          originalError: e));
    }
  }

  Future<Result<MorningCheckIn>> save(MorningCheckIn checkIn) async {
    try {
      if (checkIn.date.isEmpty) {
        return const Failure(ValidationException('Date is required.'));
      }
      final cleaned = checkIn.copyWith(
        sleepHours: checkIn.sleepHours.clamp(0.0, 24.0),
        updatedAt: DateTime.now(),
      );
      await LocalDatabase.morningBox.put(checkIn.date, cleaned.toJson());
      return Success(cleaned);
    } catch (e) {
      return Failure(PersistenceException('Could not save the check-in.',
          originalError: e));
    }
  }
}

/// Evening reflections: exactly one record per date, editable via re-save.
class EveningRepository {
  Future<Result<List<EveningReflection>>> getAll() async {
    try {
      final out = <EveningReflection>[];
      for (final key in LocalDatabase.eveningBox.keys) {
        final raw = LocalDatabase.eveningBox.get(key);
        if (raw == null) continue;
        out.add(EveningReflection.fromJson(
            Map<String, dynamic>.from(raw as Map)));
      }
      out.sort((a, b) => a.date.compareTo(b.date));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not load reflections.', originalError: e));
    }
  }

  Future<Result<EveningReflection?>> getByDate(String date) async {
    try {
      final raw = LocalDatabase.eveningBox.get(date);
      if (raw == null) return const Success(null);
      return Success(EveningReflection.fromJson(
          Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load the reflection.',
          originalError: e));
    }
  }

  Future<Result<EveningReflection>> save(EveningReflection reflection) async {
    try {
      if (reflection.date.isEmpty) {
        return const Failure(ValidationException('Date is required.'));
      }
      final cleaned = reflection.copyWith(updatedAt: DateTime.now());
      await LocalDatabase.eveningBox.put(reflection.date, cleaned.toJson());
      return Success(cleaned);
    } catch (e) {
      return Failure(PersistenceException('Could not save the reflection.',
          originalError: e));
    }
  }
}
