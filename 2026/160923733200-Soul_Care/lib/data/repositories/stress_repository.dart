import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/models.dart';

class StressRepository {
  Future<Result<List<StressEntry>>> getByDate(String date) async {
    try {
      final out = <StressEntry>[];
      for (final key in LocalDatabase.stressBox.keys) {
        final raw = LocalDatabase.stressBox.get(key);
        if (raw == null) continue;
        final e = StressEntry.fromJson(Map<String, dynamic>.from(raw as Map));
        if (e.date == date) out.add(e);
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return Success(out);
    } catch (e) {
      return Failure(
          PersistenceException('Could not load check-ins.', originalError: e));
    }
  }

  Future<Result<List<StressEntry>>> getRange(
      DateTime from, DateTime to) async {
    try {
      final start = DateTime(from.year, from.month, from.day);
      final end = DateTime(to.year, to.month, to.day);
      final out = <StressEntry>[];
      for (final key in LocalDatabase.stressBox.keys) {
        final raw = LocalDatabase.stressBox.get(key);
        if (raw == null) continue;
        final e = StressEntry.fromJson(Map<String, dynamic>.from(raw as Map));
        final d = DateTime.tryParse(e.date);
        if (d == null) continue;
        final day = DateTime(d.year, d.month, d.day);
        if (!day.isBefore(start) && !day.isAfter(end)) out.add(e);
      }
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return Success(out);
    } catch (e) {
      return Failure(
          PersistenceException('Could not load check-ins.', originalError: e));
    }
  }

  Future<Result<StressEntry>> save(StressEntry entry) async {
    try {
      if (entry.id.isEmpty) {
        return const Failure(ValidationException('Entry id is required.'));
      }
      await LocalDatabase.stressBox.put(entry.id, entry.toJson());
      return Success(entry);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not save your check-in. Please try again.',
          originalError: e));
    }
  }

  Future<Result<void>> delete(String id) async {
    try {
      await LocalDatabase.stressBox.delete(id);
      return const Success(null);
    } catch (e) {
      return Failure(
          PersistenceException('Could not delete check-in.', originalError: e));
    }
  }
}
