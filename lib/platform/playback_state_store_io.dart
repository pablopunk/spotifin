import 'package:shared_preferences/shared_preferences.dart';

class PlaybackStateStore {
  static const _legacyKey = 'playbackState';

  Future<String?> read(String accountId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key(accountId)) ??
        preferences.getString(_legacyKey);
  }

  Future<void> write(String accountId, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(accountId), value);
    await preferences.remove(_legacyKey);
  }

  Future<void> clear(String accountId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(accountId));
    await preferences.remove(_legacyKey);
  }

  String _key(String accountId) => 'playbackState.$accountId';
}
