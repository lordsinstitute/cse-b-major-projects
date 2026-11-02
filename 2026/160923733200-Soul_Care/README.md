# SoulCare

**A private, local-first personal wellness and health organization app for Android.**

SoulCare helps you track daily habits, understand your personal patterns, run small
self-experiments, organize health documents, and explore illustrative wellness scenarios —
all on your device, with no account, no login, and no cloud required.

> **Wellness, not medicine.** SoulCare is a tracking and organization tool. Scores,
> trends, and scenarios are illustrative summaries of *your logged data* — never medical
> diagnosis, disease prediction, clinical assessment, or treatment recommendations.

---

## Table of contents

- [Principles](#principles)
- [Features](#features)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Persistence](#persistence)
- [Getting started](#getting-started)
- [Commands](#commands)
- [Project structure](#project-structure)
- [Privacy & safety](#privacy--safety)
- [Testing](#testing)
- [Status & roadmap](#status--roadmap)

---

## Principles

| Principle | What it means in practice |
|---|---|
| **Local-first** | Hive boxes on-device are the source of truth. The app opens and works fully offline; cloud features (if ever added) must be optional. |
| **No authentication** | No login, signup, password, or auth wall of any kind. The app opens directly to Home. |
| **Honest numbers** | Deterministic calculators, disclosed placeholders, no fabricated data points, no causal claims, no fake AI output. |
| **Calm design** | Material 3, ColorScheme-driven, spacious and minimal — no clutter, no garish gradients. |

---

## Features

### 🏠 Home dashboard (`/home`)
Answers *"How am I doing today?"* with a deliberate visual hierarchy:
Greeting → routine cards → wellness-score hero → daily progress → goals strip →
action center (max 3 dismissible "pay attention" actions) → top insight → quick actions →
weekly overview → active experiment. Brand-new users get a polished empty state
(*"No data yet"* + *"Log your first day"*).

### 📝 Daily health (`/today`)
Five independently-saving sections — **Sleep, Movement, Nutrition & Hydration,
Mind, Stress** — built for fast mobile logging (sliders, chips, segmented controls,
sensible defaults, no unnecessary typing). Each section shows an opt-in
*"Yesterday: …"* suggestion that never overwrites data silently. Completion is tracked
as *"X / 5 sections completed"* with subtle check states. Stress check-ins cover mood
1–5, triggers, controllability, optional notes, plus an optional 60-second breathing reset.

### 🎙️ Quick Voice Log (`/home/voice`)
Speak (or type) a natural update — *"I slept around seven hours, walked for
thirty minutes, drank six glasses of water…"* — and confirm the extracted
Sleep / Energy / Exercise / Water / Stress rows before anything saves.
Deterministic parsing with per-section checkboxes and editing; on-device
speech recognition (`speech_to_text`, `RECORD_AUDIO`); recordings never
uploaded, temporary audio discarded. Only checked sections are written, and
only through the normal daily merge path.

### 🧾 Medical timeline & document vault (`/timeline`)
A local PDF organizer: import one or many PDFs (type/size/readability/duplicate
validation, 25 MB cap), files copied into an app-controlled vault, metadata stored
separately. Year → month → document grouping with document-date vs import-date clearly
distinguished, instant search (filename, category, tag, provider, notes), category filters,
detail screen (Open · Rename · Edit metadata · Delete), in-app PDF viewing, and an honest
processing abstraction (`MedicalDocumentProcessor`) that reports *unavailable* rather than
faking AI summaries.

### 🔬 Experiments lab (`/lab`)
Five 7-day templates (Earlier Sleep, Daily Walk, Breathing Reset, Hydration Consistency,
Reduced Late-Night Screen Time). One active experiment at a time, confirmed start flow with
live baseline, big DONE/MISSED check-ins with accident correction, streaks, factual
before/during baseline comparison (*"observed difference … many factors can influence it"*),
results sheets, data-driven recommendations (max 3, each with its logged-data reason),
a **personal generator** (up to 3 suggestions from goals, history, habits, trends and
past experiments — explicit approval sheet, never auto-starts, same measurement system),
and a completed/abandoned history archive.

### 🔮 Wellness simulator (`/future`)
Deterministic *"what-if"* sketches — never predictions. Baseline computed from tracked data
(refuses to invent one when data is thin), four scenario sliders, five presets starting from
current values, current-vs-scenario delta with named contributors, flat 10-year illustrative
trajectory with mandatory disclaimers, up to 4 temporary comparison sketches, one-tap reset.
Read-only: it can never modify health records.

### 🌐 SoulCare Life Twin (`/life-twin`)
An interactive visualization of tracked wellness state ( Sleep, Energy, Stress,
Movement, Hydration, Mindfulness, Consistency — never a clinical model).
Overall index with confidence and contributing days, tappable dimensions with
trend/detail panels, association-only relationship graph, 7/30/90-day and
6-month windows, and an in-memory scenario mode clearly badged My Data vs
Scenario. All computation stays on-device.

### 🕰️ Time Machine (`/time-machine`)
Replay personal history from logged records: lazy horizontal timeline with
experiment/journal/document/streak/goal markers, animated date replay
(score, sleep, calm, mood, energy, movement, water, active experiment, notes),
day/week/month periods with `Replay this period`, and A/B comparison of two
dates or periods. Gaps stay gaps — nothing is fabricated.

### 📈 Analytics Lab (`/analytics`)
Research/exploration views over the trailing 90 days: moving averages with
weekly/monthly trends and change detection, a neutral 21-cell observed-
correlation matrix (≥5 paired days, tap for coefficient/sample/range/
explanation), MAD-based unusual-day flags, baseline-vs-experiment stats
(mean/median/difference/completion), 30-day completeness bars, statistics
explainers, and JSON report export. Observed patterns only — never medical
conclusions, never causal claims.

### 📅 Wellness Calendar (`/calendar`)
A visual history of the wellness journey: monthly grid with subtle visual
states (Excellent / Good / Mixed / Difficult / No data — classifications only,
never health claims, always with icon + label, never color-only), tap-through
day detail (score, sleep, exercise, water, calm, mood, habits, experiment
status, journal/document indicators), month summaries, Sleep/Stress focus
filters, a GitHub-style 30/90/365-day consistency heatmap with per-mode
palettes, and `Explore this month` handoff into the Time Machine. Reached
from Home and from Reports. Per-month caching and key-only heatmaps keep it
fast on large histories.

### 🏅 Milestones (`/milestones`)
Quiet recognition for consistency and progress — no points, leaderboards, or
hidden achievements. Sixteen data-derived milestones (logging streaks,
experiments, habit consistency, reflections, complete days) with achieved
dates, next-milestone progress, and one calm acknowledgment per unlock.
Extremes are never rewarded; everything is recomputed from real logs, with
celebration state surviving restarts. The Home screen shows only the most
recent unlock with a View-all entry.

### 🎮 Games & mind breaks (`/games`)
Eight isolated games, each persisting play count / best / recent locally: Memory Match,
Reaction Time (5 rounds), Number Sequence (gently growing, always solvable), Breathing Pacer
(inhale 4 / hold 4 / exhale 6, 1–5 cycles), Word Scramble (curated wellness list, fair anagrams),
Color Match (Stroop ink-vs-word focus, 10 rounds), Pattern Echo (watch-then-repeat,
growing pattern), Bubble Pop (30 calm seconds). Every game screen ships its own
stats scope, so sub-routes never open without one.

### 👤 Profile & goals (`/settings/profile`)
All-optional personal context (name, age range, wake/sleep times, sleep/water/exercise/
meditation targets, reminder time, primary + secondary wellness focus) with versioned,
non-destructive migration. Focus only reorders suggestions and the dashboard "My goals"
strip (max 3, hidden when empty) — scoring never changes. The app stays fully functional
with an empty profile; no wizard, no blocking.

### 🌅🌙 Morning & evening routine (`/home/morning`, `/home/evening`)
30-second morning flow (sleep, rested, mood, energy, optional intention → summary + `/today`
link) and a quiet evening reflection (mood/energy/strain + 2 optional notes → "Today at a
glance" with completion, score, metrics, experiment progress, one factual sentence). One
record per date, editable; morning saves prefill unlogged sleep only. Quiet dashboard
cards prompt until done, collapse away after.

### 📖 Wellness journal (`/home/journal`, `/home/journal/:id`)
Local-only journaling: full entries (title/body/mood/energy/strain/curated tags) and
2-tap quick notes, entirely-local search + tag/mood filters, detail with that-day health
metrics shown as correlation-only, confirmed deletes, and a 4-digit PIN lock gate
(hash-stored, session-scoped). No journal text uploaded, logged, or AI-sent — ever.

### 📊 Wellness reports (`/home/reports`)
Deterministic weekly (overview/sleep/movement/hydration/stress/mind, week-over-week deltas,
factual summary) and monthly (trends, goal consistency, experiments, habits, journal and
document counts) summaries from existing logs, with honest empty states and JSON export
(documents as references, health snapshot only on explicit opt-in).

### 🪪 Quick Health Card (`/health-card`)
A polished personal information card (never a diagnosis system): name, blood
group, allergies, active medications, emergency contact, provider and notes —
only fields actually entered are shown, with an initials avatar (no photo
stored). `Share Health Card` mode offers per-field checkboxes with safe
defaults, an explicit recipients-can-see warning, a live offline QR code plus
text preview of the exact payload (nothing hidden), and share-sheet export.
Journal entries, history, documents and analytics can never leak into the
payload by construction.

### 🩺 Health snapshot (`/home/snapshot`)
Manually maintained record: blood group, allergies (name/severity), medications
(name/dosage/frequency/dates + active detection — record only, never advice), supplements,
conditions, emergency contact, provider, notes. Concise quick-view card, lock-gated,
clearable, optionally included in report exports.

### 💊 Reminders & appointments (`/home/care`)
User-controlled medication reminders (times, weekday subsets, start/end windows, on/off)
and appointments (title/date/time/location/provider/advance notice) via on-device
notifications with Taken / Skip / Snooze actions persisted locally. Calendar-like upcoming
view, neutral history ("No record" — never framed as failure), rescheduling on every app
start (reboot/clock/permission changes).

### 🔒 Privacy & app lock
Optional biometric unlock (`local_auth`, PIN fallback always) for sensitive sections
(journal, snapshot, timeline, reminders, reports) or the entire app; Immediately / 1 min /
5 min / on-background timing; `FLAG_SECURE` blanks app-switcher previews; failed attempts
never lock out; raw PIN never stored. Lifecycle-aware re-locking throughout.

### 👋 First-run onboarding (`/welcome`)
Skippable 6-page setup (welcome → up-to-2 focus areas → up-to-3 starter goals
→ reminder opt-in → privacy note → ready) with no login and no required
fields. Writes profile targets (higher tier wins per area), reminder
preference (permission only on explicit Yes), and a persisted completion flag;
replayable from Settings. Skipping or finishing lands directly on `/home`
with defaults intact.

### 📲 Health Connect integration (Settings → Health data)
Optional read-only access to device steps, sleep, workouts, and heart rate via the
`health` package (READ permissions only, last-14-day window). Explicit Connect / Sync /
Disconnect; denial or unsupported devices leave manual logging fully working. Imports are
stored separately with source + timestamps, badged "Imported" next to manual logs, and
deduplicated by stable platform ids — never merged into manual records, never uploaded.

### 🧩 Home-screen widget (Android)
Compact widget showing wellness score + daily completion from the last app save (offline,
no polling; guarded so the app is unaffected when unavailable). Taps deep-link to
logging screens (`/today`, `/home/morning`, `/home`); buttons hidden until first save.

### 💾 Backup & restore (Settings → Backup & Restore)
One portable `.zip` per backup: versioned manifest (`SoulCare Backup v1`), all 13 Hive
boxes, vault PDFs bundled inside. Optional AES password (never stored). Restore previews
counts + creation date before touching anything, then Merges (never overwrites newer data)
or Replaces — with an automatic safety snapshot + rollback on any failure.

### 🤖 SoulCare AI (`/ai`, Settings → SoulCare AI)
Read-only wellness assistant with two switchable backends behind one UI:
**Local AI** (your own llama.cpp server, Gemma; default
`http://127.0.0.1:11434/v1`, changeable — offline-capable, no cloud
involved) and **Cloud AI** (OpenAI, Google Gemini via REST, or any custom
OpenAI-compatible endpoint, using your API key from platform secure
storage — never in code, database, logs, or exports). Switch modes anytime
from the chat or settings; history, health data, and settings are never
touched by switching. First cloud use requires accepting a privacy notice.
Streaming markdown chat with Stop, retry/regenerate, persisted
conversations with per-message provider tags, data-gated suggestions and 5
quick actions. Answers are grounded in minimal deterministic context
(summaries, never database dumps); journal and document contents only via
explicit per-item consent. A domain guard keeps the assistant on
wellness/health/SoulCare topics; unrelated questions get a polite scope
response without spending tokens. Never diagnoses, never prescribes, never
modifies or deletes your data — there are no write tools at all.

### ⚙️ Settings (`/settings`)
Hub of grouped subsections: Appearance (Light/Dark/System, 6 color palettes,
50–200% interface zoom, font style + size), profile & goals entry, on-device local
notifications (daily reminder + time picker, experiment reminders — no FCM), privacy lock
management, detailed Privacy & About (storage, lock mechanics, network behavior,
per-permission rationale, backups, deletion, plus version/credits/tour), SoulCare AI
(server, model, generation) section, readable JSON export (PDFs referenced, never
embedded) via the share sheet, scoped deletion (daily / experiments / documents /
everything — every wipe confirmed).

---

## Architecture

```text
UI (screens/widgets)
  → Provider/Controller (ChangeNotifier, feature-scoped)
    → Repository (clean CRUD, Result<T> errors)
      → Local data source (Hive boxes, app vault dir)
```

- **State:** `provider`. App-level providers for settings, daily health, dashboard,
  experiments; feature-local state (simulator, games, documents) stays in its feature.
- **Navigation:** `go_router` declarative routing with a bottom-navigation shell.
  Routes: `/welcome` (first-run), `/home` (+ `morning`, `evening`, `journal`, `journal/:id`, `reports`,
  `snapshot`, `care`, `voice`), `/today`, `/timeline` (+ `doc/:id`, `doc/:id/view`),
  `/lab`, `/future`, `/games` (+ 8 game routes), `/settings` (+ `profile`, `appearance`,
  `notifications`, `lock`, `health`, `privacy`, `data`, `ai`),
  `/life-twin`, `/time-machine`, `/analytics`, `/health-card`, `/calendar`,
  `/milestones`, `/ai`.
  No auth routes.
- **Theme:** centralized Material 3 light/dark/system themes, seed-based `ColorScheme`,
  shared spacing/radii/typography constants — no hardcoded colors in widgets.
- **Errors:** `Result<T>` (`Success`/`Failure`) end-to-end; friendly loading/empty/error
  states everywhere; raw exceptions never reach the UI; user data is never silently lost
  (and deletions never falsely report success).

---

## Tech stack

| Role | Package |
|---|---|
| UI framework | Flutter (Material 3) · Dart |
| State | `provider` |
| Navigation | `go_router` |
| Local database | `hive` + `hive_flutter` (+ `path_provider`, `path`) |
| Tiny prefs mirror | `shared_preferences` (theme string only) |
| Charts | `fl_chart` |
| PDF viewing | `pdfrx` (PDFium, in-app) |
| File picking | `file_picker` |
| Local notifications | `flutter_local_notifications` (+ `timezone`, `flutter_timezone`) |
| Health data | `health` (read-only Health Connect: steps/sleep/workouts/HR) |
| On-device speech recognition | `speech_to_text` (Quick Voice Log; mic only, no uploads) |
| On-device QR codes | `qr_flutter` (health-card sharing, offline) |
| On-device AI fonts | `google_fonts` (display fonts; one-time download, then cached offline) |
| AI HTTP | `http` (local loopback/LAN server + user-configured cloud endpoints) |
| AI responses | `flutter_markdown_plus` (streaming markdown rendering) |
| Cloud key storage | `flutter_secure_storage` (Android Keystore-backed; keys never in Hive/logs) |
| Home widget | `home_widget` (prefs + tap deep links, guarded calls) |
| Biometric unlock | `local_auth` (PIN fallback, on-device only) |
| Export sharing | `share_plus` |
| Backup archives | `archive` (AES-capable zip, local only) |
| Utilities | `uuid`, `intl`, `collection` |

Android is the primary (and only) target: portrait-first, edge-to-edge, `adjustResize`
keyboards, `SafeArea`-aware shell, `POST_NOTIFICATIONS` permission for local reminders,
`USE_BIOMETRIC` for on-device unlock, `RECORD_AUDIO` for on-device voice input,
`INTERNET` for AI servers (local loopback/LAN + user-configured cloud
endpoints; cleartext restricted to loopback via network policy),
`FLAG_SECURE` against app-switcher previews.

---

## Persistence

One persistence solution — **Hive** — with a box per domain:

| Box | Contents |
|---|---|
| `daily_health` | `DailyHealthEntry` per day (`yyyy-MM-dd` keys) |
| `stress_entries` | `StressEntry` check-ins (uuid keys) |
| `experiments` | `Experiment` incl. check-ins/missed days |
| `medical_documents` | Document *metadata* (JSON) |
| `settings` | `UserSettings` (source of truth) |
| `game_stats` | Per-game plays/best/recent |
| `morning_checkins` / `evening_reflections` | One record per date each |
| `journal_entries` | Journal entries (uuid keys) |
| `health_snapshot` | Single manual record |
| `med_reminders` / `appointments` / `dose_log` | Reminders, appointments, Taken/Skip logs |
| `health_imports` | Imported Health Connect points (stable platform ids) |
| `milestone_state` | Celebrated milestone ids (milestones re-derived from data) |
| `ai_conversations` / `ai_messages` | AI chat turns with provider tags (uuid keys; old records migrate to `local`) |

PDF bytes live separately in the app-controlled `<app docs>/medical_documents/` vault
(content-hashed for duplicate detection). UI code never touches Hive directly — only
repositories do. `SharedPreferences` mirrors just the theme string for fast startup.

---

## Getting started

Prerequisites: Flutter 3.41+ (Dart 3.11+), Android SDK with a connected device or emulator.

```bash
# 1. Get dependencies
flutter pub get

# 2. Static analysis (must be clean)
flutter analyze --no-pub

# 3. Run the test suite
flutter test

# 4. Run on Android
flutter run

# 5. Release build (note: first build downloads/links PDFium natives, takes a while)
flutter build apk --release
```

> **Build note:** `flutter_local_notifications` requires core-library desugaring, enabled in
> `android/app/build.gradle.kts` (`isCoreLibraryDesugaringEnabled = true`,
> `desugar_jdk_libs:2.1.4`, AGP 8.11.1). Java stays at 17 — AGP 8 requires it.
> `minSdk` is hardcoded to **26** (raised from the Flutter default 24) because the
> `health` plugin's Health Connect APIs require API 26+; do not lower it while that
> dependency is present. This drops Android 7.x and below, which cannot run
> Health Connect anyway.

---

## Commands

| Command | Purpose |
|---|---|
| `flutter pub get` | Resolve dependencies |
| `flutter analyze --no-pub` | Static analysis (zero-issue policy) |
| `flutter test` | Full suite (`test/` — one file per prompt/area) |
| `flutter test test/<file>.dart` | Single area, e.g. `test/prompt6_test.dart` |
| `flutter build apk --debug` | Debug APK (also validates the Gradle fix) |
| `flutter build apk --release` | Release APK |
| `flutter install -d <device-id> --use-application-binary=<apk>` | Install a built APK |

---

## Project structure

```text
lib/
├── main.dart                  # edge-to-edge, portrait, provider wiring
├── app/
│   ├── app.dart               # MaterialApp.router + theme binding
│   ├── providers/             # settings, daily_health, dashboard,
│   │                          # experiments, documents (+ game/sim
│   │                          # controllers live in their features)
│   ├── router/                # go_router config + bottom-nav shell
│   │                          # (+ /life-twin, /time-machine, /home/voice)
│   └── theme/                 # Material 3 light/dark system
├── core/
│   ├── constants/ errors/ extensions/ utils/ widgets/
│   ├── documents/             # MedicalDocumentProcessor abstraction
│   ├── notifications/         # on-device reminder scheduling
│   └── wellness/              # score calculator + insight engine
├── data/
│   ├── models/                # typed models + enums (no magic strings)
│   ├── repositories/          # CRUD per domain, Result<T> API
│   ├── local/                 # Hive boxes + document vault storage
│   ├── export/                # JSON export + scoped deletion
│   └── backup/                # portable zip backup + safe restore
└── features/
    ├── dashboard/ daily_health/ timeline/
    ├── experiments/ simulator/ games/ settings/
    ├── profile/ checkins/ journal/ reports/ snapshot/ reminders/
    ├── life_twin/ time_machine/ voice_log/
    ├── analytics/ health_card/ calendar/
    ├── milestones/
test/
├── app_test.dart              # init, routing, settings persist, theme
├── prompt2_test.dart          # daily health + dashboard
├── prompt3_test.dart          # documents vault + timeline
├── prompt4_test.dart          # experiments lab
├── prompt5_test.dart          # simulator
├── prompt6_test.dart          # games
├── prompt7_test.dart          # settings/privacy/export/deletion
├── profile_test.dart          # profile, goals, focus ordering
├── checkin_test.dart          # morning/evening routine
├── journal_test.dart          # journal + PIN lock
├── reports_test.dart          # weekly/monthly reports
├── snapshot_test.dart         # health snapshot + lock gate
├── reminders_test.dart        # med/appointment schedules + history
├── action_center_test.dart     # engine priorities, dismissals, widgets
├── lock_test.dart              # biometrics, timeouts, scopes, gates
├── backup_test.dart            # backup/restore/versioning/rollback
├── health_connect_test.dart    # permissions, import, dedupe, fallback UI
├── home_widget_test.dart       # payload, tap routing, refresh, registry
├── onboarding_test.dart        # redirect rule, full/skip flows, persistence
├── life_twin_test.dart          # twin engine, relationships, scenario, widgets
├── time_machine_test.dart       # history replay, events, comparison, widgets
├── generator_test.dart          # experiment generation, approval, results
├── voice_log_test.dart          # voice parsing, confirmation, save, widgets
├── analytics_test.dart          # trends, correlations, anomalies, export
├── health_card_test.dart        # card fields, payload selection, QR, restart
├── calendar_test.dart           # month engine, summaries, provider caching
├── calendar_widget_test.dart    # hermetic calendar widgets (seeded provider)
├── milestones_test.dart         # milestone engine, persistence, widgets
├── ai_test.dart                 # AI: local+cloud providers, guard, safety, privacy, switching (30)
└── seed_james_test.dart         # James fixture generator + restore check
```

Development history and per-prompt verification notes live in `progress.md`.

---

## Privacy & safety

- Everything listed under [Persistence](#persistence) stays on the device.
- Nothing is uploaded automatically. Data leaves the device only when *you* share an export.
- Voice recordings are never uploaded; temporary recognition audio is discarded.
- SoulCare AI has two backends: Local AI (your configured server,
  loopback by default, no cloud involved) and Cloud AI (your provider +
  your key; requires accepting the privacy notice first). The app never
  switches backends silently and never mislabels cloud answers as local.
  Cloud keys live only in platform secure storage. Journal and document
  contents reach any backend only via your explicit per-item consent.
- No cloud backend is configured; AI document processing reports *unavailable* by default.
- Language discipline: *"wellness score"*, *"tracked pattern"*, *"personal trend"*,
  *"illustrative scenario"*, *"based on your logged data"* — never diagnosis or prediction.

---

## Testing

- `flutter analyze --no-pub`: **0 issues** (verified).
- `flutter test`: per-area suites covering models, repositories, providers, engines
  (determinism, honesty guards, fairness), persistence across restarts, empty states,
  dark mode, and widget flows. The debug APK was built, installed on a physical
  Moto G40 Fusion (Android 12), launched to a resumed `MainActivity` with zero fatal
  exceptions in logcat.
- Known environment note: Hive file writes stall intermittently on the Windows dev
  machine used here, which can flake long test runs; the two most write-sensitive widget
  tests use a `@visibleForTesting` provider seam instead of storage I/O.

---

## Status & roadmap

All feature areas are implemented, analyzer-clean, and exercised by tests
(incl. a 30-test AI suite: local + cloud providers, Gemini REST, domain
guard, data-safety, privacy, mode switching); the release APK path is
proven through the debug build + on-device install.
Remaining work is verification depth (fully-green long suite runs,
release-APK device pass, on-device AI end-to-end against a real local
server AND a real cloud key, incl. offline local inference) and future
ideas: optional cloud backup, real document-processing backend behind the
existing interface, reminder refinements, and Play Store release signing.
