import 'dart:async';
import 'package:flutter/services.dart';

import '../models/daily_usage.dart';

/// Single point of contact with the native Android side.
///
/// - [methodChannel] handles one-shot request/response calls (usage queries,
///   permission checks, service lifecycle, timer state sync).
/// - [eventChannel] streams a [SpeedSample] roughly once per second while the
///   app UI is in the foreground. It is implemented natively in
///   MainActivity.kt (see android/.../MainActivity.kt) using a Handler loop
///   over TrafficStats + NetworkStatsManager. The always-on foreground
///   Kotlin Service updates the status bar notification independently, so
///   the notification keeps ticking even if this stream isn't being listened
///   to (e.g. app backgrounded/killed by the user but service still running).
class PlatformService {
  PlatformService._internal();
  static final PlatformService instance = PlatformService._internal();

  static const MethodChannel _methodChannel =
      MethodChannel('com.bitwatch.app/methods');
  static const EventChannel _eventChannel =
      EventChannel('com.bitwatch.app/speedStream');

  Stream<SpeedSample>? _speedStream;

  /// Broadcast stream of live speed / timer / today-usage samples.
  Stream<SpeedSample> get speedStream {
    _speedStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => SpeedSample.fromMap(event as Map));
    return _speedStream!;
  }

  // ---------------------------------------------------------------------
  // Usage stats (backed by android.app.usage.NetworkStatsManager)
  // ---------------------------------------------------------------------

  /// Returns {'mobile': int, 'wifi': int} for the current calendar day.
  Future<DailyUsage> getTodayUsage(String todayDateStr) async {
    final result = await _methodChannel.invokeMethod<Map>('getTodayUsage');
    return DailyUsage(
      date: todayDateStr,
      mobileBytes: (result?['mobile'] as num?)?.toInt() ?? 0,
      wifiBytes: (result?['wifi'] as num?)?.toInt() ?? 0,
    );
  }

  /// Returns {'mobile': int, 'wifi': int} for an arbitrary past day.
  /// [dateStr] must be yyyy-MM-dd.
  Future<DailyUsage> getUsageForDate(String dateStr) async {
    final result = await _methodChannel
        .invokeMethod<Map>('getUsageForDate', {'date': dateStr});
    return DailyUsage(
      date: dateStr,
      mobileBytes: (result?['mobile'] as num?)?.toInt() ?? 0,
      wifiBytes: (result?['wifi'] as num?)?.toInt() ?? 0,
    );
  }

  // ---------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------

  /// PACKAGE_USAGE_STATS is a "special access" permission that cannot be
  /// requested via a runtime dialog - the user must flip it on in Settings.
  Future<bool> hasUsageAccessPermission() async {
    final granted =
        await _methodChannel.invokeMethod<bool>('hasUsageAccessPermission');
    return granted ?? false;
  }

  /// Opens Settings > Apps > Special app access > Usage access, scrolled (on
  /// most OEMs) to BitWatch.
  Future<void> openUsageAccessSettings() async {
    await _methodChannel.invokeMethod('openUsageAccessSettings');
  }

  // ---------------------------------------------------------------------
  // Foreground service lifecycle
  // ---------------------------------------------------------------------

  Future<void> startForegroundService() async {
    await _methodChannel.invokeMethod('startForegroundService');
  }

  /// Stops the Kotlin foreground service, cancels the ongoing notification,
  /// and (from the Dart caller) the app should follow this with
  /// SystemNavigator.pop() / exit(0) to fully terminate the process, per the
  /// "Stop And Exit" menu action.
  Future<void> stopForegroundService() async {
    await _methodChannel.invokeMethod('stopForegroundService');
  }

  // ---------------------------------------------------------------------
  // Timer state sync -> pushed into the foreground service so the
  // notification's "Timer: 142 MB in 18m 32s" line stays accurate even
  // while the Flutter UI isn't attached.
  // ---------------------------------------------------------------------

  Future<void> pushTimerState({
    required bool active,
    required bool paused,
    required int elapsedSeconds,
    required int timerBytes,
  }) async {
    await _methodChannel.invokeMethod('updateTimerState', {
      'active': active,
      'paused': paused,
      'elapsedSeconds': elapsedSeconds,
      'timerBytes': timerBytes,
    });
  }

  /// Resets the native TrafficStats baseline used to compute "bytes used
  /// since timer start". Call this whenever the timer is (re)started.
  Future<int> resetSessionBaseline() async {
    final bytes =
        await _methodChannel.invokeMethod<int>('resetSessionBaseline');
    return bytes ?? 0;
  }

  /// Returns the device's current total (mobile+wifi) rx+tx bytes, used by
  /// the Dart TimerController to compute "data used since timer start"
  /// without waiting for the next EventChannel tick.
  Future<int> getCurrentTotalBytes() async {
    final bytes =
        await _methodChannel.invokeMethod<int>('getCurrentTotalBytes');
    return bytes ?? 0;
  }
}
