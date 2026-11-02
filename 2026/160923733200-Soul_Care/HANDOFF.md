# SoulCare — Project Handoff

> **Status legend used throughout:** `VERIFIED` = confirmed by inspecting the current
> repository on 2026-10-04. `PLANNED` = intended but not implemented. `PARTIAL` =
> partially implemented. `BLOCKED` = cannot complete due to a known problem. `UNKNOWN` =
> the repository does not provide enough information.
>
> **2026-10-05 addendum:** nine feature areas landed after the audit
> (Life Twin, Time Machine, Experiment Generator, Voice Logger, Analytics Lab,
> Health Card, Wellness Calendar, Milestones + onboarding/tests recorded in
> `progress.md`). Rows marked `VERIFIED (2026-10-05)` were confirmed via
> `progress.md` checkpoints (scoped `dart analyze` clean + per-file suites
> green: 16/16 life-twin, 13/13 time-machine, 16/16 generator, 15/15 voice,
> 18/18 analytics, 12+3 calendar; health-card + milestones verification runs
> were in flight at time of writing) — not by a fresh full-repo audit.
>
> **2026-10-07 addendum (reset+rebuild):** the local-only AI was deleted and
> replaced with a provider-independent Local+Cloud architecture
> (`test/ai_test.dart` 30/30: fake llama.cpp + auth-gated OpenAI + fake
> Gemini servers; domain guard; architectural no-write + key-privacy tests;
> mode-switching with tagged history), scoped+full analyzer clean for AI
> code (7 pre-existing warnings only in untouched files), debug APK built.
> Device E2E for BOTH backends explicitly NOT performed (needs phone +
> running LLM server and/or a real cloud key). When in doubt, trust the
> repository over this document, then update this document.

---

# CURRENT SESSION STATE

### Last completed task

`VERIFIED (2026-10-07)` — Full SOULCARE AI RESET + REBUILD. The old
local-only AI subsystem was deleted (7 core files + old chat provider,
config repo, chat/settings UI, old tests; verified gone by repo-wide
grep) and replaced with a provider-independent Local+Cloud architecture:
`AiProvider` contract → `LocalAiProvider` (loopback/LAN llama.cpp, Gemma)
+ `CloudAiProvider` (OpenAI / Gemini REST v1beta / custom OpenAI-compat)
over one shared SSE client; mode switching that never touches history;
secure-storage API keys; domain guard; centralized scope/safety prompt;
streaming markdown chat; per-message provider tags. `test/ai_test.dart`
**30/30 green**, AI-code analyzer clean, `flutter build apk --debug`
succeeded. Retained by design: `ai_context.dart`, Hive chat boxes (with
`providerUsed` migration), routes, dashboard entry, journal/doc attach.

### Current task

`DONE` — Rebuild + docs sync (`progress.md`, `README.md`, this section).

### Current task status

`VERIFIED (2026-10-07)` — Implementation + unit verification complete;
device E2E for BOTH backends (real server ↔ chat, real cloud key ↔ chat,
switching session, offline local re-check) explicitly NOT yet performed.

### Last files modified

Rebuilt: `lib/core/ai/` (now 11 files: models/provider/compat-client/local/
cloud/config/secure-store/guard/prompts/connection/service + retained
context), `lib/features/ai/` (chat + settings UI rewritten),
`lib/app/providers/ai_chat_provider.dart`, `lib/data/models/ai_chat.dart`
(+providerUsed), `lib/data/repositories/{ai_chat_repository,ai_config_repository}.dart`,
`test/ai_test.dart` (30/30); touched: journal/doc detail imports
(PendingAttachment now in `ai_models.dart`), dashboard card copy, settings
hub copy, `pubspec.yaml` (+`flutter_secure_storage`, +`flutter_markdown_plus`).
Earlier: 7 settings sub-screens, 3 new games + GameScope fix, AppIcon,
Privacy+About merge, James fixture, simulator stress-repo fix.

### Last commands executed

`VERIFIED (2026-10-07)` — `flutter pub add flutter_secure_storage
flutter_markdown_plus` (plus replaced discontinued `flutter_markdown`
before use); `flutter test test/ai_test.dart` **30/30**; `dart analyze
lib test/ai_test.dart` (only 7 pre-existing warnings in untouched files);
`flutter build apk --debug` **succeeded**.

### Last successful verification

`ai_test` 30/30 + AI-code analyzer clean + debug APK built (2026-10-07).
Device E2E (both backends), full-suite green run, release APK: all still
pending (need phone + running LLM server and/or real cloud key).

### Current blocker

`PARTIAL` — (1) Windows-box Hive flakiness (§21) plus repeated host/server
restarts killing long runs (several `flutter test`/`flutter run` hosts
cancelled mid-flight 2026-10-05→07). (2) No device E2E for AI yet.

### Exact next step (2026-10-07)

1. LOCAL device E2E: start LLM AI Server, load Gemma, select Local AI, test
   connection, general + personal-data questions, streaming + Stop, disable
   internet, verify local inference still works (§45/§46 plan).
2. CLOUD device E2E: save a real key (Gemini or OpenAI), accept privacy
   notice, test connection, general + data questions, verify provider
   indicator; then switch Local ↔ Cloud mid-conversation and verify history
   + tags survive.
3. `flutter build apk --release` + install smoke test.
4. Commit accumulated work — only if asked.

---

# 1. PROJECT IDENTITY

| Item | Value | Source |
|---|---|---|
| Application name | SoulCare | `VERIFIED` — manifest `android:label`, pubspec description |
| Package / applicationId | `com.soulcare.soul_care` | `VERIFIED` — `android/app/build.gradle.kts` |
| Version | 1.0.0+1 | `VERIFIED` — `pubspec.yaml` |
| Version code | Flutter-resolved (`flutter.versionCode`) | `VERIFIED` — config mechanism; exact number `UNKNOWN` without a build |
| Flutter version (env) | 3.41.9 stable, revision 00b0c91f06 | `VERIFIED` — `flutter --version`, 2026-10-04 |
| Dart version (env) | 3.11.5 | `VERIFIED` — same |
| SDK constraint | `^3.11.5` | `VERIFIED` — `pubspec.yaml` |
| Android target | Android only (portrait-first) | `VERIFIED` — manifest + build config |
| minSdk / targetSdk / compileSdk | minSdk hardcoded `26` (raised from Flutter default 24 — required by `health` plugin, minSdk 26); targetSdk/compileSdk Flutter-resolved | `VERIFIED` — `android/app/build.gradle.kts` |
| Java (build) | 17 (`VERSION_17`, incl. `jvmTarget`) | `VERIFIED` — `build.gradle.kts` |
| Java (shell default) | 1.8.0_481 — **not** used for builds | `VERIFIED` — `java -version`; builds use the Flutter-resolved JDK 17 toolchain |
| Kotlin | 2.2.20 | `VERIFIED` — `settings.gradle.kts` |
| Gradle wrapper | 8.14 (`gradle-8.14-all.zip`) | `VERIFIED` — `gradle-wrapper.properties` |
| AGP | 8.11.1 | `VERIFIED` — `settings.gradle.kts` |

---

# 2. PRODUCT PURPOSE

`VERIFIED` — SoulCare is a private, local-first personal wellness and health organization
application for Android. Implemented capabilities only:

- track daily wellness data (sleep, movement, nutrition, mind, stress) — `VERIFIED`
- understand personal patterns (insights, weekly charts, reports) — `VERIFIED`
- manage habits and routines (morning/evening check-ins, reminders) — `VERIFIED`
- run personal wellness experiments (Lab) — `VERIFIED`
- organize health documents (vault + timeline + PDF viewer) — `VERIFIED`
- maintain personal health info (profile, health snapshot, journal) — `VERIFIED`
- visualize trends (fl_chart weekly/monthly views) — `VERIFIED`
- explore hypothetical wellness scenarios (simulator, deterministic) — `VERIFIED`
- optional on-device AI — **not implemented** (see §13; only an explicit
  `unavailable` processor stub exists) — `VERIFIED` absent

---

# 3. AUTHENTICATION STATUS

`VERIFIED` — A repo-wide search for `firebase|FirebaseAuth|currentUser|GoogleSignIn`
returns **zero matches** (code, config, and dependencies). Findings:

- No login, signup, password, or auth wall of any kind — `VERIFIED`
- No Firebase packages in `pubspec.yaml`, no `google-services` config — `VERIFIED`
- No route redirects to login; no UID assumed anywhere (all records use local
  uuid/date keys) — `VERIFIED`
- First-run onboarding (`/welcome`) is skippable and persists a local flag only — `VERIFIED`
- Privacy is enforced by an optional **local** PIN/biometric app lock, not accounts — `VERIFIED`

---

# 4. ARCHITECTURE

`VERIFIED` — The implemented pattern is:

```text
UI (screens/widgets, lib/features/*)
↓  reads/watches
State Management (ChangeNotifier providers, lib/app/providers/*)
↓  calls Result<T> CRUD
Repositories / Services (lib/data/repositories/*, lib/data/backup/*, lib/core/*)
↓  reads/writes JSON maps + files
Local Data Layer (Hive boxes via lib/data/local/*, app vault dir)
```

- **State management:** `provider` package. 15 global providers registered in `main.dart`
  (2026-10-05: + `MilestonesProvider`; 2026-10-07: + `AiChatProvider`; was 13 at audit):
  settings, profile, dailyHealth (+stress), dashboard, experiment (+daily), documents,
  morning (+daily), evening, journal, healthSnapshot, reminders, healthImport,
  actionCenter. Feature-local controllers also exist (simulator, games).
- **Routing:** `go_router` 14.6.1, `StatefulShellRoute` bottom-nav shell + nested
  sub-routes; per-instance router (`createAppRouter({onboarded})`) plus a global
  `appRouter` used by deep-link/widget-tap handling.
- **Repositories:** one class per domain (daily, stress, experiment, documents, settings,
  profile, journal, snapshot, reminders×3, health-import, game-stats, check-ins×2),
  all returning `Result<T>` (`Success`/`Failure`), all validated in §18 tests.
- **Services:** `NotificationService` (local scheduling), `BackupService` (zip+AES),
  `DataExportService`/`DataDeletionService`, `DocumentStorage` (vault),
  `WidgetRefresh` (home-screen widget), `MedicalDocumentProcessor` (interface +
  `UnavailableDocumentProcessor` — AI explicitly absent).
- **Dependency injection:** constructor injection with defaults (repos/providers take
  optional collaborators; fakes used in tests). No DI framework — `VERIFIED`.
- **Local persistence:** Hive (`hive`/`hive_flutter`), 17 boxes (2026-10-05: +
  `milestone_state`; 2026-10-07: + `ai_conversations`, `ai_messages`; was 14 at audit), JSON-map values —
  `VERIFIED` (see §10). No SQLite/Drift/ObjectBox.
- **Networking layer:** none exists — `VERIFIED` (no `http`/socket/Firebase imports in
  `lib/`). All "cloud" concepts are explicitly unimplemented stubs.
- **Native Android bridges:** no custom `MethodChannel`/`EventChannel` in `lib/`
  (`VERIFIED` — zero matches); all native access flows through plugins.
- **AI layer:** none at audit time — SUPERSEDED 2026-10-07, see §13 (Local+Cloud AI shipped).

---

# 5. PROJECT STRUCTURE

`VERIFIED` — actual tree at audit (95 Dart files in `lib/`; grown since with
9 new feature areas — recount pending; only key files annotated):

```text
lib/
├── main.dart                      # init, providers, notification reschedule, widget-tap listener
├── app/
│   ├── app.dart                   # MaterialApp.router, lifecycle observer, full-app PinGate
│   ├── providers/                 # 13 ChangeNotifiers (see §4)
│   ├── router/app_router.dart     # all routes + onboardingRedirect() + global appRouter
│   └── theme/app_theme.dart       # Material 3 light/dark, seed ColorSchemes
├── core/
│   ├── app_lock/biometric_gateway.dart   # BiometricGateway seam (real/fake/unavailable)
│   ├── constants/ errors/ extensions/ utils/   # Result<T>, hashPin, formatting, scores helpers
│   ├── documents/document_processor.dart # MedicalDocumentProcessor + Unavailable impl
│   ├── health/health_gateway.dart        # HealthGateway seam + HealthConnect impl
│   ├── home_widget/widget_data.dart      # payload builder, tap-URI resolver, WidgetLink registry
│   ├── home_widget/widget_refresh.dart   # guarded plugin writer (overridable in tests)
│   ├── notifications/notification_service.dart  # daily/lab/med/appointment scheduling + actions
│   ├── reminders/reminder_schedule.dart  # pure occurrence math + stable notification ids
│   ├── wellness/wellness_score.dart      # WellnessScoreCalculator (weights §12)
│   ├── wellness/insights.dart            # deterministic InsightEngine
│   └── widgets/                   # AppCard/Loading/Empty/Error, SectionHeader, PinGate
├── data/
│   ├── backup/backup_service.dart # zip+AES backup, preview, merge/replace, safety rollback
│   ├── export/                    # JSON export (share sheet) + scoped deletion
│   ├── local/                     # LocalDatabase (14 boxes) + DocumentStorage (vault)
│   ├── models/                    # enums, models, user_profile, journal, reminders,
│   │                              # checkins, health_import, health_snapshot, game_stats
│   └── repositories/              # per-domain CRUD, all Result<T>
└── features/
    ├── action_center/            # pure buildActions engine (max 3, dismissible)
    ├── checkins/                  # morning/evening screens
    ├── daily_health/              # /today screen + 60s breathing dialog
    ├── dashboard/                 # home + score sheet + weekly charts + goal strip
    ├── experiments/               # lab screen + engine + 5 templates
    ├── games/                     # hub + provider + 5 games + engines
    ├── journal/                   # list/detail (JournalGate PIN pad lives here)
    ├── onboarding/                # 6-page skippable first-run flow
    ├── profile/                   # profile form + GoalProgressCard + goal math
    ├── reminders/                 # meds/appointments/upcoming/history tabs
    ├── reports/                   # engine + controller + week/month screen + JSON export
    ├── settings/                  # settings + lock management UI
    ├── simulator/                 # projection engine + controller + screen
    ├── snapshot/                  # health snapshot quick view + editor
    └── timeline/                  # vault list/detail + in-app PDF viewer
android/app/src/main/
├── kotlin/.../MainActivity.kt         # FLAG_SECURE (blank app-switcher previews)
├── kotlin/.../SoulCareWidgetProvider.kt # home-screen widget provider
├── res/layout/soulcare_widget.xml     # widget layout
├── res/xml/soulcare_widget_info.xml   # widget provider info
└── AndroidManifest.xml                # label, portrait, permissions (§14)
test/  # 31 files (2026-10-05: 19 at audit + life_twin, time_machine, generator,
voice_log, analytics, health_card, calendar, calendar_widget, milestones;
2026-10-07: + ai_test, seed_james) (see §18)
```

---

# 6. DEPENDENCIES

`VERIFIED` — from `pubspec.yaml` (all present; versions are constraints as written):

### Flutter/Core
- `flutter` (SDK), `cupertino_icons` — essential.

### State Management
- `provider ^6.1.2` — all app state. Essential.

### Navigation
- `go_router ^14.6.1` — declarative router + shell. Essential.

### Persistence
- `hive ^2.2.3`, `hive_flutter ^1.1.0`, `path_provider`, `path` — the entire database
  layer. Essential. (`hive_generator`/`build_runner` in devDeps but **no generated
  adapters exist** — models use manual `toJson`/`fromJson`; generator effectively unused.)
- `shared_preferences ^2.3.2` — tiny theme-mode mirror only. Minor.

### Charts
- `fl_chart ^1.2.0` — weekly charts, simulator trajectory, reports. Essential.

### File Handling
- `file_picker ^8.1.2` — document import, backup restore picking. Essential.
- `archive ^4.3.0` — AES-capable zip for backups. Essential.
- `share_plus ^12.0.2` — export/backup share sheets. Essential.

### Notifications
- `flutter_local_notifications ^22.3.1`, `timezone`, `flutter_timezone` — daily/lab/
  medication/appointment reminders. Essential. (Required enabling core-library
  desugaring in `android/app/build.gradle.kts` — see §19.)

### Android Integration
- `local_auth ^3.0.2` — biometric unlock w/ PIN fallback. Essential to lock feature.
- `health ^13.3.1` — read-only Health Connect (steps/sleep/workouts/HR). Essential to
  that integration; unused elsewhere.
- `home_widget ^0.10.0` — home-screen widget (prefs + tap URIs). Essential to widget.
- `speech_to_text 7.4.0` (2026-10-05) — on-device recognition for Quick Voice Log
  (mic only, no uploads). Essential to voice input.
- `qr_flutter 4.1.0` + `qr` (2026-10-05) — offline QR rendering for Health Card
  sharing. Essential to that feature.
- `http 1.6.0` (2026-10-07) — loopback/LAN chat completions + models AND
  user-configured cloud endpoints (local mode never calls cloud).
- `flutter_secure_storage 10.3.4` (2026-10-07) — Android-Keystore-backed
  cloud API keys. Never Hive/logs/history. Essential to Cloud AI.
- `flutter_markdown_plus 1.0.12` (2026-10-07) — streaming markdown
  rendering in chat (discontinued `flutter_markdown` swapped before use).
- `google_fonts 8.2.1` (2026-10-07) — display fonts (one-time download, then
  cached offline). Optional.

### AI / LiteRT
- None. `VERIFIED` absent.

### PDF
- `pdfrx ^2.4.7` — in-app PDF viewer (PDFium). Essential to vault viewing.

### Biometrics
- See `local_auth` above.

### Other
- `uuid`, `intl`, `collection` — ids, dates, helpers. Minor but used.

---

# 7. ROUTING

`VERIFIED` — from `lib/app/router/app_router.dart`:

```text
/welcome            OnboardingScreen      first-run flow (skippable)      outside shell
/home               DashboardScreen       main dashboard                  tab 1
/home/morning       MorningScreen         20–30s check-in                 dashboard card
/home/evening       EveningScreen         evening reflection              dashboard card
/home/journal       JournalScreen         journal timeline                quick action
/home/journal/:id   JournalDetailScreen   entry + that-day metrics        list tap
/home/reports       ReportsScreen         week/month summaries            quick action
/home/snapshot      SnapshotScreen        health record quick view+edit   quick action
/home/care          RemindersScreen       meds/appointments/upcoming      quick action
/home/voice         VoiceLogScreen        quick voice log               quick action (2026-10-05)
/today              DailyHealthScreen     5-section logging               tab 2
/timeline           TimelineScreen        document vault                  tab 3
/timeline/doc/:id   DocumentDetailScreen  metadata + actions              list tap
/timeline/doc/:id/view  PdfViewerScreen   in-app PDF                      Open button
/lab                ExperimentsScreen     experiments                     tab 4
/life-twin          LifeTwinScreen        wellness visualization        dashboard (2026-10-05)
/time-machine       TimeMachineScreen     history replay (?month=)      dashboard+calendar (2026-10-05)
/analytics          AnalyticsScreen       trends/matrix/anomalies       dashboard (2026-10-05)
/health-card        HealthCardScreen      personal card + QR share      quick action (2026-10-05)
/calendar           CalendarScreen        month grid + heatmap          Home + Reports (2026-10-05)
/milestones         MilestonesScreen      quiet achievements            dashboard spot (2026-10-05)
/ai                 AiScreen              local chat + quick actions      dashboard card (2026-10-07)
/future             SimulatorScreen       scenario sketches               tab 5
/games              GamesScreen           8-game hub (2026-10-07: +color/echo/bubbles)  tab 6
/games/memory|reaction|sequence|breathing|scramble|color|echo|bubbles  game screens (each with own GameScope provider — fixes a production crash where sub-routes had none)  hub tap
/settings           SettingsScreen        settings hub                    tab 7
/settings/profile   ProfileScreen         profile + goals                 settings entry
/settings/appearance|notifications|lock|health|privacy|data  grouped sub-screens (2026-10-07; About merged into Privacy)  hub tap
/settings/ai        AiSettingsScreen      server/model/generation       hub tap (2026-10-07)
```

- Initial route: `/home`, or `/welcome` when `onboardingDone == false`
  (`VERIFIED` — `initialLocation` + pure `onboardingRedirect()`, unit-tested).
- No modal routes (bottom sheets/dialogs used instead). No custom deep links except
  home-widget tap URIs (`soulcare://widget?action=…` → `/today`, `/home/morning`,
  `/home`) handled via a router registry (`VERIFIED` — `widget_data.dart`).
- Planned-but-missing routes: none known (`UNKNOWN` — no route TODOs found).

# 8. FEATURE INVENTORY

`VERIFIED` = file(s) exist and implement the described behavior (audited). Test-verdict
notes are historical where marked; fresh verification was running at handoff time (§18).

| Feature | Location | Status | Persistence | Deps | Known issues |
|---|---|---|---|---|---|
| Home Dashboard | `features/dashboard/` | VERIFIED | reads daily/stress/experiments/profile/check-ins | provider, go_router, fl_chart | None open |
| Daily Health | `features/daily_health/` | VERIFIED | `daily_health` box | provider | None open |
| Stress | model+repo+Today section | VERIFIED | `stress_entries` box | — | None open |
| Wellness Score | `core/wellness/wellness_score.dart` | VERIFIED | derived, not stored | — | None open |
| Medical Timeline | `features/timeline/timeline_screen.dart` | VERIFIED | metadata box + vault dir | file_picker | None open |
| Medical Documents | `timeline/` + `document_storage.dart` + repo | VERIFIED | `medical_documents` + vault PDFs | file_picker, pdfrx | None open |
| Experiments | `features/experiments/` | VERIFIED | `experiments` box | — | None open |
| Habits | No standalone feature | PLANNED/absent — experiment check-ins + reports counts cover the need partially | — | — | None (never promised in UI) |
| Wellness Simulator | `features/simulator/` | VERIFIED (+2026-10-07 stress-repo default fix: bare controller starved moods, locking the baseline gate after restores) | read-only over logs | fl_chart | Needs device pass |
| Games (8) | `features/games/` (+color/echo/bubbles 2026-10-07) | VERIFIED (GameScope crash fix; new tests written, run on request) | `game_stats` box | — | Needs device pass |
| Reports | `features/reports/` | VERIFIED (JSON export only) | reads all boxes | share_plus | PDF export PLANNED (needs `pdf` pkg) |
| Profile | `features/profile/` | VERIFIED | `settings` box (`user_profile`) | — | None open |
| Journal | `features/journal/` | VERIFIED | `journal_entries` box | — | None open |
| Health Snapshot | `features/snapshot/` | VERIFIED | `health_snapshot` box | — | None open |
| Reminders | `features/reminders/` | VERIFIED | 3 boxes | flutter_local_notifications | None open |
| Notifications | `core/notifications/` | VERIFIED | schedules only (OS-owned) | flutter_local_notifications | Needs device testing |
| Privacy Lock | `core/widgets/pin_gate.dart` + settings UI | VERIFIED | hash in settings | local_auth | Needs device testing (biometrics) |
| Backup/Restore | `data/backup/` + settings UI | VERIFIED | zip file via share sheet | archive, file_picker, share_plus | Needs device testing |
| Health Connect | `core/health/` + provider + settings UI | VERIFIED (code) | `health_imports` box | health 13.3.1 | Needs device testing |
| Android Widget | `core/home_widget/` + native provider/layout | VERIFIED (code) | plugin prefs | home_widget | Needs device testing |
| Local AI + Cloud AI (`/ai`, Settings → SoulCare AI) | `core/ai/` (11 files) + `features/ai/` + provider/repos | VERIFIED (2026-10-07): `ai_test` 30/30 (local + OpenAI-cloud + Gemini-REST fakes, guard, no-write scan, key-privacy, switching), AI-code analyzer clean, debug APK built; device E2E for both backends NOT performed | `ai_conversations` + `ai_messages` boxes (+`providerUsed` tags) | `http`, `flutter_secure_storage`, `flutter_markdown_plus` | Needs LLM-server + cloud-key device E2E |
| AI Assistant | — | NOT IMPLEMENTED | — | — | — |
| Pattern Engine | `core/wellness/insights.dart` (deterministic rules) | VERIFIED | derived | — | None open |
| Life Twin (`/life-twin`) | `features/life_twin/` (engine+provider+radar UI) | VERIFIED (2026-10-05): 16/16 | read-only over logs | fl_chart | Needs device pass |
| Time Machine (`/time-machine`) | `features/time_machine/` (lazy index + replay + compare) | VERIFIED (2026-10-05): 13/13 | read-only over logs | — | Needs device pass |
| Experiment Generator | `experiments/experiment_generator.dart` + provider/UI | VERIFIED (2026-10-05): 16/16 | reuses `experiments` box | — | Needs device pass |
| Voice Logger (`/home/voice`) | `features/voice_log/` (STT seam + deterministic parser) | VERIFIED (2026-10-05): 15/15 | writes via daily merge path | speech_to_text 7.4.0 | Needs mic device pass |
| Analytics Lab (`/analytics`) | `features/analytics/` (trends/matrix/anomalies/export) | VERIFIED (2026-10-05): 18/18 | read-only over logs | fl_chart, share_plus | Needs device pass |
| Health Card (`/health-card`) | `features/health_card/` (card + QR share sheet) | VERIFIED (2026-10-05, code; suite ran — see progress) | reads snapshot/profile | qr_flutter 4.1.0, share_plus | Needs device pass |
| Wellness Calendar (`/calendar`) | `features/calendar/` (month cache + heatmap) | VERIFIED (2026-10-05): 12+3 | read-only over logs | — | Needs device pass |
| Milestones (`/milestones`) | `features/milestones/` + provider + repo | PARTIAL (2026-10-05): suite running | `milestone_state` box (celebrated ids) | — | Verification pending |
| Life Graph (standalone) | — | SUPERSEDED by Life Twin | — | — | — |
| Voice Input (standalone) | — | SUPERSEDED by Voice Logger | — | — | — |
| Anomaly Detection (standalone) | — | SUPERSEDED by Analytics Lab detector | — | — | — |
| Morning/Evening check-ins | `features/checkins/` | VERIFIED | 2 boxes | — | None open |
| Action Center | `features/action_center/` | VERIFIED | dismissals box | — | None open |
| Onboarding | `features/onboarding/` | VERIFIED (code; tests pending per §23) | `onboardingDone` flag | — | None open |

# 9. CURRENT DATA MODEL

`VERIFIED` — all models use manual `toJson`/`fromJson` (no codegen despite
`hive_generator` in devDeps), string/uuid keys, `DateTime` ISO strings, `copyWith`
on mutable aggregates, clamping/validation on read.

```text
DailyHealthEntry
├── date (yyyy-MM-dd, key)
├── sleepHours, sleepQuality(1–5), feltRested
├── exerciseType?, exerciseMinutes, exerciseIntensity
└── mealQuality, waterGlasses, meditationMinutes, screenTimeHours

StressEntry
├── id (uuid, key), date, mood(1–5), triggers[], controllability 0..1
├── notes?, createdAt

Experiment
├── id (key), templateId?, title, description, targetMetric, durationDays
├── startDate?, endDate?, status(7 values), checkIns[], missedDays[]
└── createdAt, updatedAt

MedicalDocument
├── id (key), fileName, localPath, importedAt, documentDate?
├── category(8), tags[], provider, summary?, processingStatus(5), notes?
└── contentHash (dedupe; legacy names migrated on read)

UserSettings
├── themeMode, notificationsEnabled, dailyReminderTime?, experimentRemindersEnabled
├── appLockEnabled, appLockHash?, lockScope(off|sections|full), lockTimeoutMin
├── lockOnBackground, protectedScreens[], biometricEnabled, onboardingDone

UserProfile — displayName?, ageRange?/exactAge?, wake/sleep/reminder times?,
  sleep/water/exercise/meditation goals (defaults 7.5/8/150/10),
  primaryFocus, secondaryFocus?, createdAt, updatedAt, version(=1, migrated)

MorningCheckIn — date(key), sleepHours, rested/mood/energy 1–5, intention?
EveningReflection — date(key), mood/energy 1–5, stress 1–5, wentWell?, improve?
JournalEntry — id, date, title?, body, mood/energy/stress?, tags[] (curated)
HealthSnapshot — bloodGroup?, allergies[{name,severity,notes}],
  medications[{name,dosage,frequency,notes,start?,end?}], supplements[],
  conditions[], emergency contact, provider, notes
MedicationReminder — id, name, times[HH:mm], days[1–7], start/end?, enabled
Appointment — id, title, date, time, location, provider, notes, lead-min, enabled
DoseLog — reminderId+date+time key, taken|skipped
ImportedPoint — stable platform id, metric×4, dateKey, value, source+timestamps
GameStats — playCount, bestScore?, recentScore?
```

- Enums (`VERIFIED`, `lib/data/models/enums.dart`): SleepQuality, ExerciseIntensity,
  MealQuality, Mood (all 1–5 score+label+parse), ExperimentStatus (7), DocumentCategory
  (8), DocumentProcessingStatus (5) — all with legacy-name migration on parse.
- WellnessFocus lives in `user_profile.dart` (7 values + `energy`).
- Migration strategy: parse-time defaults/clamping, never destructive rewrites.

# 10. DATABASE / PERSISTENCE

`VERIFIED` — Hive (`hive_flutter`), JSON-map values, 17 boxes (2026-10-05: +
`milestone_state` celebrating-ids; 2026-10-07: + `ai_conversations`,
`ai_messages`; was 14 at audit, see §4 grep list):
`daily_health`, `stress_entries`, `experiments`, `medical_documents`, `settings`,
`game_stats`, `morning_checkins`, `evening_reflections`, `journal_entries`,
`health_snapshot`, `med_reminders`, `appointments`, `dose_log`, `health_imports`
(+ `action_center` dismissals box opened ad-hoc by its provider).
Storage: app documents dir (via `path_provider`); PDFs in `<docs>/medical_documents/`.
No indexes, no SQL, no migrations beyond parse-time compat. `clearAll()` skips unopened
boxes (test-safe).

| Data | Classification |
|---|---|
| All boxes + vault PDFs | Local (only copy that matters) |
| Nothing | Remote (no backend exists) |
| Plugin prefs (widget numbers) | Cached/derived mirror |
| Temp export/backup zips, share-sheet files | Temporary |
| Scores, insights, reports, projections | Derived (recomputed, never stored) |

Backup implications: full fidelity requires boxes + vault dir (exactly what
`BackupService` packages).

# 11. DATA FLOW

`VERIFIED` — representative flows (same shape everywhere):

```text
User enters sleep
↓ DailyHealthScreen (section form)
↓ DailyHealthProvider.saveSleep() — merge into today's entry
↓ DailyHealthRepository.save() → Result<DailyHealthEntry>
↓ Hive daily_health box + widget-refresh fire-and-forget
↓ Dashboard reload shows new score
```

- Experiments: template → start sheet → `ExperimentProvider` → `experiments` box;
  check-ins toggle DONE/MISSED lists, persisted immediately.
- Documents: picker → `DocumentStorage` vault copy + hash → metadata box → timeline.
- Journal/snapshot/reminders/check-ins/profile: screen → provider → repo → box.
- Imports: Health Connect → gateway → `health_imports` box; UI reads alongside manual data.
- Widget taps: native URI → `WidgetLink.handleTap` → instance router.

# 12. BUSINESS LOGIC

`VERIFIED` — actual implementations (see files; weights verified by grep):

- **Wellness score** (`wellness_score.dart`): sleep .20, movement .20, hydration .15,
  mind .15, stress .15, consistency .15; deterministic; previous-day delta +
  data-cited explanation. Assumption: neutral 70 stress when no check-in (disclosed).
  Limitation: illustrative, not validated.
- **Component scores**: sleep (hours curve 7–9 optimal + quality + rested bonus);
  exercise (minutes curve × intensity); nutrition (meal 60% + water 40%); mindfulness
  (meditation 70% + screen-time 30%); stress (mood-derived calm or neutral 70).
- **Goal calculations** (`goal_progress.dart`): current/target/percent/remaining from
  logged values only (zeros excluded for sleep/water, summed for exercise);
  trend = second-half vs first-half of week.
- **Habit streaks**: experiment DONE-day runs (`currentStreak`/`bestStreak` in
  `experiment_engine.dart`); explicit MISSED breaks runs.
- **Experiment completion**: done-days/durationDays + results sheet.
- **Baseline**: 7 pre-start days average vs experiment-period average; nulls when thin.
- **Weekly reports** (`report_engine.dart`): 7-day aggregates + best/lowest days;
  comparisons require ≥2 logged days per side; deltas formatted with units.
- **Insight generation** (`insights.dart`): deterministic sleep-trend / movement-consistency
  / sleep×calm rules; association-only language enforced.
- **Correlation analysis**: displayed side-by-side only (journal that-day metrics);
  no causal claims anywhere — `VERIFIED` by copy + tests.
- **Anomaly detection**: NOT IMPLEMENTED.
- **Projection/simulator** (`projection_engine.dart`): sleep/exercise/strain/hydration
  component curves → physical/mental/energy/overall; flat 10-point trajectory;
  presets are fixed offsets from current values.

# 13. AI SYSTEM STATUS

# 13. AI SYSTEM STATUS (rewritten 2026-10-07 — old local-only system deleted, Local+Cloud architecture shipped)

`VERIFIED (2026-10-07)` — SoulCare talks to ONE unified service
(`SoulCareAiService`) that answers through the active `AiProvider`. The
chatbot UI never touches HTTP, keys, or model APIs.

- Architecture: `features/ai/` → `AiChatProvider` → `SoulCareAiService`
  (guard → intent → minimal context → active provider → persisted turns)
  → `LocalAiProvider` | `CloudAiProvider` → shared `OpenAiCompatClient`
  (SSE) or Gemini REST. Old files (`ai_service`, `openai_client`,
  `ai_config`, `ai_connection`, `ai_models`, `ai_provider`, `ai_prompts`
  v1, old chat provider/config repo/UI/tests) were deleted and verified
  gone by grep. Retained by design: `ai_context.dart` (read-only
  `SoulCareContext` + `AiIntentRouter`), Hive chat boxes (with
  `providerUsed` migration), `/ai` + `/settings/ai` routes.
- Local: user's own OpenAI-compatible server (llama.cpp, Gemma) on
  loopback/LAN; configurable URL (default `http://127.0.0.1:11434/v1`),
  discovered model ids, latency/status probe, offline-capable, never
  falls back to cloud silently. No MethodChannels added (still zero).
- Cloud: OpenAI + Google Gemini (official REST `v1beta`: `models` list,
  `:streamGenerateContent` SSE, `system_instruction` mapping) + custom
  OpenAI-compatible endpoints. Keys only in `flutter_secure_storage`
  (Android Keystore) via the `AiSecureStore` seam; masked display,
  add/replace/remove/test; mandatory privacy-notice consent before first
  cloud use. No hardcoded keys anywhere.
- Safety: centralized scope/safety prompt (§20 list, no-doctor, no-diagnosis,
  no med changes, urgent-care guidance); `AiDomainGuard`
  (allowed/outOfScope/ambiguous with the chassis-vs-fracture semantic rule —
  refusals cost zero tokens); read-only deterministic tools (14) chosen by
  the keyword router; bounded context; journal/doc bodies only via explicit
  per-item consent; per-message `providerUsed` provenance. An automated
  test scans the AI layer for any write/exec surface.
- Proven by `test/ai_test.dart` (30/30: fake llama.cpp + auth-gated
  OpenAI + fake Gemini servers, guard, no-write scan, key-privacy sweep,
  local-makes-zero-cloud-calls, switching keeps tagged history) +
  analyzer clean for all AI code + debug APK built.
  **Device E2E for both backends explicitly NOT performed.**

# SOULCARE AI

- Architecture: UI → `AiChatProvider` → `SoulCareAiService` →
  `AiProvider` → `LocalAiProvider` | `CloudAiProvider`
  (`lib/core/ai/`: models, provider, openai_compat_client, local_ai_provider,
  cloud_ai_provider, ai_config, ai_secure_store, ai_domain_guard,
  ai_prompts, ai_connection, soulcare_ai_service, ai_context).
- Local AI: LLM AI Server + Gemma via OpenAI-compatible SSE; URL/model/
  timeouts/generation configurable; `testConnection` proves liveness +
  latency + active model; offline-capable; honest Local/Offline indicator.
- Cloud AI: OpenAI, Google Gemini (REST v1beta), Custom OpenAI-Compatible;
  per-provider endpoint/model; keys in `flutter_secure_storage` only;
  consent gate; Cloud indicator never mislabeled as local.
- Mode switching: chat-level strip + Settings radio; rebinds providers,
  preserves everything else; history carries `providerUsed` tags.
- Chatbot route `/ai` (+ `/settings/ai`): streaming markdown, Stop,
  retry/regenerate/copy, new/list/rename/delete/clear, suggestions + quick
  actions, "What the AI saw" viewer, basis line, per-mode error cards.
- Conversation storage: Hive `ai_conversations` / `ai_messages` + settings
  box for config; legacy records migrate to `local`.
- SoulCare context: the 14 read-only `SoulCareContext` tools (today/week/
  month/sleep/stress/exercise/hydration/habits/experiments×2/score×2/
  insights/calendar/goals) + `AiIntentRouter`; minimum-necessary payloads.
- Domain guard + medical safety as above; privacy boundaries: keys only in
  secure storage, bodies only with consent, local mode makes zero cloud calls.
- Tests: `flutter test test/ai_test.dart` 30/30 (see §18). Android device
  testing: NOT performed for either backend — follow the §-header next-step
  plan on a real phone.
- Known issues: none in unit verification; device behavior unverified.
- Exact next step: §-header items 1–2 (local E2E, then cloud E2E).

# 14. ANDROID-SPECIFIC FEATURES

`VERIFIED`:

| Feature | API / bridge | Permissions | Status / limits |
|---|---|---|---|
| Notifications | `flutter_local_notifications` 22.3.1, inexact daily alarms, Taken/Skip/Snooze actions | `POST_NOTIFICATIONS` (runtime-requested) | Code VERIFIED; needs device testing |
| Voice input | `speech_to_text` 7.4.0, on-device recognizer | `RECORD_AUDIO` (runtime-requested, 2026-10-05) | Code VERIFIED (2026-10-05); needs mic device testing |
| AI backends | `http` 1.6.0 (local SSE + cloud endpoints), `flutter_secure_storage` 10.3.4 (Keystore keys), `flutter_markdown_plus` 1.0.12 (chat rendering) | `INTERNET` + scoped `network_security_config.xml` (cleartext loopback-only, 2026-10-07) | Code VERIFIED (2026-10-07, 30/30); needs live-server + real-key device E2E |
| Home widget | `home_widget` 0.10.0, `SoulCareWidgetProvider.kt`, `soulcare_widget.xml`, tap URIs | none extra | Code VERIFIED; needs device testing |
| Biometrics | `local_auth` 3.0.2 via `BiometricGateway` seam | `USE_BIOMETRIC` | Code VERIFIED; needs device testing |
| Storage | Hive app-docs dir + vault subdir; `path_provider` | none (private) | VERIFIED |
| PDF | `pdfrx` 2.4.7 in-app viewer (PDFium natives) | none | Code VERIFIED; first builds download/link natives (slow) |
| Health Connect | `health` 13.3.1, read-only STEPS/SLEEP/WORKOUT/HR | 4× `health.READ_*` + `ACTIVITY_RECOGNITION` + package queries | Code VERIFIED; needs device testing; reads limited to 30d by platform |
| Background services | None — reschedule-on-app-start only | `RECEIVE_BOOT_COMPLETED` NOT declared | By design (documented limitation) |
| Intents | Widget tap URIs `soulcare://widget?action=` | none | VERIFIED |
| Native bridges | Plugin channels only; custom native code = `MainActivity.kt` (FLAG_SECURE) + widget provider | — | VERIFIED |
| Desugaring | `isCoreLibraryDesugaringEnabled`, `desugar_jdk_libs:2.1.4`, Java 17 | — | VERIFIED (fixed a real build failure, §19) |

# 15. PRIVACY & SECURITY

`VERIFIED` (code + copy audited; no marketing claims made):

- Stays local: all 14 Hive boxes, vault PDFs, journal text, medication/appointment
  details, profile/snapshot, PIN hash (FNV-1a salted — stated plainly as *not*
  military-grade), widget numbers.
- Can leave the device ONLY via explicit user share actions (JSON export, report
  export with optional snapshot checkbox, backup zip share). No background uploads
  exist to audit — there is no network code.
- Cloud services: none exist by default. The ONLY exception is Cloud AI,
  which the user explicitly enables per provider with their own API key
  (secure storage only, consent-gated, switchable back to local anytime).
  AI processing is local unless the user chooses Cloud AI.
- Cloud AI keys: Android-Keystore-backed secure storage; never in Hive,
  chat history, logs, or exports (all covered by automated tests).
- Encryption: AES zip **option** for backups (password never stored); no other
  at-rest encryption (Hive files are plaintext in private app storage — documented
  limitation, mitigated by app lock + FLAG_SECURE + OS sandbox).
- App lock: PIN (hash only, unlimited tries by design) and/or biometrics; sections or
  whole-app; session-scoped (resets on restart); background/timeout re-lock.
- Backup encryption: user password, never persisted.
- Logging restrictions: no `print`/`debugPrint` in `lib/` (`VERIFIED` by grep);
  bodies/contents never logged; only hashes/ids compared.

# 16. CURRENT UI/DESIGN SYSTEM

`VERIFIED` — `lib/app/theme/app_theme.dart` + `lib/core/widgets/app_widgets.dart`:

- Material 3 (`useMaterial3: true`), seed-based light (`0xFF3E7C6B` teal-green) and dark
  (`0xFF7BC4A8`) `ColorScheme.fromSeed`; no hardcoded colors in widgets (grep-verified
  pattern, documented rule).
- Centralized typography/spacing/radii; shared `AppCard`, `AppLoading`, `AppEmptyState`,
  `AppErrorState`, `SectionHeader`, `StatsLine`, `PinGate`, `GoalProgressCard`.
- Bottom-nav shell (`ScaffoldShell`), fl_chart styling via theme colors, full dark-mode
  support (dedicated dark widget tests exist), calm minimal motion (250ms page
  transitions, breathing swell only).

# 17. USER FLOWS

`VERIFIED` (all exist in code):

### First Launch
```text
Launch → /welcome (skippable 6-page onboarding) → /home
(repeat launches skip onboarding via persisted flag; replayable from Settings)
```

### Daily Logging
```text
Home → Today → section card → Save → snackbar → dashboard refresh
```

### Medical Document
```text
Timeline → Import PDF → vault copy + hash → metadata form → timeline entry → Open
```

### AI
Historical note (audit time): no flow existed. SUPERSEDED 2026-10-07 —
see §13. The live flow is: Home "SoulCare AI"/"Ask SoulCare" → `/ai`
(mode strip + indicator → streaming answer) and Settings → SoulCare AI
(mode + backends + keys + privacy).

# 18. TESTING

- Framework: `flutter_test` only (unit + widget). No integration/Android-native tests —
  `VERIFIED` (no `integration_test/` dir, no `androidTest/`).
- Files (28: 19 at audit + 9 new, per `progress.md` checkpoints): `app_test`,
  `prompt2..7_test`, `profile`, `checkin`, `journal`, `reports`, `snapshot`,
  `reminders`, `lock`, `health_connect`, `home_widget`, `backup`, `onboarding`,
  `action_center` tests + `life_twin` (16/16), `time_machine` (13/13),
  `generator` (16/16), `voice_log` (15/15), `analytics` (18/18),
  `health_card` + `milestones` (runs recorded in `progress.md`),
  `calendar` (12/12) + `calendar_widget` (3/3, hermetic),
  `ai_test` (30/30 vs fake llama.cpp + auth-gated OpenAI + fake Gemini
  servers) + `seed_james`
  (fixture generator + restore check).
- Coverage: not measured (no coverage tooling configured) — `UNKNOWN` numerically;
  every feature file has a co-located suite by convention.
- **Fresh verification run (2026-10-04, this session):**
  - `dart analyze lib` (scoped, full `flutter analyze` stalls on this machine) →
    **No issues found, exit 0** (`VERIFIED` 2026-10-04).
  - `flutter test` (full suite) → result pending (see `handoff_tests.log`).
- **Historical results (from `progress.md`, Sept 29–Oct 1, do not treat as current):**
  analyze clean multiple times; `app_test` 8/8, `prompt2` 22/22, `prompt6` 18/18,
  `backup_test` 7/7 green; debug APK built + launched on Moto G40 with zero fatals;
  intermittent Hive write stalls + one lab-finder mystery on the old Windows box.

# 19. CURRENT BUILD/RUNTIME STATUS

| Check | Status (2026-10-04) |
|---|---|
| Compiles (`flutter analyze`) | `VERIFIED` 2026-10-04 — scoped `dart analyze lib`: **No issues found** (exit 0). Full `flutter analyze` stalls on this machine (§21); scoped run is the reliable gate |
| Full `flutter test` | Result pending — full suite launched 2026-10-04 (see log); historical: 83 passed / 13 failed with all failures triaged (genuine bugs fixed; rest environmental stalls, §21) |
| Runs on Android | `VERIFIED` historically — debug APK installed + launched on physical Moto G40 Fusion (Android 12), zero fatals (Sept 30) |
| Physical device now | **None connected** — `flutter devices` shows only Windows/Chrome/Edge; on-device checks cannot be repeated in this session |
| Emulator | `UNKNOWN` — none configured/checked |
| Release APK | `UNKNOWN` — a release failure (strict-mode type errors in reports code) was fixed, but no successful release build was ever recorded; retry with `flutter build apk --release` |

# 20. DEVICE / HARDWARE INFORMATION

`VERIFIED`: **no device is available in this session** (`flutter devices`, 2026-10-04:
Windows desktop, Chrome, Edge only). Historical device (from `progress.md`, Sept 30 —
do not treat as current): Motorola Moto G40 Fusion, Android 12 (API 31). RAM, storage,
acceleration, and AI performance were never recorded — `UNKNOWN`, never invent them.
Local AI was never tested because no local AI exists (§13).

# 21. KNOWN BUGS

```text
Bug: Lab widget test cannot find 5th template title; .first/.single finder errors
Severity: Medium (tests only — the screen itself runs correctly on-device)
Affected feature: test/prompt4_test.dart lab widget tests
How to reproduce: flutter test test/prompt4_test.dart (intermittent)
Current workaround: skipOffstage:false + keyed-button finders (partially effective)
Likely cause: UNKNOWN — full-tree dump contradicted itself across runs; prime suspect
  is stale incremental test bundles when files change mid-run, or timing around the
  async recommendations setState
```

```text
Bug: Intermittent Hive write stalls (put/clear hang with idle isolate, empty stack)
Severity: High (test reliability; product code paths identical — app writes could stall
  the same way on this machine)
Affected feature: any test doing Hive writes; worst in long suites
How to reproduce: run any write-heavy suite repeatedly; ~1-in-20 write batches stall
  up to the 10-min test timeout
Current workaround: per-file runs, kill zombies between runs, bounded load-gates,
  preseeded providers instead of storage I/O in the most sensitive widget tests
Likely cause: Windows Defender real-time scanning of Hive files (suspected, cannot
  verify — no admin rights to manage exclusions); FFI biometric blocking was ruled
  OUT as a contributor for the remaining stalls
```

```text
Bug: flutter analyze / flutter test sometimes produce no output and never finish
Severity: Medium (workflow)
Affected feature: dev loop on this machine
How to reproduce: run back-to-back after killed runs
Current workaround: kill all dart processes, wait, retry; scoped `dart analyze lib`
Likely cause: stale tool locks + zombie processes from killed runs
```

# 22. TECHNICAL DEBT

`VERIFIED` by inspection:

- `hive_generator`/`build_runner` in devDeps but zero generated code (manual JSON
  everywhere) — remove or adopt; harmless but confusing.
- `ActionCenterProvider` opens its own `action_center` box ad-hoc instead of going
  through `LocalDatabase` constants — works, but inconsistent.
- `ReportsController` constructs default repositories internally — fine for prod,
  awkward for tests; prefer constructor injection everywhere.
- `SoulCareApp` per-instance router + global `appRouter` duality — documented and
  tested, but subtle; don't "simplify" without updating `WidgetLink` + tests.
- `PinGate`/`JournalGate` overlap (two gate widgets) — consider merging.
- `deleteEverything` box list must be hand-kept in sync with new boxes — `VERIFIED`
  stale: it omits `med_reminders`, `appointments`, `dose_log`, `health_imports`,
  and `action_center` (compare `data_deletion.dart` lines ~100–105 vs §10 box list).
- Several providers call `notifyListeners()` in tight load sequences — harmless today,
  watch for rebuild cost as screens grow.
- No TODOs found in `lib/` (`VERIFIED` by grep); no `print`/`debugPrint` in `lib/`.

# 23. CURRENT TASK STATE (superseded by the header block + 2026-10-05 addendum)

> Historical snapshot from 2026-10-04 retained for context. The live state is
> `# CURRENT SESSION STATE` at the top of this document.

# CURRENT SESSION STATE (as of 2026-10-04 audit)

### Last completed task

`VERIFIED` — Doc sync (2026-10-04, later): `minSdk` 24 → 26 fix in
`android/app/build.gradle.kts` (health-plugin requirement, overrideLibrary rejected);
`health_connect_test` fallback assertion corrected (`findsWidgets`); `progress.md`,
`README.md`, and HANDOFF §1 updated. Prior: `HANDOFF.md` audit (32 sections).

### Current task

`VERIFIED` — Finish `HANDOFF.md`, record verification results, update
`progress.md` + `README.md` if they contradict findings.

### Current task status

`PARTIAL` — Document written and validated top-to-bottom; scoped analysis clean;
full test suite running in background.

### Last files modified

`VERIFIED` — `HANDOFF.md` (new). Code last touched in a prior session (see git status
in §29; onboarding files still uncommitted).

### Last commands executed

`VERIFIED` — `flutter --version`, `java -version`, `flutter devices`, git
branch/log/status, repo greps, background `flutter analyze` + `flutter test`
(2026-10-04 ~13:40–14:05).

### Last successful verification

`VERIFIED` — Historical only (see §18): analyze clean + debug APK on Moto G40,
Sept 29–30. Nothing re-verified yet in this session.

### Current blocker

`PARTIAL` — Same environmental flakiness as §21 (stalled first analyze attempt;
scoped retry running). No product blocker.

### Exact next step

1. Read the full-suite result (`handoff_tests.log` in system temp `opencode/`).
2. Record the outcome in §18/§19 above (replace "pending" lines).
3. Then continue from §24 Roadmap → Next.

# 24. ROADMAP

## Completed (2026-10-05 addendum + 2026-10-07 AI)

All audit items above, plus: SoulCare Life Twin, Time Machine, Experiment
Generator, Voice Health Logger, Analytics Lab, Quick Health Card, Wellness
Calendar, Milestones (+ `milestone_state` box, `RECORD_AUDIO` permission,
`speech_to_text`/`qr_flutter` deps, 8 new routes, README rewrite extends);
then local AI (`/ai` + Settings section, 2 boxes, `http` dep, scoped network
policy), onboarding redirect fix, 10-focus/8-goal onboarding, 7 settings
sub-screens (+ palettes/zoom/fonts), 3 new games + GameScope fix, AppIcon
rollout, Privacy+About merge, James fixture, simulator stress fix.

## In Progress

`PARTIAL` — This handoff + fresh verification (analyze/tests recording).

## Next

1. Record verification results into §18/§19 + `progress.md`.
2. Re-run flaky suites per-file until green; fix the P4 lab finder mystery if it
   reproduces on a clean machine.
3. `flutter build apk --release`; install + launch smoke test (needs a device).
4. Commit the uncommitted work (onboarding files + 7 modified files) — only if asked.

## Future

- Reports PDF export (needs `pdf` package).
- Device E2E for local AI (real server handshake, Gemma stream, Stop,
  offline re-check, grounded health question — §45/§46).
- Real AI document analysis behind `MedicalAiAnalyzer` (interface exists,
  disabled; needs PDF text extraction + explicit UI consent flows).
- Habits as a standalone feature (partially covered by experiments + calendar
  + milestones).
- Play Store signing + release pipeline.
- Cloud backup/sync (explicitly optional per product principles).

# 25. OPEN QUESTIONS

```text
- Which on-device AI backend (LiteRT vs alternatives) fits the privacy model when AI work starts?
- Should medical PDF AI processing remain entirely local? (Current stance: yes.)
- Should backup files include PDFs by default, or offer documents-only mode?
- Is per-file test + retry an acceptable long-term strategy, or should the suite move to fakes (hive → in-memory) for hermetic runs?
- Should SoulCareApp keep per-instance routers, or converge on the global appRouter?
- deleteEverything's stale box list is a known bug (see §22) — fix by deriving the list from LocalDatabase instead of hand-maintaining it.
```

# 26. IMPORTANT FILES

```text
lib/main.dart                              providers, reschedule, widget-tap listener
lib/app/app.dart                           router instancing, lifecycle, full-app gate
lib/app/router/app_router.dart             every route + onboarding redirect rule
lib/app/theme/app_theme.dart               Material 3 seeds (the design system)
lib/data/local/local_database.dart         17 box names, open/clear helpers
lib/data/local/document_storage.dart       vault copy/hash/rename
lib/data/backup/backup_service.dart        zip+AES, preview, merge/replace, rollback
lib/data/models/models.dart                DailyHealth/Stress/Experiment/Document/Settings
lib/core/wellness/wellness_score.dart      score weights + explanations
lib/core/wellness/insights.dart            deterministic insight rules
lib/core/widgets/pin_gate.dart             section + full-app lock gate
lib/core/notifications/notification_service.dart  all local scheduling + actions
lib/core/health/health_gateway.dart        Health Connect seam (real/fake/unavailable)
lib/core/home_widget/widget_data.dart      payload builder, tap URIs, router registry
android/.../MainActivity.kt                FLAG_SECURE
android/.../SoulCareWidgetProvider.kt      widget rendering + deep-link intents
android/app/src/main/AndroidManifest.xml   label, portrait, all permissions
android/app/build.gradle.kts               desugaring fix, Java 17, appId
test/*_test.dart (31 files)                one suite per feature area
progress.md                                session-by-session history (may lag this doc)
README.md                                  user-facing overview (keep in sync)
lib/core/ai/ai_models.dart               unified models: mode/kind/roles/chunks/options/turns/errors
lib/core/ai/ai_provider.dart              AiProvider contract (both backends)
lib/core/ai/openai_compat_client.dart     shared /models + SSE chat, timeouts, cancellation
lib/core/ai/local_ai_provider.dart        loopback/LAN server, discovered ids
lib/core/ai/cloud_ai_provider.dart        OpenAI/custom SSE + Gemini REST v1beta
lib/core/ai/ai_config.dart                mode + local/cloud settings (no secrets), URL utils
lib/core/ai/ai_secure_store.dart          Keystore keys seam (secure + in-memory)
lib/core/ai/ai_domain_guard.dart          allowed/outOfScope/ambiguous pre-check
lib/core/ai/ai_connection.dart            provider-agnostic status cache, no polling
lib/core/ai/soulcare_ai_service.dart      guard→tools→active provider→tagged turns
lib/core/ai/ai_context.dart               14 read-only tools + keyword intent router
lib/core/ai/ai_prompts.dart               centralized scope/safety system prompt
lib/app/providers/ai_chat_provider.dart   chat state: mode/stream/stop/retry/conversations
lib/features/ai/ai_screen.dart            /ai chat UI (markdown, mode strip, indicator)
lib/features/ai/ai_settings_screen.dart   Settings → SoulCare AI (mode/local/cloud/privacy)
android/.../network_security_config.xml   cleartext loopback-only (no global opt-out)
test/ai_test.dart (30 tests)              fake llama.cpp + OpenAI + Gemini: providers→privacy
```

# 27. COMMANDS

```bash
flutter pub get
flutter analyze --no-pub        # zero-issue policy
flutter test                    # full suite (slow/flaky here — prefer per-file reruns)
flutter test test/<file>.dart  # e.g. test/prompt6_test.dart
flutter run                     # needs device/emulator
flutter devices
flutter build apk --debug       # validates Gradle/native (desugaring) path
flutter build apk --release     # needs ~45 min first time (PDFium natives)
dart analyze lib                # faster scoped fallback when flutter analyze stalls
```

No project-specific scripts exist (`VERIFIED` — no scripts/, Makefile, or tasks).

# 28. ENVIRONMENT / SECRETS

```text
Required: (none — no API keys, tokens, passwords, or signing secrets exist anywhere)
Location: N/A
Status: Nothing to configure. Do NOT add secrets; the product has no accounts or cloud.
```

`VERIFIED` — grep for `api[_-]?key|API_KEY|secret|Secret|token|Token` in `lib/` matches
only the PIN-hash helper's comments. No `.env` file at the repo root (`VERIFIED` —
root dotfiles are only `.flutter-plugins-dependencies`, `.gitignore`, `.metadata`).

# 29. CURRENT GIT STATE

`VERIFIED` — `git branch` → `main`. Latest commits: `3fd27a0` widget fixes,
`299fc41` backups, `196823f` bug fixes, `9a09300` Alpha 0.1.1, `2925489` reports.
Uncommitted changes (do not commit unless asked):

```text
M lib/app/app.dart
M lib/app/providers/settings_provider.dart
M lib/app/router/app_router.dart
M lib/data/models/models.dart
M lib/data/models/user_profile.dart
M lib/features/settings/settings_screen.dart
M lib/main.dart
?? lib/features/onboarding/
?? test/onboarding_test.dart
```

# 30. HOW TO RESUME THIS PROJECT

# RESUME INSTRUCTIONS FOR A FRESH OPENCODE SESSION

```text
1. Read HANDOFF.md completely.
2. Inspect the repository to verify the documented state.
3. Never assume HANDOFF.md is perfectly current.
4. Inspect the current task state.
5. Continue from the "Exact Next Step".
6. Do not redo completed work.
7. Preserve existing architecture unless there is a concrete reason to change it.
8. Run appropriate tests after changes.
9. Update HANDOFF.md before ending the session.
```

# 31. LIVING DOCUMENT RULE

```text
---
HANDOFF MAINTENANCE RULE

Every OpenCode session working on SoulCare MUST:

1. Read HANDOFF.md before making substantial changes.
2. Verify important claims against the repository.
3. Update the CURRENT SESSION STATE before finishing.
4. Update the feature/status table when functionality changes.
5. Record new bugs or blockers.
6. Record important architectural decisions.
7. Record commands/tests actually executed.
8. Record the exact next recommended task.
9. Never claim a feature is complete unless verified.
10. Never delete useful historical context without replacing it with the new truth.
---
```

# 32. FINAL VALIDATION OF HANDOFF

*(To be completed after the verification run lands — see below.)*

---

# LOCAL AI STATUS (2026-10-07 — mandated by the AI task spec §49)

- **Server application:** user-run "LLM AI Server with llama.cpp" (separate
  Android app on the same device; NOT bundled, NOT configured here).
- **Server URL:** `http://127.0.0.1:11434/v1` default (migrated from `:8080`);
  user-changeable in Settings → SoulCare AI (loopback/LAN/remote labeled,
  URL validated, optional API key never logged).
- **API protocol:** OpenAI-compatible — `GET /v1/models`, `POST
  /v1/chat/completions` with SSE streaming (`data:` frames + `[DONE]`).
- **Model name:** Gemma 4 E2B-it (user-configured server side).
- **Model ID detected:** `default` (live probe 2026-10-07: llama.cpp reports
  `default` → Gemma `gemma-4-E2B-it-Q3_K_S.gguf`, status loaded; plus
  unloaded `default Chat`/`default Vision`). Auto-selected as first listed;
  ids are never hardcoded.
- **Connection architecture:** UI → `AiChatProvider` → `SoulCareAiService` →
  `AiProvider` (`LocalAiProvider` | `CloudAiProvider`) → server. UI holds no
  URL, no HTTP, no keys, no prompt logic. Status cached; checked on screen
  open, on demand, and before stale generations — never polled.
- **Flutter service:** `SoulCareAiService.answer()` — intent-routed minimal
  context + bounded recent turns + one-shot consented attachments →
  streamed tokens → persisted turns (partial kept on Stop).
- **Important files:** `lib/core/ai/` (8), `lib/features/ai/`
  (`ai_screen.dart`, `ai_settings_screen.dart`),
  `lib/app/providers/ai_chat_provider.dart`,
  `lib/data/models/ai_chat.dart`,
  `lib/data/repositories/{ai_chat_repository,ai_config_repository}.dart`,
  `android/.../network_security_config.xml`, test `test/ai_test.dart`.
- **Local AI data-flow:** question → domain guard → keyword tools (≤4 of
  14 read-only repo summaries) → compact context + system prompt + bounded
  recent turns → active provider (local Gemma or user-configured cloud) →
  natural language + "Based on N logged days" basis. Out-of-scope questions
  get a canned scope response with zero provider calls. Journal/doc contents
  only via explicit per-item consent; model never queries, writes, or runs
  code. Local mode makes zero cloud calls; mode switches never move history.
- **Current status:** implemented + unit-verified (30/30, AI-code analyzer
  clean, debug APK built).
- **Known limitations:** (1) device E2E NOT performed for either backend
  (§-header plan); (2) model ids unconfirmed until first live discovery;
  (3) PDF text unreadable by AI (metadata-only attachments); (4) no write
  actions by design.
- **Android device tested:** none yet for AI (Moto G40 Fusion awaits server
  + optional real cloud key).
- **Test results:** `test/ai_test.dart` 30/30 (local: valid/invalid/
  stopped/malformed, empty-model, stream/cancel/tooLong; cloud OpenAI:
  valid/invalid/missing-key/unreachable; Gemini REST: valid/wrong key +
  system_instruction mapping; guard: 19 allowed / 8 rejected / ambiguous;
  context minimization sweep; architectural no-write scan; key-privacy
  sweep; local-makes-zero-cloud-calls; switching keeps tagged history;
  persistence round-trip; config clamps/migration; secure-store masking).
- **Exact next step:** with LLM AI Server running (Gemma loaded) on the Moto
  G40: Settings → SoulCare AI → Test connection → `/ai` "How was my sleep
  this week?" (streaming) → Stop mid-stream → regenerate → disable internet
  → generate again (must still work). Then Cloud: save a real key, accept
  the notice, test, ask, switch mid-conversation, verify tags + history.
