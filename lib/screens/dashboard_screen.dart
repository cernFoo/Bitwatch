import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_usage.dart';
import '../providers/history_provider.dart';
import '../providers/speed_provider.dart';
import '../providers/timer_provider.dart';
import '../services/permission_service.dart';
import '../services/platform_service.dart';
import '../utils/formatters.dart';
import '../widgets/speed_indicator.dart';
import '../widgets/timer_card.dart';
import 'history_screen.dart';

enum _MenuAction { resetStats, stopAndExit }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Duration? _pendingLimit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final result = await PermissionService.instance.ensureAll();
    if (!mounted) return;
    if (!result.usageAccessGranted) {
      _promptUsageAccess();
    }
    await PlatformService.instance.startForegroundService();
  }

  void _promptUsageAccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Usage Access Required'),
        content: const Text(
          'BitWatch needs the "Usage access" special permission to read '
          'your mobile & Wi-Fi data statistics. You\'ll be taken to Settings '
          '- please enable BitWatch there and return to the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              PermissionService.instance.openUsageAccessSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(_MenuAction action) async {
    switch (action) {
      case _MenuAction.resetStats:
        await _confirmResetStats();
        break;
      case _MenuAction.stopAndExit:
        await _confirmStopAndExit();
        break;
    }
  }

  Future<void> _promptSetLimit() async {
    final controller = TextEditingController(
      text: _pendingLimit != null ? _pendingLimit!.inMinutes.toString() : '',
    );
    final minutes = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Countdown Limit'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Minutes',
            hintText: 'e.g. 30',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(-1),
            child: const Text('No Limit'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              Navigator.of(ctx).pop(value);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (minutes == null) return; // cancelled
    setState(() {
      _pendingLimit = minutes <= 0 ? null : Duration(minutes: minutes);
    });
  }

  Future<void> _confirmResetStats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Stats?'),
        content: const Text(
          'This wipes all historical usage entries and resets the current '
          'session timer. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(timerControllerProvider.notifier).reset();
      await ref.read(historyProvider.notifier).resetStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stats have been reset')),
        );
      }
    }
  }

  Future<void> _confirmStopAndExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop And Exit?'),
        content: const Text(
          'This stops the background monitoring service, removes the '
          'notification, and closes BitWatch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop & Exit'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await PlatformService.instance.stopForegroundService();
      SystemNavigator.pop();
      // Ensure the process is fully terminated per spec, not just the UI.
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final speedAsync = ref.watch(speedSampleProvider);
    final timerState = ref.watch(timerControllerProvider);
    final history = ref.watch(historyProvider);
    final timerController = ref.read(timerControllerProvider.notifier);

    final sample = speedAsync.valueOrNull ?? SpeedSample.initial();

    return Scaffold(
      appBar: AppBar(
        title: const Text('BitWatch'),
        actions: [
          PopupMenuButton<_MenuAction>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MenuAction.resetStats,
                child: ListTile(
                  leading: Icon(Icons.restart_alt_rounded),
                  title: Text('Reset Stats'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.stopAndExit,
                child: ListTile(
                  leading: Icon(Icons.power_settings_new_rounded),
                  title: Text('Stop And Exit'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(historyProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Active Data Timer',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TimerCard(
              timerState: timerState,
              pendingLimit: _pendingLimit,
              onStart: () =>
                  timerController.start(countdownFrom: _pendingLimit),
              onPause: timerController.pause,
              onReset: () {
                timerController.reset();
                setState(() => _pendingLimit = null);
              },
              onSetLimit: _promptSetLimit,
            ),
            const SizedBox(height: 24),
            Text(
              'Live Speed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SpeedIndicatorRow(
              downloadBps: sample.downloadBps,
              uploadBps: sample.uploadBps,
            ),
            const SizedBox(height: 24),
            Text(
              'Today',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _TodaySummaryCard(
              mobileBytes: sample.todayMobileBytes,
              wifiBytes: sample.todayWifiBytes,
              loading: history.loading && speedAsync.valueOrNull == null,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              icon: const Icon(Icons.calendar_month_rounded),
              label: const Text('View Monthly Usage'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummaryCard extends StatelessWidget {
  final int mobileBytes;
  final int wifiBytes;
  final bool loading;

  const _TodaySummaryCard({
    required this.mobileBytes,
    required this.wifiBytes,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatColumn(
              label: 'Mobile',
              value: Formatters.bytes(mobileBytes),
              icon: Icons.signal_cellular_alt_rounded,
            ),
            _StatColumn(
              label: 'Wi-Fi',
              value: Formatters.bytes(wifiBytes),
              icon: Icons.wifi_rounded,
            ),
            _StatColumn(
              label: 'Total',
              value: Formatters.bytes(mobileBytes + wifiBytes),
              icon: Icons.data_usage_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.titleMedium),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
