import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/daily_usage.dart';
import '../services/database_service.dart';
import '../services/platform_service.dart';

final _dateFmt = DateFormat('yyyy-MM-dd');

String todayDateString() => _dateFmt.format(DateTime.now());

class HistoryState {
  final DailyUsage today;
  final List<DailyUsage> pastDays; // most recent first, excludes today
  final bool loading;

  const HistoryState({
    required this.today,
    required this.pastDays,
    required this.loading,
  });

  factory HistoryState.initial() => HistoryState(
        today: DailyUsage.empty(todayDateString()),
        pastDays: const [],
        loading: true,
      );

  DailyUsage get monthTotal {
    final all = [today, ...pastDays];
    final currentMonth = DateTime.now().month;
    final inMonth = all.where((d) {
      final date = DateTime.tryParse(d.date);
      return date != null && date.month == currentMonth;
    });
    var mobile = 0;
    var wifi = 0;
    for (final d in inMonth) {
      mobile += d.mobileBytes;
      wifi += d.wifiBytes;
    }
    return DailyUsage(date: 'This Month', mobileBytes: mobile, wifiBytes: wifi);
  }

  HistoryState copyWith({
    DailyUsage? today,
    List<DailyUsage>? pastDays,
    bool? loading,
  }) {
    return HistoryState(
      today: today ?? this.today,
      pastDays: pastDays ?? this.pastDays,
      loading: loading ?? this.loading,
    );
  }
}

/// Owns the 30-day usage history table shown on the History screen.
///
/// Strategy:
/// - "Today" is always fetched live from NetworkStatsManager (via
///   PlatformService) since it changes constantly.
/// - Past days are cached in SQLite. On [refresh], any past day missing from
///   the local DB is backfilled by querying the native side once, then
///   persisted so future launches are fast and don't need to re-query native
///   stats for days that can no longer change.
/// - Yesterday's row is always re-queried natively and upserted, in case the
///   app was killed before midnight rollover finished persisting it.
class HistoryController extends StateNotifier<HistoryState> {
  HistoryController() : super(HistoryState.initial()) {
    refresh();
  }

  static const historyDays = 30;

  Future<void> refresh() async {
    state = state.copyWith(loading: true);

    final today =
        await PlatformService.instance.getTodayUsage(todayDateString());

    final now = DateTime.now();
    final earliest = now.subtract(const Duration(days: historyDays));
    final startStr = _dateFmt.format(earliest);
    final yesterdayStr =
        _dateFmt.format(now.subtract(const Duration(days: 1)));

    final cached =
        await DatabaseService.instance.getRange(startStr, yesterdayStr);
    final cachedDates = cached.map((d) => d.date).toSet();

    // Backfill any missing days (e.g. first run, or a day the service missed)
    // and always refresh yesterday since it may have finalized after the
    // last read.
    final toFetch = <String>[];
    for (var i = 1; i <= historyDays; i++) {
      final d = _dateFmt.format(now.subtract(Duration(days: i)));
      if (!cachedDates.contains(d) || d == yesterdayStr) {
        toFetch.add(d);
      }
    }

    final merged = {for (final d in cached) d.date: d};
    for (final dateStr in toFetch) {
      final usage = await PlatformService.instance.getUsageForDate(dateStr);
      merged[dateStr] = usage;
      await DatabaseService.instance.upsertDay(usage);
    }

    final pastDays = merged.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    state = state.copyWith(today: today, pastDays: pastDays, loading: false);
  }

  /// "Reset Stats" menu action: wipes the local history DB and refreshes
  /// today's figure (native counters themselves are device-level and can't
  /// be zeroed, but the app's own recorded history is cleared).
  Future<void> resetStats() async {
    await DatabaseService.instance.resetAll();
    await refresh();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryController, HistoryState>(
        (ref) => HistoryController());
