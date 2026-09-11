import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

class SessionStore {
  const SessionStore(this._secureStorage);
  final FlutterSecureStorage _secureStorage;

  Future<void> save(JellyfinSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('serverUrl', session.serverUrl);
    await preferences.setString('serverId', session.serverId);
    await preferences.setString('deviceId', session.deviceId);
    await preferences.setString('userId', session.userId);
    await preferences.setString('userName', session.userName);
    await _secureStorage.write(key: 'accessToken', value: session.accessToken);
  }

  Future<JellyfinSession?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final serverUrl = preferences.getString('serverUrl');
    final serverId = preferences.getString('serverId');
    final deviceId = await getDeviceId();
    final userId = preferences.getString('userId');
    final userName = preferences.getString('userName');
    final accessToken = await _secureStorage.read(key: 'accessToken');
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

  Future<String> getDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('deviceId');
    if (saved != null && saved.isNotEmpty) return saved;
    final random = Random.secure();
    final generated =
        'spotifin-${List.generate(4, (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join()}';
    await preferences.setString('deviceId', generated);
    return generated;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in ['serverUrl', 'serverId', 'userId', 'userName']) {
      await preferences.remove(key);
    }
    await _secureStorage.delete(key: 'accessToken');
  }
}
