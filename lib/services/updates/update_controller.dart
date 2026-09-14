import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'release_info.dart';
import 'update_service.dart';
import 'version_comparison.dart';

enum UpdateCheckStatus { upToDate, available, failed }

class UpdateCheck {
  const UpdateCheck(
    this.status, {
    this.release,
    this.currentVersion,
    this.error,
  });

  final UpdateCheckStatus status;
  final ReleaseInfo? release;
  final String? currentVersion;
  final String? error;
}

class UpdateState {
  const UpdateState({this.checking = false, this.release});

  final bool checking;
  final ReleaseInfo? release;
}

const updateCheckInterval = Duration(hours: 24);

@visibleForTesting
bool withinUpdateCooldown(DateTime? checkedAt, DateTime now) =>
    checkedAt != null && now.difference(checkedAt) < updateCheckInterval;

class UpdateController extends Notifier<UpdateState> {
  static const _checkedAtKey = 'updateCheckedAt';
  static const _dismissedVersionKey = 'dismissedUpdateVersion';

  @override
  UpdateState build() => const UpdateState();

  Future<void> checkOnStartup() async {
    try {
      if (kIsWeb || await _storeManaged()) return;
      final preferences = await SharedPreferences.getInstance();
      final checkedAt = DateTime.tryParse(
        preferences.getString(_checkedAtKey) ?? '',
      );
      final now = DateTime.now();
      if (withinUpdateCooldown(checkedAt, now)) return;
      await preferences.setString(_checkedAtKey, now.toIso8601String());
      final check = await _run();
      final release = check.release;
      if (check.status != UpdateCheckStatus.available || release == null) {
        return;
      }
      final dismissed = preferences.getString(_dismissedVersionKey);
      if (dismissed != null && !isNewerVersion(release.version, dismissed)) {
        return;
      }
      state = UpdateState(release: release);
    } catch (_) {}
  }

  Future<UpdateCheck> checkNow() async {
    state = UpdateState(checking: true, release: state.release);
    final check = await _run();
    state = UpdateState(release: state.release);
    return check;
  }

  Future<void> dismiss() async {
    final release = state.release;
    if (release != null) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_dismissedVersionKey, release.version);
    }
    state = const UpdateState();
  }

  Future<UpdateCheck> _run() async {
    try {
      final release = await ref.read(updateServiceProvider).fetchLatest();
      final current = await ref.read(packageInfoProvider.future);
      if (!isNewerVersion(release.version, current.version)) {
        return UpdateCheck(
          UpdateCheckStatus.upToDate,
          currentVersion: current.version,
        );
      }
      return UpdateCheck(
        UpdateCheckStatus.available,
        release: release,
        currentVersion: current.version,
      );
    } on UpdateException catch (error) {
      return UpdateCheck(UpdateCheckStatus.failed, error: error.message);
    } catch (error) {
      return UpdateCheck(UpdateCheckStatus.failed, error: error.toString());
    }
  }

  Future<bool> _storeManaged() async {
    try {
      final installer = (await ref.read(packageInfoProvider.future))
          .installerStore;
      return installer != null &&
          (installer.startsWith('com.apple') ||
              installer == 'com.android.vending');
    } catch (_) {
      return false;
    }
  }
}
