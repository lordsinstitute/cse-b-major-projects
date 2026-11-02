import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:soul_care/core/constants/app_constants.dart';
import 'package:soul_care/data/backup/backup_service.dart';
import 'package:soul_care/data/models/checkins.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/game_stats.dart';
import 'package:soul_care/data/models/health_snapshot.dart';
import 'package:soul_care/data/models/journal.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/models/reminders.dart';
import 'package:soul_care/data/models/user_profile.dart';

/// Builds "James" — a 45-year-old, 7–8-month SoulCare user — and writes him
/// as a restorable backup zip at the repo root (`james_test_profile.zip`).
///
/// To use on the phone: copy the zip to the device, then Settings →
/// Backup & Restore → Restore → pick the file → Replace. Deterministic
/// (seeded Random), so re-running regenerates the identical profile.
void main() {
  test('generate James test profile backup', () async {
    final rng = Random(7);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // ~7.5 months of history.
    const totalDays = 228;
    final startDay = today.subtract(const Duration(days: totalDays - 1));

    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    double clampD(double v, double lo, double hi) =>
        v < lo ? lo : (v > hi ? hi : v);
    int clampI(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

    T pick<T>(List<T> xs) => xs[rng.nextInt(xs.length)];

    // --- Day selection: mostly logged, Sundays mostly skipped, plus one
    // 12-day lapse mid-period (realistic imperfection).
    final lapseStart = startDay.add(const Duration(days: 140));
    final loggedDays = <DateTime>[];
    for (var i = 0; i < totalDays; i++) {
      final d = startDay.add(Duration(days: i));
      if (d.isAfter(today)) break;
      if (!d.isBefore(lapseStart) &&
          d.isBefore(lapseStart.add(const Duration(days: 12)))) {
        continue;
      }
      if (d.weekday == DateTime.sunday && rng.nextDouble() < 0.8) {
        continue;
      }
      if (rng.nextDouble() < 0.04) continue;
      loggedDays.add(d);
    }

    final daily = <String, Map<String, dynamic>>{};
    final stress = <String, Map<String, dynamic>>{};
    final morning = <String, Map<String, dynamic>>{};
    final evening = <String, Map<String, dynamic>>{};
    var stressN = 0;

    for (final d in loggedDays) {
      final k = key(d);
      // Slow improvement over the months (0 = first day → 1 = today).
      final t = totalDays <= 1
          ? 1.0
          : (d.difference(startDay).inDays / totalDays).clamp(0.0, 1.0);
      final sleep = clampD(
        6.3 + t * 1.1 + (rng.nextDouble() - 0.5) * 2.2,
        4.5,
        9.5,
      );
      final exercisesThisWeek = 2 + (t * 2).round(); // 2 → 4x/week
      final exercise = rng.nextDouble() < (exercisesThisWeek / 7)
          ? 15 + rng.nextInt(46)
          : 0;
      final water = clampI(
        (5 + t * 2.5 + (rng.nextDouble() - 0.5) * 3).round(),
        2,
        12,
      );
      final meditation = t < 0.25
          ? (rng.nextDouble() < 0.2 ? 5 + rng.nextInt(6) : 0)
          : (rng.nextDouble() < 0.6 ? 5 + rng.nextInt(16) : 0);
      final screen = clampD(
        4.5 - t * 2.0 + (rng.nextDouble() - 0.5) * 1.5,
        0.5,
        7.0,
      );
      final moodScore = clampI(
        (2.6 + t * 1.2 + (rng.nextDouble() - 0.5) * 1.6).round(),
        1,
        5,
      );

      final entry = DailyHealthEntry(
        date: k,
        sleepHours: (sleep * 2).round() / 2,
        sleepQuality: SleepQualityX.fromScore(
          sleep >= 7.5 ? 4 : (sleep >= 6 ? 3 : 2),
        ),
        feltRested: sleep >= 7,
        exerciseType: exercise == 0
            ? null
            : pick(['Walk', 'Run', 'Gym', 'Cycle']),
        exerciseMinutes: exercise,
        exerciseIntensity: exercise == 0
            ? ExerciseIntensity.none
            : (exercise >= 40
                  ? ExerciseIntensity.high
                  : ExerciseIntensity.moderate),
        mealQuality: MealQualityX.fromScore(
          3 + (t > 0.5 && rng.nextBool() ? 1 : 0),
        ),
        waterGlasses: water,
        meditationMinutes: meditation,
        screenTimeHours: (screen * 2).round() / 2,
      );
      daily[k] = entry.toJson();

      // Stress check-ins most days (mood improves over time).
      if (rng.nextDouble() < 0.8) {
        final n = rng.nextDouble() < 0.25 ? 2 : 1;
        for (var i = 0; i < n; i++) {
          final id = 'stress-$k-$i';
          stress[id] = StressEntry(
            id: id,
            date: k,
            mood: MoodX.fromScore(
              clampI(
                moodScore +
                    (rng.nextDouble() < 0.3 ? (rng.nextBool() ? 1 : -1) : 0),
                1,
                5,
              ),
            ),
            triggers: rng.nextDouble() < 0.5
                ? [
                    pick(['Work', 'Health', 'Money', 'Relationships']),
                  ]
                : const [],
            controllability: 0.5,
            createdAt: DateTime(d.year, d.month, d.day, 9 + rng.nextInt(10)),
          ).toJson();
          stressN++;
        }
      }

      morning[k] = MorningCheckIn(
        date: k,
        sleepHours: entry.sleepHours,
        rested: clampI((sleep >= 7 ? 4 : 2) + (rng.nextBool() ? 1 : 0), 1, 5),
        mood: clampI(moodScore + (rng.nextBool() ? 0 : -1), 1, 5),
        energy: clampI((sleep >= 7 ? 4 : 3) + (rng.nextBool() ? 0 : -1), 1, 5),
        intention: rng.nextDouble() < 0.5
            ? pick([
                'Move more',
                'Stay hydrated',
                'Reduce stress',
                'Sleep on time',
              ])
            : null,
        updatedAt: DateTime(d.year, d.month, d.day, 7),
      ).toJson();

      if (rng.nextDouble() < 0.7) {
        evening[k] = EveningReflection(
          date: k,
          mood: moodScore,
          energy: clampI(moodScore + (rng.nextBool() ? 0 : -1), 1, 5),
          stress: clampI(6 - moodScore, 1, 5),
          wentWell: rng.nextDouble() < 0.5
              ? pick([
                  'Morning walk felt good.',
                  'Ate on time today.',
                  'Called an old friend.',
                  'Finished work early.',
                ])
              : null,
          improve: rng.nextDouble() < 0.3
              ? pick(['Less phone at night.', 'Earlier bedtime.'])
              : null,
          updatedAt: DateTime(d.year, d.month, d.day, 21),
        ).toJson();
      }
    }

    // --- Experiments: 2 completed, 1 active, 1 abandoned.
    String ckey(DateTime d) => key(d);
    final exps = <String, Map<String, dynamic>>{};
    void addExp(Experiment e) => exps[e.id] = e.toJson();
    List<String> doneRun(DateTime from, int n, {int skipEvery = 0}) {
      final out = <String>[];
      for (var i = 0; i < n; i++) {
        if (skipEvery > 0 && i % skipEvery == skipEvery - 1) continue;
        out.add(ckey(from.add(Duration(days: i))));
      }
      return out;
    }

    final e1start = today.subtract(const Duration(days: 160));
    addExp(
      Experiment(
        id: 'exp-james-walk',
        templateId: 'daily-walk',
        title: 'Daily Walk',
        description: 'Walk at least 20 minutes daily.',
        targetMetric: 'exerciseMinutes',
        durationDays: 21,
        startDate: e1start,
        endDate: e1start.add(const Duration(days: 20)),
        status: ExperimentStatus.completed,
        checkIns: doneRun(e1start, 21, skipEvery: 5),
        missedDays: [ckey(e1start.add(const Duration(days: 4)))],
        createdAt: e1start,
        updatedAt: e1start.add(const Duration(days: 21)),
      ),
    );
    final e2start = today.subtract(const Duration(days: 90));
    addExp(
      Experiment(
        id: 'exp-james-sleep',
        templateId: 'earlier-sleep',
        title: 'Earlier Sleep',
        description: 'Wind down 30 minutes earlier each night.',
        targetMetric: 'sleepHours',
        durationDays: 14,
        startDate: e2start,
        endDate: e2start.add(const Duration(days: 13)),
        status: ExperimentStatus.completed,
        checkIns: doneRun(e2start, 14, skipEvery: 6),
        createdAt: e2start,
        updatedAt: e2start.add(const Duration(days: 14)),
      ),
    );
    final e3start = today.subtract(const Duration(days: 5));
    addExp(
      Experiment(
        id: 'exp-james-water',
        templateId: 'hydration',
        title: 'Hydration Consistency',
        description: 'Drink 8 glasses of water daily.',
        targetMetric: 'waterGlasses',
        durationDays: 7,
        startDate: e3start,
        endDate: e3start.add(const Duration(days: 6)),
        status: ExperimentStatus.active,
        checkIns: doneRun(e3start, 2),
        createdAt: e3start,
        updatedAt: today,
      ),
    );
    final e4start = today.subtract(const Duration(days: 200));
    addExp(
      Experiment(
        id: 'exp-james-breath',
        templateId: 'breathing-reset',
        title: 'Breathing Reset',
        description: 'One 60-second breathing reset daily.',
        targetMetric: 'meditationMinutes',
        durationDays: 7,
        startDate: e4start,
        endDate: e4start.add(const Duration(days: 6)),
        status: ExperimentStatus.abandoned,
        checkIns: doneRun(e4start, 2),
        missedDays: [ckey(e4start.add(const Duration(days: 2)))],
        createdAt: e4start,
        updatedAt: e4start.add(const Duration(days: 4)),
      ),
    );

    // --- Journal: 24 entries across the period.
    final journals = <String, Map<String, dynamic>>{};
    const bodies = [
      'Long day at the plant. The evening walk helped me switch off.',
      'Slept badly — too much coffee after lunch. Noting it for tomorrow.',
      'Blood pressure check at the clinic. All stable, keep the walks going.',
      'Daughter visited with the kids. Good day, ate a bit much at dinner.',
      'First week of the walking experiment done. Knees feel better already.',
      'Rainy day, skipped the walk. Did stairs instead, counts for something.',
      'Woke up before the alarm for once. The earlier bedtime is working.',
      'Work deadline stress. Breathing reset at lunch actually helped.',
      'Tried the new running shoes — 5k without stopping. Pleased.',
      'Sugar cravings all evening. Drank water instead, mostly worked.',
      'Dentist appointment done. Next cleaning in six months.',
      'Weekend hike, 9km. Best energy in months.',
      'Late night with the match on. Sleep will suffer, worth it.',
      'Meditation streak at two weeks. Mornings feel calmer.',
      'Forgot to log yesterday — backdating from memory, roughly right.',
      'Annual physical booked for next month. Need recent logs ready.',
      'Gardening all afternoon. Back aches a little, good ache.',
      'Screen time creeping up again. Phone stays out of the bedroom.',
      'Cooked a proper meal for once. Greens, grains, no shortcuts.',
      'Restless legs last night. Less caffeine after noon from now on.',
      'Flu-ish, stayed in. Light day, no guilt.',
      'Grandson taught me a card game. Laughed a lot.',
      'Two months of steady logging. The charts finally mean something.',
      'Feeling good about this routine. Keeping it simple.',
    ];
    const tags = ['Personal', 'Exercise', 'Sleep', 'Work', 'Food', 'Stress'];
    for (var i = 0; i < bodies.length; i++) {
      final d = startDay.add(
        Duration(days: (i * (totalDays ~/ bodies.length)) + rng.nextInt(4)),
      );
      if (d.isAfter(today)) break;
      final k = key(d);
      final id = 'journal-james-$i';
      journals[id] = JournalEntry(
        id: id,
        date: k,
        title: i.isEven ? 'Day notes' : null,
        body: bodies[i],
        mood: 2 + rng.nextInt(3),
        energy: 2 + rng.nextInt(3),
        stress: 1 + rng.nextInt(4),
        tags: [tags[i % tags.length]],
        createdAt: DateTime(d.year, d.month, d.day, 20),
        updatedAt: DateTime(d.year, d.month, d.day, 20),
      ).toJson();
    }

    // --- Profile + settings + snapshot.
    final profile = UserProfile(
      displayName: 'James',
      ageRange: '40–49',
      exactAge: 45,
      wakeTime: '06:30',
      sleepTime: '22:30',
      sleepGoal: 7.0,
      waterGoal: 8,
      exerciseGoalWeek: 120,
      meditationGoal: 10,
      reminderTime: '07:30',
      primaryFocus: WellnessFocus.moreMovement,
      secondaryFocus: WellnessFocus.betterSleep,
      createdAt: startDay,
      updatedAt: today,
    );
    final settings = const UserSettings(
      themeMode: 'dark',
      notificationsEnabled: true,
      dailyReminderTime: '07:30',
      experimentRemindersEnabled: true,
      onboardingDone: true,
    );
    final snapshot = HealthSnapshot(
      bloodGroup: 'O+',
      allergies: const [AllergyRecord(name: 'Peanuts', severity: 'Severe')],
      medications: const [
        MedicationRecord(
          name: 'Atorvastatin',
          dosage: '10mg',
          frequency: 'once daily',
        ),
      ],
      supplements: const ['Vitamin D'],
      conditions: const ['Raised cholesterol (record only)'],
      emergencyName: 'Mary Carter',
      emergencyPhone: '555-0142',
      provider: 'Dr. Rao',
      notes: 'Allergic to peanuts — carry antihistamine.',
      createdAt: startDay,
      updatedAt: today,
    );

    // --- Games, reminder, appointment.
    final games = <String, Map<String, dynamic>>{
      'memory': const GameStats(
        gameId: 'memory',
        playCount: 12,
        bestScore: 850,
        recentScore: 720,
      ).toJson(),
      'breathing': const GameStats(
        gameId: 'breathing',
        playCount: 20,
        bestScore: 5,
        recentScore: 3,
      ).toJson(),
      'reaction': const GameStats(
        gameId: 'reaction',
        playCount: 8,
        bestScore: 320,
        recentScore: 410,
      ).toJson(),
    };
    final reminders = <String, Map<String, dynamic>>{
      'rem-james-vitd': MedicationReminder(
        id: 'rem-james-vitd',
        medicationName: 'Vitamin D',
        times: const ['08:00'],
        enabled: true,
        createdAt: startDay,
        updatedAt: startDay,
      ).toJson(),
    };
    final futureAppt = today.add(const Duration(days: 20));
    final appointments = <String, Map<String, dynamic>>{
      'appt-james-physical': Appointment(
        id: 'appt-james-physical',
        title: 'Annual physical',
        date: DateTime(futureAppt.year, futureAppt.month, futureAppt.day),
        time: '10:30',
        location: 'Riverside Clinic',
        provider: 'Dr. Rao',
        createdAt: today.subtract(const Duration(days: 6)),
        updatedAt: today.subtract(const Duration(days: 6)),
      ).toJson(),
    };

    final boxes = <String, Map<String, dynamic>>{
      'daily_health': daily,
      'stress_entries': stress,
      'experiments': exps,
      'medical_documents': {},
      'settings': {
        'user_settings': settings.toJson(),
        'user_profile': profile.toJson(),
      },
      'game_stats': games,
      'morning_checkins': morning,
      'evening_reflections': evening,
      'journal_entries': journals,
      'health_snapshot': {'snapshot': snapshot.toJson()},
      'med_reminders': reminders,
      'appointments': appointments,
      'dose_log': {},
    };
    final counts = {for (final k in boxes.keys) k: boxes[k]!.length};
    final manifest = {
      'format': 'soulcare-backup',
      'formatVersion': 1,
      'appVersion': AppConstants.appVersion,
      'createdAt': now.toIso8601String(),
      'encrypted': false,
      'counts': counts,
    };

    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    final dataBytes = utf8.encode(jsonEncode(boxes));
    archive.addFile(ArchiveFile('data.json', dataBytes.length, dataBytes));
    final zipped = ZipEncoder().encode(archive);

    final outPath =
        '${Directory.current.path}${Platform.pathSeparator}james_test_profile.zip';
    await File(outPath).writeAsBytes(zipped, flush: true);

    // --- Validate: preview must accept it + models round-trip.
    final preview = await BackupService().preview(outPath);
    preview.fold(
      onSuccess: (p) {
        expect(p.totalRecords, greaterThan(400));
        expect(p.counts['daily_health'], daily.length);
      },
      onFailure: (e) => fail('preview rejected James backup: $e'),
    );
    final back = UserProfile.fromJson(profile.toJson());
    expect(back.displayName, 'James');
    expect(back.exactAge, 45);
    expect(back.primaryFocus, WellnessFocus.moreMovement);
    final sample = DailyHealthEntry.fromJson(
      Map<String, dynamic>.from(daily.values.first),
    );
    expect(sample.sleepHours, greaterThan(0));
    expect(stressN, greaterThan(100));

    // ignore: avoid_print
    print(
      'Wrote $outPath '
      '(${daily.length} days, $stressN stress check-ins, '
      '${journals.length} journal entries, ${exps.length} experiments)',
    );
  });

  test('james backup restores cleanly (replace)', () async {
    final zipPath =
        '${Directory.current.path}${Platform.pathSeparator}james_test_profile.zip';
    expect(
      File(zipPath).existsSync(),
      isTrue,
      reason: 'run the generator test first',
    );

    // Isolated Hive + vault so the real boxes are never touched.
    final dir = await Directory.systemTemp.createTemp('soulcare_james_restore');
    Hive.init(dir.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
    final vault = Directory('${dir.path}${Platform.pathSeparator}vault');
    final res = await BackupService(
      vaultDir: vault,
    ).restore(zipPath, strategy: RestoreStrategy.replace);
    res.fold(
      onSuccess: (o) => expect(o.added, greaterThan(400)),
      onFailure: (e) => fail('restore failed: $e'),
    );
    expect(Hive.box('daily_health').length, greaterThan(150));
    final profile = Map<String, dynamic>.from(
      Hive.box('settings').get('user_profile') as Map,
    );
    expect(profile['displayName'], 'James');
    expect(profile['exactAge'], 45);
  });
}
