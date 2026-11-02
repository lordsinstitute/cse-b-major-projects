/// Per-game persisted stats: play count, best score, recent score.
/// Best direction (higher/lower wins) is decided by the game, not storage.
class GameStats {
  final String gameId;
  final int playCount;
  final int? bestScore;
  final int? recentScore;
  final DateTime? updatedAt;

  const GameStats({
    required this.gameId,
    this.playCount = 0,
    this.bestScore,
    this.recentScore,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'playCount': playCount,
        'bestScore': bestScore,
        'recentScore': recentScore,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory GameStats.fromJson(Map<String, dynamic> json) {
    return GameStats(
      gameId: json['gameId'] as String,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      bestScore: (json['bestScore'] as num?)?.toInt(),
      recentScore: (json['recentScore'] as num?)?.toInt(),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.tryParse(json['updatedAt'] as String),
    );
  }
}
