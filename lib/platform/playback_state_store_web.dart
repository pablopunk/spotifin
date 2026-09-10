import 'package:web/web.dart' as web;

class PlaybackStateStore {
  static const _key = 'spotifin.playbackState';

  Future<String?> read() async => web.window.localStorage.getItem(_key);

  Future<void> write(String value) async {
    web.window.localStorage.setItem(_key, value);
  }

  Future<void> clear() async {
    web.window.localStorage.removeItem(_key);
  }
}
