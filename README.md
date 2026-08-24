# BitWatch

A Flutter (Android-only) real-time network data usage monitor. Tracks live
upload/download speed, an "Active Data Timer" session, and a 30-day Mobile /
Wi-Fi / Total usage history — backed by a Kotlin foreground service that
keeps a persistent, self-healing status bar notification alive even when the
app is backgrounded.

Supports Android 6.0 (API 23) through Android 15 (API 35).

## Project layout

```
lib/
  models/        DailyUsage, SpeedSample
  services/      DatabaseService (sqflite), PlatformService (Method/EventChannel),
                  PermissionService
  providers/     Riverpod: speedSampleProvider, timerControllerProvider, historyProvider
  screens/       DashboardScreen, HistoryScreen
  widgets/       TimerCard, SpeedIndicatorRow
  main.dart

android/app/src/main/kotlin/com/bitwatch/app/
  MainActivity.kt               MethodChannel + EventChannel host
  BitWatchForegroundService.kt  Persistent notification + per-second ticking
  NetworkStatsHelper.kt         NetworkStatsManager / TrafficStats queries
  SpeedIconFactory.kt           Renders download speed as a status bar bitmap icon
  NotificationDismissReceiver.kt  Re-anchors the notification if swiped away
  BootReceiver.kt               Restarts the service after device reboot

.github/workflows/build_apk.yml   CI: builds a release APK on every push to main
```

## Prerequisites

- Flutter SDK (stable channel), 3.24+
- Android SDK / command-line tools, with `ANDROID_HOME` set
- JDK 17

## Running locally

```bash
flutter pub get
flutter devices          # confirm an Android device/emulator is attached
flutter run
```

On first launch BitWatch will:
1. Request the `POST_NOTIFICATIONS` and `READ_PHONE_STATE` runtime permissions.
2. Detect that it lacks the **Usage access** special permission and prompt
   you to grant it in Settings (there is no runtime dialog for this one —
   Android requires a manual toggle at
   *Settings → Apps → Special app access → Usage access → BitWatch*).
3. Start the foreground service, which posts the persistent notification.

## Building a release APK

```bash
flutter build apk --release --split-per-abi
# output: build/app/outputs/flutter-apk/app-*-release.apk
```

The debug signing config is used by default (see `android/app/build.gradle`)
so this works out of the box. **Before publishing**, replace it with your own
release keystore:

```gradle
signingConfigs {
    release {
        storeFile file("your-release-key.jks")
        storePassword "..."
        keyAlias "..."
        keyPassword "..."
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
        ...
    }
}
```

## CI/CD

`.github/workflows/build_apk.yml` builds a release APK on every push/PR to
`main` and uploads it as a workflow artifact named `bitwatch-release-apk`.
No secrets are required since it uses debug signing; add a signing step once
you wire up a release keystore.

## Pushing this project to GitHub

This project was generated in a sandbox without direct GitHub write access.
From your machine, after downloading/extracting the project:

```bash
cd bitwatch
git init
git add .
git commit -m "Initial commit: BitWatch Flutter app"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

Once pushed, the GitHub Actions workflow will run automatically and build
the APK for you.

## Known platform caveats (read before relying on this in production)

- **Mobile subscriber ID**: `NetworkStatsManager.querySummary` technically
  wants a subscriber ID for `TYPE_MOBILE` queries. `NetworkStatsHelper`
  tries the real one via `TelephonyManager`, then falls back to an empty
  string. Most devices holding the `PACKAGE_USAGE_STATS` special permission
  return correct aggregate totals either way, but a minority of OEM builds
  are stricter — test on your target devices.
- **Status bar icon**: Android doesn't support arbitrary text natively on
  `setSmallIcon`; `SpeedIconFactory` draws the download speed onto a bitmap
  each tick. This is a common, well-established technique but does mean the
  icon is a bitmap rather than a themed adaptive vector.
- **"Non-dismissible" notification**: `setOngoing(true)` plus
  `NotificationDismissReceiver` (which immediately restarts the service if
  the delete intent fires) covers the vast majority of OEM launchers. A
  small number of heavily customized skins (e.g. some MIUI/ColorOS battery
  managers) can still kill background services outright regardless of app
  code; users may need to disable battery optimization for BitWatch.
- **App icon**: `ic_launcher.xml` is a placeholder vector icon. Replace it
  with a real adaptive icon (via Android Studio's Image Asset Studio) before
  publishing.
- **Release signing**: ships with debug signing so the CI workflow succeeds
  immediately; swap in a real keystore before publishing to Play Store.
