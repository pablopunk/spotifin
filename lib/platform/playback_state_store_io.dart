import 'package:shared_preferences/shared_preferences.dart';

class PlaybackStateStore {
  static const _key = 'playbackState';

  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(_key, value);
  }

  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
