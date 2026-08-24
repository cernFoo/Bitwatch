import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_usage.dart';
import '../services/platform_service.dart';

/// Streams live [SpeedSample]s (download/upload speed, today's totals, timer
/// echo) from the native EventChannel. Consumed by the dashboard speed
/// indicator and the "Today" row on the history screen.
final speedSampleProvider = StreamProvider<SpeedSample>((ref) {
  return PlatformService.instance.speedStream;
});
