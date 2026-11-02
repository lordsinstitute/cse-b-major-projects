import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';

/// Celebrated-milestone ids. Milestones themselves are always derived from
/// real data (see the engine); this only remembers which unlocks the user
/// has already seen celebrated, so each is celebrated exactly once.
class MilestoneRepository {
  static const _key = 'celebrated_ids';

  Future<Result<Set<String>>> getCelebrated() async {
    try {
      final raw = LocalDatabase.milestoneBox.get(_key);
      if (raw == null) return const Success({});
      final list = (raw as List).map((e) => e.toString()).toSet();
      return Success(Set<String>.from(list));
    } catch (e) {
      return Failure(PersistenceException(
          'Could not load milestone state.', originalError: e));
    }
  }

  Future<Result<void>> saveCelebrated(Set<String> ids) async {
    try {
      await LocalDatabase.milestoneBox.put(_key, ids.toList());
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not save milestone state.', originalError: e));
    }
  }
}
