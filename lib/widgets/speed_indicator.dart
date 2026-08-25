import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// Small pill showing a live up/down arrow + speed value.
class SpeedChip extends StatelessWidget {
  final IconData icon;
  final int bytesPerSecond;
  final Color color;

  const SpeedChip({
    super.key,
    required this.icon,
    required this.bytesPerSecond,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            Formatters.speed(bytesPerSecond),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class SpeedIndicatorRow extends StatelessWidget {
  final int downloadBps;
  final int uploadBps;

  const SpeedIndicatorRow({
    super.key,
    required this.downloadBps,
    required this.uploadBps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SpeedChip(
          icon: Icons.arrow_downward_rounded,
          bytesPerSecond: downloadBps,
          color: Colors.blueAccent,
        ),
        const SizedBox(width: 12),
        SpeedChip(
          icon: Icons.arrow_upward_rounded,
          bytesPerSecond: uploadBps,
          color: Colors.deepOrangeAccent,
        ),
      ],
    );
  }
}
