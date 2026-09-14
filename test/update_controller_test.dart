import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/services/updates/release_info.dart';
import 'package:spotifin/services/updates/update_controller.dart';
import 'package:spotifin/services/updates/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 14, 12);

  test('does not throttle a check without a previous check', () {
    expect(withinUpdateCooldown(null, now), isFalse);
  });

  test('throttles a check one hour after the last check', () {
    expect(
      withinUpdateCooldown(now.subtract(const Duration(hours: 1)), now),
      isTrue,
    );
  });

  test('allows a check a day after the last check', () {
    expect(
      withinUpdateCooldown(now.subtract(const Duration(hours: 24)), now),
      isFalse,
    );
  });

  test('manual check reports an available release', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeUpdateService(_release('0.2.0'));
    final container = _container(service);

    final check = await container
        .read(updateControllerProvider.notifier)
        .checkNow();

    expect(check.status, UpdateCheckStatus.available);
    expect(check.release?.version, '0.2.0');
    expect(check.currentVersion, '0.1.4');
    expect(container.read(updateControllerProvider).checking, isFalse);
  });

  test('manual check reports an up-to-date app', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container(_FakeUpdateService(_release('0.1.4')));

    final check = await container
        .read(updateControllerProvider.notifier)
        .checkNow();

    expect(check.status, UpdateCheckStatus.upToDate);
    expect(check.currentVersion, '0.1.4');
  });

  test('manual check reports failures', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeUpdateService(_release('0.2.0'))
      ..error = const UpdateException('offline');
    final container = _container(service);

    final check = await container
        .read(updateControllerProvider.notifier)
        .checkNow();

    expect(check.status, UpdateCheckStatus.failed);
    expect(check.error, 'offline');
  });

  test('startup check surfaces a newer release', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeUpdateService(_release('0.2.0'));
    final container = _container(service);

    await container.read(updateControllerProvider.notifier).checkOnStartup();

    expect(container.read(updateControllerProvider).release?.version, '0.2.0');
    expect(service.calls, 1);
  });

  test('startup check throttles within a day', () async {
    SharedPreferences.setMockInitialValues({
      'updateCheckedAt': DateTime.now().toIso8601String(),
    });
    final service = _FakeUpdateService(_release('0.2.0'));
    final container = _container(service);

    await container.read(updateControllerProvider.notifier).checkOnStartup();

    expect(container.read(updateControllerProvider).release, isNull);
    expect(service.calls, 0);
  });

  test('startup check skips a store-managed install', () async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeUpdateService(_release('0.2.0'));
    final container = _container(
      service,
      installerStore: 'com.android.vending',
    );

    await container.read(updateControllerProvider.notifier).checkOnStartup();

    expect(container.read(updateControllerProvider).release, isNull);
    expect(service.calls, 0);
  });

  test('startup check skips a dismissed version', () async {
    SharedPreferences.setMockInitialValues({
      'updateCheckedAt': _aDayAgo(),
      'dismissedUpdateVersion': '0.2.0',
    });
    final service = _FakeUpdateService(_release('0.2.0'));
    final container = _container(service);

    await container.read(updateControllerProvider.notifier).checkOnStartup();

    expect(container.read(updateControllerProvider).release, isNull);
    expect(service.calls, 1);
  });

  test('startup check surfaces a release newer than the dismissal', () async {
    SharedPreferences.setMockInitialValues({
      'updateCheckedAt': _aDayAgo(),
      'dismissedUpdateVersion': '0.2.0',
    });
    final service = _FakeUpdateService(_release('0.3.0'));
    final container = _container(service);

    await container.read(updateControllerProvider.notifier).checkOnStartup();

    expect(container.read(updateControllerProvider).release?.version, '0.3.0');
  });

  test('dismiss remembers the version and clears the prompt', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container(_FakeUpdateService(_release('0.2.0')));
    final controller = container.read(updateControllerProvider.notifier);
    await controller.checkOnStartup();

    await controller.dismiss();

    expect(container.read(updateControllerProvider).release, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('dismissedUpdateVersion'), '0.2.0');
  });
}

String _aDayAgo() =>
    DateTime.now().subtract(const Duration(hours: 25)).toIso8601String();

ReleaseInfo _release(String version) => ReleaseInfo(
  version: version,
  name: 'v$version - Tuned up',
  url: 'https://github.com/pablopunk/spotifin/releases/tag/v$version',
  publishedAt: DateTime.utc(2026, 9, 1),
);

ProviderContainer _container(
  _FakeUpdateService service, {
  String? installerStore,
}) {
  final container = ProviderContainer(
    overrides: [
      updateServiceProvider.overrideWithValue(service),
      packageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'Spotifin',
          packageName: 'app.spotifin',
          version: '0.1.4',
          buildNumber: '1',
          installerStore: installerStore,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _FakeUpdateService implements UpdateService {
  _FakeUpdateService(this.release);

  final ReleaseInfo release;
  Object? error;
  int calls = 0;

  @override
  Future<ReleaseInfo> fetchLatest() async {
    calls++;
    final error = this.error;
    if (error != null) throw error;
    return release;
  }

  @override
  void close() {}
}
