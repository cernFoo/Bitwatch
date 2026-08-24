/// Represents aggregated mobile + Wi-Fi byte counts for a single calendar day.
class DailyUsage {
  final String date; // yyyy-MM-dd
  final int mobileBytes;
  final int wifiBytes;

  const DailyUsage({
    required this.date,
    required this.mobileBytes,
    required this.wifiBytes,
  });

  int get totalBytes => mobileBytes + wifiBytes;

  DailyUsage copyWith({int? mobileBytes, int? wifiBytes}) => DailyUsage(
        date: date,
        mobileBytes: mobileBytes ?? this.mobileBytes,
        wifiBytes: wifiBytes ?? this.wifiBytes,
      );

  Map<String, Object?> toMap() => {
        'date': date,
        'mobile_bytes': mobileBytes,
        'wifi_bytes': wifiBytes,
      };

  factory DailyUsage.fromMap(Map<String, Object?> map) => DailyUsage(
        date: map['date'] as String,
        mobileBytes: (map['mobile_bytes'] as num?)?.toInt() ?? 0,
        wifiBytes: (map['wifi_bytes'] as num?)?.toInt() ?? 0,
      );

  factory DailyUsage.empty(String date) =>
      DailyUsage(date: date, mobileBytes: 0, wifiBytes: 0);
}

/// Live speed + timer + today snapshot pushed from the native EventChannel.
class SpeedSample {
  final int downloadBps;
  final int uploadBps;
  final int todayMobileBytes;
  final int todayWifiBytes;
  final bool timerActive;
  final bool timerPaused;
  final int timerElapsedSeconds;
  final int timerBytes;

  const SpeedSample({
    required this.downloadBps,
    required this.uploadBps,
    required this.todayMobileBytes,
    required this.todayWifiBytes,
    required this.timerActive,
    required this.timerPaused,
    required this.timerElapsedSeconds,
    required this.timerBytes,
  });

  factory SpeedSample.initial() => const SpeedSample(
        downloadBps: 0,
        uploadBps: 0,
        todayMobileBytes: 0,
        todayWifiBytes: 0,
        timerActive: false,
        timerPaused: false,
        timerElapsedSeconds: 0,
        timerBytes: 0,
      );

  factory SpeedSample.fromMap(Map<dynamic, dynamic> map) => SpeedSample(
        downloadBps: (map['downloadBps'] as num?)?.toInt() ?? 0,
        uploadBps: (map['uploadBps'] as num?)?.toInt() ?? 0,
        todayMobileBytes: (map['todayMobile'] as num?)?.toInt() ?? 0,
        todayWifiBytes: (map['todayWifi'] as num?)?.toInt() ?? 0,
        timerActive: map['timerActive'] as bool? ?? false,
        timerPaused: map['timerPaused'] as bool? ?? false,
        timerElapsedSeconds: (map['timerElapsedSeconds'] as num?)?.toInt() ?? 0,
        timerBytes: (map['timerBytes'] as num?)?.toInt() ?? 0,
      );
}
