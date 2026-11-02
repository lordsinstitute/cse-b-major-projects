import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/journal.dart';

/// Private journal storage. Reads/writes stay on-device; bodies are never
/// logged, only stored. Search is entirely local.
class JournalRepository {
  const JournalRepository();

  Future<Result<List<JournalEntry>>> getAll() async {
    try {
      final out = <JournalEntry>[];
      for (final key in LocalDatabase.journalBox.keys) {
        final raw = LocalDatabase.journalBox.get(key);
        if (raw == null) continue;
        out.add(
            JournalEntry.fromJson(Map<String, dynamic>.from(raw as Map)));
      }
      out.sort((a, b) {
        final d = b.date.compareTo(a.date);
        return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
      });
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Could not load journal.',
          originalError: e));
    }
  }

  Future<Result<JournalEntry?>> getById(String id) async {
    try {
      final raw = LocalDatabase.journalBox.get(id);
      if (raw == null) return const Success(null);
      return Success(
          JournalEntry.fromJson(Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load the entry.',
          originalError: e));
    }
  }

  Future<Result<JournalEntry>> save(JournalEntry entry) async {
    try {
      if (entry.body.trim().isEmpty) {
        return const Failure(
            ValidationException('Write something first.'));
      }
      if (entry.date.isEmpty) {
        return const Failure(ValidationException('Date is required.'));
      }
      final cleaned = entry.copyWith(
        tags: _cleanTags(entry.tags),
        updatedAt: DateTime.now(),
      );
      await LocalDatabase.journalBox.put(entry.id, cleaned.toJson());
      return Success(cleaned);
    } catch (e) {
      return Failure(PersistenceException('Could not save the entry.',
          originalError: e));
    }
  }

  Future<Result<void>> delete(String id) async {
    try {
      await LocalDatabase.journalBox.delete(id);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete the entry.',
          originalError: e));
    }
  }

  /// Local search across title, body, and tags (all words must match).
  /// Optional tag set, date, and mood filters narrow further.
  Future<Result<List<JournalEntry>>> search({
    String query = '',
    Set<String> tags = const {},
    String? date,
    int? mood,
  }) async {
    try {
      final all = await getAll();
      return all.fold(
        onSuccess: (list) {
          final q = query.trim().toLowerCase();
          final out = list.where((e) {
            if (tags.isNotEmpty &&
                !e.tags.any((t) => tags.contains(t))) {
              return false;
            }
            if (date != null && e.date != date) return false;
            if (mood != null && e.mood != mood) return false;
            if (q.isEmpty) return true;
            final hay = '${e.title ?? ''} ${e.body} ${e.tags.join(' ')}'
                .toLowerCase();
            return q
                .split(RegExp(r'\s+'))
                .every((w) => hay.contains(w));
          }).toList();
          return Success(out);
        },
        onFailure: (e) => Failure(e),
      );
    } catch (e) {
      return Failure(PersistenceException('Search failed.', originalError: e));
    }
  }

  static List<String> _cleanTags(List<String> tags) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in tags) {
      final c = t.trim();
      if (!journalTags.contains(c)) continue;
      if (seen.add(c)) out.add(c);
    }
    return out;
  }
}
