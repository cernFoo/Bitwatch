import 'dart:ui';

import 'package:flutter/material.dart';

import '../providers/timer_provider.dart';
import '../utils/formatters.dart';

class TimerCard extends StatelessWidget {
  final TimerState timerState;
  final Duration? pendingLimit;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;
  final VoidCallback onSetLimit;

  const TimerCard({
    super.key,
    required this.timerState,
    required this.pendingLimit,
    required this.onStart,
    required this.onPause,
    required this.onReset,
    required this.onSetLimit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = timerState.remainingSeconds;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              Formatters.duration(timerState.elapsedSeconds),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${Formatters.bytes(timerState.bytesUsed)} : ${Formatters.durationShort(timerState.elapsedSeconds)} used',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (remaining != null) ...[
              const SizedBox(height: 2),
              Text(
                'Remaining: ${Formatters.duration(remaining)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: timerState.status == TimerStatus.idle
                  ? onSetLimit
                  : null,
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: Text(
                pendingLimit != null
                    ? 'Limit: ${pendingLimit!.inMinutes} min'
                    : 'No limit set',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (timerState.status != TimerStatus.running)
                  _ControlButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Start',
                    onTap: onStart,
                    filled: true,
                  )
                else
                  _ControlButton(
                    icon: Icons.pause_rounded,
                    label: 'Pause',
                    onTap: onPause,
                    filled: true,
                  ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: Icons.replay_rounded,
                  label: 'Reset',
                  onTap: onReset,
                  filled: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
