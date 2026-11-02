import 'package:flutter/material.dart';

import '../../data/models/game_stats.dart';
import '../../data/repositories/game_stats_repository.dart';

/// Game ids + best-score direction per game.
class GameMeta {
  final String id;
  final bool higherBetter;
  final String scoreUnit;

  const GameMeta(this.id,
      {required this.higherBetter, this.scoreUnit = ''});
}

const gameMetas = <GameMeta>[
  GameMeta('memory', higherBetter: true, scoreUnit: ' pts'),
  GameMeta('reaction', higherBetter: false, scoreUnit: ' ms'),
  GameMeta('sequence', higherBetter: true, scoreUnit: ' pts'),
  GameMeta('breathing', higherBetter: true, scoreUnit: ' cycles'),
  GameMeta('scramble', higherBetter: true, scoreUnit: ' pts'),
  GameMeta('color', higherBetter: true, scoreUnit: ' pts'),
  GameMeta('echo', higherBetter: true, scoreUnit: ' pts'),
  GameMeta('bubbles', higherBetter: true, scoreUnit: ' pts'),
];

/// Hub state: stats for all games. Provided locally inside /games.
class GamesProvider extends ChangeNotifier {
  final GameStatsRepository _repo;
  Map<String, GameStats> _stats = {};
  bool _loading = true;

  GamesProvider({GameStatsRepository? repo})
      : _repo = repo ?? GameStatsRepository() {
    refresh();
  }

  bool get loading => _loading;

  GameStats statsFor(String gameId) =>
      _stats[gameId] ?? GameStats(gameId: gameId);

  Future<void> refresh() async {
    final res =
        await _repo.getAll([for (final m in gameMetas) m.id]);
    res.fold(
      onSuccess: (map) => _stats = map,
      onFailure: (_) {},
    );
    _loading = false;
    notifyListeners();
  }

  Future<void> record(String gameId, int score) async {
    final meta = gameMetas.firstWhere((m) => m.id == gameId);
    final res = await _repo.recordPlay(gameId, score,
        higherBetter: meta.higherBetter);
    res.fold(
      onSuccess: (s) {
        _stats[gameId] = s;
        notifyListeners();
      },
      onFailure: (_) {},
    );
  }
}
