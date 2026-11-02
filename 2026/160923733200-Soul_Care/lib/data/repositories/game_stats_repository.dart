import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/game_stats.dart';

/// Game stats repository: one record per game id.
/// [higherBetter] decides the best-score direction per game
/// (e.g. reaction time is lower-better).
class GameStatsRepository {
  const GameStatsRepository();  Future<Result<GameStats>> getStats(String gameId) async {
    try {
      final raw = LocalDatabase.gameStatsBox.get(gameId);
      if (raw == null) return Success(GameStats(gameId: gameId));
      return Success(
          GameStats.fromJson(Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load game stats.',
          originalError: e));
    }
  }

  Future<Result<Map<String, GameStats>>> getAll(List<String> gameIds) async {
    try {
      final out = <String, GameStats>{};
      for (final id in gameIds) {
        final res = await getStats(id);
        res.fold(
          onSuccess: (s) => out[id] = s,
          onFailure: (_) => out[id] = GameStats(gameId: id),
        );
      }
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Could not load game stats.',
          originalError: e));
    }
  }

  Future<Result<GameStats>> recordPlay(String gameId, int score,
      {required bool higherBetter}) async {
    try {
      final current = (await getStats(gameId)).fold(
        onSuccess: (s) => s,
        onFailure: (_) => GameStats(gameId: gameId),
      );
      final best = current.bestScore == null
          ? score
          : higherBetter
              ? (score > current.bestScore! ? score : current.bestScore!)
              : (score < current.bestScore! ? score : current.bestScore!);
      final updated = GameStats(
        gameId: gameId,
        playCount: current.playCount + 1,
        bestScore: best,
        recentScore: score,
        updatedAt: DateTime.now(),
      );
      await LocalDatabase.gameStatsBox.put(gameId, updated.toJson());
      return Success(updated);
    } catch (e) {
      return Failure(PersistenceException('Could not save game stats.',
          originalError: e));
    }
  }
}
