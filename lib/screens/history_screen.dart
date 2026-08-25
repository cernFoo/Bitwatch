import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/daily_usage.dart';
import '../providers/history_provider.dart';
import '../providers/speed_provider.dart';
import '../utils/formatters.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final speedAsync = ref.watch(speedSampleProvider);
    final theme = Theme.of(context);

    // "Today" row uses the live EventChannel sample when available (updates
    // every second) and falls back to the last DB/native fetch otherwise.
    final liveSample = speedAsync.valueOrNull;
    final todayUsage = liveSample != null
        ? DailyUsage(
            date: history.today.date,
            mobileBytes: liveSample.todayMobileBytes,
            wifiBytes: liveSample.todayWifiBytes,
          )
        : history.today;

    final monthTotal = history.monthTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Usage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(historyProvider.notifier).refresh(),
          ),
        ],
      ),
      body: history.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(historyProvider.notifier).refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _HeaderRow(theme: theme),
                    const Divider(height: 1),
                    _DataRow(
                      label: 'Today',
                      usage: todayUsage,
                      highlight: true,
                    ),
                    ...history.pastDays.map(
                      (d) => _DataRow(label: _friendlyDate(d.date), usage: d),
                    ),
                    const Divider(height: 1, thickness: 2),
                    _DataRow(
                      label: 'This Month',
                      usage: monthTotal,
                      highlight: true,
                      bold: true,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  static String _friendlyDate(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    return DateFormat('EEE, MMM d').format(date);
  }
}

class _HeaderRow extends StatelessWidget {
  final ThemeData theme;
  const _HeaderRow({required this.theme});

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Date', style: style)),
          Expanded(
              flex: 2,
              child:
                  Text('Mobile', style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text('WiFi', style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text('Total', style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final DailyUsage usage;
  final bool highlight;
  final bool bold;

  const _DataRow({
    required this.label,
    required this.usage,
    this.highlight = false,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );

    return Container(
      color: highlight
          ? theme.colorScheme.primaryContainer.withOpacity(0.25)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: baseStyle)),
          Expanded(
            flex: 2,
            child: Text(Formatters.bytes(usage.mobileBytes),
                style: baseStyle, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text(Formatters.bytes(usage.wifiBytes),
                style: baseStyle, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text(Formatters.bytes(usage.totalBytes),
                style: baseStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}