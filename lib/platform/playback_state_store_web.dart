import 'package:web/web.dart' as web;

class PlaybackStateStore {
  static const _legacyKey = 'spotifin.playbackState';

  Future<String?> read(String accountId) async =>
      web.window.localStorage.getItem(_key(accountId)) ??
      web.window.localStorage.getItem(_legacyKey);

  Future<void> write(String accountId, String value) async {
    web.window.localStorage.setItem(_key(accountId), value);
    web.window.localStorage.removeItem(_legacyKey);
  }

  Future<void> clear(String accountId) async {
    web.window.localStorage.removeItem(_key(accountId));
    web.window.localStorage.removeItem(_legacyKey);
  }

  String _key(String accountId) => 'spotifin.playbackState.$accountId';
}
