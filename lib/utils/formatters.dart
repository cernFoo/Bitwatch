/// Formatting helpers shared across BitWatch screens.
class Formatters {
  Formatters._();

  /// Formats a byte count as a human readable string, e.g. "142 MB" or "1.2 GB".
  static String bytes(int bytes) {
    if (bytes < 0) bytes = 0;
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  /// Formats a bytes-per-second value as a speed string, e.g. "512 KB/s".
  static String speed(int bytesPerSecond) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytesPerSecond >= mb) {
      return '${(bytesPerSecond / mb).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= kb) {
      return '${(bytesPerSecond / kb).toStringAsFixed(0)} KB/s';
    }
    return '$bytesPerSecond B/s';
  }

  /// Formats elapsed seconds as HH:MM:SS or MM:SS.
  static String duration(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  /// Short "18m 32s" style duration used in the ratio readout.
  static String durationShort(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }
}
