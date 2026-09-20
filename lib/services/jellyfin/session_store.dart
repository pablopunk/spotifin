import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_config.dart';
import 'session.dart';

class SessionStore {
  const SessionStore(
    this._secureStorage, {
    this.legacySecureStorage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage _secureStorage;

  /// Storage using the pre-fix iOS options (default `unlocked`
  /// accessibility), used only to migrate tokens written before the iOS
  /// accessibility change. The native keychain keeps the original
  /// accessibility attribute on update and filters reads by it, so entries
  /// written with the old options are invisible to the new ones until they
  /// are re-added.
  final FlutterSecureStorage legacySecureStorage;

  static const accessTokenKey = 'accessToken';

  Future<void> save(JellyfinSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('serverUrl', session.serverUrl);
    await preferences.setString('serverId', session.serverId);
    await preferences.setString('deviceId', session.deviceId);
    await preferences.setString('userId', session.userId);
    await preferences.setString('userName', session.userName);
    try {
      await _secureStorage.write(
        key: accessTokenKey,
        value: session.accessToken,
      );
    } catch (error) {
      if (!isKeychainDuplicateItem(error)) rethrow;
      // A pre-migration entry can share the keychain account with a different
      // accessibility attribute; clear it and re-add the token with the
      // current options instead of losing the session.
      await _secureStorage.delete(key: accessTokenKey);
      await _secureStorage.write(
        key: accessTokenKey,
        value: session.accessToken,
      );
    }
  }

  Future<JellyfinSession?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final serverUrl = preferences.getString('serverUrl');
    final serverId = preferences.getString('serverId');
    final deviceId = await getDeviceId();
    final userId = preferences.getString('userId');
    final userName = preferences.getString('userName');
    // A locked keychain (-25308) throws here and propagates to the caller so
    // the app can show actionable recovery steps instead of silently
    // dropping the saved session.
    var accessToken = await _secureStorage.read(key: accessTokenKey);
    accessToken ??= await _migrateLegacyToken();
    if ([
      serverUrl,
      serverId,
      userId,
      userName,
      accessToken,
    ].any((value) => value == null)) {
      return null;
    }
    return JellyfinSession(
      serverUrl: serverUrl!,
      serverId: serverId!,
      deviceId: deviceId,
      userId: userId!,
      userName: userName!,
      accessToken: accessToken!,
    );
  }

  /// Re-adds a token written with the pre-fix iOS options under the current
  /// options. Returns null when there is no legacy token to migrate.
  Future<String?> _migrateLegacyToken() async {
    final legacyToken = await legacySecureStorage.read(key: accessTokenKey);
    if (legacyToken == null) return null;
    // The keychain delete query ignores accessibility, so this removes the
    // stale entry regardless of which options created it.
    await _secureStorage.delete(key: accessTokenKey);
    try {
      await _secureStorage.write(key: accessTokenKey, value: legacyToken);
    } catch (_) {
      // Best effort: restore the pre-migration entry so an upgrade never
      // silently drops an existing session.
      try {
        await legacySecureStorage.write(
          key: accessTokenKey,
          value: legacyToken,
        );
      } catch (_) {}
      rethrow;
    }
    return legacyToken;
  }

  Future<String> getDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('deviceId');
    if (saved != null && saved.isNotEmpty) return saved;
    final random = Random.secure();
    final generated =
        'spotifin-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    await preferences.setString('deviceId', generated);
    return generated;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in ['serverUrl', 'serverId', 'userId', 'userName']) {
      await preferences.remove(key);
    }
    await _secureStorage.delete(key: accessTokenKey);
    // Best effort: also drop a pre-migration entry that a failed migration
    // may have restored under the legacy options.
    try {
      await legacySecureStorage.delete(key: accessTokenKey);
    } catch (_) {}
  }
}
