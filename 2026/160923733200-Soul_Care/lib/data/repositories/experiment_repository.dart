import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/models.dart';

class ExperimentRepository {
  Future<Result<List<Experiment>>> getAll() async {
    try {
      final out = <Experiment>[];
      for (final key in LocalDatabase.experimentsBox.keys) {
        final raw = LocalDatabase.experimentsBox.get(key);
        if (raw == null) continue;
        out.add(Experiment.fromJson(Map<String, dynamic>.from(raw as Map)));
      }
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Could not load experiments.',
          originalError: e));
    }
  }

  Future<Result<Experiment?>> getById(String id) async {
    try {
      final raw = LocalDatabase.experimentsBox.get(id);
      if (raw == null) return const Success(null);
      return Success(
          Experiment.fromJson(Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load experiment.',
          originalError: e));
    }
  }

  Future<Result<Experiment>> save(Experiment exp) async {
    try {
      if (exp.title.trim().isEmpty) {
        return const Failure(
            ValidationException('Experiment title is required.'));
      }
      if (exp.durationDays < 1 || exp.durationDays > 365) {
        return const Failure(ValidationException(
            'Duration must be between 1 and 365 days.'));
      }
      await LocalDatabase.experimentsBox.put(exp.id, exp.toJson());
      return Success(exp);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not save experiment. Please try again.',
          originalError: e));
    }
  }

  Future<Result<void>> delete(String id) async {
    try {
      await LocalDatabase.experimentsBox.delete(id);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete experiment.',
          originalError: e));
    }
  }
}
