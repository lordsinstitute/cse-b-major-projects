/// Curated journal tags.
const List<String> journalTags = [
  'Sleep',
  'Work',
  'Relationships',
  'Exercise',
  'Food',
  'Stress',
  'Personal',
  'Other',
];

/// One private journal entry. Everything except the date is optional so a
/// quick note is just a body. Never uploaded, never logged.
class JournalEntry {
  final String id;
  final String date; // yyyy-MM-dd
  final String? title;
  final String body;
  final int? mood; // 1–5
  final int? energy; // 1–5
  final int? stress; // 1 calm – 5 high
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JournalEntry({
    required this.id,
    required this.date,
    this.title,
    required this.body,
    this.mood,
    this.energy,
    this.stress,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// A quick note carries body only.
  bool get isQuickNote =>
      (title == null || title!.trim().isEmpty) &&
      mood == null &&
      energy == null &&
      stress == null &&
      tags.isEmpty;

  JournalEntry copyWith({
    String? Function()? title,
    String? body,
    int? Function()? mood,
    int? Function()? energy,
    int? Function()? stress,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id,
      date: date,
      title: title != null ? title() : this.title,
      body: body ?? this.body,
      mood: mood != null ? mood() : this.mood,
      energy: energy != null ? energy() : this.energy,
      stress: stress != null ? stress() : this.stress,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'title': title,
        'body': body,
        'mood': mood,
        'energy': energy,
        'stress': stress,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    int? clamp5(String key) {
      final v = (json[key] as num?)?.toInt();
      return v?.clamp(1, 5);
    }

    String? clean(String? v) => switch (v?.trim()) {
          '' || null => null,
          final t => t,
        };

    return JournalEntry(
      id: json['id'] as String,
      date: json['date'] as String,
      title: clean(json['title'] as String?),
      body: (json['body'] as String?) ?? '',
      mood: clamp5('mood'),
      energy: clamp5('energy'),
      stress: clamp5('stress'),
      tags: (json['tags'] as List?)
              ?.map((e) => e.toString())
              .where((t) => journalTags.contains(t))
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
