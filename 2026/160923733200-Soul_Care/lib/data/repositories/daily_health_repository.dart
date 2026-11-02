import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/models.dart';

/// Daily health CRUD. UI must go through this, never touch Hive directly.
class DailyHealthRepository {

  Future<Result<DailyHealthEntry?>> getByDate(String date) async {
    try {
      final raw = LocalDatabase.dailyBox.get(date);
      if (raw == null) return const Success(null);
      return Success(
          DailyHealthEntry.fromJson(Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load entry for $date.',
          originalError: e));
    }
  }

  Future<Result<DailyHealthEntry>> save(DailyHealthEntry entry) async {
    try {
      if (entry.date.isEmpty) {
        return const Failure(
            ValidationException('Date is required.'));
      }
      await LocalDatabase.dailyBox.put(entry.date, entry.toJson());
      return Success(entry);
    } catch (e) {
      return Failure(PersistenceException('Could not save your entry. Your data was not lost — please try again.',
          originalError: e));
    }
  }

  Future<Result<List<DailyHealthEntry>>> getRange(
      DateTime from, DateTime to) async {
    try {
      final entries = <DailyHealthEntry>[];
      for (final key in LocalDatabase.dailyBox.keys) {
        final raw = LocalDatabase.dailyBox.get(key);
        if (raw == null) continue;
        final entry =
            DailyHealthEntry.fromJson(Map<String, dynamic>.from(raw as Map));
        final d = DateTime.tryParse(entry.date);
        if (d == null) continue;
        if (!d.isBefore(DateTime(from.year, from.month, from.day)) &&
            !d.isAfter(DateTime(to.year, to.month, to.day))) {
          entries.add(entry);
        }
      }
      entries.sort((a, b) => a.date.compareTo(b.date));
      return Success(entries);
    } catch (e) {
      return Failure(
          PersistenceException('Could not load entries.', originalError: e));
    }
  }

  Future<Result<void>> delete(String date) async {
    try {
      await LocalDatabase.dailyBox.delete(date);
      return const Success(null);
    } catch (e) {
      return Failure(
          PersistenceException('Could not delete entry.', originalError: e));
    }
  }
}
