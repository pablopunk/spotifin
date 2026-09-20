import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/services/jellyfin/secure_storage_config.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/jellyfin/session_store.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

const _session = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server-id',
  deviceId: 'device-id',
  userId: 'user-id',
  userName: 'user-name',
  accessToken: 'token',
);

Map<String, Object> _savedPrefs() => {
  'serverUrl': _session.serverUrl,
  'serverId': _session.serverId,
  'deviceId': _session.deviceId,
  'userId': _session.userId,
  'userName': _session.userName,
};

void _stubVoid(_MockSecureStorage storage, {required String method}) {
  switch (method) {
    case 'delete':
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
    case 'write':
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
  }
}

void main() {
  group('session secure storage configuration', () {
    test('iOS uses first-unlock accessibility', () {
      expect(
        buildSessionSecureStorage().iOptions.accessibility,
        KeychainAccessibility.first_unlock,
      );
    });

    test('macOS storage behavior is unchanged', () {
      final macOs = buildSessionSecureStorage().mOptions as MacOsOptions;

      expect(macOs.accountName, sessionMacAccountName);
      expect(macOs.accountName, 'com.pablopunk.spotifin.session');
      expect(macOs.usesDataProtectionKeychain, isFalse);
    });

    test('iOS keeps the default service name so upgrades find the item', () {
      expect(
        buildSessionSecureStorage().iOptions.accountName,
        AppleOptions.defaultAccountName,
      );
    });

    test('pre-fix default was unlocked accessibility', () {
      expect(
        const FlutterSecureStorage().iOptions.accessibility,
        KeychainAccessibility.unlocked,
      );
    });

    test('session store provider uses the hardened storage', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(sessionSecureStorageProvider).iOptions.accessibility,
        KeychainAccessibility.first_unlock,
      );
    });
  });

  group('keychain error mapping', () {
    final interactionNotAllowed = PlatformException(
      code: '-25308',
      message: 'User interaction is not allowed.',
    );
    final realisticReport = PlatformException(
      code: 'Unexpected security result code',
      message: 'Code: -25308, Message: User interaction is not allowed.',
    );

    test('detects errSecInteractionNotAllowed (-25308)', () {
      expect(isKeychainInteractionNotAllowed(interactionNotAllowed), isTrue);
      expect(isKeychainInteractionNotAllowed(realisticReport), isTrue);
      expect(
        isKeychainInteractionNotAllowed(
          'PlatformException(errSecInteractionNotAllowed, null, null, null)',
        ),
        isTrue,
      );
    });

    test('does not flag unrelated errors', () {
      expect(isKeychainInteractionNotAllowed(Exception('boom')), isFalse);
      expect(
        isKeychainInteractionNotAllowed(
          PlatformException(code: '-25299', message: 'duplicate item'),
        ),
        isFalse,
      );
    });

    test('detects duplicate keychain entries', () {
      expect(
        isKeychainDuplicateItem(
          PlatformException(code: '-25299', message: 'duplicate item'),
        ),
        isTrue,
      );
      expect(isKeychainDuplicateItem(Exception('boom')), isFalse);
    });

    test('restore message is actionable for a locked keychain', () {
      final message = sessionRestoreErrorMessage(realisticReport);

      expect(message, contains('-25308'));
      expect(message, contains('Unlock the device'));
      expect(message, contains('sign in again'));
    });

    test('restore message keeps the raw error otherwise', () {
      final error = Exception('disk is gone');

      expect(sessionRestoreErrorMessage(error), contains(error.toString()));
    });
  });

  group('SessionStore', () {
    test('migrates a legacy token without losing the session', () async {
      SharedPreferences.setMockInitialValues(_savedPrefs());
      final storage = _MockSecureStorage();
      final legacy = _MockSecureStorage();
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => legacy.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'legacy-token');
      _stubVoid(storage, method: 'delete');
      _stubVoid(storage, method: 'write');

      final session = await SessionStore(
        storage,
        legacySecureStorage: legacy,
      ).load();

      expect(session?.accessToken, 'legacy-token');
      expect(session?.serverUrl, _session.serverUrl);
      verify(() => storage.delete(key: 'accessToken')).called(1);
      verify(() => storage.write(key: 'accessToken', value: 'legacy-token'))
          .called(1);
    });

    test('returns null on a fresh install without writing', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = _MockSecureStorage();
      final legacy = _MockSecureStorage();
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => legacy.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      final session = await SessionStore(
        storage,
        legacySecureStorage: legacy,
      ).load();

      expect(session, isNull);
      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
    });

    test(
      'surfaces a locked keychain instead of signing out silently',
      () async {
        SharedPreferences.setMockInitialValues(_savedPrefs());
        final storage = _MockSecureStorage();
        final legacy = _MockSecureStorage();
        when(() => storage.read(key: any(named: 'key'))).thenThrow(
          PlatformException(
            code: '-25308',
            message: 'User interaction is not allowed.',
          ),
        );

        final store = SessionStore(storage, legacySecureStorage: legacy);

        await expectLater(store.load(), throwsA(isA<PlatformException>()));
        verifyNever(() => legacy.read(key: any(named: 'key')));
      },
    );

    test('retries a duplicate keychain entry on save', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = _MockSecureStorage();
      final legacy = _MockSecureStorage();
      var writes = 0;
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {
        writes++;
        if (writes == 1) {
          throw PlatformException(code: '-25299', message: 'duplicate item');
        }
      });
      _stubVoid(storage, method: 'delete');

      await SessionStore(storage, legacySecureStorage: legacy).save(_session);

      expect(writes, 2);
      verify(() => storage.delete(key: 'accessToken')).called(1);
    });

    test('rethrows non-duplicate save errors', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = _MockSecureStorage();
      final legacy = _MockSecureStorage();
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenThrow(Exception('boom'));

      final store = SessionStore(storage, legacySecureStorage: legacy);

      await expectLater(store.save(_session), throwsA(isException));
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });

    test('clear removes the token from both storages', () async {
      SharedPreferences.setMockInitialValues(_savedPrefs());
      final storage = _MockSecureStorage();
      final legacy = _MockSecureStorage();
      _stubVoid(storage, method: 'delete');
      _stubVoid(legacy, method: 'delete');

      await SessionStore(storage, legacySecureStorage: legacy).clear();

      verify(() => storage.delete(key: 'accessToken')).called(1);
      verify(() => legacy.delete(key: 'accessToken')).called(1);
    });

    test('round-trips a session on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final store = SessionStore(buildSessionSecureStorage());

      await store.save(_session);
      final restored = await store.load();

      expect(restored?.accessToken, _session.accessToken);
      expect(restored?.serverUrl, _session.serverUrl);
      expect(restored?.serverId, _session.serverId);
      expect(restored?.userId, _session.userId);
      expect(restored?.userName, _session.userName);
    });
  });
}
