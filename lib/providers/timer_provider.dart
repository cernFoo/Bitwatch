import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/platform_service.dart';

enum TimerStatus { idle, running, paused }

class TimerState {
  final TimerStatus status;
  final int elapsedSeconds;
  final int bytesUsed;
  final Duration? countdownFrom; // optional target duration, null = count up

  const TimerState({
    required this.status,
    required this.elapsedSeconds,
    required this.bytesUsed,
    this.countdownFrom,
  });

  factory TimerState.initial() => const TimerState(
        status: TimerStatus.idle,
        elapsedSeconds: 0,
        bytesUsed: 0,
      );

  int? get remainingSeconds {
    if (countdownFrom == null) return null;
    final remaining = countdownFrom!.inSeconds - elapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  TimerState copyWith({
    TimerStatus? status,
    int? elapsedSeconds,
    int? bytesUsed,
    Duration? countdownFrom,
  }) {
    return TimerState(
      status: status ?? this.status,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      bytesUsed: bytesUsed ?? this.bytesUsed,
      countdownFrom: countdownFrom ?? this.countdownFrom,
    );
  }
}

/// Drives the "Active Data Timer" section of the dashboard. Ticks locally
/// every second for a snappy UI, while periodically reconciling the byte
/// counter against the native TrafficStats baseline (see
/// PlatformService.resetSessionBaseline / getCurrentTotalBytes) so the
/// figure stays accurate even though Dart isn't the source of truth for
/// network counters. Every tick is also pushed to the foreground service so
/// the persistent notification's "Timer: ..." line mirrors the UI.
class TimerController extends StateNotifier<TimerState> {
  TimerController() : super(TimerState.initial());

  Timer? _ticker;
  int _baselineBytes = 0;

  Future<void> start({Duration? countdownFrom}) async {
    if (state.status == TimerStatus.running) return;

    if (state.status == TimerStatus.idle) {
      // Fresh start: reset baseline + elapsed/byte counters.
      _baselineBytes = await PlatformService.instance.resetSessionBaseline();
      state = state.copyWith(
        status: TimerStatus.running,
        elapsedSeconds: 0,
        bytesUsed: 0,
        countdownFrom: countdownFrom,
      );
    } else {
      // Resuming from paused: keep elapsed/bytes, just resume the baseline
      // reference point so future deltas add on top correctly.
      final current = await PlatformService.instance.getCurrentTotalBytes();
      _baselineBytes = current - state.bytesUsed;
      state = state.copyWith(status: TimerStatus.running);
    }

    _startTicking();
    await _syncToService();
  }

  void pause() {
    if (state.status != TimerStatus.running) return;
    _ticker?.cancel();
    state = state.copyWith(status: TimerStatus.paused);
    _syncToService();
  }

  Future<void> reset() async {
    _ticker?.cancel();
    _baselineBytes = await PlatformService.instance.resetSessionBaseline();
    state = TimerState.initial();
    await _syncToService();
  }

  void _startTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final current = await PlatformService.instance.getCurrentTotalBytes();
      final used = current - _baselineBytes;
      state = state.copyWith(
        elapsedSeconds: state.elapsedSeconds + 1,
        bytesUsed: used < 0 ? 0 : used,
      );
      await _syncToService();

      // Auto-stop at zero for countdown mode.
      if (state.remainingSeconds == 0) {
        pause();
      }
    });
  }

  Future<void> _syncToService() {
    return PlatformService.instance.pushTimerState(
      active: state.status != TimerStatus.idle,
      paused: state.status == TimerStatus.paused,
      elapsedSeconds: state.elapsedSeconds,
      timerBytes: state.bytesUsed,
      remainingSeconds: state.remainingSeconds,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final timerControllerProvider =
    StateNotifierProvider<TimerController, TimerState>(
        (ref) => TimerController());
