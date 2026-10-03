# Workout Tracker

This version includes the active workout experience and the storage fixes for Android and Web.

## What is implemented

- Home dashboard with working search entry into the Exercise Library
- Exercise and workout-template search
- Exercise information with images/instructions when the online library is available
- Personalized workout suggestions remain in the existing suggestion system
- Active workout screen
- Workout elapsed timer
- Pause/resume
- Set-by-set completion
- Reps for normal exercises
- Seconds/minutes for timed/cardio exercises
- Per-set timer for timed/cardio exercises
- Rest timer directly inside the workout
- 30s / 60s / 90s / 2m / 3m / custom rest presets
- Auto-start rest after completing a set
- Pause/skip/+30s rest controls
- Active workout auto-save and resume
- Completed workout saving
- Workout duration saved with history
- Workout history with exercise/set counts and duration
- Workout detail and Repeat Workout
- Progress based on workouts, sessions, reps, timed duration, frequency, and streaks
- Separate body-weight tracking/history
- No load/weight field is used for workout exercises or sets

## Storage

- Android/iOS/desktop: SQLite
- Web: SharedPreferences browser storage
- The Web SQLite/WASM dependency that caused the previous WebAssembly error is no longer used.

## Run

After extracting the project:

```bash
flutter pub get
flutter run -d emulator-5554
```

For Chrome:

```bash
flutter run -d chrome
```

Run `flutter devices` first if your emulator ID is different.

## Important

The Flutter SDK is not installed in the build environment used to prepare this archive, so this archive was source-inspected but not runtime-tested here. Run `flutter pub get` before launching so Flutter regenerates `pubspec.lock` for the current dependency set.
