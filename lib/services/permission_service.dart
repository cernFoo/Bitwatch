import 'package:permission_handler/permission_handler.dart';

import 'platform_service.dart';

/// Centralizes the three permission concerns BitWatch needs on Android:
///
/// - POST_NOTIFICATIONS (runtime permission, API 33+): required to show the
///   persistent foreground-service notification. On API < 33 this is
///   granted automatically at install time so the request is a no-op there.
/// - READ_PHONE_STATE (runtime permission): used when querying per-SIM
///   mobile data stats via NetworkStatsManager on some OEMs/API levels.
/// - PACKAGE_USAGE_STATS ("special access", not a runtime permission): must
///   be granted by the user manually in Settings > Apps > Special app
///   access > Usage access. We can only deep-link there, not request it via
///   a dialog.
class PermissionService {
  PermissionService._internal();
  static final PermissionService instance = PermissionService._internal();

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  Future<bool> requestPhoneStatePermission() async {
    final status = await Permission.phone.status;
    if (status.isGranted) return true;
    final result = await Permission.phone.request();
    return result.isGranted;
  }

  Future<bool> hasUsageAccess() {
    return PlatformService.instance.hasUsageAccessPermission();
  }

  Future<void> openUsageAccessSettings() {
    return PlatformService.instance.openUsageAccessSettings();
  }

  /// Runs through notification + phone-state requests and reports whether
  /// usage access is still needed (the caller should prompt the user to
  /// visit Settings for that one, since it can't be requested inline).
  Future<PermissionCheckResult> ensureAll() async {
    final notif = await requestNotificationPermission();
    final phone = await requestPhoneStatePermission();
    final usage = await hasUsageAccess();
    return PermissionCheckResult(
      notificationsGranted: notif,
      phoneStateGranted: phone,
      usageAccessGranted: usage,
    );
  }
}

class PermissionCheckResult {
  final bool notificationsGranted;
  final bool phoneStateGranted;
  final bool usageAccessGranted;

  const PermissionCheckResult({
    required this.notificationsGranted,
    required this.phoneStateGranted,
    required this.usageAccessGranted,
  });

  bool get allGranted =>
      notificationsGranted && phoneStateGranted && usageAccessGranted;
}
