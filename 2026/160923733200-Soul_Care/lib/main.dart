import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/providers/action_center_provider.dart';
import 'app/providers/checkin_providers.dart';
import 'app/providers/daily_health_provider.dart';
import 'app/providers/health_import_provider.dart';
import 'app/providers/health_snapshot_provider.dart';
import 'app/providers/journal_provider.dart';
import 'app/providers/reminders_provider.dart';
import 'app/providers/ai_chat_provider.dart';
import 'app/providers/milestones_provider.dart';
import 'core/home_widget/widget_data.dart';
import 'core/notifications/notification_service.dart';
import 'app/providers/dashboard_provider.dart';
import 'app/providers/documents_provider.dart';
import 'app/providers/profile_provider.dart';
import 'app/providers/experiment_provider.dart';
import 'app/providers/settings_provider.dart';
import 'data/local/local_database.dart';
import 'data/repositories/checkin_repository.dart';
import 'data/repositories/daily_health_repository.dart';
import 'data/repositories/health_import_repository.dart';
import 'data/repositories/health_snapshot_repository.dart';
import 'data/repositories/journal_repository.dart';
import 'data/repositories/experiment_repository.dart';
import 'data/repositories/medical_document_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/stress_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge + portrait-first.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Local-first: app must open even if storage init has issues.
  try {
    await LocalDatabase.init();
  } catch (_) {
    // Providers will surface friendly errors per-screen; never crash on boot.
  }

  final settingsRepo = SettingsRepository();
  final dailyRepo = DailyHealthRepository();
  final experimentRepo = ExperimentRepository();
  final stressRepo = StressRepository();

  final settingsProvider = SettingsProvider(settingsRepo);
  // Load settings before first frame so theme is correct.
  try {
    await settingsProvider.load();
  } catch (_) {}

  final profileProvider = ProfileProvider(ProfileRepository());
  try {
    await profileProvider.load();
  } catch (_) {}

  // Refresh local reminder schedules (covers reboot, clock changes,
  // permission toggles, expired alerts). Fire-and-forget, never blocking.
  try {
    await NotificationService.init();
    await NotificationService.rescheduleAll();
  } catch (_) {}

  // Home-screen widget taps (cold start + warm). All guarded: without a
  // widget or plugin the app simply opens normally.
  try {
    _listenWidgetTaps();
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider(
            create: (_) =>
                DailyHealthProvider(dailyRepo, stressRepo: stressRepo)),
        ChangeNotifierProvider(
            create: (_) =>
                DashboardProvider(dailyRepo, stressRepo: stressRepo)),
        ChangeNotifierProvider(
            create: (_) =>
                ExperimentProvider(experimentRepo, dailyRepo: dailyRepo)),
        ChangeNotifierProvider(
            create: (_) => DocumentsProvider(MedicalDocumentRepository())),
        ChangeNotifierProvider(
            create: (_) => MorningProvider(MorningRepository(),
                dailyRepo: dailyRepo)),
        ChangeNotifierProvider(create: (_) => EveningProvider(EveningRepository())),
        ChangeNotifierProvider(
            create: (_) => JournalProvider(JournalRepository())),
        ChangeNotifierProvider(
            create: (_) =>
                HealthSnapshotProvider(HealthSnapshotRepository())),
        ChangeNotifierProvider(create: (_) => RemindersProvider()),
        ChangeNotifierProvider(
            create: (_) =>
                HealthImportProvider(HealthImportRepository())),
        ChangeNotifierProvider(create: (_) => ActionCenterProvider()),
        ChangeNotifierProvider(create: (_) => MilestonesProvider()),
        ChangeNotifierProvider(create: (_) => AiChatProvider()),
      ],
      child: SoulCareApp(
          onboarded: settingsProvider.settings.onboardingDone),
    ),
  );
}

/// Subscribes to home-widget tap streams (warm taps + cold-start launch).
/// Everything is guarded so environments without the widget behave
/// exactly like before.
void _listenWidgetTaps() {
  try {
    HomeWidget.widgetClicked.listen(
      (uri) {
        try {
          WidgetLink.handleTap(uri);
        } catch (_) {}
      },
      onError: (_) {},
      cancelOnError: false,
    );
  } catch (_) {}
  try {
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      try {
        WidgetLink.handleTap(uri);
      } catch (_) {}
    }).catchError((_) {});
  } catch (_) {}
}
